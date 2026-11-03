import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/vocabulary_controller.dart';
import 'package:marginmind/features/vocabulary/vocabulary_screen.dart';
import 'package:marginmind/features/vocabulary/vocabulary_sync.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

VocabularyEntry word({String note = 'old'}) => VocabularyEntry(
  id: 'word-id',
  term: 'Word',
  language: 'en',
  kind: VocabularyKind.word,
  forms: ['word'],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  note: note,
);

class Lease implements ContentEditLease {
  Lease(this.ready);
  @override
  final Future<void> ready;
  bool released = false;
  @override
  Future<void> release() async {
    released = true;
  }
}

class SyncVocabulary extends InMemoryVocabularyRepository
    implements VocabularySyncRepository, VocabularyEditRepository, VocabularyIdentityRepository {
  @override
  Future<String?> resolveVocabularyEntryId(String id) async => id == 'legacy-id' ? 'word-id' : null;
  VocabularySyncState status = VocabularySyncState(enabled: true);
  final events = StreamController<VocabularySyncState>.broadcast();
  final choices = <(String, VocabularySyncField, String, String)>[];
  Object? loadError, actionError;
  Completer<void>? actionGate, inputGate, saveGate;
  Lease? lease;
  bool failSave = false;
  int retries = 0;
  @override
  ContentEditLease protectVocabulary(String id) => lease = Lease(inputGate?.future ?? Future.value());
  @override
  Future<void> save(List<VocabularyEntry> entries) async {
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('save failed');
    await super.save(entries);
  }

  @override
  Future<VocabularySyncState> vocabularySyncState() async => status;
  @override
  Stream<VocabularySyncState> watchVocabularySync() async* {
    if (loadError != null) throw loadError!;
    yield status;
    yield* events.stream;
  }

  Future<void> action() async {
    if (actionGate != null) await actionGate!.future;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> chooseVocabulary(
    String id,
    VocabularySyncField field,
    String choice, {
    required String expectedRevision,
  }) async {
    choices.add((id, field, choice, expectedRevision));
    await action();
  }

  @override
  Future<void> retryVocabularySync() async {
    retries++;
    await action();
  }
}

VocabularySyncConflict conflict({String revision = 'observed', VocabularySyncField field = VocabularySyncField.note}) =>
    VocabularySyncConflict(
      entryId: 'word-id',
      term: 'Word',
      revision: revision,
      field: field,
      choices: const [VocabularySyncChoice('private-a', 'Local text'), VocabularySyncChoice('private-b', 'Other text')],
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncVocabulary repo;
  setUp(() {
    repo = SyncVocabulary();
  });
  tearDown(() async {
    await repo.events.close();
  });
  Future<void> pump(WidgetTester tester, {bool detail = false, bool optional = true, String locale = 'en'}) async {
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (detail) await repo.save([word()]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(vocabulary: optional ? repo : InMemoryVocabularyRepository()),
        child: MaterialApp(
          theme: MMTheme.light(),
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MMHudHost(
            child: Scaffold(body: detail ? VocabularyDetail(entry: word()) : const VocabularySyncButton()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!detail && optional) {
      await tester.tap(find.byKey(const ValueKey('vocabulary-sync-open')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('old word links resolve to the canonical detail on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await repo.save([word()]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(vocabulary: repo),
        child: MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: VocabularyScreen(
              route: VocabularyRoute(entryId: 'legacy-id', returnTo: LibraryRoute()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyDetail), findsOneWidget);
    expect(tester.widget<VocabularyDetail>(find.byType(VocabularyDetail)).entry.id, 'word-id');
    tester.view.physicalSize = const Size(1100, 850);
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(vocabulary: repo),
        child: MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: VocabularyScreen(
              key: ValueKey('unresolved'),
              route: VocabularyRoute(entryId: 'ambiguous-id', returnTo: LibraryRoute()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyDetail), findsNothing); // Never guess the first word on desktop.
  });

  final pick = find.byKey(const ValueKey('word-choice-word-id-note-private-b'));
  testWidgets('human candidates use the displayed revision and failed choices can retry', (tester) async {
    repo.status = VocabularySyncState(enabled: true, conflicts: [conflict()]);
    repo.actionError = const ContentSyncActionException(ContentSyncActionFailure.stale);
    await pump(tester);
    expect(find.text('Local text'), findsOneWidget);
    expect(find.text('Other text'), findsOneWidget);
    expect(find.textContaining('private-a'), findsNothing);
    repo.status = VocabularySyncState(enabled: true, conflicts: [conflict(revision: 'latest')]);
    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(repo.choices.single.$4, 'observed');
    expect(find.textContaining('Content changed during review.'), findsOneWidget);
    repo.actionError = null;
    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(repo.choices.last.$4, 'latest');
  });
  testWidgets('editing disables choices; deletion and learning choices have human labels', (tester) async {
    repo.status = VocabularySyncState(
      enabled: true,
      editingEntries: ['word-id'],
      conflicts: [
        conflict(),
        VocabularySyncConflict(
          entryId: 'deleted',
          term: 'Removed word',
          revision: 'v',
          field: VocabularySyncField.alive,
          choices: const [
            VocabularySyncChoice('yes', 'true', deleted: false),
            VocabularySyncChoice('no', 'false', deleted: true),
          ],
        ),
        VocabularySyncConflict(
          entryId: 'status',
          term: 'Known word',
          revision: 'v',
          field: VocabularySyncField.status,
          choices: const [VocabularySyncChoice('known', 'known'), VocabularySyncChoice('learning', 'learning')],
        ),
      ],
    );
    await pump(tester, locale: 'zh');
    expect(tester.widget<MMButton>(pick).onPressed, isNull);
    expect(find.text('保留这个词条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('load and repair failures retain retry and busy actions are not duplicated', (tester) async {
    repo.loadError = StateError('read');
    await pump(tester);
    repo.loadError = null;
    repo.status = VocabularySyncState(
      enabled: true,
      repairNeeded: true,
      retryFailed: true,
      problems: [ContentSyncProblem.invalidHistory],
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    repo.actionGate = Completer<void>();
    final retry = find.byKey(const ValueKey('vocabulary-sync-retry'));
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(retry).onPressed, isNull);
    expect(repo.retries, 1);
    await tester.pumpWidget(const SizedBox());
    repo.actionGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final error in [const ContentSyncActionException(ContentSyncActionFailure.editing), StateError('disk')]) {
    testWidgets('action error $error is visible without discarding choices', (tester) async {
      repo.status = VocabularySyncState(enabled: true, conflicts: [conflict()]);
      repo.actionError = error;
      await pump(tester);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vocabulary-sync-error')), findsOneWidget);
      expect(pick, findsOneWidget);
    });
  }
  testWidgets('optional repositories keep local vocabulary quiet', (tester) async {
    await pump(tester, optional: false);
    expect(find.byKey(const ValueKey('vocabulary-sync-open')), findsNothing);
  });
  testWidgets('focused input waits for repository barrier and rereads content before typing', (tester) async {
    repo.inputGate = Completer<void>();
    await pump(tester, detail: true);
    final note = find.byKey(const ValueKey('vocabulary-note'));
    await tester.ensureVisible(note);
    await tester.tap(note);
    await tester.pump();
    expect(tester.widget<MMTextField>(note).readOnly, isTrue);
    await repo.save([word(note: 'Arrived before barrier')]);
    repo.inputGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<MMTextField>(note).controller!.text, 'Arrived before barrier');
    expect(tester.widget<MMTextField>(note).readOnly, isFalse);
    await tester.enterText(note, 'Typed');
    await tester.pumpAndSettle();
    expect((await repo.load()).single.note, 'Typed');
    final lease = repo.lease!;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(lease.released, isTrue);
  });
  testWidgets('failed input keeps its buffer and lease until a successful retry; disposal waits for save', (
    tester,
  ) async {
    await pump(tester, detail: true);
    final note = find.byKey(const ValueKey('vocabulary-note'));
    await tester.ensureVisible(note);
    await tester.tap(note);
    await tester.pumpAndSettle();
    repo.failSave = true;
    await tester.enterText(note, 'Unsaved');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(repo.lease!.released, isFalse);
    expect(tester.widget<MMTextField>(note).controller!.text, 'Unsaved');
    repo.failSave = false;
    final gloss = find.byKey(const ValueKey('vocabulary-gloss'));
    await tester.ensureVisible(gloss);
    await tester.enterText(gloss, 'ok');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(repo.lease!.released, isFalse); // A different field did not save the failed note.
    expect(tester.widget<MMTextField>(note).controller!.text, 'Unsaved');
    repo.saveGate = Completer<void>();
    await tester.tap(note);
    await tester.enterText(note, 'Retried');
    await tester.pump();
    final lease = repo.lease!;
    await tester.pumpWidget(const SizedBox());
    expect(lease.released, isFalse);
    repo.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(lease.released, isTrue);
    expect((await repo.load()).single.note, 'Retried');
  });
  test('real sync repository gives controller canonical receipts and conditional undo', () async {
    final root = await Directory.systemTemp.createTemp('vocabulary-controller-');
    final ledger = FileSyncLedger(root, libraryId: 'lib', deviceId: 'a');
    final real = FileVocabularyStore(root, sync: ledger);
    final container = ProviderContainer(overrides: await testOverrides(vocabulary: real));
    try {
      await container.read(vocabularyProvider.future);
      final controller = container.read(vocabularyProvider.notifier);
      final receipt = await controller.edit((_) => [word()]);
      expect((await real.load()).single.id, startsWith('word-'));
      expect((await real.load()).single.id, isNot('word-id'));
      await controller.undo(receipt);
      expect(await real.load(), isEmpty);
      await controller.edit((_) => [word()]);
      final edit = await controller.edit((e) => [e.single.copyWith(note: 'edit')]);
      await real.updateVocabulary((e) => [e.single.copyWith(note: 'later')]);
      await expectLater(controller.undo(edit), throwsA(isA<ContentSyncActionException>()));
      expect((await real.load()).single.note, 'later');
    } finally {
      container.dispose();
      await real.dispose();
      await root.delete(recursive: true);
    }
  });
  test('an identical remote contribution invalidates an older undo receipt', () async {
    final root = await Directory.systemTemp.createTemp('word-undo-');
    final ledger = FileSyncLedger(root, libraryId: 'lib', deviceId: 'a');
    final real = FileVocabularyStore(root, sync: ledger);
    final container = ProviderContainer(overrides: await testOverrides(vocabulary: real));
    try {
      await container.read(vocabularyProvider.future);
      final controller = container.read(vocabularyProvider.notifier);
      final receipt = await controller.edit((_) => [word()]);
      final displayed = (await real.load()).single.toJson();
      final base = vocabularyBaseline('lib', 'en', 'word');
      final remote = SyncCommit.create(
        libraryId: 'lib',
        scope: base.scope,
        deviceId: 'other',
        sequence: 1,
        parents: [base.id],
        payload: VocabularyWord.fromJson(base.payload)
            .edit(null, word(), deviceId: 'other', operation: 'copy')
            .toJson(),
      );
      await real.receiveSync([remote]);
      expect((await real.load()).single.toJson(), displayed);
      await expectLater(controller.undo(receipt), throwsA(isA<ContentSyncActionException>()));
      expect(await real.load(), hasLength(1));
    } finally {
      container.dispose();
      await real.dispose();
      await root.delete(recursive: true);
    }
  });
}
