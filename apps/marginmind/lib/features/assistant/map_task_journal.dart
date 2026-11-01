import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Domain workflow index. Runtime owns paid results and usage; this journal
/// owns the original command, frozen route, stable stage IDs and repair inputs.
/// It contains no credentials. Opening it never dispatches a model request.
class MapTaskJournal {
  MapTaskJournal(this.directory);
  final String directory;
  static final _queues = <String, Future<void>>{};

  Future<T> _locked<T>(Future<T> Function(Directory) action) async {
    final root = await Directory(directory).resolveSymbolicLinks();
    final previous = _queues[root] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[root] = done.future;
    await previous;
    try {
      var dir = Directory(root);
      for (final part in ['ai-map-tasks', 'v1']) {
        dir = Directory(p.join(dir.path, part));
        await _noLink(dir.path);
        await dir.create();
      }
      final lockFile = p.join(dir.path, '.lock');
      await _noLink(lockFile);
      final lock = await File(lockFile).open(mode: FileMode.append);
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
      throw const FileSystemException('Map journal refuses symbolic links');
    }
  }

  Future<File> _file(Directory dir, String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) throw const FormatException('Invalid map session');
    final file = File(p.join(dir.path, '$id.json'));
    await _noLink(file.path);
    return file;
  }

  Future<Map<String, dynamic>> _read(File file) async {
    final data = Map<String, dynamic>.from(jsonDecode(await file.readAsString()));
    if (data['version'] != 1 || '${data['id']}.json' != p.basename(file.path)) {
      throw const FormatException('Invalid map journal');
    }
    return data;
  }

  Future<Map<String, dynamic>> load(String id) => _locked((dir) async => _read(await _file(dir, id)));

  Future<List<Map<String, dynamic>>> list() => _locked((dir) async {
    final result = <Map<String, dynamic>>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final data = await _read(entity);
      if (data['dismissed'] != true && data['workflow'] != null) result.add(data);
    }
    return result;
  });

  Future<void> update(String id, void Function(Map<String, dynamic>) change) => _locked((dir) async {
    final file = await _file(dir, id);
    final data = await file.exists() ? await _read(file) : <String, dynamic>{'version': 1, 'id': id, 'stages': {}};
    change(data);
    final tmp = File('${file.path}.$pid.tmp');
    await _noLink(tmp.path);
    try {
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(file.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  });
}
