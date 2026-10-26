import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

/// Disposable raw documents live outside .mmset packages. This API cannot address
/// research/snapshots, so clearing cache never garbage-collects retained evidence.
class ResearchWebCache implements ResearchDocumentCache {
  ResearchWebCache(Directory supportDirectory)
    : _directory = Directory(p.join(supportDirectory.path, 'research-cache'));
  final Directory _directory;
  Future<void> _queue = Future.value();
  File _file(Uri url) => File(p.join(_directory.path, '${sha256.convert(utf8.encode(url.toString()))}.html'));
  Future<void> _serialize(Future<void> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  @override
  Future<String?> read(Uri url) async {
    await _queue;
    final file = _file(url);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(Uri url, String html) => _serialize(() async {
    if (utf8.encode(html).length > 2097152) throw ArgumentError('Document exceeds cache limit');
    await _directory.create(recursive: true);
    final file = _file(url);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(html, flush: true);
    await temporary.rename(file.path);
  });
  @override
  Future<void> clear() => _serialize(() async {
    if (await _directory.exists()) await _directory.delete(recursive: true);
  });
}
