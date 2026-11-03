import 'dart:async';
import 'dart:convert';

import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';

import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import 'file_sync_ledger.dart';

/// Application-wide vocabulary; saves are serialized and published only after
/// flush + rename. Unsupported or corrupt source files are never overwritten.
class FileVocabularyStore implements VocabularyRepository {
  // Public option for a private field that may be restored lazily.
  // ignore: prefer_initializing_formals
  FileVocabularyStore(this.root, {FileSyncLedger? sync}) : _sync = sync;
  FileVocabularyStore.browser({FileSyncLedger? sync}) : this(browserRoot(), sync: sync);
  final Directory root;
  FileSyncLedger? _sync;
  bool _syncChecked = false;
  String? _revision;
  File get _file => File(p.join(root.path, 'vocabulary.json'));
  List<VocabularyEntry>? _entries;
  Future<void> _queue = Future.value();
  final _changes = StreamController<List<VocabularyEntry>>.broadcast();

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<List<VocabularyEntry>> _read() async {
    if (!_syncChecked) {
      _sync ??= await FileSyncLedger.restore(root);
      if (_sync != null && p.normalize(p.absolute(_sync!.root.path)) != p.normalize(p.absolute(root.path))) {
        throw ArgumentError('Sync ledger must belong to this library');
      }
      _syncChecked = true;
    }
    try {
      final snapshot = (await _sync?.snapshots())?['vocabulary'];
      if (snapshot?.deleted == true) throw const FormatException('Vocabulary aggregate cannot be deleted');
      final j =
          snapshot?.value ??
          (await _file.exists()
              ? jsonDecode(await _file.readAsString()) as Map
              : {'format': 1, 'entries': <Object?>[]});
      if (j['format'] is! int || j['format'] != 1) {
        throw const FormatException('Unsupported vocabulary format');
      }
      final entries = (j['entries'] as List).map((e) => VocabularyEntry.fromJson((e as Map).cast())).toList();
      _validate(entries);
      if (_sync case final sync?) {
        final heads = snapshot == null
            ? await sync.commit(
                [SyncMutation('vocabulary', local: j.cast<String, Object?>(), shared: j.cast<String, Object?>())],
                expected: {'vocabulary': null},
              )
            : {'vocabulary': snapshot};
        _revision = heads['vocabulary']!.revision;
        await sync.project(_file.path, () => _write(j));
      }
      return List.unmodifiable(entries);
    } on TypeError catch (error) {
      throw FormatException('Invalid vocabulary: $error');
    } on ArgumentError catch (error) {
      throw FormatException('Invalid vocabulary: $error');
    }
  }

  void _validate(List<VocabularyEntry> entries) {
    final ids = <String>{}, keys = <(String, String)>{};
    for (final e in entries) {
      if (!ids.add(e.id) || !keys.add((e.language, e.key))) {
        throw const FormatException('Duplicate vocabulary entry');
      }
    }
  }

  @override
  Future<List<VocabularyEntry>> load() => _serial(() async => _entries ??= await _read());
  @override
  Future<void> save(List<VocabularyEntry> entries) {
    final snapshot = List<VocabularyEntry>.unmodifiable(entries);
    return _serial(() async {
      // Validate disk even before a first save and after an external corruption.
      await _read();
      _validate(snapshot);
      final value = <String, Object?>{'format': 1, 'entries': snapshot.map((e) => e.toJson()).toList()};
      if (_sync case final sync?) {
        final heads = await sync.commit(
          [SyncMutation('vocabulary', local: value, shared: value)],
          expected: {'vocabulary': _revision},
        );
        _revision = heads['vocabulary']!.revision;
        await sync.project(_file.path, () => _write(value));
      } else {
        await _write(value);
      }
      _entries = snapshot;
      _changes.add(snapshot);
    });
  }

  Future<void> _write(Map value) async {
    final bytes = utf8.encode(jsonEncode(value));
    await root.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(_file.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        /* Preserve original failure. */
      }
      rethrow;
    }
  }

  @override
  Stream<List<VocabularyEntry>> watch() => Stream.multi((out) {
    StreamSubscription<List<VocabularyEntry>>? sub;
    var cancelled = false;
    out.onCancel = () async {
      cancelled = true;
      await sub?.cancel();
    };
    _serial(() async {
      try {
        final entries = _entries ??= await _read();
        if (cancelled) return;
        sub = _changes.stream.listen(out.add, onError: out.addError, onDone: out.close);
        out.add(entries);
      } catch (error, stack) {
        if (!cancelled) out.addError(error, stack);
      }
    });
  });

  /// Wait for all queued reads and writes.
  Future<void> flush() => _queue;

  /// Flush and release stream resources when the owning scope closes.
  Future<void> dispose() async {
    await flush();
    await _changes.close();
  }
}
