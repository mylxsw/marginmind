import 'package:mm_core/mm_core.dart';

import 'commit.dart';
import 'reconciliation.dart';

Map<String, Object?> reviewData(StudySetContent c) => {
  'reviews': [for (final r in c.reviews) r.toJson()],
  'memoryStates': [for (final m in c.memoryStates) m.toJson()],
  'reviewLogs': [for (final l in c.reviewLogs) l.toJson()],
};

Map<String, Object?> _map(Object? v) => (v as Map).cast<String, Object?>();
Object? _freeze(Object? v) => v is Map
    ? Map<String, Object?>.unmodifiable(v.map((k, value) => MapEntry(k as String, _freeze(value))))
    : v is List
    ? List<Object?>.unmodifiable(v.map(_freeze))
    : v;

Map<String, Object?> _log(ReviewLog log) => {...log.toJson(), 'reviewedAt': log.reviewedAt.toUtc().toIso8601String()};

/// Canonical baseline/projection. Legacy schedules are captured, never inferred
/// by pretending their incomplete logs are a complete event history.
Map<String, Object?> normalizeReviewData(Map<String, Object?> value) {
  if (value.keys.toSet().difference({'reviews', 'memoryStates', 'reviewLogs'}).isNotEmpty) {
    throw const FormatException('Unknown review data');
  }
  List<Map<String, Object?>> list(
    String key,
    String identity,
    Map<String, Object?> Function(Map<String, Object?>) decode,
  ) {
    final result = (value[key] as List).map((v) => decode(_map(v))).toList();
    final ids = result.map((v) => v[identity] as String).toSet();
    if (ids.length != result.length || ids.any((id) => id.isEmpty)) {
      throw const FormatException('Duplicate review identity');
    }
    result.sort((a, b) => (a[identity] as String).compareTo(b[identity] as String));
    return result;
  }

  final normalized = <String, Object?>{
    'reviews': list('reviews', 'cardId', (v) {
      final r = ReviewState.fromJson(v);
      if (!r.intervalDays.isFinite ||
          r.intervalDays < 0 ||
          !r.ease.isFinite ||
          r.ease <= 0 ||
          r.reps < 0 ||
          r.lapses < 0) {
        throw const FormatException('Invalid review baseline');
      }
      return {
        ...r.toJson(),
        'due': r.due.toUtc().toIso8601String(),
        'last': r.lastReviewedAt.toUtc().toIso8601String(),
      };
    }),
    'memoryStates': list('memoryStates', 'cardId', (v) {
      final m = MemoryState.fromJson(v);
      if (!m.stability.isFinite ||
          m.stability <= 0 ||
          !m.difficulty.isFinite ||
          m.difficulty < 1 ||
          m.difficulty > 10 ||
          m.learningStep < 0) {
        throw const FormatException('Invalid memory baseline');
      }
      return m.toJson();
    }),
    'reviewLogs': list('reviewLogs', 'id', (v) {
      final log = ReviewLog.fromJson(v);
      if (log.cardId.isEmpty ||
          !log.intervalBefore.isFinite ||
          !log.intervalAfter.isFinite ||
          log.intervalBefore < 0 ||
          log.intervalAfter < 0) {
        throw const FormatException('Invalid review log');
      }
      return _log(log);
    }),
  };
  // Match the existing package reader's deterministic legacy migration. This
  // materializes missing memory only; it never moves a saved due date or
  // invents ratings for incomplete legacy logs.
  final memory = (normalized['memoryStates'] as List<Map<String, Object?>>);
  final known = memory.map((m) => m['cardId']).toSet();
  for (final raw in normalized['reviews'] as List<Map<String, Object?>>) {
    final review = ReviewState.fromJson(raw);
    if (known.add(review.cardId)) memory.add(ReviewScheduler.fromLegacy(review).toJson());
  }
  memory.sort((a, b) => (a['cardId'] as String).compareTo(b['cardId'] as String));
  return normalized;
}

class ReviewTimeline {
  ReviewTimeline._(this.baseline, this.events);
  factory ReviewTimeline.seed(Map<String, Object?> data) =>
      ReviewTimeline._(_freeze(normalizeReviewData(data)) as Map<String, Object?>, const {});
  factory ReviewTimeline.fromJson(Map<String, Object?> json) {
    if (json['kind'] != 'review-events' ||
        json['version'] != 1 ||
        json.keys.any((k) => !{'kind', 'version', 'baseline', 'baselineId', 'events'}.contains(k))) {
      throw const FormatException('Unsupported review timeline');
    }
    final baseline = normalizeReviewData(_map(json['baseline']));
    if (!contentValueEquals(baseline, json['baseline']) || syncDigest(baseline) != json['baselineId']) {
      throw const FormatException('Invalid review baseline digest');
    }
    final events = _map(json['events']);
    final legacyIds = (baseline['reviewLogs'] as List).map((v) => (v as Map)['id']).toSet();
    for (final entry in events.entries) {
      final e = _map(entry.value);
      final log = ReviewLog.fromJson(_map(e['log']));
      final parents = (e['parents'] as List).cast<String>();
      if (e.keys.any((k) => !{'device', 'log', 'parents'}.contains(k)) ||
          e['device'] is! String ||
          (e['device'] as String).isEmpty ||
          log.id.isEmpty ||
          log.id != entry.key ||
          legacyIds.contains(log.id) ||
          log.algorithm == null ||
          log.cardId.isEmpty ||
          !log.intervalBefore.isFinite ||
          !log.intervalAfter.isFinite ||
          log.intervalBefore < 0 ||
          log.intervalAfter < 0 ||
          !contentValueEquals(_log(log), e['log']) ||
          parents.toSet().length != parents.length ||
          parents.any((p) => !events.containsKey(p))) {
        throw const FormatException('Invalid rating event');
      }
    }
    final result = ReviewTimeline._(_freeze(baseline) as Map<String, Object?>, _freeze(events) as Map<String, Object?>);
    result.orderedEvents(); // Reject cycles before accepting a snapshot.
    return result;
  }
  final Map<String, Object?> baseline, events;
  Map<String, Object?> toJson() => {
    'kind': 'review-events',
    'version': 1,
    'baselineId': syncDigest(baseline),
    'baseline': baseline,
    'events': events,
  };
  Set<String> get frontier => events.keys.toSet().difference({
    for (final event in events.values) ...(_map(event)['parents'] as List).cast<String>(),
  });

  /// Causal order first; independent scores use their recorded UTC time and ID.
  /// Clock skew cannot move the schedule backwards (see project).
  List<String> orderedEvents() {
    final remaining = events.keys.toSet(), done = <String>{}, result = <String>[];
    while (remaining.isNotEmpty) {
      final ready = remaining.where((id) => (_map(events[id])['parents'] as List).every(done.contains)).toList()
        ..sort((a, b) {
          final one = ReviewLog.fromJson(_map(_map(events[a])['log']));
          final two = ReviewLog.fromJson(_map(_map(events[b])['log']));
          final byTime = one.reviewedAt.compareTo(two.reviewedAt);
          return byTime == 0 ? a.compareTo(b) : byTime;
        });
      if (ready.isEmpty) throw const FormatException('Cyclic review events');
      // Pick one, then reconsider readiness: batches would reorder a newly
      // unblocked causal successor against the other independent events.
      final id = ready.first;
      remaining.remove(id);
      done.add(id);
      result.add(id);
    }
    return result;
  }

  Map<String, Object?> project() {
    final reviews = {
      for (final v in baseline['reviews'] as List) (v as Map)['cardId'] as String: ReviewState.fromJson(_map(v)),
    };
    final memory = {
      for (final v in baseline['memoryStates'] as List) (v as Map)['cardId'] as String: MemoryState.fromJson(_map(v)),
    };
    final logs = [for (final v in baseline['reviewLogs'] as List) _map(v)];
    for (final id in orderedEvents()) {
      final log = ReviewLog.fromJson(_map(_map(events[id])['log']));
      final previous = reviews[log.cardId];
      final time = previous != null && log.reviewedAt.isBefore(previous.lastReviewedAt)
          ? previous.lastReviewedAt.toUtc()
          : log.reviewedAt.toUtc();
      final result = ReviewScheduler.schedule(
        log.cardId,
        previous,
        log.rating,
        time,
        memory: memory[log.cardId],
        parameters: log.algorithm!.parameters,
      );
      reviews[log.cardId] = result.review;
      memory[log.cardId] = result.memory;
      // Interval observations belong to the immutable original rating. Do not
      // rewrite history to look as if another device was observed at the time.
      logs.add(_log(log));
    }
    return normalizeReviewData({
      'reviews': reviews.values.map((r) => r.toJson()).toList(),
      'memoryStates': memory.values.map((m) => m.toJson()).toList(),
      'reviewLogs': logs,
    });
  }

  ReviewTimeline append(Map<String, Object?> next, {required String deviceId}) {
    final projected = project();
    final oldLogs = {for (final v in projected['reviewLogs'] as List) (v as Map)['id']: v};
    final normalized = normalizeReviewData(next);
    final proposed = {for (final v in normalized['reviewLogs'] as List) (v as Map)['id']: v};
    if (oldLogs.entries.any((e) => !contentValueEquals(e.value, proposed[e.key]))) {
      throw const FormatException('Rating history is immutable');
    }
    var timeline = this;
    // Keep the caller's actual order for several ratings in one repository write.
    for (final raw in next['reviewLogs'] as List) {
      final log = ReviewLog.fromJson(_map(raw));
      if (oldLogs.containsKey(log.id)) continue;
      timeline = ReviewTimeline.fromJson({
        ...timeline.toJson(),
        'events': {
          ...timeline.events,
          log.id: {'device': deviceId, 'parents': timeline.frontier.toList()..sort(), 'log': _log(log)},
        },
      });
    }
    if (!contentValueEquals(normalized, timeline.project())) {
      throw const FormatException('Schedule changes require versioned rating events');
    }
    return timeline;
  }

  ReviewTimeline merge(ReviewTimeline other) {
    if (!contentValueEquals(baseline, other.baseline)) throw const FormatException('Different review baselines');
    for (final id in events.keys.toSet().intersection(other.events.keys.toSet())) {
      if (!contentValueEquals(events[id], other.events[id])) throw const FormatException('Rating identity collision');
    }
    return ReviewTimeline.fromJson({
      ...toJson(),
      'events': {...events, ...other.events},
    });
  }

  StudySetContent apply(StudySetContent content) {
    final data = project();
    return content.copyWith(
      reviews: (data['reviews'] as List).map((v) => ReviewState.fromJson(_map(v))).toList(),
      memoryStates: (data['memoryStates'] as List).map((v) => MemoryState.fromJson(_map(v))).toList(),
      reviewLogs: (data['reviewLogs'] as List).map((v) => ReviewLog.fromJson(_map(v))).toList(),
    );
  }
}

/// Validate each immutable snapshot against its own parents, including legacy
/// snapshot-to-baseline transitions. A merge cannot hide or alter a rating.
SyncMergePlan planReviewMerge(Map<String, SyncCommit> known, {required String remote, String? local}) {
  SyncMergePlan result(SyncMergeState state, String reason, {Map<String, Object?>? payload, bool adopt = false}) =>
      SyncMergePlan(remote: remote, local: local, state: state, reason: reason, payload: payload, adopt: adopt);
  try {
    final ancestry = syncAncestry(known, [remote, ?local]);
    final graph = SyncGraph(ancestry.values);
    if (local != null && graph.ancestors(local).contains(remote)) {
      return result(SyncMergeState.unchanged, 'alreadyApplied');
    }
    if (ancestry.values.where((c) => c.parents.isEmpty).length != 1) {
      return result(SyncMergeState.conflict, 'noBase');
    }
    final decoded = <String, ReviewTimeline>{};
    for (final c in ancestry.values) {
      if (c.parents.length > 2) throw const FormatException('Unsupported review checkpoint');
      if (c.parents.length == 2) {
        final bases = graph.mergeBases(c.parents[0], c.parents[1]);
        if (bases.length != 1) {
          return result(SyncMergeState.conflict, bases.isEmpty ? 'noBase' : 'multipleBases');
        }
      }
      if (c.deleted || c.pending.isNotEmpty || c.resolves.isNotEmpty) {
        throw const FormatException('Review history lifecycle');
      }
      if (c.payload['kind'] == 'review-events') decoded[c.id] = ReviewTimeline.fromJson(c.payload);
    }
    if (decoded[remote] == null) {
      return result(SyncMergeState.waiting, 'unsupportedReviews');
    }
    for (final c in ancestry.values.where((c) => decoded.containsKey(c.id))) {
      final timeline = decoded[c.id]!;
      final inherited = <String, Object?>{};
      for (final parentId in c.parents) {
        final parent = decoded[parentId] ?? ReviewTimeline.seed(ancestry[parentId]!.payload);
        if (!contentValueEquals(parent.baseline, timeline.baseline)) {
          throw const FormatException('Changed review baseline');
        }
        for (final e in parent.events.entries) {
          if (!contentValueEquals(e.value, timeline.events[e.key])) {
            throw const FormatException('Lost or altered rating');
          }
          inherited[e.key] = e.value;
        }
      }
      final added = timeline.events.keys.toSet().difference(inherited.keys.toSet());
      if (c.parents.length > 1 && added.isNotEmpty) throw const FormatException('Merge fabricated ratings');
      for (final id in added) {
        if (_map(timeline.events[id])['device'] != c.deviceId) throw const FormatException('Wrong rating author');
        final visited = <String>{}, pending = <String>[id];
        while (pending.isNotEmpty) {
          final next = pending.removeLast();
          if (visited.add(next)) pending.addAll((_map(timeline.events[next])['parents'] as List).cast<String>());
        }
        if (!visited.containsAll(inherited.keys)) throw const FormatException('Rating omitted observed causal history');
      }
      timeline.project();
    }
    if (local == null || graph.ancestors(remote).contains(local)) {
      return result(SyncMergeState.ready, 'fastForward', payload: decoded[remote]!.toJson(), adopt: true);
    }
    final bases = graph.mergeBases(local, remote);
    if (bases.length != 1) return result(SyncMergeState.conflict, bases.isEmpty ? 'noBase' : 'multipleBases');
    final left = decoded[local] ?? ReviewTimeline.seed(ancestry[local]!.payload);
    return result(SyncMergeState.ready, 'mergedReviews', payload: left.merge(decoded[remote]!).toJson());
  } on MissingSyncParents {
    return result(SyncMergeState.waiting, 'missingParents');
  } on FormatException {
    return result(SyncMergeState.conflict, 'invalidReviews');
  } on ArgumentError {
    return result(SyncMergeState.conflict, 'invalidReviews');
  } on TypeError {
    return result(SyncMergeState.conflict, 'invalidReviews');
  }
}
