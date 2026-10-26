import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

ReviewLog log(String id, DateTime at, Rating rating) =>
    ReviewLog(id: id, cardId: 'a', reviewedAt: at, rating: rating, intervalBefore: 0, intervalAfter: 1);

void main() {
  final now = DateTime(2026, 10, 26, 15);

  group('daily', () {
    test('has one entry per day, oldest first, ending today', () {
      final days = ReviewStats.daily(const [], now);
      expect(days.length, 30);
      expect(days.last.day, DateTime(2026, 10, 26));
      expect(days.first.day, DateTime(2026, 9, 27));
      expect(days.every((d) => d.reviewed == 0 && d.retention == null), isTrue);
      expect(ReviewStats.daily(const [], now, days: 7).length, 7);
    });

    test('counts reviews and remembered per local day', () {
      final days = ReviewStats.daily([
        log('1', DateTime(2026, 10, 26, 0, 1), Rating.good),
        log('2', DateTime(2026, 10, 26, 23, 59), Rating.again),
        log('3', DateTime(2026, 10, 26, 9), Rating.hard),
        log('4', DateTime(2026, 10, 25, 23, 59), Rating.easy),
        log('5', DateTime(2026, 9, 27, 8), Rating.good),
        log('6', DateTime(2026, 9, 26, 23, 59), Rating.good),
        log('7', DateTime(2026, 10, 27, 1), Rating.good),
      ], now);
      expect((days.last.reviewed, days.last.remembered), (3, 2));
      expect(days.last.retention, closeTo(2 / 3, 1e-9));
      expect((days[28].reviewed, days[28].remembered), (1, 1));
      expect(days[28].retention, 1);
      expect(days.first.reviewed, 1);
      expect(days.fold<int>(0, (n, d) => n + d.reviewed), 5);
    });

    test('is stable across a daylight saving change', () {
      final days = ReviewStats.daily(const [], DateTime(2026, 11, 2, 12));
      expect(days.map((d) => d.day).toSet().length, 30);
      expect(days.last.day, DateTime(2026, 11, 2));
    });
  });

  test('retention over all logs', () {
    expect(ReviewStats.retention(const []), isNull);
    expect(
      ReviewStats.retention([log('1', now, Rating.again), log('2', now, Rating.good), log('3', now, Rating.easy)]),
      closeTo(2 / 3, 1e-9),
    );
    expect(ReviewStats.remembered(Rating.again), isFalse);
    expect(ReviewStats.remembered(Rating.hard), isTrue);
  });

  group('upcoming', () {
    test('buckets dues by day, folding overdue into today and dropping the far future', () {
      final counts = ReviewStats.upcoming([
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 26, 8),
        DateTime(2026, 10, 26, 23),
        DateTime(2026, 10, 27),
        DateTime(2026, 11, 24, 23),
        DateTime(2026, 11, 25),
      ], now);
      expect(counts.length, 30);
      expect(counts[0], 3);
      expect(counts[1], 1);
      expect(counts[29], 1);
      expect(counts.fold<int>(0, (a, b) => a + b), 5);
    });

    test('content exposes dues of live, reviewable, unsuspended cards only', () {
      Card card(String id, {bool suspended = false, String title = 'x'}) =>
          Card(id: id, kind: CardKind.note, title: title, createdAt: now, suspended: suspended);
      ReviewState state(String id, DateTime due) =>
          ReviewState(cardId: id, due: due, intervalDays: 1, ease: 2.5, reps: 1, lapses: 0, lastReviewedAt: now);
      final content = StudySetContent(
        cards: [
          card('a'),
          card('b', suspended: true),
          card('c', title: ''),
          card('d'),
          card('e'),
        ],
        nodes: const [
          MapNode(cardId: 'a', order: 0),
          MapNode(cardId: 'b', order: 1),
          MapNode(cardId: 'c', order: 2),
          MapNode(cardId: 'd', order: 3),
        ],
        reviews: [
          state('a', DateTime(2026, 10, 28)),
          state('b', DateTime(2026, 10, 28)),
          state('c', DateTime(2026, 10, 28)),
          state('e', DateTime(2026, 10, 28)),
        ],
      );
      expect(content.scheduledDues.toList(), [DateTime(2026, 10, 28)]);
    });
  });
}
