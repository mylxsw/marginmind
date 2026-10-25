import 'dart:math' as math;

import 'package:meta/meta.dart';

/// How well the user recalled a card.
enum Rating { again, hard, good, easy }

/// Spaced-repetition state of one card. Cards without a state are "new".
@immutable
class ReviewState {
  const ReviewState({
    required this.cardId,
    required this.due,
    required this.intervalDays,
    required this.ease,
    required this.reps,
    required this.lapses,
    required this.lastReviewedAt,
  });

  final String cardId;
  final DateTime due;

  /// Current interval; 0 while (re)learning.
  final double intervalDays;

  /// Interval multiplier for "good" (SM-2 ease factor).
  final double ease;

  /// Successful reviews in a row.
  final int reps;
  final int lapses;
  final DateTime lastReviewedAt;

  Map<String, Object?> toJson() => {
    'cardId': cardId,
    'due': due.toIso8601String(),
    'interval': intervalDays,
    'ease': ease,
    'reps': reps,
    'lapses': lapses,
    'last': lastReviewedAt.toIso8601String(),
  };

  factory ReviewState.fromJson(Map<String, Object?> j) => ReviewState(
    cardId: j['cardId'] as String,
    due: DateTime.parse(j['due'] as String),
    intervalDays: (j['interval'] as num).toDouble(),
    ease: (j['ease'] as num).toDouble(),
    reps: j['reps'] as int,
    lapses: j['lapses'] as int,
    lastReviewedAt: DateTime.parse(j['last'] as String),
  );
}

/// A simplified SM-2 scheduler. "Again" brings the card back in ten minutes
/// (so it returns in the same session); the other ratings grow the interval.
abstract final class ReviewScheduler {
  static const initialEase = 2.5;
  static const minEase = 1.3;
  static const relearnDelay = Duration(minutes: 10);

  /// New cards introduced per study set per session.
  static const newPerSession = 20;

  static ReviewState rate(String cardId, ReviewState? s, Rating rating, DateTime now) {
    final ease = s?.ease ?? initialEase;
    final interval = s?.intervalDays ?? 0;
    final reps = s?.reps ?? 0;
    final lapses = s?.lapses ?? 0;

    ReviewState next(double days, double newEase, int newReps, int newLapses, {Duration? delay}) => ReviewState(
      cardId: cardId,
      due: now.add(delay ?? _days(days)),
      intervalDays: days,
      ease: newEase.clamp(minEase, 3.5),
      reps: newReps,
      lapses: newLapses,
      lastReviewedAt: now,
    );

    switch (rating) {
      case Rating.again:
        return next(0, ease - 0.2, 0, reps > 0 ? lapses + 1 : lapses, delay: relearnDelay);
      case Rating.hard:
        // A new card rated "hard" comes back later today, before "good".
        final days = reps == 0 ? 0.5 : math.max(1.0, interval * 1.2);
        return next(days, ease - 0.15, reps + 1, lapses);
      case Rating.good:
        final days = switch (reps) {
          0 => 1.0,
          1 => 3.0,
          _ => math.max(interval + 1, interval * ease),
        };
        return next(days, ease, reps + 1, lapses);
      case Rating.easy:
        final days = reps == 0 ? 4.0 : math.max(interval + 2, interval * ease * 1.3);
        return next(days, ease + 0.15, reps + 1, lapses);
    }
  }

  /// When the card would be due after each rating (for button labels).
  static Map<Rating, Duration> preview(String cardId, ReviewState? s, DateTime now) => {
    for (final r in Rating.values) r: rate(cardId, s, r, now).due.difference(now),
  };

  static Duration _days(double days) => Duration(minutes: (days * 24 * 60).round());
}
