import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/content_sync_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/settings/sync_settings_controller.dart';
import 'package:marginmind/settings/sync_settings_page.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_design/mm_design.dart';

import '../helpers.dart';

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String account) async => throw StateError('No account access in this test');
  @override
  Future<void> write(String account, String value) async => throw StateError('No account access in this test');
  @override
  Future<void> delete(String account) async => throw StateError('No account access in this test');
}

class _Device {
  _Device(Directory root, String device)
    : ledger = FileSyncLedger(root, libraryId: 'native-acceptance', deviceId: device) {
    library = FileLibraryStore(root, sync: ledger, clock: () => testNow);
    words = FileVocabularyStore(root, sync: ledger);
  }
  final FileSyncLedger ledger;
  late final FileLibraryStore library;
  late final FileVocabularyStore words;
  Future<void> receive(_Device other) async => FileSyncReceiver(library, words).receive(await other.ledger.pending());
  Future<void> close() async {
    await library.dispose();
    await words.dispose();
  }
}

/// Shared with the native Flutter runner. Uses real private directories and
/// repositories; exchange is an explicit in-process delivery, not a cloud claim.
void syncNativeAcceptance() {
  testWidgets('native sync: protected input, choices, safe history, settings and disk restart', (tester) async {
    // Pump both real I/O and widget work. Neither pumpAndSettle alone nor a
    // runAsync awaiting a widget-zone future can drain both kinds of work.
    Future<void> until(bool Function() ready, String description) async {
      for (var i = 0; i < 1000; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 16));
        if (ready()) return;
      }
      fail('Timed out waiting for $description');
    }

    Future<T> drive<T>(Future<T> work) async {
      var done = false;
      T? value;
      Object? error;
      StackTrace? trace;
      work.then(
        (result) {
          value = result;
          done = true;
        },
        onError: (Object e, StackTrace s) {
          error = e;
          trace = s;
          done = true;
        },
      );
      await until(() => done, 'repository operation');
      if (error != null) Error.throwWithStackTrace(error!, trace!);
      return value as T;
    }

    Future<void> tapKey(String key) async {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(target);
      await tester.pump();
    }

    final root = (await tester.runAsync(() => Directory.systemTemp.createTemp('foliarc-native-sync-')))!;
    final a = _Device(Directory('${root.path}/a'), 'a');
    final b = _Device(Directory('${root.path}/b'), 'b');
    SyncSettingsController? settings;
    _Device? reopened;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      debugPrint('SYNC_ACCEPTANCE: create');
      final set = await drive(a.library.create(const NewStudySet(title: 'Native sync fixture', colorIndex: 0)));
      final id = set.id;
      var serial = 0;
      final editor = StudySetEditor(newId: () => 'card-${++serial}', now: () => testNow);
      late Card card;
      await drive(
        a.library.update(id, (content) {
          final result = editor.addTopic(content, title: 'Original topic');
          card = result.$2;
          return result.$1;
        }),
      );
      await drive(b.receive(a));
      final overrides = await drive(testOverrides(content: a.library, vocabulary: a.words));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides.where((o) => o.origin != studySetRepositoryProvider),
            studySetRepositoryProvider.overrideWithValue(a.library),
          ],
          child: const MarginMindApp(),
        ),
      );
      final container = ProviderScope.containerOf(tester.element(find.byType(MarginMindApp)));
      container.read(navigationProvider.notifier).openStudySet(id);
      await until(() => container.read(workspaceProvider(id)).content != null, 'workspace');
      final owner = container.read(workspaceProvider(id).notifier);
      debugPrint('SYNC_ACCEPTANCE: edit');
      await drive(owner.beginEditing(card.id));
      await until(() => find.byType(EditableText).evaluate().isNotEmpty, 'inline input');
      final input = find.byType(EditableText).last;
      await tester.enterText(input, 'Local human choice');
      await drive(b.library.update(id, (c) => editor.rename(c, card.id, 'Other device choice')));
      await drive(a.receive(b));
      expect(tester.widget<EditableText>(input).controller.text, 'Local human choice');
      expect((await drive(a.library.load(id))).card(card.id)!.title, 'Original topic');
      debugPrint('SYNC_ACCEPTANCE: save');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      // The desktop inline editor commits on Enter, not an IME action.
      if (container.read(workspaceProvider(id)).editingCardId != null) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await until(() => container.read(workspaceProvider(id)).editingCardId == null, 'saved input');
      debugPrint('SYNC_ACCEPTANCE: await conflicts');
      // Closing the text field precedes asynchronous lease release/reconciliation.
      var status = await drive(a.library.watchContentSync(id).firstWhere((s) => s.conflicts.isNotEmpty));
      expect(status.conflicts, hasLength(1));
      await until(() => find.byKey(const ValueKey('content-sync-open')).evaluate().isNotEmpty, 'sync entry');
      debugPrint('SYNC_ACCEPTANCE: open conflict');
      await tapKey('content-sync-open');
      await until(
        () =>
            find.byType(ContentSyncSheet).evaluate().isNotEmpty &&
            find.byKey(ValueKey('content-sync-use-${status.conflicts.single.id}')).evaluate().isNotEmpty,
        'loaded conflict panel',
      );
      debugPrint('SYNC_ACCEPTANCE: choose conflict');
      final conflict = status.conflicts.single;
      final difference = conflict.changes.firstWhere((d) => d.field == ContentSyncField.title);
      expect(find.text('Local human choice'), findsWidgets);
      expect(find.text('Other device choice'), findsWidgets);
      final useCandidate = difference.candidate == 'Other device choice';
      await tapKey('content-sync-${useCandidate ? 'use' : 'keep'}-${conflict.id}');
      await until(
        () => find.textContaining('No conflicts need a choice.').evaluate().isNotEmpty,
        'saved conflict choice',
      );
      expect((await drive(a.library.load(id))).card(card.id)!.title, 'Other device choice');
      Navigator.of(tester.element(find.byType(ContentSyncSheet))).pop();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );

      debugPrint('SYNC_ACCEPTANCE: undo');
      // This local undo predates the observed remote choice and must not erase it.
      await tapKey('workspace-undo');
      await until(() => container.read(workspaceProvider(id)).historyConflictVersion > 0, 'safe undo conflict');
      expect((await drive(a.library.load(id))).card(card.id)!.title, 'Other device choice');
      await drive(owner.rename(card.id, 'A later local edit'));
      await drive(b.receive(a));
      late Card remoteCard;
      await drive(
        b.library.update(id, (content) {
          final result = editor.addTopic(content, title: 'Unrelated remote addition');
          remoteCard = result.$2;
          return result.$1;
        }),
      );
      await drive(a.receive(b));
      await tapKey('workspace-undo');
      await until(
        () =>
            owner.content.card(card.id)!.title == 'Other device choice' &&
            container.read(workspaceProvider(id)).canRedo,
        'completed independent undo',
      );
      expect(owner.content.card(remoteCard.id)!.title, 'Unrelated remote addition');
      await tapKey('workspace-redo');
      await until(() => owner.content.card(card.id)!.title == 'A later local edit', 'redo');
      expect(owner.content.card(remoteCard.id), isNotNull);
      await drive(b.receive(a));
      expect((await drive(b.library.load(id))).card(card.id)!.title, 'A later local edit');

      debugPrint('SYNC_ACCEPTANCE: settings');
      settings = SyncSettingsController(
        a.library,
        a.words,
        secrets: _NoSecrets(),
        canActivate: true,
        canStoreSecrets: true,
        cloud: () async => throw StateError('No cloud access in this test'),
      );
      debugPrint('SYNC_ACCEPTANCE: initialize settings');
      await drive(settings.initialize());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncSettingsControllerProvider.overrideWithValue(settings)],
          child: MaterialApp(
            theme: MMTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: SyncSettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      debugPrint('SYNC_ACCEPTANCE: rename device');
      await tapKey('sync-rename');
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('sync-rename-input')), matching: find.byType(EditableText)),
        'Native test device',
      );
      await tapKey('sync-rename-save');
      await until(() => settings!.deviceName == 'Native test device' && !settings.busy, 'device name');
      debugPrint('SYNC_ACCEPTANCE: cache');
      await tapKey('sync-cache-inspect');
      await until(() => settings!.cacheUsage != null && !settings.busy, 'cache report');
      expect(settings.failure, isNull);
      expect(settings.target, isNull);
      expect(settings.paused, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      settings = null;
      await drive(a.close());
      debugPrint('SYNC_ACCEPTANCE: restart');
      reopened = _Device(Directory('${root.path}/a'), 'a');
      final restored = await drive(reopened.library.load(id));
      expect(restored.card(card.id)!.title, 'A later local edit');
      expect(restored.card(remoteCard.id)!.title, 'Unrelated remote addition');
      status = await drive(reopened.library.contentSyncStatus(id));
      expect(status.conflicts, isEmpty);
      expect((await drive(FileSyncDevices(reopened.ledger).list())).single.name, 'Native test device');
    } finally {
      await tester.pumpWidget(const SizedBox());
      settings?.dispose();
      if (reopened != null) {
        await drive(reopened.close());
      } else {
        await drive(a.close());
      }
      await drive(b.close());
      await tester.runAsync(() => root.delete(recursive: true));
    }
  });
}
