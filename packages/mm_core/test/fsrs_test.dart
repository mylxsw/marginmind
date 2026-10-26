import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

// Official FSRS-5 fixtures: ts-fsrs v4.5.2, __tests__/FSRSV5.test.ts.
// Copyright (c) 2024 Open Spaced Repetition; third_party/ts-fsrs-LICENSE.
void main() {
  final start = DateTime.utc(2022, 12, 29, 12, 30);
  test('official first repeat', () {
    final difficulties = [7.1949, 6.48830527, 5.28243442, 3.22450159];
    for (final rating in Rating.values) {
      final result = ReviewScheduler.schedule('a', null, rating, start);
      expect(result.memory.stability, FsrsParameters.defaultWeights[rating.index]);
      expect(result.memory.difficulty, closeTo(difficulties[rating.index], 1e-8));
      expect(result.review.intervalDays, [0, 0, 0, 16][rating.index]);
      expect(
        result.review.due.difference(start),
        [
          const Duration(minutes: 1),
          const Duration(minutes: 5),
          const Duration(minutes: 10),
          const Duration(days: 16),
        ][rating.index],
      );
    }
  });
  test('official interval history', () {
    ReviewState? review;
    MemoryState? memory;
    var now = start;
    final intervals = <double>[];
    for (final rating in [...List.filled(6, Rating.good), Rating.again, Rating.again, ...List.filled(5, Rating.good)]) {
      final result = ReviewScheduler.schedule('a', review, rating, now, memory: memory);
      review = result.review;
      memory = result.memory;
      intervals.add(review.intervalDays);
      now = review.due;
    }
    expect(intervals, [0, 4, 14, 44, 125, 328, 0, 0, 7, 16, 34, 71, 142]);
  });
  test('official memory history', () {
    ReviewState? review;
    MemoryState? memory;
    var now = start;
    final elapsed = [0, 0, 1, 3, 8, 21];
    for (var i = 0; i < elapsed.length; i++) {
      final result = ReviewScheduler.schedule('a', review, i == 0 ? Rating.again : Rating.good, now, memory: memory);
      review = result.review;
      memory = result.memory;
      now = now.add(Duration(days: elapsed[i]));
    }
    final next = ReviewScheduler.schedule('a', review, Rating.good, now, memory: memory);
    expect(next.memory.stability, closeTo(48.4848, .00005));
    expect(next.memory.difficulty, closeTo(7.0866, .00005));
  });
  test('all phases/ratings, preview parity, custom parameters and caps', () {
    for (final phase in MemoryPhase.values) {
      final memory = MemoryState(cardId: 'a', stability: 10, difficulty: 5, phase: phase);
      final review = ReviewState(
        cardId: 'a',
        due: start,
        intervalDays: 10,
        ease: 2.5,
        reps: 5,
        lapses: 2,
        lastReviewedAt: start.subtract(const Duration(days: 10)),
      );
      for (final p in [FsrsParameters.defaults, FsrsParameters(retention: .95, maximumInterval: 3)]) {
        final previews = ReviewScheduler.preview('a', review, start, memory: memory, parameters: p);
        for (final rating in Rating.values) {
          final result = ReviewScheduler.schedule('a', review, rating, start, memory: memory, parameters: p);
          expect(result.review.due.difference(start), previews[rating]);
          expect(result.review.intervalDays, lessThanOrEqualTo(p.maximumInterval));
          expect(result.memory.stability, greaterThanOrEqualTo(.01));
          expect(result.memory.difficulty, inInclusiveRange(1, 10));
          expect(result.review.lapses, phase == MemoryPhase.review && rating == Rating.again ? 3 : 2);
        }
      }
    }
  });
  test('whole parameter set is copied, validated and used', () {
    final weights = [...FsrsParameters.defaultWeights]..[3] = 20;
    final p = FsrsParameters(weights: weights);
    weights[3] = 40;
    expect(ReviewScheduler.rate('a', null, Rating.easy, start, parameters: p).intervalDays, 20);
    expect(() => p.weights[0] = 3, throwsUnsupportedError);
    expect(() => FsrsParameters(weights: [1]), throwsArgumentError);
    expect(() => FsrsParameters(weights: [...weights]..[3] = double.nan), throwsArgumentError);
    expect(() => FsrsParameters(retention: 1), throwsArgumentError);
    expect(() => FsrsParameters(maximumInterval: 0), throwsArgumentError);
  });
  test('legacy initializer preserves due/logs, is idempotent, respects existing memory', () {
    ReviewState legacy(double interval, double ease, int lapses) => ReviewState(
      cardId: 'a',
      due: start,
      intervalDays: interval,
      ease: ease,
      reps: 3,
      lapses: lapses,
      lastReviewedAt: start,
    );
    final old = legacy(30, 2.5, 0);
    final c = StudySetContent(reviews: [old]);
    final initialized = StudySetEditor.initializeMemory(c);
    expect(initialized.reviews, c.reviews);
    expect(initialized.reviewLogs, c.reviewLogs);
    expect(initialized.memoryOf('a')!.stability, 30);
    expect(initialized.memoryOf('a')!.difficulty, 5);
    expect(StudySetEditor.initializeMemory(initialized), same(initialized));
    expect(ReviewScheduler.fromLegacy(legacy(0, 1.3, 20)).phase, MemoryPhase.relearning);
    expect(ReviewScheduler.fromLegacy(legacy(0, 1.3, 20)).difficulty, greaterThan(5));
    expect(ReviewScheduler.fromLegacy(legacy(30, 3.5, 0)).difficulty, lessThan(5));
    expect(ReviewScheduler.rate('a', old, Rating.good, start).due.isAfter(start), isTrue);
  });
}
