import 'package:mm_core/mm_core.dart';

import 'commit.dart';
import 'merge.dart';

/// An entire repository write is withheld when any of its changes conflicts.
/// The immutable transaction and its parent retain both complete candidates.
class PendingSyncTransaction {
  PendingSyncTransaction(this.transaction, this.reason, this.conflicts);
  final String transaction, reason;
  final List<SyncConflict> conflicts;
}

/// Concurrent human choices need an explicit reconciliation of those choices.
/// Never infer a winner merely from the display ordering of edit transactions.
class ConcurrentSyncResolutions implements Exception {
  const ConcurrentSyncResolutions();
}

class SyncReplayResult {
  SyncReplayResult(this.payload, this.pending);
  final Map<String, Object?> payload;
  final List<PendingSyncTransaction> pending;
}

/// Deterministic projection of a complete, single-root live history. Merge
/// commits are integration checkpoints, not new user edits. Single-parent
/// commits supply atomic deltas against their own observed parent snapshot.
/// A later transaction changing an unrelated field can therefore proceed even
/// when an earlier transaction from that device is still unresolved.
///
/// The stable ordering chooses a DISPLAY candidate, not a conflict resolution.
/// Unapplied transactions must travel in the resulting commit's pending list.
/// Domain validation runs before publishing each atomic candidate, so a failed
/// structural move cannot partly create cards, highlights or dangling nodes.
SyncReplayResult replaySyncTransactions(
  Map<String, SyncCommit> ancestry, {
  required void Function(Map<String, Object?>) validate,
}) {
  final graph = SyncGraph(ancestry.values);
  final roots = ancestry.values.where((c) => c.parents.isEmpty).toList();
  if (roots.length != 1 || ancestry.values.any((c) => c.deleted)) {
    throw const FormatException('Transaction replay requires one live baseline');
  }
  for (final c in ancestry.values) {
    validate(c.payload);
  }
  final resolutions = ancestry.values.where((c) => c.resolves.isNotEmpty).toList();
  for (var i = 0; i < resolutions.length; i++) {
    for (final other in resolutions.skip(i + 1)) {
      final c = resolutions[i];
      if (c.resolves.any(other.resolves.contains) &&
          !graph.ancestors(c.id).contains(other.id) &&
          !graph.ancestors(other.id).contains(c.id)) {
        throw const ConcurrentSyncResolutions();
      }
    }
  }
  final root = roots.single;
  var value = root.payload;
  final resolved = {for (final c in ancestry.values) ...c.resolves};
  final events = {for (final c in ancestry.values.where((c) => c.parents.length == 1)) c.id: c};
  // Ignore integration checkpoint IDs in the tie-break: their arrival/device
  // must not affect ordering of the actual edits.
  final frontiers = <String, Set<String>>{};
  Set<String> frontier(String id) => frontiers.putIfAbsent(id, () {
    final c = ancestry[id]!;
    return c.parents.length == 1 ? {id} : {for (final parent in c.parents) ...frontier(parent)};
  });
  final children = {for (final id in events.keys) id: <String>[]};
  final remaining = <String, int>{};
  for (final c in events.values) {
    final dependencies = frontier(c.parents.single);
    remaining[c.id] = dependencies.length;
    for (final id in dependencies) {
      children[id]!.add(c.id);
    }
  }
  final ready = events.keys.where((id) => remaining[id] == 0).toList();
  final pending = <PendingSyncTransaction>[];
  var visited = 0;
  while (ready.isNotEmpty) {
    ready.sort();
    final c = events[ready.removeAt(0)]!;
    visited++;
    for (final child in children[c.id]!) {
      remaining[child] = remaining[child]! - 1;
      if (remaining[child] == 0) ready.add(child);
    }
    if (resolved.contains(c.id)) continue;
    final merged = mergeSyncObject(ancestry[c.parents.single]!.payload, value, c.payload);
    if (merged.conflicts.isNotEmpty) {
      pending.add(PendingSyncTransaction(c.id, 'fields', merged.conflicts));
      continue;
    }
    try {
      validate(merged.value);
    } on FormatException {
      pending.add(PendingSyncTransaction(c.id, 'structure', const []));
      continue;
    }
    value = merged.value;
  }
  if (visited != events.length) throw const FormatException('Cyclic transaction history');
  return SyncReplayResult(value, List.unmodifiable(pending));
}

/// Explicitly choose one pending transaction's changes against today's state.
/// Only its changed paths are replaced; unrelated later edits stay intact.
/// The caller must validate the whole result and commit with a revision CAS.
Map<String, Object?> chooseSyncTransaction(
  Map<String, Object?> before,
  Map<String, Object?> after,
  Map<String, Object?> current,
) {
  Object? apply(Object? a, Object? b, Object? now) {
    if (contentValueEquals(a, b)) return now;
    if (a is Map && b is Map && now is Map) {
      final result = Map<String, Object?>.from(now);
      for (final key in {...a.keys.cast<String>(), ...b.keys.cast<String>()}) {
        final value = apply(
          a.containsKey(key) ? a[key] : contentMissing,
          b.containsKey(key) ? b[key] : contentMissing,
          now.containsKey(key) ? now[key] : contentMissing,
        );
        if (value == contentMissing) {
          result.remove(key);
        } else {
          result[key] = value;
        }
      }
      return result;
    }
    return b;
  }

  return apply(before, after, current) as Map<String, Object?>;
}
