import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

class Titles extends InMemoryStudySetRepository implements StudySetTitleRepository {
  String title = 'Latest', revision = 'v1';
  Future<void> barrier = Future.value();
  bool failRead = false, failWrite = false;
  @override
  Future<StudySetTitle> titleForEditing(String id) async {
    await barrier;
    if (failRead) throw StateError('read failed');
    return StudySetTitle(title, revision);
  }

  @override
  Future<void> renameObserved(String id, String value, {required String expectedRevision}) async {
    if (expectedRevision != revision) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    if (failWrite) throw StateError('write refused');
    title = value;
  }
}

void main() {
  Future<void> host(WidgetTester tester, StudySetRepository repo, StudySet set) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...(await testOverrides()).where((o) => o.origin != studySetRepositoryProvider),
          studySetRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showStudySetRenameSheet(context, ref, set),
                child: const Text('Rename set'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('title reads after a barrier, preserves failed input and retries the same observation', (tester) async {
    final repo = Titles(), gate = Completer<void>();
    final set = await repo.create(const NewStudySet(title: 'Stale list', colorIndex: 0));
    repo.barrier = gate.future;
    await host(tester, repo, set);
    await tester.tap(find.text('Rename set'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Mine');
    repo.failWrite = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Mine'), findsOneWidget);
    repo.failWrite = false;
    repo.revision = 'v2';
    repo.title = 'Remote';
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Mine'), findsOneWidget);
    expect(repo.title, 'Remote');
    expect(find.textContaining('Cancel and reopen Rename'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename set'));
    await tester.pumpAndSettle();
    expect(find.text('Remote'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Chosen');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.title, 'Chosen');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('unreadable metadata does not open a stale form', (tester) async {
    final repo = Titles()..failRead = true;
    final set = await repo.create(const NewStudySet(title: 'Old', colorIndex: 0));
    await host(tester, repo, set);
    await tester.tap(find.text('Rename set'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('local repositories without the optional port keep rename behavior', (tester) async {
    final repo = InMemoryStudySetRepository();
    final set = await repo.create(const NewStudySet(title: 'Local', colorIndex: 0));
    await host(tester, repo, set);
    await tester.tap(find.text('Rename set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final latest = await tester.runAsync(() => repo.watchAll().first);
    expect(latest!.single.title, 'Renamed');
  });
}
