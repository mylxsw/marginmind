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
  final choices = syncConcurrentChoices(ancestry, graph: graph);
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
    if (choices[c.id] != null) {
      pending.add(PendingSyncTransaction(c.id, 'concurrentChoices', const []));
      continue;
    }
    final before = ancestry[c.parents.single]!.payload;
    final merged = mergeSyncObject(before, value, c.payload);
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

/// Human choices carry the intent of the reviewed transactions, even when
/// keeping the displayed value produced no delta. Nested choices retain that
/// intent, including atomic companion changes and removals.
List<List<String>> syncTransactionPaths(Map<String, SyncCommit> history, String id) {
  final memo = <String, List<List<String>>>{};
  List<List<String>> paths(String id) => memo.putIfAbsent(id, () {
    final c = history[id]!;
    final result = <List<String>>[];
    void diff(Object? a, Object? b, List<String> path) {
      if (contentValueEquals(a, b)) return;
      if (a is Map && b is Map) {
        for (final key in {...a.keys.cast<String>(), ...b.keys.cast<String>()}) {
          diff(a.containsKey(key) ? a[key] : contentMissing, b.containsKey(key) ? b[key] : contentMissing, [
            ...path,
            key,
          ]);
        }
      } else {
        result.add(path);
      }
    }

    diff(history[c.parents.single]!.payload, c.payload, const []);
    for (final target in c.resolves) {
      result.addAll(paths(target));
    }
    // A whole-entity write subsumes its child paths. Do not recreate a deleted
    // entity by subsequently applying one of its old child paths.
    final unique = <List<String>>[];
    result.sort((a, b) => a.length.compareTo(b.length));
    for (final path in result) {
      if (!unique.any((p) => p.length <= path.length && contentValueEquals(p, path.take(p.length).toList()))) {
        unique.add(List.unmodifiable(path));
      }
    }
    return List.unmodifiable(unique);
  });
  return paths(id);
}

Object? syncValueAt(Map<String, Object?> payload, List<String> path) {
  Object? value = payload;
  for (final key in path) {
    if (value is! Map || !value.containsKey(key)) return contentMissing;
    value = value[key];
  }
  return value;
}

Map<String, Object?> _applyPaths(Map<String, Object?> current, Map<String, Object?> source, List<List<String>> paths) {
  Object? write(Object? node, List<String> path, Object? value) {
    if (path.isEmpty) return value;
    if (node is! Map && value == contentMissing) return node;
    final result = node is Map ? Map<String, Object?>.from(node) : <String, Object?>{};
    final key = path.first;
    final next = write(result.containsKey(key) ? result[key] : contentMissing, path.sublist(1), value);
    if (next == contentMissing) {
      result.remove(key);
    } else {
      result[key] = next;
    }
    return result;
  }

  var value = current;
  for (final path in paths) {
    value = write(value, path, syncValueAt(source, path)) as Map<String, Object?>;
  }
  return value;
}

Map<String, Object?> chooseSyncCandidate(Map<String, SyncCommit> history, String id, Map<String, Object?> current) {
  final c = history[id]!;
  return c.resolves.isEmpty
      ? chooseSyncTransaction(history[c.parents.single]!.payload, c.payload, current)
      : _applyPaths(current, c.payload, syncTransactionPaths(history, id));
}

/// Connected sets of concurrent, still-unreviewed choices of the same original
/// transactions. All members remain pending, including identical/no-op choices.
/// A later explicit choice reviews the whole observed group; a late unseen
/// choice remains a new candidate instead of being silently discarded.
Map<String, Set<String>> syncConcurrentChoices(Map<String, SyncCommit> history, {SyncGraph? graph}) {
  graph ??= SyncGraph(history.values);
  final resolved = {for (final c in history.values) ...c.resolves};
  final choices = history.values.where((c) => c.resolves.isNotEmpty && !resolved.contains(c.id)).toList();
  final roots = <String, Set<String>>{};
  Set<String> targets(String id) => roots.putIfAbsent(id, () {
    final c = history[id]!;
    return c.resolves.isEmpty ? {id} : {for (final target in c.resolves) ...targets(target)};
  });
  final groups = <String, Set<String>>{};
  for (var i = 0; i < choices.length; i++) {
    final a = choices[i];
    for (final b in choices.skip(i + 1)) {
      if (targets(a.id).intersection(targets(b.id)).isEmpty ||
          graph.ancestors(a.id).contains(b.id) ||
          graph.ancestors(b.id).contains(a.id)) {
        continue;
      }
      final group = {...?groups[a.id], ...?groups[b.id], a.id, b.id};
      for (final id in group) {
        groups[id] = group;
      }
    }
  }
  return groups;
}

List<String> syncChoiceGroup(Map<String, SyncCommit> ancestry, String id) =>
    (syncConcurrentChoices(ancestry)[id] ?? {id}).toList()..sort();

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
