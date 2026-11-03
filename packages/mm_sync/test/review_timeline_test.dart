import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

import 'fixtures/review_wire_v2.dart';

void main() {
  final time = DateTime.utc(2026, 11, 1);
  final content = StudySetEditor(
    newId: () => 'card',
    now: () => time,
  ).addNote(StudySetContent.empty, text: 'Question').$1;
  StudySetContent rate(StudySetContent c, String id, Rating rating, {DateTime? at, FsrsParameters? parameters}) =>
      StudySetEditor(newId: () => id, now: () => at ?? time, fsrsParameters: parameters).rate(c, 'card', rating);
  ReviewTimeline append(ReviewTimeline t, StudySetContent c, String device) =>
      t.append(reviewData(c), deviceId: device);
  Map<String, Object?> copy(Map<String, Object?> value) => (jsonDecode(jsonEncode(value)) as Map).cast();
  SyncCommit commit(ReviewTimeline t, String device, int seq, [List<SyncCommit> parents = const []]) =>
      SyncCommit.create(
        libraryId: 'lib',
        scope: 'reviews/set',
        deviceId: device,
        sequence: seq,
        parents: parents.map((c) => c.id).toList(),
        payload: t.toJson(),
      );

  test('native wire fixture verifies and replays on both native and browser runtimes', () {
    final fixture = (jsonDecode(reviewWireV2) as Map).cast<String, Object?>();
    final received = SyncCommit.fromJson((fixture['commit'] as Map).cast());
    final plan = planReviewMerge({received.id: received}, remote: received.id);
    expect(plan.state, SyncMergeState.ready);
    expect(contentValueEquals(ReviewTimeline.fromJson(plan.payload!).project(), fixture['projection']), isTrue);
  });

  test('legacy baseline preserves schedule and incomplete history without replaying it', () {
    final legacy = content.copyWith(
      reviews: [
        ReviewState(
          cardId: 'card',
          due: time.add(const Duration(days: 9)),
          intervalDays: 9,
          ease: 2.1,
          reps: 12,
          lapses: 4,
          lastReviewedAt: time,
        ),
      ],
      reviewLogs: [
        ReviewLog(
          id: 'old',
          cardId: 'card',
          reviewedAt: time,
          rating: Rating.hard,
          intervalBefore: 6,
          intervalAfter: 9,
        ),
      ],
    );
    final baseline = ReviewTimeline.seed(reviewData(legacy));
    expect(baseline.events, isEmpty);
    expect(baseline.apply(content).reviewOf('card')!.due, legacy.reviewOf('card')!.due);
    expect(baseline.apply(content).reviewLogs.single.algorithm, isNull);
    final next = rate(legacy, 'new', Rating.good, at: time.add(const Duration(days: 10)));
    final t = append(baseline, next, 'a');
    expect(t.project(), normalizeReviewData(reviewData(next)));
    expect(t.events.length, 1);
    expect(ReviewTimeline.fromJson(t.toJson()).project(), t.project());
  });

  test('offline ratings converge and deduplicate while preserving custom parameters and observations', () {
    final seed = ReviewTimeline.seed(reviewData(content));
    final a = append(seed, rate(content, 'a-score', Rating.good), 'a');
    final parameters = FsrsParameters(retention: .82, maximumInterval: 120);
    final b = append(seed, rate(content, 'b-score', Rating.easy, parameters: parameters), 'b');
    final merged = a.merge(b);
    expect(merged.project(), b.merge(a).project());
    expect(merged.merge(a).project(), merged.project());
    expect(merged.apply(content).reviewLogs, hasLength(2));
    expect(merged.apply(content).reviewOf('card')!.reps, 2);
    expect(merged.apply(content).reviewLogs.last.algorithm!.parameters.retention, .82);
    expect(merged.events['a-score'], a.events['a-score']);
    expect(() => (merged.events['a-score'] as Map)['device'] = 'changed', throwsUnsupportedError);
    final root = commit(seed, 'origin', 1), left = commit(a, 'a', 1), right = commit(b, 'b', 1);
    final l = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'a',
      sequence: 1,
      parents: [root.id],
      payload: left.payload,
    );
    final r = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'b',
      sequence: 1,
      parents: [root.id],
      payload: right.payload,
    );
    final plan = planReviewMerge(
      {
        for (final c in [root, l, r]) c.id: c,
      },
      remote: r.id,
      local: l.id,
    );
    expect(plan.state, SyncMergeState.ready);
    expect(plan.payload, merged.toJson());
  });

  test('causal order survives clock rollback without regressing due time or altering recorded timestamps', () {
    final first = rate(content, 'first', Rating.good);
    final seed = ReviewTimeline.seed(reviewData(content));
    final a = append(seed, first, 'a');
    final earlier = time.subtract(const Duration(days: 100));
    final second = rate(first, 'second', Rating.good, at: earlier);
    final b = append(a, second, 'b');
    expect(b.orderedEvents(), ['first', 'second']);
    expect(b.apply(content).reviewOf('card')!.lastReviewedAt, time);
    expect(b.apply(content).reviewLogs.last.reviewedAt, earlier);
    expect(b.project(), normalizeReviewData(reviewData(second)));
  });

  test('history deletion, out-of-band schedule edits and duplicate identities are rejected', () {
    final seed = ReviewTimeline.seed(reviewData(content));
    final c = rate(content, 'same', Rating.good), a = append(seed, rate(content, 'same', Rating.good), 'a');
    expect(() => a.append(reviewData(content), deviceId: 'a'), throwsFormatException);
    expect(() => seed.append(reviewData(c.copyWith(memoryStates: const [])), deviceId: 'a'), throwsFormatException);
    expect(() => a.merge(append(seed, rate(content, 'same', Rating.easy), 'b')), throwsFormatException);
    expect(
      () => ReviewTimeline.seed({
        ...reviewData(content),
        'reviewLogs': [c.reviewLogs.single.toJson(), c.reviewLogs.single.toJson()],
      }),
      throwsFormatException,
    );
    expect(
      () => seed.append(
        reviewData(
          c.copyWith(
            reviewLogs: [
              ReviewLog(
                id: 'old-policy',
                cardId: 'card',
                reviewedAt: time,
                rating: Rating.good,
                intervalBefore: 0,
                intervalAfter: 0,
              ),
            ],
          ),
        ),
        deviceId: 'a',
      ),
      throwsFormatException,
    );
  });

  test('unsupported policy, mutated baseline and invalid causal event graphs fail closed', () {
    final seed = ReviewTimeline.seed(reviewData(content));
    final timeline = append(seed, rate(content, 'rating', Rating.good), 'a');
    final variants = <void Function(Map<String, Object?>)>[
      (j) => j['version'] = 2,
      (j) => j['baselineId'] = 'wrong',
      (j) => (j['events'] as Map)['rating']['log']['algorithm']['version'] = 2,
      (j) => (j['events'] as Map)['rating']['log']['algorithm']['weights'] = [1.0],
      (j) => (j['events'] as Map)['rating']['parents'] = ['missing'],
      (j) => (j['events'] as Map)['rating']['parents'] = ['rating'],
      (j) => (j['events'] as Map)['rating']['device'] = '',
      (j) => (j['events'] as Map)['rating']['device'] = 'forged-author',
      (j) => (j['events'] as Map)['rating']['log']['id'] = '',
      (j) => (j['events'] as Map)['rating']['log']['intervalAfter'] = -1,
    ];
    final root = commit(seed, 'a', 1);
    for (final mutate in variants) {
      final body = copy(timeline.toJson());
      mutate(body);
      final bad = SyncCommit.create(
        libraryId: 'lib',
        scope: root.scope,
        deviceId: 'a',
        sequence: 2,
        parents: [root.id],
        payload: body,
      );
      expect(
        planReviewMerge({root.id: root, bad.id: bad}, remote: bad.id, local: root.id).state,
        SyncMergeState.conflict,
      );
    }
  });

  test('immutable checkpoints cannot hide, rewrite or invent observed events', () {
    final seed = ReviewTimeline.seed(reviewData(content));
    final root = commit(seed, 'root', 1);
    final a = append(seed, rate(content, 'a', Rating.good), 'a');
    final b = append(seed, rate(content, 'b', Rating.easy), 'b');
    final l = commit(a, 'a', 1, [root]), r = commit(b, 'b', 1, [root]);
    final valid = commit(a.merge(b), 'a', 2, [l, r]);
    final history = {
      for (final c in [root, l, r, valid]) c.id: c,
    };
    expect(planReviewMerge(history, remote: valid.id, local: l.id).adopt, isTrue);
    expect(planReviewMerge(history, remote: l.id, local: valid.id).state, SyncMergeState.unchanged);
    for (final payload in [
      a.toJson(),
      append(a.merge(b), rate(a.merge(b).apply(content), 'invented', Rating.good), 'a').toJson(),
    ]) {
      final bad = SyncCommit.create(
        libraryId: 'lib',
        scope: root.scope,
        deviceId: 'other',
        sequence: 1,
        parents: [l.id, r.id],
        payload: payload,
      );
      expect(
        planReviewMerge({...history, bad.id: bad}, remote: bad.id, local: valid.id).state,
        SyncMergeState.conflict,
      );
    }
    final later = append(a, rate(a.apply(content), 'later', Rating.good), 'a');
    final broken = copy(later.toJson());
    (broken['events'] as Map)['later']['parents'] = [];
    final bad = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'a',
      sequence: 2,
      parents: [l.id],
      payload: broken,
    );
    expect(planReviewMerge({root.id: root, l.id: l, bad.id: bad}, remote: bad.id).state, SyncMergeState.conflict);
  });

  test('concurrent integration checkpoints retain multiple merge bases instead of guessing one', () {
    final seed = ReviewTimeline.seed(reviewData(content)),
        root = commit(ReviewTimeline.seed(reviewData(content)), 'root', 1);
    final a = append(seed, rate(content, 'a', Rating.good), 'a'),
        b = append(seed, rate(content, 'b', Rating.easy), 'b');
    final left = commit(a, 'a', 1, [root]), right = commit(b, 'b', 1, [root]);
    final l = commit(a.merge(b), 'a', 2, [left, right]), r = commit(a.merge(b), 'b', 2, [left, right]);
    expect(
      planReviewMerge(
        {
          for (final c in [root, left, right, l, r]) c.id: c,
        },
        local: l.id,
        remote: r.id,
      ).reason,
      'multipleBases',
    );
  });

  test('a remote checkpoint cannot legitimize unrelated roots or ambiguous merge bases', () {
    final seed = ReviewTimeline.seed(reviewData(content));
    final one = commit(seed, 'one', 1), two = commit(seed, 'two', 1);
    final unsupported = commit(seed, 'third', 1, [one, two]);
    expect(
      planReviewMerge({
        for (final c in [one, two, unsupported]) c.id: c,
      }, remote: unsupported.id).reason,
      'noBase',
    );
    final a = commit(seed, 'a', 1, [one]), b = commit(seed, 'b', 1, [one]);
    final x = commit(seed, 'x', 1, [a, b]), y = commit(seed, 'y', 1, [a, b]);
    final ambiguous = commit(seed, 'z', 1, [x, y]);
    expect(
      planReviewMerge({
        for (final c in [one, a, b, x, y, ambiguous]) c.id: c,
      }, remote: ambiguous.id).reason,
      'multipleBases',
    );
  });

  test('legacy transition is explicit; missing ancestry and unrelated baselines are retained', () {
    final old = SyncCommit.create(
      libraryId: 'lib',
      scope: 'reviews/set',
      deviceId: 'a',
      sequence: 1,
      payload: reviewData(content),
    );
    final seed = ReviewTimeline.seed(old.payload);
    final upgraded = commit(seed, 'a', 2, [old]);
    expect(planReviewMerge({old.id: old, upgraded.id: upgraded}, remote: upgraded.id, local: old.id).adopt, isTrue);
    expect(planReviewMerge({upgraded.id: upgraded}, remote: upgraded.id).reason, 'missingParents');
    expect(planReviewMerge({old.id: old}, remote: old.id).reason, 'unsupportedReviews');
    final other = commit(seed, 'b', 1);
    expect(
      planReviewMerge(
        {upgraded.id: upgraded, old.id: old, other.id: other},
        remote: other.id,
        local: upgraded.id,
      ).reason,
      'noBase',
    );
  });
}
