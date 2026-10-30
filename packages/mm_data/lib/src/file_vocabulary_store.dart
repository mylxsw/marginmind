import 'dart:async';
import 'dart:convert';

import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';

import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

/// Application-wide vocabulary; saves are serialized and published only after
/// flush + rename. Unsupported or corrupt source files are never overwritten.
class FileVocabularyStore implements VocabularyRepository {
  FileVocabularyStore(this.root);
  FileVocabularyStore.browser() : this(browserRoot());
  final Directory root;
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
    if (!await _file.exists()) return const [];
    try {
      final j = jsonDecode(await _file.readAsString()) as Map;
      if (j['format'] is! int || j['format'] != 1) {
        throw const FormatException('Unsupported vocabulary format');
      }
      final entries = (j['entries'] as List).map((e) => VocabularyEntry.fromJson((e as Map).cast())).toList();
      _validate(entries);
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
      final bytes = utf8.encode(jsonEncode({'format': 1, 'entries': snapshot.map((e) => e.toJson()).toList()}));
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
      _entries = snapshot;
      _changes.add(snapshot);
    });
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
