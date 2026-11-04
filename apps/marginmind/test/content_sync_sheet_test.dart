import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/content_sync_sheet.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

class SyncRepository extends InMemoryStudySetContentRepository implements ContentSyncRepository {
  ContentSyncStatus status = ContentSyncStatus(enabled: true, revision: 'version', queued: 3);
  final changes = StreamController<ContentSyncStatus>.broadcast();
  final choices = <(String, String, bool)>[];
  final acknowledgements = <String>[];
  int retries = 0;
  Object? actionError;
  Object? loadError;
  Completer<void>? gate;
  @override
  Stream<ContentSyncStatus> watchContentSync(String id) async* {
    if (loadError != null) throw loadError!;
    yield status;
    yield* changes.stream;
  }

  void publish(ContentSyncStatus value) {
    status = value;
    changes.add(value);
  }

  @override
  Future<ContentSyncStatus> contentSyncStatus(String id) async => status;
  Future<void> action() async {
    if (gate != null) await gate!.future;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> chooseContentSync(
    String id,
    String conflict, {
    required String expectedRevision,
    required bool useCandidate,
  }) async {
    choices.add((conflict, expectedRevision, useCandidate));
    await action();
  }

  @override
  Future<void> acknowledgeContentRecovery(String id, String recovery) async {
    acknowledgements.add(recovery);
    await action();
    publish(ContentSyncStatus(enabled: true));
  }

  @override
  Future<void> retryContentSync(String id) async {
    retries++;
    await action();
  }
}

ContentSyncConflict choice({bool valid = true, int concurrentChoices = 0}) => ContentSyncConflict(
  id: 'private-hash',
  concurrentChoices: concurrentChoices,
  canUseCandidate: valid,
  changes: const [
    ContentSyncDifference(
      entity: ContentSyncEntity.card,
      title: 'Study question',
      field: ContentSyncField.text,
      current: 'Current explanation',
      candidate: 'Other device explanation',
    ),
  ],
);

void main() {
  late SyncRepository repo;
  setUp(() => repo = SyncRepository());
  tearDown(() async {
    await repo.changes.close();
  });
  Future<void> pump(
    WidgetTester tester, {
    bool sidebar = false,
    double width = 760,
    String locale = 'en',
    bool optional = true,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [contentRepositoryProvider.overrideWithValue(optional ? repo : InMemoryStudySetContentRepository())],
        child: MaterialApp(
          locale: Locale(locale),
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 680,
                child: sidebar
                    ? const ContentSyncSidebarItem(studySetId: 'set')
                    : const ContentSyncSheet(studySetId: 'set'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.scrollUntilVisible(target, 150, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('concurrent human choices explain the scope of a guarded selection', (tester) async {
    repo.status = ContentSyncStatus(
      enabled: true,
      revision: 'observed-group',
      conflicts: [choice(concurrentChoices: 2)],
    );
    await pump(tester, width: 390, locale: 'zh');
    await tester.tap(find.text('选择说明'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不同设备对同一项修改作出了选择'), findsOneWidget);
    await tap(tester, 'content-sync-use-private-hash');
    expect(repo.choices.single, ('private-hash', 'observed-group', true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('translation choices keep the summary from declaring no conflicts', (tester) async {
    repo.status = ContentSyncStatus(enabled: true, translationConflicts: 2);
    await pump(tester);
    expect(find.textContaining('2 translated paragraphs need a choice'), findsOneWidget);
    expect(find.textContaining('No conflicts need a choice'), findsNothing);
    repo.publish(ContentSyncStatus(enabled: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('No conflicts need a choice'), findsOneWidget);
  });
  testWidgets('optional port keeps local mode quiet; enabled sidebar opens an honest status sheet', (tester) async {
    await pump(tester, sidebar: true, optional: false);
    expect(find.byKey(const ValueKey('content-sync-open')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, sidebar: true);
    await tester.tap(find.byKey(const ValueKey('content-sync-open')));
    await tester.pumpAndSettle();
    expect(
      find.text('Manage saved content and conflicts here. For service delivery status, open Settings → Sync.'),
      findsOneWidget,
    );
    expect(find.text('Saved changes are awaiting service confirmation.'), findsOneWidget);
    expect(find.textContaining('No conflicts need a choice.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final useCandidate in [false, true]) {
    testWidgets('review shows human content and ${useCandidate ? 'apply' : 'keep'} uses the displayed revision', (
      tester,
    ) async {
      repo.status = ContentSyncStatus(enabled: true, revision: 'reviewed-version', conflicts: [choice()]);
      await pump(tester);
      expect(find.text('Current explanation'), findsOneWidget);
      expect(find.text('Other device explanation'), findsOneWidget);
      expect(find.textContaining('private-hash'), findsNothing);
      await tap(tester, 'content-sync-${useCandidate ? 'use' : 'keep'}-private-hash');
      expect(repo.choices.single, ('private-hash', 'reviewed-version', useCandidate));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('stale choice asks for review and retries with the refreshed version', (tester) async {
    repo.status = ContentSyncStatus(enabled: true, revision: 'old', conflicts: [choice()]);
    repo.actionError = const ContentSyncActionException(ContentSyncActionFailure.stale);
    await pump(tester);
    repo.status = ContentSyncStatus(enabled: true, revision: 'new', conflicts: [choice()]);
    await tap(tester, 'content-sync-use-private-hash');
    expect(repo.choices.single.$2, 'old');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('content-sync-error')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Content changed during review.'), findsOneWidget);
    repo.actionError = null;
    await tap(tester, 'content-sync-use-private-hash');
    expect(repo.choices.last.$2, 'new');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('active input and invalid structure disable unsafe choices', (tester) async {
    repo.status = ContentSyncStatus(enabled: true, revision: 'v', editing: true, conflicts: [choice()]);
    await pump(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('content-sync-use-private-hash')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    for (final action in ['keep', 'use']) {
      expect(tester.widget<MMButton>(find.byKey(ValueKey('content-sync-$action-private-hash'))).onPressed, isNull);
    }
    repo.publish(ContentSyncStatus(enabled: true, revision: 'v', conflicts: [choice(valid: false)]));
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('content-sync-use-private-hash'))).onPressed, isNull);
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('content-sync-keep-private-hash'))).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recovery acknowledgement is explicit and failure keeps the notice available', (tester) async {
    repo.status = ContentSyncStatus(enabled: true, recoveryId: 'specific-draft', repairNeeded: true);
    repo.actionError = StateError('disk unavailable');
    await pump(tester);
    await tap(tester, 'content-sync-acknowledge');
    expect(repo.acknowledgements, ['specific-draft']);
    expect(find.byKey(const ValueKey('content-sync-acknowledge')), findsOneWidget);
    expect(find.textContaining('operation could not finish'), findsOneWidget);
    repo.actionError = null;
    await tap(tester, 'content-sync-acknowledge');
    expect(find.byKey(const ValueKey('content-sync-acknowledge')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('busy actions are not duplicated and completing after close is safe', (tester) async {
    repo.gate = Completer<void>();
    await pump(tester);
    await tap(tester, 'content-sync-retry');
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('content-sync-retry'))).onPressed, isNull);
    expect(repo.retries, 1);
    await tester.pumpWidget(const SizedBox());
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('load errors offer a retry and the subscription recovers', (tester) async {
    repo.loadError = StateError('unreadable');
    await pump(tester);
    expect(find.textContaining('Sync information could not be read.'), findsOneWidget);
    repo.loadError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content-sync-status')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow Chinese review stacks both versions and preserves branch warnings', (tester) async {
    repo.status = ContentSyncStatus(
      enabled: true,
      revision: 'v',
      conflicts: [choice()],
      problems: [ContentSyncProblem.missingHistory, ContentSyncProblem.concurrentChoices],
    );
    await pump(tester, width: 360, locale: 'zh');
    await tester.scrollUntilVisible(
      find.text('Other device explanation'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.getTopLeft(find.text('Other device explanation')).dy,
      greaterThan(tester.getTopLeft(find.text('Current explanation')).dy),
    );
    await tap(tester, 'content-sync-keep-private-hash');
    expect(repo.choices.single.$3, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
