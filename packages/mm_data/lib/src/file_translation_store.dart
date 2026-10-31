import 'dart:convert';
import 'dart:isolate';

import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';
import 'translation_journal_io.dart' if (dart.library.js_interop) 'translation_journal_browser.dart';

import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

/// A study-set-scoped journal under `<set>.mmset/translations`.
/// Operations serialize by absolute document directory across store instances,
/// so deleting a document also waits for all of its languages' queued writes.
class FileTranslationStore implements TranslationStore {
  FileTranslationStore(this.packageRoot, {this.documentExists});

  /// Optional lifecycle guard; the library supplies this to reject late writes
  /// after a document or study set has been deleted.
  final bool Function(String)? documentExists;

  void _requireDocument(String id) {
    if (documentExists?.call(id) == false) throw StateError('Document no longer exists');
  }

  final Directory packageRoot;
  static final _queues = <String, Future<void>>{};

  String _component(String value) {
    if (value.isEmpty || value == '.' || value == '..' || RegExp(r'[/\\\x00-\x1f:]').hasMatch(value)) {
      throw ArgumentError.value(value, 'path component');
    }
    return value;
  }

  Directory get _root => Directory(p.join(packageRoot.path, 'translations'));
  Directory _document(String id) => Directory(p.join(_root.path, _component(id)));
  Directory _pair(String id, String lang) => Directory(p.join(_document(id).path, _component(lang)));
  File _file(String id, String lang, String name) => File(p.join(_pair(id, lang).path, name));

  Future<T> _serial<T>(String id, Future<T> Function() action) {
    final key = p.normalize(p.absolute(_document(id).path));
    final next = (_queues[key] ?? Future<void>.value()).then((_) => action());
    final settled = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _queues[key] = settled;
    settled.then((_) {
      if (identical(_queues[key], settled)) _queues.remove(key);
    });
    return next;
  }

  @override
  Future<TranslationSnapshot> load(String documentId, String targetLang) =>
      _serial(documentId, () => _read(documentId, targetLang));

  Future<TranslationSnapshot> _read(String id, String lang) async {
    final file = _file(id, lang, 'segments.jsonl');
    if (!await file.exists()) return TranslationSnapshot();
    final bytes = await file.readAsBytes();
    // Parsing large journals never blocks the Flutter UI isolate on native.
    if (const bool.fromEnvironment('dart.library.js_interop')) return _parse(bytes);
    return Isolate.run(() => _parse(bytes));
  }

  static TranslationSnapshot _parse(List<int> bytes) {
    final segments = <String, TranslationSegment>{};
    var start = 0, lines = 0, corrupt = 0, overwritten = 0;
    var badTail = false;
    for (var end = 0; end < bytes.length; end++) {
      if (bytes[end] != 10) continue;
      lines++;
      try {
        final json = jsonDecode(utf8.decode(bytes.sublist(start, end))) as Map;
        final segment = TranslationSegment.fromJson(json.cast());
        if (segments.containsKey(segment.key)) overwritten++;
        segments[segment.key] = segment;
      } on FormatException {
        if (end == bytes.length - 1) {
          badTail = true;
        } else {
          corrupt++;
        }
      } on TypeError {
        if (end == bytes.length - 1) {
          badTail = true;
        } else {
          corrupt++;
        }
      } on ArgumentError {
        if (end == bytes.length - 1) {
          badTail = true;
        } else {
          corrupt++;
        }
      }
      start = end + 1;
    }
    // Even syntactically valid JSON without the commit newline is a torn tail.
    return TranslationSnapshot(
      segments: segments,
      lineCount: lines,
      corruptLines: corrupt,
      overwrittenLines: overwritten,
      discardedTail: badTail || start < bytes.length,
    );
  }

  @override
  Future<void> append(String documentId, String targetLang, TranslationSegment segment) =>
      _serial(documentId, () => _append(documentId, targetLang, segment));

  Future<void> _append(String id, String lang, TranslationSegment segment) async {
    _requireDocument(id);
    final file = _file(id, lang, 'segments.jsonl');
    await file.parent.create(recursive: true);
    await appendTranslationLine(file, utf8.encode('${jsonEncode(segment.toJson())}\n'));
  }

  @override
  Future<void> compact(String documentId, String targetLang) => _serial(documentId, () async {
    final snapshot = await _read(documentId, targetLang);
    if (!snapshot.needsCompaction) return;
    final contents = snapshot.segments.values.map((s) => '${jsonEncode(s.toJson())}\n').join();
    await _atomic(_file(documentId, targetLang, 'segments.jsonl'), utf8.encode(contents));
  });

  Future<void> _atomic(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      // If cleanup also fails, leave the harmless temp for the next write.
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        /* original error wins */
      }
    }
  }

  @override
  Future<TranslationJob?> loadJob(String documentId, String targetLang) => _serial(documentId, () async {
    final file = _file(documentId, targetLang, 'job.json');
    if (!await file.exists()) return null;
    try {
      var job = TranslationJob.fromJson((jsonDecode(await file.readAsString()) as Map).cast());
      if (job.documentId != documentId || job.targetLang != targetLang) return null;
      if (job.state == TranslationJobState.running || job.state == TranslationJobState.offline) {
        job = job.copyWith(state: TranslationJobState.paused, pauseReason: TranslationPauseReason.quit);
      }
      return job;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  });

  @override
  Future<void> saveJob(TranslationJob job) => _serial(job.documentId, () {
    _requireDocument(job.documentId);
    return _atomic(_file(job.documentId, job.targetLang, 'job.json'), utf8.encode(jsonEncode(job.toJson())));
  });

  File _legacyTombstone(String id, String lang) =>
      File(p.join(_document(id).path, '.removed-legacy-${_component(lang)}'));

  @override
  Future<void> remove(String documentId, String targetLang) => _serial(documentId, () async {
    // Persist first: a crash between this marker and directory deletion cannot
    // resurrect read-only studyset.json caches on the next open.
    await _atomic(_legacyTombstone(documentId, targetLang), utf8.encode('1'));
    final dir = _pair(documentId, targetLang);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Deletes every language when a document is removed from its study set.
  Future<void> removeDocument(String documentId) => _serial(documentId, () async {
    final dir = _document(documentId);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Removes orphan directories after successfully decoding studyset.json.
  /// Directory enumeration never follows symlinks.
  Future<void> cleanOrphans(Set<String> documentIds) async {
    if (!await _root.exists()) return;
    await for (final entry in _root.list(followLinks: false)) {
      if (entry is Directory && !documentIds.contains(p.basename(entry.path))) {
        await removeDocument(p.basename(entry.path));
      }
    }
  }

  /// Read-only legacy bridge. Exact fingerprint/document/language matches are
  /// copied to content keys; new-format values (especially edits) always win.
  /// Call after segmentation, before estimating or requesting missing text.
  @override
  Future<TranslationSnapshot> importLegacy(
    String documentId,
    String targetLang, {
    required Iterable<TranslationParagraph> paragraphs,
    required Iterable<TranslationCache> caches,
  }) {
    final inputs = paragraphs.toList(), legacy = caches.toList();
    return _serial(documentId, () async {
      if (await _legacyTombstone(documentId, targetLang).exists()) return _read(documentId, targetLang);
      final known = Map<String, TranslationSegment>.of((await _read(documentId, targetLang)).segments);
      for (final cache in legacy) {
        if (cache.documentId != documentId || cache.targetLang != targetLang) continue;
        for (final paragraph in inputs) {
          if (paragraph.documentId != documentId) continue;
          final key = textKey(paragraph.text, targetLang);
          final text = cache.paragraphs[paragraph.fingerprint];
          if (known.containsKey(key) || text == null || text.trim().isEmpty) continue;
          final segment = TranslationSegment(
            key: key,
            fingerprint: paragraph.fingerprint,
            page: paragraph.textAnchor == null ? paragraph.page : paragraph.index + 1,
            index: paragraph.index,
            text: text,
            model: cache.model,
            profile: '',
            origin: TranslationOrigin.legacy,
            at: cache.createdAt,
          );
          await _append(documentId, targetLang, segment);
          known[key] = segment;
        }
      }
      return _read(documentId, targetLang);
    });
  }
}
