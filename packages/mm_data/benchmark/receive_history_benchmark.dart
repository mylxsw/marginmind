import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';

// Run from mm_data: dart run benchmark/receive_history_benchmark.dart 100 300
// Uses disposable synthetic repositories. No remote account or network.
Future<void> main(List<String> args) async {
  for (final count in args.isEmpty ? [100, 300] : args.map(int.parse)) {
    if (count < 2) throw ArgumentError.value(count);
    final root = await Directory.systemTemp.createTemp('sync-history-benchmark-');
    final sourceLedger = FileSyncLedger(Directory('${root.path}/source'), libraryId: 'benchmark', deviceId: 'source');
    final targetLedger = FileSyncLedger(Directory('${root.path}/target'), libraryId: 'benchmark', deviceId: 'target');
    final source = FileLibraryStore(sourceLedger.root, sync: sourceLedger);
    var target = FileLibraryStore(targetLedger.root, sync: targetLedger);
    try {
      final id = (await source.create(const NewStudySet(title: 'Source', colorIndex: 0))).id;
      var tip = (await sourceLedger.snapshots())['sets/$id']!.commit;
      final commits = [tip];
      while (commits.length < count) {
        tip = SyncCommit.create(
          libraryId: tip.libraryId,
          scope: tip.scope,
          deviceId: tip.deviceId,
          sequence: tip.sequence + 1,
          parents: [tip.id],
          payload: {...tip.payload, 'title': 'Version ${commits.length}'},
        );
        commits.add(tip);
      }
      final receive = Stopwatch()..start();
      await target.receiveSync(commits.reversed);
      receive.stop();
      final retry = Stopwatch()..start();
      await target.reconcileSync();
      retry.stop();
      await target.dispose();
      final reopen = Stopwatch()..start();
      final restored = (await FileSyncLedger.restore(targetLedger.root))!;
      target = FileLibraryStore(restored.root, sync: restored);
      final content = await target.watchAll().first;
      reopen.stop();
      if (content.single.title != 'Version ${count - 1}' ||
          !(await restored.history()).keys.toSet().containsAll(commits.map((c) => c.id))) {
        throw StateError('Lost received content/history');
      }
      print(
        jsonEncode({
          'commits': count,
          'receive_us': receive.elapsedMicroseconds,
          'retry_us': retry.elapsedMicroseconds,
          'reopen_us': reopen.elapsedMicroseconds,
        }),
      );
    } finally {
      await source.dispose();
      await target.dispose();
      await root.delete(recursive: true);
    }
  }
}
