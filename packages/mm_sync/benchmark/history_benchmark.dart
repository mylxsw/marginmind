import 'dart:convert';

import 'package:mm_sync/mm_sync.dart';

import '../test/support/history_fixture.dart';

// Run from mm_sync: dart run benchmark/history_benchmark.dart 1000 5000
// Synthetic metadata histories; no filesystem/network, attachments or UI.
// Report construction separately, and do not make wall time a test assertion.
void main(List<String> args) {
  for (final count in args.isEmpty ? [1000, 5000] : args.map(int.parse)) {
    for (final pending in [false, true]) {
      final preparation = Stopwatch()..start();
      final history = buildHistory(count, pending: pending);
      preparation.stop();
      final commits = history.values.toList(), tip = commits.last;
      final runs = <int>[];
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        final graph = SyncGraph(commits.reversed);
        watch.stop();
        if (graph.ancestors(tip.id).length != history.length) throw StateError('Lost ancestors');
        runs.add(watch.elapsedMicroseconds);
      }
      runs.sort();
      final watch = Stopwatch()..start();
      final plan = planSyncMerge(history, remote: tip.id, local: commits.first.id, validateTransaction: (_) {});
      watch.stop();
      if (plan.state != SyncMergeState.ready || plan.pending.length != (pending ? 1 : 0)) {
        throw StateError('Changed replay semantics: ${plan.reason}');
      }
      print(
        jsonEncode({
          'scenario': pending ? 'carried_conflict' : 'linear',
          'commits': history.length,
          'build_us': preparation.elapsedMicroseconds,
          'graph_median_us': runs[1],
          'plan_us': watch.elapsedMicroseconds,
          'pending': plan.pending.length,
        }),
      );
    }
  }
}
