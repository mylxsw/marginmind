import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';

/// Immutable source text and resource descriptors, with no drawable paragraphs.
class ReflowDocument {
  ReflowDocument(this.document, this.chapters, this.toc, this.resources, this.read);
  final Document document;
  final List<BookChapter> chapters;
  final List<BookTocEntry> toc;
  final Map<String, Map<String, Object?>> resources;
  final Future<List<int>> Function(String) read;
  String get revision => document.revision!;
  int get length => chapters.fold(0, (n, c) => n + math.max(1, c.canonicalText.length));

  static Future<ReflowDocument> load(DocumentRepository repo, String setId, Document document) async {
    final manifest = document.contentManifest!;
    final base = 'books/${document.id}/${document.revision}/';
    if (manifest != '${base}manifest.json') throw const FormatException('Invalid book manifest path');
    var bytesRead = 0;
    Future<List<int>> read(String path) async {
      validateDocumentPath(path);
      if (!path.startsWith(base)) throw const FormatException('Resource outside document version');
      final bytes = await repo.readDocumentFile(setId, path);
      return bytes;
    }

    Future<Map<String, Object?>> json(String path, [String? digest]) async {
      final bytes = await read(path);
      bytesRead += bytes.length;
      if (bytesRead > 64 * 1024 * 1024) throw const FormatException('Book IR exceeds limit');
      if (digest != null && sha256.convert(bytes).toString() != digest) {
        throw const FormatException('Chapter digest mismatch');
      }
      return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    }

    final data = await json(manifest);
    if (data['version'] != 1 ||
        data['normalizationVersion'] != 1 ||
        data['revision'] != document.revision ||
        document.revision?.isNotEmpty != true) {
      throw const FormatException('Unsupported book revision');
    }
    final chapters = <BookChapter>[];
    for (final raw in data['spine'] as List) {
      final entry = raw as Map;
      final chapter = BookChapter.fromJson(await json(entry['path'] as String, entry['sha256'] as String));
      if (chapter.id != entry['id'] || chapters.any((c) => c.id == chapter.id)) {
        throw const FormatException('Invalid spine');
      }
      chapters.add(chapter);
    }
    if (chapters.isEmpty) throw const FormatException('Empty spine');
    BookTocEntry toc(Map e) => BookTocEntry(
      e['id'] as String,
      e['title'] as String,
      e['chapterId'] as String,
      e['offset'] as int,
      [for (final child in e['children'] as List? ?? []) toc(child as Map)],
    );
    return ReflowDocument(
      document,
      List.unmodifiable(chapters),
      [for (final e in data['toc'] as List? ?? []) toc(e as Map)],
      {for (final r in data['resources'] as List) (r as Map)['sourcePath'] as String: r.cast<String, Object?>()},
      read,
    );
  }

  Future<Uint8List> resource(String sourcePath) async {
    final entry = resources[sourcePath];
    if (entry == null) throw const FormatException('Missing resource');
    final bytes = await read(entry['path'] as String);
    if (bytes.length != entry['length'] || sha256.convert(bytes).toString() != entry['sha256']) {
      throw const FormatException('Resource digest mismatch');
    }
    return Uint8List.fromList(bytes);
  }

  TextReadingPosition position(String chapter, int offset) =>
      TextReadingPosition(revision: revision, chapterId: chapter, offset: offset);
  TextReadingPosition get start => position(chapters.first.id, 0);
  TextReadingPosition get end => position(chapters.last.id, chapters.last.canonicalText.length);
  BookChapter? chapter(String id) => chapters.where((c) => c.id == id).firstOrNull;
  List<BookTocEntry> get outline {
    Iterable<BookTocEntry> walk(List<BookTocEntry> entries) sync* {
      for (final e in entries) {
        yield e;
        yield* walk(e.children);
      }
    }

    return walk(toc).toList();
  }

  String title(TextReadingPosition position, {String? fallback}) {
    var title = fallback ?? document.title;
    for (final e in outline) {
      if (e.chapterId == position.chapterId && e.offset <= position.offset) title = e.title;
    }
    return title;
  }

  double progress(TextReadingPosition position) {
    var offset = 0;
    for (final c in chapters) {
      if (c.id == position.chapterId) return (offset + position.offset) / length;
      offset += math.max(1, c.canonicalText.length);
    }
    return 0;
  }

  TextReadingPosition atProgress(double fraction) {
    var offset = (fraction.clamp(0, 1) * length).round();
    for (final c in chapters) {
      final weight = math.max(1, c.canonicalText.length);
      if (offset < weight) return position(c.id, offset.clamp(0, c.canonicalText.length));
      offset -= weight;
    }
    return end;
  }

  /// Version changes require a unique quote/context match; never guess by distance.
  TextAnchor? resolve(TextAnchor anchor) {
    if (anchor.normalizationVersion != 1 || anchor.revision.isEmpty) return null;
    final original = chapter(anchor.chapterId);
    if (anchor.revision == revision) {
      if (original?.resolves(anchor) != true) return null;
      final snapped = original!.anchor(anchor.start, anchor.end, revision: revision);
      return snapped.start == anchor.start && snapped.end == anchor.end ? anchor : null;
    }
    if (anchor.quote.isEmpty) return null;
    List<TextAnchor> matches(Iterable<BookChapter> candidates) => [
      for (final c in candidates)
        for (final match in RegExp(RegExp.escape(anchor.quote)).allMatches(c.canonicalText))
          // Compare context in place: copying the chapter per match is quadratic.
          if ((anchor.prefix.isEmpty ||
                  (match.start >= anchor.prefix.length &&
                      c.canonicalText.startsWith(anchor.prefix, match.start - anchor.prefix.length))) &&
              (anchor.suffix.isEmpty || c.canonicalText.startsWith(anchor.suffix, match.end)))
            if (c.anchor(match.start, match.end, revision: revision) case final candidate)
              if (candidate.start == match.start && candidate.end == match.end) candidate,
    ];
    final local = matches(original == null ? [] : [original]);
    if (local.length == 1) return local.single;
    final all = matches(chapters);
    return all.length == 1 ? all.single : null;
  }

  List<TextAnchor> search(String query) => query.trim().isEmpty
      ? []
      : [
          for (final c in chapters)
            for (final m in RegExp(
              RegExp.escape(query),
              caseSensitive: false,
              unicode: true,
            ).allMatches(c.canonicalText))
              c.anchor(m.start, m.end, revision: revision),
        ];
}
