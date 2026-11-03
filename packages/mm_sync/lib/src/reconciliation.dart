import 'commit.dart';
import 'merge.dart';

class MissingSyncParents implements Exception {
  MissingSyncParents(Iterable<String> ids) : ids = Set.unmodifiable(ids);
  final Set<String> ids;
}

/// Validate only the requested ancestry: another incomplete branch must not
/// stall unrelated work. Known duplicate device sequences still fail closed.
Map<String, SyncCommit> syncAncestry(
  Map<String, SyncCommit> known,
  Iterable<String> tips, {
  bool checkKnownForks = true,
}) {
  final result = <String, SyncCommit>{}, missing = <String>{};
  final todo = tips.toList();
  while (todo.isNotEmpty) {
    final id = todo.removeLast();
    if (result.containsKey(id)) continue;
    final commit = known[id];
    if (commit == null) {
      missing.add(id);
    } else {
      result[id] = commit;
      todo.addAll(commit.parents);
    }
  }
  if (missing.isNotEmpty) throw MissingSyncParents(missing);
  final sequences = {for (final c in result.values) (c.libraryId, c.scope, c.deviceId, c.sequence): c.id};
  for (final c in checkKnownForks ? known.values : const <SyncCommit>[]) {
    final id = sequences[(c.libraryId, c.scope, c.deviceId, c.sequence)];
    if (id != null && id != c.id) throw const FormatException('Device sequence fork');
  }
  SyncGraph(result.values);
  return result;
}

enum SyncMergeState { unchanged, ready, waiting, conflict }

/// Durable explanation refers to immutable input commits. Payload candidates
/// are not persisted here; the input versions remain in the receipt history.
class SyncMergePlan {
  SyncMergePlan({
    required this.remote,
    this.local,
    required this.state,
    required this.reason,
    this.payload,
    this.deleted = false,
    this.adopt = false,
    Iterable<String> bases = const [],
    Iterable<String> missing = const [],
    Iterable<SyncConflict> conflicts = const [],
  }) : bases = List.unmodifiable(bases),
       missing = List.unmodifiable(missing),
       conflicts = List.unmodifiable(conflicts);

  final String remote, reason;
  final String? local;
  final SyncMergeState state;
  final Map<String, Object?>? payload;
  final bool deleted, adopt;
  final List<String> bases, missing;
  final List<SyncConflict> conflicts;

  Map<String, Object?> toJson() => {
    'version': 1,
    'remote': remote,
    'local': local,
    'state': state.name,
    'reason': reason,
    'bases': bases,
    'missing': missing,
    'conflicts': [for (final c in conflicts) c.toJson()],
  };
}

/// Plan without IO. A ready candidate still needs domain validation and an
/// atomic expected-revision check before it can replace a local snapshot.
SyncMergePlan planSyncMerge(Map<String, SyncCommit> known, {required String remote, String? local}) {
  SyncMergePlan result(
    SyncMergeState state,
    String reason, {
    Map<String, Object?>? payload,
    bool deleted = false,
    bool adopt = false,
    Iterable<String> bases = const [],
    Iterable<String> missing = const [],
    Iterable<SyncConflict> conflicts = const [],
  }) => SyncMergePlan(
    remote: remote,
    local: local,
    state: state,
    reason: reason,
    payload: payload,
    deleted: deleted,
    adopt: adopt,
    bases: bases,
    missing: missing,
    conflicts: conflicts,
  );
  late Map<String, SyncCommit> ancestry;
  try {
    ancestry = syncAncestry(known, [remote, ?local]);
  } on MissingSyncParents catch (error) {
    return result(SyncMergeState.waiting, 'missingParents', missing: error.ids);
  } on FormatException {
    return result(SyncMergeState.conflict, 'invalidHistory');
  }
  final right = ancestry[remote]!;
  final graph = SyncGraph(ancestry.values);
  if (local != null) {
    final left = ancestry[local]!;
    if (left.scope != right.scope || left.libraryId != right.libraryId) {
      return result(SyncMergeState.conflict, 'differentScope');
    }
    if (graph.ancestors(local).contains(remote)) return result(SyncMergeState.unchanged, 'alreadyApplied');
  }
  if (local == null || graph.ancestors(remote).contains(local)) {
    return result(SyncMergeState.ready, 'fastForward', payload: right.payload, deleted: right.deleted, adopt: true);
  }
  final bases = graph.mergeBases(local, remote).toList()..sort();
  if (bases.length != 1) {
    return result(SyncMergeState.conflict, bases.isEmpty ? 'noBase' : 'multipleBases', bases: bases);
  }
  final left = ancestry[local]!, base = ancestry[bases.single]!;
  if (left.deleted || right.deleted || base.deleted) {
    if (left.deleted && right.deleted) {
      return result(SyncMergeState.ready, 'bothDeleted', payload: {}, deleted: true, bases: bases);
    }
    return result(SyncMergeState.conflict, 'deleteEdit', bases: bases);
  }
  final merged = mergeSyncObject(base.payload, left.payload, right.payload);
  return result(
    merged.conflicts.isEmpty ? SyncMergeState.ready : SyncMergeState.conflict,
    merged.conflicts.isEmpty ? 'merged' : 'fields',
    payload: merged.value,
    bases: bases,
    conflicts: merged.conflicts,
  );
}
