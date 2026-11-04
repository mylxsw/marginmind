import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  final history = <String, SyncCommit>{};
  SyncCommit commit(
    String device,
    Map<String, Object?> payload, {
    List<SyncCommit> parents = const [],
    List<String> pending = const [],
    List<String> resolves = const [],
  }) {
    final c = SyncCommit.create(
      libraryId: 'lib',
      scope: 'set',
      deviceId: device,
      sequence: 1,
      parents: parents.map((p) => p.id).toList(),
      payload: payload,
      pending: pending,
      resolves: resolves,
    );
    history[c.id] = c;
    return c;
  }

  void valid(Map<String, Object?> value) {}
  SyncReplayResult replay() => replaySyncTransactions(history, validate: valid);
  setUp(history.clear);

  test('separate choice groups stay independent, overlapping atomic choices form one review', () {
    final base = commit('base', {'a': 0, 'b': 0, 'c': 0});
    final a1 = commit('a1', {...base.payload, 'a': 1}, parents: [base]);
    final a2 = commit('a2', {...base.payload, 'a': 2}, parents: [base]);
    final b1 = commit('b1', {...base.payload, 'b': 1}, parents: [base]);
    final b2 = commit('b2', {...base.payload, 'b': 2}, parents: [base]);
    final c1 = commit('c1', {...base.payload, 'c': 1}, parents: [base]);
    final c2 = commit('c2', {...base.payload, 'c': 2}, parents: [base]);
    final r = replay();
    final pending = r.pending.map((p) => p.transaction).toList();
    expect(pending, hasLength(3));
    final integrated = commit('integrated', r.payload, parents: [a1, a2, b1, b2, c1, c2], pending: pending);
    final one = commit('one', r.payload, parents: [integrated], resolves: [pending[0]], pending: pending.sublist(1));
    final two = commit(
      'two',
      r.payload,
      parents: [integrated],
      resolves: [pending[1]],
      pending: [pending[0], pending[2]],
    );
    final three = commit(
      'three',
      r.payload,
      parents: [integrated],
      resolves: [pending[2]],
      pending: pending.sublist(0, 2),
    );
    expect(syncConcurrentChoices(history), isEmpty);
    expect(replay().pending, isEmpty);
    final overlap = commit(
      'overlap',
      r.payload,
      parents: [integrated],
      resolves: pending.sublist(0, 2),
      pending: [pending[2]],
    );
    final groups = syncConcurrentChoices(history);
    expect(groups[one.id], {one.id, two.id, overlap.id});
    expect(groups[two.id], groups[one.id]);
    expect(groups.containsKey(three.id), isFalse);
    expect(replay().pending.map((p) => p.transaction).toSet(), groups[one.id]);
  });

  for (final chooseKeep in [true, false]) {
    test('concurrent choices and late choices converge; keep=$chooseKeep', () {
      final base = commit('base', {'text': 'base', 'title': 'base', 'later': false});
      final a = commit('a', {...base.payload, 'text': 'A'}, parents: [base]);
      final b = commit('b', {...base.payload, 'text': 'B'}, parents: [base]);
      final first = replay(), pending = replay().pending.single.transaction;
      final merged = commit('merged', first.payload, parents: [a, b], pending: [pending]);
      final keep = commit('keep', merged.payload, parents: [merged], resolves: [pending]);
      final use = commit(
        'use',
        chooseSyncCandidate(history, pending, merged.payload),
        parents: [merged],
        resolves: [pending],
      );
      final later = commit('later', {...use.payload, 'title': 'later'}, parents: [use]);
      final result = replay();
      expect(result.payload['title'], 'later');
      expect(result.pending.map((p) => p.transaction).toSet(), {keep.id, use.id});
      expect(result.pending.every((p) => p.reason == 'concurrentChoices'), isTrue);
      final integrated = commit('integrated', result.payload, parents: [keep, later], pending: [keep.id, use.id]);
      expect(planSyncMerge(history, remote: integrated.id, validateTransaction: valid).state, SyncMergeState.ready);
      expect(
        replaySyncTransactions(Map.fromEntries(history.entries.toList().reversed), validate: valid).payload,
        result.payload,
      );
      final selected = chooseKeep ? keep : use;
      final chosen = chooseSyncCandidate(history, selected.id, integrated.payload);
      expect(chosen['text'], selected.payload['text']);
      expect(chosen['title'], 'later');
      final finalChoice = commit(
        'final',
        chosen,
        parents: [integrated],
        resolves: syncChoiceGroup(history, selected.id),
      );
      expect(replay().pending, isEmpty);
      expect(planSyncMerge(history, remote: finalChoice.id, validateTransaction: valid).state, SyncMergeState.ready);
      final late = commit('late', merged.payload, parents: [merged], resolves: [pending]);
      final extra = commit('extra', {...late.payload, 'later': true}, parents: [late]);
      final lateResult = replay();
      expect(lateResult.pending.map((p) => p.transaction).toSet(), {finalChoice.id, late.id});
      expect(lateResult.payload['later'], true);
      expect(lateResult.payload['title'], 'later');
      final reviewed = commit(
        'reviewed',
        lateResult.payload,
        parents: [finalChoice, extra],
        pending: [finalChoice.id, late.id],
      );
      final settled = commit(
        'settled',
        chooseSyncCandidate(history, finalChoice.id, reviewed.payload),
        parents: [reviewed],
        resolves: syncChoiceGroup(history, finalChoice.id),
      );
      expect(replay().pending, isEmpty);
      expect(replay().payload['text'], chosen['text']);
      expect(replay().payload['later'], true);
      expect(planSyncMerge(history, remote: settled.id, validateTransaction: valid).state, SyncMergeState.ready);
    });
  }

  test('choice intent retains whole-entity removal and no-op companion values', () {
    final base = commit('base', {
      'item': {'a': 1, 'b': 2},
      'text': 'x',
      'untouched': 0,
    });
    final a = commit('a', {...base.payload, 'text': 'a'}, parents: [base]);
    final b = commit('b', {'text': 'b', 'untouched': 0}, parents: [base]);
    final result = replay(), pending = replay().pending.single.transaction;
    final merged = commit('merged', result.payload, parents: [a, b], pending: [pending]);
    final keep = commit('keep', merged.payload, parents: [merged], resolves: [pending]);
    final current = {...merged.payload, 'untouched': 9};
    expect(chooseSyncCandidate(history, keep.id, current), current);
    expect(syncTransactionPaths(history, keep.id), syncTransactionPaths(history, pending));
    expect(syncValueAt({}, ['missing', 'child']), contentMissing);
    expect(chooseSyncCandidate(history, b.id, base.payload), b.payload);
  });

  test('existing delta semantics retain competing edits and merge bookkeeping timestamps', () {
    final base = commit('base', {'text': 'base', 'updatedAt': '2026-01-01', 'other': 0});
    final a = commit('a', {...base.payload, 'text': 'A', 'updatedAt': '2026-01-02'}, parents: [base]);
    final b = commit('b', {...base.payload, 'text': 'B', 'updatedAt': '2026-01-03'}, parents: [base]);
    final initial = replay(), pending = replay().pending.single.transaction;
    final merged = commit('merged', initial.payload, parents: [a, b], pending: [pending]);
    final choice = commit(
      'choice',
      chooseSyncCandidate(history, pending, merged.payload),
      parents: [merged],
      resolves: [pending],
    );
    final timestamp = commit(
      'timestamp',
      {...merged.payload, 'other': 1, 'updatedAt': '2026-01-09'},
      parents: [merged],
      pending: [pending],
    );
    var result = replay();
    expect(result.pending, isEmpty);
    expect(result.payload['other'], 1);
    expect(result.payload['updatedAt'], '2026-01-09');
    final same = commit('same', result.payload, parents: [choice, timestamp]);
    expect(planSyncMerge(history, remote: same.id, validateTransaction: valid).state, SyncMergeState.ready);
    // A causally later write on the competing branch is still an independent
    // transaction with a real field precondition, never overwritten by intent.
    final edit = commit('edit', {...timestamp.payload, 'text': 'third'}, parents: [timestamp], pending: [pending]);
    result = replay();
    expect(result.pending, hasLength(1));
    expect({result.pending.single.transaction}, anyOf({choice.id}, {edit.id}));
    expect(result.payload['other'], 1);
  });

  test('nested removal intent never recreates an absent ancestor', () {
    final base = commit('base', {
      'item': {'a': 1, 'b': 2},
      'text': 'base',
    });
    final a = commit(
      'a',
      {
        'item': {'b': 2},
        'text': 'A',
      },
      parents: [base],
    );
    final b = commit(
      'b',
      {
        'item': {'b': 2},
        'text': 'B',
      },
      parents: [base],
    );
    final r = replay(), target = replay().pending.single.transaction;
    final merged = commit('merged', r.payload, parents: [a, b], pending: [target]);
    final selected = commit(
      'selected',
      chooseSyncCandidate(history, target, merged.payload),
      parents: [merged],
      resolves: [target],
    );
    // Explicit choice writes the original entity only when its original
    // operation inserted/replaced it, not merely because a child was removed.
    final now = <String, Object?>{'text': 'later'};
    final chosen = chooseSyncCandidate(history, selected.id, now);
    expect(chosen.containsKey('item'), isFalse);
    expect(chooseSyncCandidate(history, selected.id, base.payload)['item'], {'b': 2});
  });
}
