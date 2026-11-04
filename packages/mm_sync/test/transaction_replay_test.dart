import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  SyncCommit commit(
    String device,
    Map<String, Object?> payload, {
    List<SyncCommit> parents = const [],
    List<String> pending = const [],
    List<String> resolves = const [],
  }) => SyncCommit.create(
    libraryId: 'library',
    scope: 'set',
    deviceId: device,
    sequence: 1,
    parents: parents.map((c) => c.id).toList(),
    payload: payload,
    pending: pending,
    resolves: resolves,
  );
  Map<String, SyncCommit> history(List<SyncCommit> commits) => {for (final c in commits) c.id: c};
  void valid(Map<String, Object?> value) {
    if (value['p'] == 'q' && value['q'] == 'p') throw const FormatException('cycle');
  }

  SyncReplayResult replay(List<SyncCommit> commits) => replaySyncTransactions(history(commits), validate: valid);

  test('atomic fields, dependent writes, independent successors and receipt permutation', () {
    final base = commit('base', {'text': 'base', 'a': false, 'b': false, 'later': 0});
    final a = commit('a', {...base.payload, 'text': 'A', 'a': true}, parents: [base]);
    final b = commit('b', {...base.payload, 'text': 'B', 'b': true}, parents: [base]);
    final first = replay([base, a, b]);
    final loser = first.pending.single.transaction == a.id ? a : b;
    expect(first.payload[loser == a ? 'a' : 'b'], false);
    final next = commit('next', {...loser.payload, 'later': 1}, parents: [loser]);
    final dependent = commit('dependent', {...next.payload, 'text': 'dependent'}, parents: [next]);
    final inputs = [base, a, b, next, dependent];
    final result = replay(inputs);
    expect(result.payload['later'], 1);
    expect(result.pending.map((p) => p.transaction), containsAll([loser.id, dependent.id]));
    expect(replay(inputs.reversed.toList()).payload, result.payload);
    expect(
      replay(inputs.reversed.toList()).pending.map((p) => p.transaction),
      result.pending.map((p) => p.transaction),
    );
  });

  test('structural conflict withholds the whole related transaction, unrelated metadata proceeds', () {
    final base = commit('base', {'p': null, 'q': null, 'a': false, 'b': false, 'title': 'base'});
    final a = commit('a', {...base.payload, 'p': 'q', 'a': true}, parents: [base]);
    final b = commit('b', {...base.payload, 'q': 'p', 'b': true}, parents: [base]);
    final result = replay([base, a, b]);
    final blocked = result.pending.single;
    expect(blocked.reason, 'structure');
    final loser = blocked.transaction == a.id ? a : b;
    expect(result.payload[loser == a ? 'a' : 'b'], false);
    final later = commit('later', {...loser.payload, 'title': 'new'}, parents: [loser]);
    expect(replay([base, a, b, later]).payload['title'], 'new');
    expect(() => valid(result.payload), returnsNormally);
  });

  test('pending state is portable, resolutions are causal and integration payloads are verified', () {
    final base = commit('base', {'text': 'base', 'title': 'base'});
    final a = commit('a', {...base.payload, 'text': 'A'}, parents: [base]);
    final b = commit('b', {...base.payload, 'text': 'B'}, parents: [base]);
    final projected = replay([base, a, b]);
    final pending = projected.pending.single.transaction;
    final merged = commit('merged', projected.payload, parents: [a, b], pending: [pending]);
    expect(SyncCommit.fromJson(merged.toJson()).pending, [pending]);
    final commits = [base, a, b, merged];
    expect(planSyncMerge(history(commits), remote: merged.id, validateTransaction: valid).pending, [pending]);
    final forged = commit('forged', projected.payload, parents: [a, b]);
    expect(
      planSyncMerge(history([...commits, forged]), remote: forged.id, validateTransaction: valid).reason,
      'invalidIntegration',
    );
    final candidate = pending == a.id ? a : b;
    final chosen = chooseSyncTransaction(base.payload, candidate.payload, {...merged.payload, 'title': 'later'});
    expect(chosen['title'], 'later');
    final resolution = commit('resolution', {...chosen, 'title': 'base'}, parents: [merged], resolves: [pending]);
    final result = replay([...commits, resolution]);
    expect(result.pending, isEmpty);
    expect(result.payload['text'], candidate.payload['text']);
    expect(
      planSyncMerge(history([...commits, resolution]), remote: resolution.id, validateTransaction: valid).state,
      SyncMergeState.ready,
    );
    final otherResolution = commit('other-resolution', merged.payload, parents: [merged], resolves: [pending]);
    expect(
      planSyncMerge(
        history([...commits, resolution, otherResolution]),
        remote: resolution.id,
        local: otherResolution.id,
        validateTransaction: valid,
      ).reason,
      'pendingTransactions',
    );
    final concealedChoices = commit('concealed-choices', resolution.payload, parents: [resolution, otherResolution]);
    expect(
      planSyncMerge(
        history([...commits, resolution, otherResolution, concealedChoices]),
        remote: concealedChoices.id,
        validateTransaction: valid,
      ).reason,
      'invalidIntegration',
    );
    final concealed = commit('concealed', {...forged.payload, 'title': 'later'}, parents: [forged]);
    expect(
      planSyncMerge(history([...commits, forged, concealed]), remote: concealed.id, validateTransaction: valid).reason,
      'invalidIntegration',
    );
    final dropped = commit('dropped', merged.payload, parents: [merged]);
    expect(() => SyncGraph([...commits, dropped]), throwsFormatException);
    final invalid = commit('invalid', base.payload, parents: [base], resolves: [a.id]);
    expect(() => SyncGraph([base, a, invalid]), throwsFormatException);
    final duplicate = {
      ...merged.toJson(),
      'pending': [pending, pending],
    };
    expect(() => SyncCommit.fromJson(duplicate), throwsFormatException);
  });

  test('invalid transaction content and checkpoint errors retain branches', () {
    final base = commit('base', {'p': null, 'q': null});
    final invalid = commit('bad', {'p': 'q', 'q': 'p'}, parents: [base]);
    final other = commit('other', {...base.payload, 'title': 'ok'}, parents: [base]);
    expect(
      planSyncMerge(
        history([base, invalid, other]),
        remote: invalid.id,
        local: other.id,
        validateTransaction: valid,
      ).reason,
      'invalidTransactions',
    );
    final checkpoint = commit('merge', invalid.payload, parents: [invalid, other]);
    expect(
      planSyncMerge(
        history([base, invalid, other, checkpoint]),
        remote: checkpoint.id,
        validateTransaction: valid,
      ).reason,
      'invalidIntegration',
    );
  });

  test('explicit choice changes only edited paths including removals, arrays and new entities', () {
    final chosen = chooseSyncTransaction(
      {
        'remove': 1,
        'item': {'a': 1, 'b': 2},
        'order': ['a'],
      },
      {
        'item': {'a': 2, 'b': 2},
        'order': ['a', 'b'],
        'new': {'x': 1},
      },
      {
        'remove': 2,
        'item': {'a': 3, 'b': 4},
        'order': ['a'],
        'later': true,
      },
    );
    expect(chosen, {
      'item': {'a': 2, 'b': 4},
      'order': ['a', 'b'],
      'new': {'x': 1},
      'later': true,
    });
  });

  test('unknown baseline and deletion histories remain explicit recovery branches', () {
    final a = commit('a', {}), b = commit('b', {});
    expect(() => replay([a, b]), throwsFormatException);
    final deleted = SyncCommit.create(
      libraryId: 'library',
      scope: 'set',
      deviceId: 'delete',
      sequence: 1,
      parents: [a.id],
      payload: {},
      deleted: true,
    );
    expect(() => replay([a, deleted]), throwsFormatException);
    expect(
      () => SyncCommit.create(
        libraryId: 'library',
        scope: 'set',
        deviceId: 'delete',
        sequence: 1,
        payload: {},
        deleted: true,
        pending: [a.id],
      ),
      throwsFormatException,
    );
    expect(() => commit('bad', {}, pending: ['not-a-hash']), throwsFormatException);
  });
}
