import 'dart:convert';
import 'dart:math';

import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

import 'support/history_fixture.dart' show buildHistory;

void main() {
  test('long carried conflict survives shuffled JSON reload and a later explicit choice', () {
    final original = buildHistory(2000, pending: true);
    final tip = original.values.last;
    final commits =
        original.values
            .map((c) => SyncCommit.fromJson((jsonDecode(jsonEncode(c.toJson())) as Map).cast<String, Object?>()))
            .toList()
          ..shuffle(Random(604));
    final history = {for (final c in commits) c.id: c};
    expect(SyncGraph(commits).ancestors(tip.id).length, 2000);
    final plan = planSyncMerge(history, remote: tip.id, validateTransaction: (_) {});
    expect(plan.payload, tip.payload);
    expect(plan.pending, tip.pending);
    final choice = SyncCommit.create(
      libraryId: tip.libraryId,
      scope: tip.scope,
      deviceId: 'choice',
      sequence: 1,
      parents: [tip.id],
      payload: tip.payload,
      resolves: tip.pending,
    );
    history[choice.id] = choice;
    final selected = planSyncMerge(history, remote: choice.id, local: tip.id, validateTransaction: (_) {});
    expect(selected.state, SyncMergeState.ready);
    expect(selected.pending, isEmpty);
    expect(selected.payload!['counter'], 1999);
    expect(history.keys, containsAll(original.keys));
  });

  test('long plain history retains every ancestor and unrelated roots have no base', () {
    final history = buildHistory(5000, pending: false);
    final unrelated = SyncCommit.create(
      libraryId: 'bench',
      scope: 'sets/a',
      deviceId: 'unrelated',
      sequence: 1,
      payload: {},
    );
    final graph = SyncGraph([...history.values.toList().reversed, unrelated]);
    expect(graph.ancestors(history.values.last.id).length, 5000);
    expect(graph.mergeBases(history.values.last.id, unrelated.id), isEmpty);
  });

  test('topological validation agrees with direct ancestry rules for generated DAGs', () {
    var accepted = 0, rejected = 0;
    for (var seed = 0; seed < 200; seed++) {
      final random = Random(seed), history = <String, SyncCommit>{};
      for (var i = 0; i < 15; i++) {
        final prior = history.values.toList()..shuffle(random);
        final parents = prior.take(random.nextInt(3)).toList();
        final eligible = prior.where((c) => c.parents.length == 1).map((c) => c.id).toList();
        var pending = parents.length == 1 ? parents.single.pending.toList() : <String>[];
        final resolves = <String>[];
        if (parents.length == 1 && pending.isNotEmpty && random.nextBool()) {
          resolves.add(pending.removeLast());
        }
        if (eligible.isNotEmpty && (parents.length > 1 || random.nextInt(8) == 0)) {
          pending = [eligible.first];
        }
        final c = SyncCommit.create(
          libraryId: 'l',
          scope: 's',
          deviceId: 'd$i',
          sequence: 1,
          parents: parents.map((p) => p.id).toList(),
          payload: {},
          pending: pending,
          resolves: resolves,
        );
        history[c.id] = c;
      }
      final expected = _directAncestryRules(history);
      final input = history.values.toList()..shuffle(random);
      if (expected) {
        accepted++;
        expect(() => SyncGraph(input), returnsNormally, reason: 'seed $seed');
      } else {
        rejected++;
        expect(() => SyncGraph(input), throwsFormatException, reason: 'seed $seed');
      }
    }
    expect(accepted, greaterThan(0));
    expect(rejected, greaterThan(0));
  });

  test('cycles are explicitly rejected even through a caller-supplied commit implementation', () {
    expect(() => SyncGraph([_CyclicCommit('a', 'b'), _CyclicCommit('b', 'a')]), throwsFormatException);
  });
}

// Deliberately uses full ancestor enumeration as a small-graph specification,
// independent of the optimized parent-before-child inheritance proof.
bool _directAncestryRules(Map<String, SyncCommit> history) {
  Set<String> ancestors(String id) {
    final result = <String>{}, todo = history[id]!.parents.toList();
    while (todo.isNotEmpty) {
      final parent = todo.removeLast();
      if (result.add(parent)) todo.addAll(history[parent]!.parents);
    }
    return result;
  }

  for (final c in history.values) {
    if (!ancestors(c.id).containsAll([...c.pending, ...c.resolves])) return false;
    if (c.pending.any((id) => history[id]?.parents.length != 1 || c.resolves.contains(id))) return false;
    if (c.parents.length == 1) {
      final expected = history[c.parents.single]!.pending.where((p) => !c.resolves.contains(p)).toSet();
      if (expected.length != c.pending.length || !expected.containsAll(c.pending)) return false;
    }
    if (c.resolves.isNotEmpty &&
        (c.parents.length != 1 || !c.resolves.every(history[c.parents.single]!.pending.contains))) {
      return false;
    }
  }
  return true;
}

class _CyclicCommit implements SyncCommit {
  _CyclicCommit(this.id, String parent) : parents = [parent];
  @override
  final String id;
  @override
  final List<String> parents;
  @override
  String get libraryId => 'l';
  @override
  String get scope => 's';
  @override
  String get deviceId => id;
  @override
  int get sequence => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
