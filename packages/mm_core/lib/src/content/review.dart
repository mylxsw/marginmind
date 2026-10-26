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

/// Persisted FSRS phase. Scheduling policy is supplied by the scheduler.
enum MemoryPhase { learning, review, relearning }

/// Optional FSRS state, separate from the legacy schedule. Absence means the
/// card has not been initialized by FSRS; migration never guesses these values.
@immutable
class MemoryState {
  const MemoryState({
    required this.cardId,
    required this.stability,
    required this.difficulty,
    required this.phase,
    this.learningStep = 0,
  });

  final String cardId;

  /// Stability in days.
  final double stability;
  final double difficulty;
  final MemoryPhase phase;
  final int learningStep;

  Map<String, Object?> toJson() => {
    'cardId': cardId,
    'stability': stability,
    'difficulty': difficulty,
    'phase': phase.name,
    'learningStep': learningStep,
  };

  factory MemoryState.fromJson(Map<String, Object?> j) => MemoryState(
    cardId: j['cardId'] as String,
    stability: (j['stability'] as num).toDouble(),
    difficulty: (j['difficulty'] as num).toDouble(),
    phase: MemoryPhase.values.byName(j['phase'] as String),
    learningStep: j['learningStep'] as int,
  );
}

/// One actual rating (previews never append entries). Intervals use the same
/// days/zero-for-relearning convention as ReviewState.intervalDays.
@immutable
class ReviewLog {
  const ReviewLog({
    required this.id,
    required this.cardId,
    required this.reviewedAt,
    required this.rating,
    required this.intervalBefore,
    required this.intervalAfter,
  });

  final String id;
  final String cardId;
  final DateTime reviewedAt;
  final Rating rating;
  final double intervalBefore;
  final double intervalAfter;

  Map<String, Object?> toJson() => {
    'id': id,
    'cardId': cardId,
    'reviewedAt': reviewedAt.toIso8601String(),
    'rating': rating.name,
    'intervalBefore': intervalBefore,
    'intervalAfter': intervalAfter,
  };

  factory ReviewLog.fromJson(Map<String, Object?> j) => ReviewLog(
    id: j['id'] as String,
    cardId: j['cardId'] as String,
    reviewedAt: DateTime.parse(j['reviewedAt'] as String),
    rating: Rating.values.byName(j['rating'] as String),
    intervalBefore: (j['intervalBefore'] as num).toDouble(),
    intervalAfter: (j['intervalAfter'] as num).toDouble(),
  );
}

/// Immutable, replaceable FSRS-5 parameter set. No optimizer or IO lives here.
@immutable
class FsrsParameters {
  FsrsParameters({List<double> weights = defaultWeights, this.retention = .9, this.maximumInterval = 36500})
    : weights = List.unmodifiable(weights) {
    if (weights.length != 19 ||
        weights.any((w) => !w.isFinite || w < 0) ||
        weights.take(4).any((w) => w < .01) ||
        weights[7] > 1 ||
        !retention.isFinite ||
        retention <= 0 ||
        retention >= 1 ||
        maximumInterval < 1) {
      throw ArgumentError('Invalid FSRS-5 parameters');
    }
  }

  static const defaultWeights = <double>[
    .40255,
    1.18385,
    3.173,
    15.69105,
    7.1949,
    .5345,
    1.4604,
    .0046,
    1.54575,
    .1192,
    1.01925,
    1.9395,
    .11,
    .29605,
    2.2698,
    .2315,
    2.9898,
    .51655,
    .6621,
  ];
  static final defaults = FsrsParameters();
  final List<double> weights;
  final double retention;
  final int maximumInterval;
}

/// FSRS-5, with deterministic steps from ts-fsrs v4.5.2 (fuzz disabled).
/// See third_party/ts-fsrs-LICENSE and docs/evidence/gul-508/README.md.
abstract final class ReviewScheduler {
  static const initialEase = 2.5;
  static const minEase = 1.3;
  static const relearnDelay = Duration(minutes: 5);
  static const newPerSession = 20;
  static double _round(double n) => double.parse(n.toStringAsFixed(8));
  static double _stability(double n) => _round(n.clamp(.01, 36500));

  /// Approximation, not recovered history: at 90% retention stability equals
  /// the old interval. Ease maps inversely to difficulty; lapses increase it.
  /// A failed legacy card starts relearning. This never changes its due date.
  static MemoryState fromLegacy(ReviewState s) => MemoryState(
    cardId: s.cardId,
    stability: s.intervalDays > 0 ? s.intervalDays.clamp(.01, 36500) : FsrsParameters.defaultWeights[0],
    difficulty: (5 + (initialEase - s.ease) * 2 + math.log(1 + math.max(0, s.lapses))).clamp(1, 10),
    phase: s.intervalDays <= 0 ? MemoryPhase.relearning : MemoryPhase.review,
  );

  static ReviewState rate(
    String cardId,
    ReviewState? s,
    Rating rating,
    DateTime now, {
    MemoryState? memory,
    FsrsParameters? parameters,
  }) => schedule(cardId, s, rating, now, memory: memory, parameters: parameters).review;

  /// Both outputs must be committed together with one ReviewLog.
  static ({ReviewState review, MemoryState memory}) schedule(
    String cardId,
    ReviewState? s,
    Rating rating,
    DateTime now, {
    MemoryState? memory,
    FsrsParameters? parameters,
  }) {
    final p = parameters ?? FsrsParameters.defaults;
    final w = p.weights;
    final old = memory ?? (s == null ? null : fromLegacy(s));
    final g = rating.index + 1;
    double initialDifficulty(int grade) => _round(w[4] - math.exp((grade - 1) * w[5]) + 1).clamp(1, 10);
    double short(double stability, int grade) => _stability(stability * math.exp(w[17] * (grade - 3 + w[18])));
    int interval(double stability) =>
        (stability * _round((math.pow(p.retention, -2) - 1) / (19 / 81))).round().clamp(1, p.maximumInterval);

    double difficulty;
    double stability;
    int days = 0;
    int minutes = 0;
    var phase = MemoryPhase.review;
    var lapses = s?.lapses ?? 0;
    if (old == null) {
      difficulty = initialDifficulty(g);
      stability = math.max(.1, w[g - 1]);
      if (rating == Rating.easy) {
        days = interval(stability);
      } else {
        minutes = [1, 5, 10][g - 1];
        phase = MemoryPhase.learning;
      }
    } else {
      final d = old.difficulty.clamp(1.0, 10.0);
      final st = old.stability.clamp(.01, 36500.0);
      difficulty = _round(w[7] * initialDifficulty(4) + (1 - w[7]) * (d + _round(-w[6] * (g - 3) * (10 - d) / 9)))
          .clamp(1, 10);
      if (old.phase != MemoryPhase.review) {
        stability = short(st, g);
        if (rating == Rating.again || rating == Rating.hard) {
          minutes = rating == Rating.again ? 5 : 10;
          phase = old.phase;
        } else {
          days = interval(stability);
          if (rating == Rating.easy) days = math.max(days, interval(short(st, 3)) + 1);
        }
      } else {
        // Whole elapsed 24-hour days, UTC duration arithmetic (also across DST).
        final elapsed = s == null ? 0 : math.max(0, now.difference(s.lastReviewedAt).inDays);
        final r = _round(math.pow(1 + (19 / 81) * elapsed / st, -.5).toDouble());
        double recalled(int grade) => _stability(
          st *
              (1 +
                  math.exp(w[8]) *
                      (11 - d) *
                      math.pow(st, -w[9]) *
                      (math.exp((1 - r) * w[10]) - 1) *
                      (grade == 2 ? w[15] : 1) *
                      (grade == 4 ? w[16] : 1)),
        );
        if (rating == Rating.again) {
          stability = math
              .min(
                _round(st / math.exp(w[17] * w[18])),
                _stability(w[11] * math.pow(d, -w[12]) * (math.pow(st + 1, w[13]) - 1) * math.exp((1 - r) * w[14])),
              )
              .clamp(.01, 36500);
          minutes = 5;
          phase = MemoryPhase.relearning;
          lapses++;
        } else {
          stability = recalled(g);
          final hard = math.min(interval(recalled(2)), interval(recalled(3)));
          final good = math.max(interval(recalled(3)), hard + 1);
          days = switch (rating) {
            Rating.hard => hard,
            Rating.good => good,
            _ => math.max(interval(stability), good + 1),
          };
        }
      }
    }
    days = days.clamp(0, p.maximumInterval);
    return (
      review: ReviewState(
        cardId: cardId,
        due: now.add(days > 0 ? Duration(days: days) : Duration(minutes: minutes)),
        intervalDays: days.toDouble(),
        ease: s?.ease ?? initialEase,
        reps: rating == Rating.again ? 0 : (s?.reps ?? 0) + 1,
        lapses: lapses,
        lastReviewedAt: now,
      ),
      memory: MemoryState(cardId: cardId, stability: stability, difficulty: difficulty, phase: phase),
    );
  }

  static Map<Rating, Duration> preview(
    String cardId,
    ReviewState? s,
    DateTime now, {
    MemoryState? memory,
    FsrsParameters? parameters,
  }) => {
    for (final r in Rating.values)
      r: rate(cardId, s, r, now, memory: memory, parameters: parameters).due.difference(now),
  };
}
