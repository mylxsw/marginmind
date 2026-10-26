import 'package:meta/meta.dart';

import 'review.dart';

/// Reviews on one calendar day. "Remembered" means any rating but "again".
@immutable
class ReviewDayStat {
  const ReviewDayStat({required this.day, required this.reviewed, required this.remembered});

  /// Local midnight of the day.
  final DateTime day;
  final int reviewed;
  final int remembered;

  /// Share of reviews that were remembered, 0–1; null when nothing was reviewed.
  double? get retention => reviewed == 0 ? null : remembered / reviewed;
}

/// Pure statistics over the review log. Days are local calendar days.
abstract final class ReviewStats {
  static const windowDays = 30;

  static DateTime _dayOf(DateTime t) {
    final local = t.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Whole calendar days from [from] to [to] (DST-safe).
  static int _daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static bool remembered(Rating rating) => rating != Rating.again;

  /// One entry per day for the [days] days ending with the day of [now],
  /// oldest first. Days without reviews are present with zero counts.
  static List<ReviewDayStat> daily(Iterable<ReviewLog> logs, DateTime now, {int days = windowDays}) {
    final today = _dayOf(now);
    final reviewed = List.filled(days, 0);
    final kept = List.filled(days, 0);
    for (final log in logs) {
      final index = days - 1 + _daysBetween(today, _dayOf(log.reviewedAt));
      if (index < 0 || index >= days) continue;
      reviewed[index]++;
      if (remembered(log.rating)) kept[index]++;
    }
    return [
      for (var i = 0; i < days; i++)
        ReviewDayStat(
          day: DateTime(today.year, today.month, today.day - (days - 1 - i)),
          reviewed: reviewed[i],
          remembered: kept[i],
        ),
    ];
  }

  /// Share of all [logs] that were remembered, 0–1; null without logs.
  static double? retention(Iterable<ReviewLog> logs) {
    var total = 0, kept = 0;
    for (final log in logs) {
      total++;
      if (remembered(log.rating)) kept++;
    }
    return total == 0 ? null : kept / total;
  }

  /// Cards falling due on each of the next [days] days starting with today.
  /// Anything already overdue counts for today; later dues are left out.
  static List<int> upcoming(Iterable<DateTime> dues, DateTime now, {int days = windowDays}) {
    final today = _dayOf(now);
    final counts = List.filled(days, 0);
    for (final due in dues) {
      final index = _daysBetween(today, _dayOf(due));
      if (index >= days) continue;
      counts[index < 0 ? 0 : index]++;
    }
    return counts;
  }
}
