import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/review/review_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

class SavingReviews extends InMemoryStudySetContentRepository {
  SavingReviews() : super({'demo-1': demoContent()});
  Completer<void>? gate;
  Object? error;
  int calls = 0;
  bool deleteBeforeRating = false;
  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) async {
    calls++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    if (deleteBeforeRating) await super.update(id, (_) => StudySetContent.empty);
    return super.update(id, change);
  }
}

void main() {
  testWidgets('a failed score keeps the revealed card and retry saves exactly once', (tester) async {
    final repo = SavingReviews()..error = StateError('disk full');
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).startReview('demo-1');
    await tester.pumpAndSettle();
    final provider = reviewSessionProvider('demo-1'),
        controller = container.read(reviewSessionProvider('demo-1').notifier);
    controller.reveal();
    await tester.pumpAndSettle();
    final id = container.read(provider).currentId;
    await controller.rate(Rating.good);
    await tester.pumpAndSettle();
    expect(container.read(provider).currentId, id);
    expect(container.read(provider).reviewed, 0);
    expect(find.byKey(const ValueKey('review-save-problem')), findsOneWidget);
    expect((await repo.load('demo-1')).reviewLogs, isEmpty);
    repo.error = null;
    await controller.rate(Rating.good);
    await tester.pumpAndSettle();
    expect(container.read(provider).reviewed, 1);
    expect((await repo.load('demo-1')).reviewLogs, hasLength(1));
    expect(find.byKey(const ValueKey('review-save-problem')), findsNothing);
  });

  for (final problem in [ReviewSaveProblem.awaitingBaseline, ReviewSaveProblem.editing]) {
    testWidgets('$problem is explained without advancing the review queue', (tester) async {
      final repo = SavingReviews()..error = ReviewWriteUnavailable(problem);
      final container = await pumpApp(tester, content: repo);
      container.read(navigationProvider.notifier).startReview('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(reviewSessionProvider('demo-1').notifier);
      controller.reveal();
      await controller.rate(Rating.good);
      await tester.pumpAndSettle();
      expect(container.read(reviewSessionProvider('demo-1')).saveProblem, problem);
      expect(
        find.textContaining(problem == ReviewSaveProblem.editing ? 'Finish the current' : 'Earlier review history'),
        findsOneWidget,
      );
    });
  }

  testWidgets('repeated input during save records one rating and reopening a scope is not advanced by old completion', (
    tester,
  ) async {
    final repo = SavingReviews()..gate = Completer<void>();
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).startReview('demo-1');
    await tester.pumpAndSettle();
    final provider = reviewSessionProvider('demo-1'),
        controller = container.read(reviewSessionProvider('demo-1').notifier);
    controller.reveal();
    final saving = controller.rate(Rating.good);
    await controller.rate(Rating.easy);
    expect(repo.calls, 1);
    expect(container.read(provider).saving, isTrue);
    await tester.pump();
    final rating = find.descendant(of: find.byKey(const ValueKey('rate-good')), matching: find.byType(MMInteractive));
    expect(tester.widget<MMInteractive>(rating).onTap, isNull);
    controller.startScope();
    repo.gate!.complete();
    await saving;
    await tester.pumpAndSettle();
    expect(container.read(provider).index, 0);
    expect(container.read(provider).reviewed, 0);
    expect((await repo.load('demo-1')).reviewLogs, hasLength(1));
  });

  testWidgets('a rebuilt session is not advanced by the previous save completion', (tester) async {
    final repo = SavingReviews()..gate = Completer<void>();
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).startReview('demo-1');
    await tester.pumpAndSettle();
    final provider = reviewSessionProvider('demo-1');
    final controller = container.read(provider.notifier);
    controller.reveal();
    final saving = controller.rate(Rating.good);
    container.invalidate(provider);
    await tester.pump();
    repo.gate!.complete();
    await saving;
    await tester.pumpAndSettle();
    expect(container.read(provider).reviewed, 0);
    expect(container.read(provider).saving, isFalse);
    expect((await repo.load('demo-1')).reviewLogs, hasLength(1));
  });

  testWidgets('closing the review during a save does not access a disposed session', (tester) async {
    final repo = SavingReviews()..gate = Completer<void>();
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).startReview('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(reviewSessionProvider('demo-1').notifier);
    controller.reveal();
    final saving = controller.rate(Rating.good);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    repo.gate!.complete();
    await saving;
    expect((await repo.load('demo-1')).reviewLogs, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone retains the card and readable failure message', (tester) async {
    final repo = SavingReviews()..error = StateError('full');
    final container = await pumpApp(
      tester,
      content: repo,
      size: const Size(360, 780),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).startReview('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(reviewSessionProvider('demo-1').notifier);
    controller.reveal();
    await controller.rate(Rating.good);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-save-problem')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));

  testWidgets('a deleted card is skipped without fabricating a rating', (tester) async {
    final repo = SavingReviews()..deleteBeforeRating = true;
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).startReview('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(reviewSessionProvider('demo-1').notifier);
    controller.reveal();
    await controller.rate(Rating.good);
    await tester.pumpAndSettle();
    expect(container.read(reviewSessionProvider('demo-1')).reviewed, 0);
    expect((await repo.load('demo-1')).reviewLogs, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
