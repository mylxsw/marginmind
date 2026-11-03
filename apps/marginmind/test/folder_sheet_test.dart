import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/library/folder_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

class OrganizationRepository extends InMemoryStudySetRepository implements LibraryOrganizationRepository {
  LibraryOrganization state = LibraryOrganization(syncEnabled: true, queued: 2, placements: {'set': null});
  final updates = StreamController<LibraryOrganization>.broadcast();
  Object? failure, loadFailure;
  Completer<void>? gate;
  final actions = <Object>[];
  @override
  Stream<LibraryOrganization> watchOrganization() async* {
    if (loadFailure != null) throw loadFailure!;
    yield state;
    yield* updates.stream;
  }

  void publish(LibraryOrganization next) {
    state = next;
    updates.add(next);
  }

  Future<void> action(Object value) async {
    actions.add(value);
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<Folder> createFolder(String name) async {
    await action(('create', name));
    final folder = Folder(id: 'folder', name: name);
    publish(
      LibraryOrganization(
        entries: [FolderEntry(id: folder.id, revision: 'version', folder: folder)],
      ),
    );
    return folder;
  }

  @override
  Future<void> renameFolder(String id, String name, {required String expectedRevision}) async {
    await action(('rename', id, name, expectedRevision));
    if (state.entries.single.revision != expectedRevision) {
      throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    }
    publish(
      LibraryOrganization(
        entries: [
          FolderEntry(
            id: id,
            revision: 'next',
            folder: Folder(id: id, name: name),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> deleteFolder(String id, {required String expectedRevision}) async {
    await action(('delete', id, expectedRevision));
    publish(LibraryOrganization());
  }

  @override
  Future<void> moveStudySet(String id, String? folderId, {required String? expectedFolderId}) =>
      action(('move', id, folderId, expectedFolderId));
  @override
  Future<void> chooseFolderName(
    String id,
    String transaction, {
    required String expectedRevision,
    required bool useCandidate,
  }) => action(('choose', id, transaction, expectedRevision, useCandidate));
  @override
  Future<void> retryOrganization() => action('retry');
  @override
  Future<void> dispose() async {
    await updates.close();
    await super.dispose();
  }
}

void main() {
  late OrganizationRepository repo;
  setUp(() => repo = OrganizationRepository());
  tearDown(() => repo.dispose());
  final folder = FolderEntry(
    id: 'folder',
    revision: 'observed',
    folder: const Folder(id: 'folder', name: 'Initial'),
  );
  final set = StudySet(
    id: 'set',
    title: 'Study',
    colorIndex: 0,
    createdAt: DateTime.utc(2026),
    lastOpenedAt: DateTime.utc(2026),
  );
  Future<void> pump(
    WidgetTester tester, {
    String locale = 'en',
    double width = 700,
    StudySet? move,
    bool optional = true,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [studySetRepositoryProvider.overrideWithValue(optional ? repo : InMemoryStudySetRepository())],
        child: MaterialApp(
          locale: Locale(locale),
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 600, child: FolderSheet(move: move)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String value) => tester.enterText(
    find.descendant(of: find.byKey(const ValueKey('folder-name')), matching: find.byType(EditableText)),
    value,
  );

  testWidgets('create, rename, cancel and confirm deletion use typed repository actions', (tester) async {
    await pump(tester);
    await type(tester, 'Languages');
    await tap(tester, 'folder-save');
    expect(repo.actions.last, ('create', 'Languages'));
    await tap(tester, 'folder-rename-folder');
    await type(tester, 'Renamed');
    await tap(tester, 'folder-save');
    expect(repo.actions.last, ('rename', 'folder', 'Renamed', 'version'));
    await tap(tester, 'folder-rename-folder');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Create'), findsOneWidget);
    await tap(tester, 'folder-delete-folder');
    expect(find.text('Study sets are kept and shown under Unfiled.'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(repo.actions.last, ('delete', 'folder', 'next'));
  });

  testWidgets('received rename leaves input and observed revision intact', (tester) async {
    repo.state = LibraryOrganization(entries: [folder]);
    await pump(tester);
    await tap(tester, 'folder-rename-folder');
    await type(tester, 'Typed name');
    repo.publish(
      LibraryOrganization(
        entries: [
          FolderEntry(
            id: 'folder',
            revision: 'received',
            folder: const Folder(id: 'folder', name: 'Received name'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'folder-save');
    expect(repo.actions.last, ('rename', 'folder', 'Typed name', 'observed'));
    expect(find.byKey(const ValueKey('folder-error')), findsOneWidget);
    expect(find.text('Typed name'), findsOneWidget);
    expect(repo.state.entries.single.folder!.name, 'Received name');
  });

  testWidgets('names, branches and repairs are visible without displaying internal identifiers', (tester) async {
    repo.state = LibraryOrganization(
      syncEnabled: true,
      queued: 3,
      repairNeeded: true,
      entries: [
        FolderEntry(
          id: 'folder',
          revision: 'version',
          folder: const Folder(id: 'folder', name: 'Current name'),
          choices: [const FolderChoice(transaction: 'private-hash', name: 'Candidate name')],
          problems: [ContentSyncProblem.deletion],
        ),
        FolderEntry(id: 'missing', revision: '', problems: [ContentSyncProblem.missingHistory]),
      ],
    );
    await pump(tester);
    expect(find.textContaining('Candidate name'), findsOneWidget);
    expect(find.textContaining('private-hash'), findsNothing);
    expect(find.text('Folder awaiting recovery'), findsOneWidget);
    for (final use in [true, false]) {
      await tap(tester, 'folder-choice-private-hash-$use');
      expect(repo.actions.last, ('choose', 'folder', 'private-hash', 'version', use));
    }
    await tap(tester, 'folder-retry');
    expect(repo.actions.last, 'retry');
  });

  testWidgets('invalid name, storage failure and saving state retain retryable input', (tester) async {
    await pump(tester);
    await tap(tester, 'folder-save');
    expect(find.text('Enter a folder name with 1–256 characters.'), findsOneWidget);
    repo.failure = StateError('write');
    await type(tester, 'Retained');
    await tap(tester, 'folder-save');
    expect(find.text('Retained'), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-error')), findsOneWidget);
    repo.failure = null;
    repo.gate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('folder-save')));
    await tester.pump();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('folder-save'))).onPressed, isNull);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(repo.state.entries.single.folder!.name, 'Retained');
  });

  testWidgets('Chinese narrow layout reports invalid conflict choice and recovers from load errors', (tester) async {
    repo.loadFailure = StateError('read');
    await pump(tester, locale: 'zh', width: 390);
    repo.loadFailure = null;
    repo.state = LibraryOrganization(syncEnabled: true);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    repo.failure = const ContentSyncActionException(ContentSyncActionFailure.invalidCandidate);
    await tap(tester, 'folder-retry');
    expect(find.byKey(const ValueKey('folder-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('move uses observed membership and failed move keeps the sheet open', (tester) async {
    repo.state = LibraryOrganization(entries: [folder], placements: {'set': 'not-yet-received'});
    repo.failure = StateError('write');
    await pump(tester, move: set);
    await tap(tester, 'folder-move-folder');
    expect(repo.actions.last, ('move', 'set', 'folder', 'not-yet-received'));
    expect(find.byKey(const ValueKey('folder-error')), findsOneWidget);
    repo.publish(LibraryOrganization(entries: [folder], placements: {'set': 'changed-elsewhere'}));
    await tester.pumpAndSettle();
    await tap(tester, 'folder-unfiled');
    expect(repo.actions.last, ('move', 'set', null, 'not-yet-received'));
  });

  testWidgets('unsupported repositories do not gain mutation behavior', (tester) async {
    await pump(tester, optional: false);
    await type(tester, 'Not supported');
    await tap(tester, 'folder-save');
    expect(repo.actions, isEmpty);
  });

  testWidgets('library navigation opens the management sheet and a successful move closes its sheet', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = (await testOverrides()).where((o) => o.origin != studySetRepositoryProvider);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, studySetRepositoryProvider.overrideWithValue(repo)],
        child: const MarginMindApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'manage-folders');
    expect(find.byType(FolderSheet), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(FolderSheet), findsNothing);
    final context = tester.element(find.byKey(const ValueKey('manage-folders')));
    final closed = showFolderSheet(context, move: set);
    await tester.pumpAndSettle();
    await tap(tester, 'folder-unfiled');
    await closed;
    expect(repo.actions.last, ('move', 'set', null, null));
    expect(find.byType(FolderSheet), findsNothing);
  });
}
