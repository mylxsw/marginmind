import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

/// Atomic manifest + result envelope. Cross-instance and cross-process CAS use
/// a directory-scoped lock; result writes never invoke model generation.
class FileRunStore implements RunStore, RunReader {
  FileRunStore(this.studySetDirectory);
  final Directory studySetDirectory;
  static final _queues = <String, Future<void>>{};
  static final _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
  Future<T> _locked<T>(Future<T> Function(Directory) action) async {
    final root = await studySetDirectory.resolveSymbolicLinks();
    final previous = _queues[root] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[root] = done.future;
    await previous;
    try {
      var dir = Directory(root);
      for (final part in ['ai-runs', 'v1']) {
        dir = Directory(p.join(dir.path, part));
        await _noLink(dir.path);
        await dir.create();
      }
      final lockPath = p.join(dir.path, '.lock');
      await _noLink(lockPath);
      final lock = await File(lockPath).open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.blockingExclusive);
        return await action(dir);
      } finally {
        await lock.unlock();
        await lock.close();
      }
    } finally {
      done.complete();
      if (identical(_queues[root], done.future)) _queues.remove(root);
    }
  }

  static Future<void> _noLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) == FileSystemEntityType.link) {
      throw const FileSystemException('Run store refuses symbolic links');
    }
  }

  Future<File> _file(Directory dir, String id) async {
    if (!_id.hasMatch(id)) throw const FormatException('Invalid run ID');
    final file = File(p.join(dir.path, '$id.json'));
    await _noLink(file.path);
    return file;
  }

  Future<Map<String, dynamic>?> _read(File file) async {
    if (!await file.exists()) return null;
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (j['version'] != 1) throw const FormatException('Unsupported run envelope');
    final manifest = decodeRunManifest(Map<String, dynamic>.from(j['manifest']));
    if ('${manifest.context.runId}.json' != p.basename(file.path)) throw const FormatException('Run ID mismatch');
    return j;
  }

  @override
  Future<RunManifest?> load(String runId) => _locked((dir) async {
    final j = await _read(await _file(dir, runId));
    return j == null ? null : decodeRunManifest(Map<String, dynamic>.from(j['manifest']));
  });
  @override
  Future<Map<String, dynamic>?> loadResult(String runId) => _locked((dir) async {
    final j = await _read(await _file(dir, runId));
    return j?['result'] == null ? null : Map<String, dynamic>.from(j!['result']);
  });
  @override
  Future<void> checkpoint(RunManifest snapshot, {required int? expectedRevision}) =>
      _write(snapshot, null, expectedRevision);
  @override
  Future<void> complete(RunManifest snapshot, Map<String, dynamic> result, {required int expectedRevision}) {
    if (!{RunStatus.completed, RunStatus.partial, RunStatus.failed, RunStatus.cancelled}.contains(snapshot.status)) {
      throw ArgumentError('Completion requires terminal status');
    }
    return _write(snapshot, result, expectedRevision);
  }

  Future<void> _write(RunManifest snapshot, Map<String, dynamic>? result, int? expected) {
    final envelope = jsonEncode({'version': 1, 'manifest': encodeRunManifest(snapshot), 'result': result});
    return _locked((dir) async {
      final file = await _file(dir, snapshot.context.runId);
      final old = await _read(file);
      if (old != null && jsonEncode(old) == envelope) return; // lost ACK/repeated event
      final previous = old == null ? null : decodeRunManifest(Map<String, dynamic>.from(old['manifest']));
      if (previous?.revision != expected ||
          snapshot.revision != (expected ?? -1) + 1 ||
          (previous != null &&
              {
                RunStatus.completed,
                RunStatus.partial,
                RunStatus.failed,
                RunStatus.cancelled,
              }.contains(previous.status))) {
        throw const RunStoreConflict();
      }
      final tmp = File('${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
      try {
        await tmp.create(exclusive: true);
        await tmp.writeAsString(envelope, flush: true);
        await tmp.rename(file.path);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    });
  }

  @override
  Future<List<RunManifest>> resumable() => _locked((dir) async {
    final results = <RunManifest>[];
    await for (final file in dir.list(followLinks: false)) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final j = await _read(file);
      final m = decodeRunManifest(Map<String, dynamic>.from(j!['manifest']));
      if (runMayResume(m)) {
        results.add(m);
      }
    }
    return results;
  });
}
