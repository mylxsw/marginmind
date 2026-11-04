import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/app.dart';

import 'helpers.dart';

import 'package:marginmind/features/library/recovery_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

class RecoveryRepository extends InMemoryStudySetRepository implements LibraryRecoveryRepository {
  LibraryRecovery state = LibraryRecovery(enabled: true, entries: [entry()]);
  Object? failure, loadFailure;
  Completer<void>? gate;
  final calls = <(LibraryRecoveryEntry, String)>[];
  static LibraryRecoveryEntry entry({String revision = 'old', String? copy, bool deleted = true}) =>
      LibraryRecoveryEntry(
        studySetId: 'set',
        version: 'version',
        observedRevision: revision,
        title: 'Original',
        deleted: deleted,
        documents: ['Book'],
        cards: 2,
        hasUnresolvedChoices: true,
        copyId: copy,
        preview: ['Retained card'],
      );
  @override
  Future<bool> get libraryRecoveryEnabled async => state.enabled;
  @override
  Future<LibraryRecovery> libraryRecovery() async => state;
  @override
  Stream<LibraryRecovery> watchLibraryRecovery() async* {
    if (loadFailure != null) throw loadFailure!;
    yield state;
  }

  @override
  Future<String> recoverLibraryCopy(LibraryRecoveryEntry selection, {required String title}) async {
    calls.add((selection, title));
    await gate?.future;
    if (failure != null) throw failure!;
    state = LibraryRecovery(enabled: true, entries: [entry(copy: 'copy')]);
    return 'copy';
  }
}

void main() {
  late RecoveryRepository repository;
  setUp(() => repository = RecoveryRepository());
  tearDown(() => repository.dispose());
  Future<void> pump(WidgetTester tester, {String locale = 'en', bool optional = true}) async {
    tester.view.physicalSize = Size(locale == 'zh' ? 390 : 600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [studySetRepositoryProvider.overrideWithValue(optional ? repository : InMemoryStudySetRepository())],
        child: MaterialApp(
          theme: MMTheme.light(),
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) =>
                    TextButton(onPressed: () => showLibraryRecovery(context), child: const Text('Open')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, [String label = 'Recover as a copy']) async {
    await tester.ensureVisible(find.text(label).first);
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  testWidgets('explicit selection preserves title on failure and retry creates one durable copy', (tester) async {
    await pump(tester);
    expect(find.text('Deleted study set'), findsOneWidget);
    await select(tester);
    expect(find.textContaining('unresolved choices'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('recovery-title')), 'My recovery');
    repository.failure = StateError('disk');
    await tester.ensureVisible(find.byKey(const ValueKey('recovery-confirm')));
    await tester.tap(find.byKey(const ValueKey('recovery-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('My recovery'), findsOneWidget);
    expect(find.textContaining('Recovery could not finish'), findsOneWidget);
    repository.failure = null;
    repository.gate = Completer();
    await tester.tap(find.byKey(const ValueKey('recovery-confirm')));
    await tester.pump();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('recovery-confirm'))).onPressed, isNull);
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(repository.calls.map((e) => e.$2), ['My recovery', 'My recovery']);
    expect(find.text('Recovery copy created'), findsWidgets);
    expect(find.byKey(const ValueKey('recovery-confirm')), findsNothing);
  });
  testWidgets('stale choice retains observed version; cancel allows a fresh selection', (tester) async {
    await pump(tester);
    await select(tester);
    repository.state = LibraryRecovery(
      enabled: true,
      entries: [RecoveryRepository.entry(revision: 'new', deleted: false)],
    );
    repository.failure = const ContentSyncActionException(ContentSyncActionFailure.stale);
    await tester.ensureVisible(find.byKey(const ValueKey('recovery-confirm')));
    await tester.tap(find.byKey(const ValueKey('recovery-confirm')));
    await tester.pumpAndSettle();
    expect(repository.calls.single.$1.observedRevision, 'old');
    expect(find.byKey(const ValueKey('recovery-error')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Version containing deleted documents'), findsOneWidget);
    await select(tester);
    repository.failure = null;
    await tester.ensureVisible(find.byKey(const ValueKey('recovery-confirm')));
    await tester.tap(find.byKey(const ValueKey('recovery-confirm')));
    await tester.pumpAndSettle();
    expect(repository.calls.last.$1.observedRevision, 'new');
  });
  testWidgets('load errors retry, empty title does not submit, Chinese copy can be cancelled', (tester) async {
    repository.loadFailure = StateError('read');
    await pump(tester);
    expect(find.text('Retry'), findsOneWidget);
    repository.loadFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await select(tester);
    await tester.enterText(find.byKey(const ValueKey('recovery-title')), ' ');
    await tester.ensureVisible(find.byKey(const ValueKey('recovery-confirm')));
    await tester.tap(find.byKey(const ValueKey('recovery-confirm')));
    await tester.pumpAndSettle();
    expect(repository.calls, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await pump(tester, locale: 'zh');
    await select(tester, '恢复为副本');
    expect(find.text('Original（恢复副本）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty library still exposes recovery and close returns to library', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = (await testOverrides()).where((o) => o.origin != studySetRepositoryProvider);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, studySetRepositoryProvider.overrideWithValue(repository)],
        child: const MarginMindApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-recovery')));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryRecoverySheet), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryRecoverySheet), findsNothing);
  });

  testWidgets('optional local repositories show no invented history', (tester) async {
    await pump(tester, optional: false);
    expect(find.textContaining('No recoverable content'), findsOneWidget);
    expect(find.text('Recover as a copy'), findsNothing);
  });
}
