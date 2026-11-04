import 'package:mm_sync/mm_sync.dart';

Map<String, SyncCommit> buildHistory(int count, {required bool pending}) {
  if (count < 4) throw ArgumentError.value(count, 'count');
  final history = <String, SyncCommit>{};
  SyncCommit add(SyncCommit c) {
    history[c.id] = c;
    return c;
  }

  var tip = add(
    SyncCommit.create(
      libraryId: 'bench',
      scope: 'sets/a',
      deviceId: 'a',
      sequence: 1,
      payload: {'title': 'base', 'counter': 0},
    ),
  );
  var sequence = 2;
  if (pending) {
    final left = add(
      SyncCommit.create(
        libraryId: 'bench',
        scope: 'sets/a',
        deviceId: 'b',
        sequence: 1,
        parents: [tip.id],
        payload: {'title': 'left', 'counter': 0},
      ),
    );
    final right = add(
      SyncCommit.create(
        libraryId: 'bench',
        scope: 'sets/a',
        deviceId: 'c',
        sequence: 1,
        parents: [tip.id],
        payload: {'title': 'right', 'counter': 0},
      ),
    );
    final plan = planSyncMerge(history, local: left.id, remote: right.id, validateTransaction: (_) {});
    tip = add(
      SyncCommit.create(
        libraryId: 'bench',
        scope: 'sets/a',
        deviceId: 'a',
        sequence: sequence++,
        parents: [left.id, right.id],
        payload: plan.payload!,
        pending: plan.pending,
      ),
    );
  }
  while (history.length < count) {
    tip = add(
      SyncCommit.create(
        libraryId: 'bench',
        scope: 'sets/a',
        deviceId: 'a',
        sequence: sequence++,
        parents: [tip.id],
        payload: {...tip.payload, 'counter': history.length},
        pending: tip.pending,
      ),
    );
  }
  return history;
}
