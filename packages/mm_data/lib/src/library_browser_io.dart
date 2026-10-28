// This adapter deliberately implements only the file operations used by the
// shared package store. JSON codecs, migrations and write ordering stay shared.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:path/path.dart' as p;

class BrowserFiles {
  BrowserFiles._();
  static web.IDBDatabase? _db;
  static final _files = <String, Uint8List>{};
  static final _urls = <String, String>{};

  /// Hydrate before exposing the repository. Only completed IDB transactions
  /// update the cache, so quota/transaction failures never acknowledge a write.
  static Future<void> open({String name = 'marginmind-library'}) async {
    if (_db != null) return;
    final request = web.window.indexedDB.open(name, 1);
    request.onupgradeneeded = ((web.Event event) {
      (request.result as web.IDBDatabase).createObjectStore('files');
    }).toJS;
    final db = await _request(request) as web.IDBDatabase;
    final transaction = db.transaction('files'.toJS, 'readonly');
    final completed = _completed(transaction);
    final store = transaction.objectStore('files');
    final keysRequest = _request(store.getAllKeys());
    final valuesRequest = _request(store.getAll());
    final keys = (await keysRequest as JSArray<JSString>).toDart;
    final values = (await valuesRequest as JSArray<JSUint8Array>).toDart;
    await completed;
    final files = <String, Uint8List>{for (var i = 0; i < keys.length; i++) keys[i].toDart: values[i].toDart};
    _files.addAll(files);
    _db = db;
  }

  static Future<void> commit(Map<String, Uint8List> writes, Iterable<String> deletes) async {
    final db = _db ?? (throw StateError('Open browser storage before use'));
    final removed = deletes.toList();
    final tx = db.transaction('files'.toJS, 'readwrite');
    final completed = _completed(tx);
    final store = tx.objectStore('files');
    final names = {...removed, ...writes.keys};
    var remaining = names.length;
    // Compare against the version this tab loaded in the same transaction.
    // Another tab may have edited the package since then; never overwrite it.
    for (final name in names) {
      final request = store.get(name.toJS);
      request.onsuccess = ((web.Event _) {
        final current = request.result;
        final bytes = current == null ? null : (current as JSUint8Array).toDart;
        final expected = _files[name];
        if (!_equal(bytes, expected)) {
          tx.abort();
          return;
        }
        if (--remaining == 0) {
          for (final name in removed) {
            store.delete(name.toJS);
          }
          for (final entry in writes.entries) {
            store.put(entry.value.toJS, entry.key.toJS);
          }
        }
      }).toJS;
    }
    await completed;
    for (final name in {...removed, ...writes.keys}) {
      final url = _urls.remove(name);
      if (url != null) web.URL.revokeObjectURL(url);
    }
    for (final name in removed) {
      _files.remove(name);
    }
    _files.addAll(writes);
  }

  static void close() {
    _db?.close();
    _db = null;
    _files.clear();
    for (final url in _urls.values) {
      web.URL.revokeObjectURL(url);
    }
    _urls.clear();
  }
}

String resourcePath(String path) {
  final bytes = BrowserFiles._files[path];
  if (bytes == null) return path;
  return BrowserFiles._urls.putIfAbsent(path, () => web.URL.createObjectURL(web.Blob([bytes.toJS].toJS)));
}

class FileSystemException implements Exception {
  const FileSystemException(this.message, [this.path = '']);
  final String message, path;
  @override
  String toString() => 'FileSystemException: $message ($path)';
}

class Directory {
  Directory(this.path);
  final String path;
  Future<Directory> create({bool recursive = false}) async => this;
  Future<bool> exists() async => BrowserFiles._files.keys.any((key) => p.isWithin(path, key));
  Stream<Object> list({bool followLinks = true}) async* {
    final dirs = <String>{};
    for (final name in BrowserFiles._files.keys.toList()) {
      if (!p.isWithin(path, name)) continue;
      final relative = p.relative(name, from: path);
      final parts = p.split(relative);
      if (parts.length == 1) {
        yield File(name);
      } else if (dirs.add(parts.first)) {
        yield Directory(p.join(path, parts.first));
      }
    }
  }

  Future<void> delete({bool recursive = false}) =>
      BrowserFiles.commit({}, BrowserFiles._files.keys.where((key) => p.isWithin(path, key)));
}

class File {
  File(this.path);
  final String path;
  Directory get parent => Directory(p.dirname(path));
  Future<bool> exists() async => BrowserFiles._files.containsKey(path);
  Future<Uint8List> readAsBytes() async {
    final bytes = BrowserFiles._files[path];
    if (bytes != null) return Uint8List.fromList(bytes);
    // Browser file_selector exposes a blob URL, never a host filesystem path.
    if (path.startsWith('blob:') || path.startsWith('data:')) {
      final response = await web.window.fetch(path.toJS).toDart;
      if (!response.ok) throw FileSystemException('Cannot read selected file', path);
      return (await response.arrayBuffer().toDart).toDart.asUint8List();
    }
    throw FileSystemException('File not found', path);
  }

  Future<String> readAsString() async => utf8.decode(await readAsBytes());
  Future<void> writeAsBytes(List<int> bytes, {bool flush = false}) =>
      BrowserFiles.commit({path: Uint8List.fromList(bytes)}, []);
  Future<void> copy(String target) async => File(target).writeAsBytes(await readAsBytes());
  Future<void> rename(String target) async => BrowserFiles.commit({target: await readAsBytes()}, [path]);
  Future<void> delete() => BrowserFiles.commit({}, [path]);
}

Directory browserRoot() => Directory('/Library');

Future<JSAny?> _request(web.IDBRequest request) {
  final result = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) {
    result.complete(request.result);
  }).toJS;
  request.onerror = ((web.Event _) {
    result.completeError(StateError(request.error?.message ?? 'IndexedDB request failed'));
  }).toJS;
  return result.future;
}

Future<void> _completed(web.IDBTransaction transaction) {
  final result = Completer<void>();
  transaction.oncomplete = ((web.Event _) {
    result.complete();
  }).toJS;
  transaction.onabort = ((web.Event _) {
    result.completeError(FileSystemException(transaction.error?.message ?? 'IndexedDB transaction aborted'));
  }).toJS;
  return result.future;
}

bool _equal(Uint8List? a, Uint8List? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
