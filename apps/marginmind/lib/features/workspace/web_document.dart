import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mm_book/mm_book.dart' as bk;
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_pdf/mm_pdf.dart';

typedef WebPdfInfo = ({int pageCount, List<TranslationPage> pages, Uint8List? preview});
typedef WebPdfInspector = Future<WebPdfInfo> Function(Uint8List bytes);

class PreparedWebDocument {
  const PreparedWebDocument(this.package, this.book, this.markdown, this.preview);
  final DocumentPackage package;
  final bk.Book book;
  final String? markdown;
  final Uint8List? preview;
}

/// No network access: all inputs came from one live browser capture.
class WebDocumentConverter {
  const WebDocumentConverter({this.inspectPdf = MMPdfEngine.inspectData});
  final WebPdfInspector inspectPdf;

  Future<PreparedWebDocument> prepare(
    BrowserDocumentCapture capture, {
    required String id,
    required String title,
    required WebCaptureMode mode,
    Document? previous,
    Map<String, String> oldChapters = const {},
  }) async {
    if (title.trim().isEmpty) throw const FormatException('Empty title');
    const parser = bk.WebBookParser();
    final capturedResources = parser.sanitizeResources(capture.resources);
    final sanitized = parser.sanitizeHtml(capture.html, capturedResources.keys.toSet());
    final sourceHtml = mode == WebCaptureMode.original
        ? sanitized
        : parser.withAttribution(sanitized, capture.title, capture.url, capture.capturedAt);
    final snapshot = parser.sanitizeHtml(capture.snapshot, capturedResources.keys.toSet());
    final initial = mode == WebCaptureMode.original
        ? bk.Book(capture.title, [], capturedResources, [])
        : parser.parse(capture.title, sourceHtml, capturedResources);
    var parsed = initial;
    String? markdown;
    if (mode == WebCaptureMode.markdown) {
      markdown = parser.markdown(sourceHtml);
      parsed = await const bk.MarkdownBookParser().parse(
        utf8.encode(markdown),
        resolver: (path) async => capturedResources[path],
      );
      parsed = bk.Book(capture.title, parsed.chapters, parsed.resources, parsed.diagnostics, toc: parsed.toc);
    }
    final WebPdfInfo? pdf = mode == WebCaptureMode.original
        ? await inspectPdf(capture.pdf ?? (throw const FormatException('Missing PDF')))
        : null;
    if (pdf != null && pdf.pageCount < 1) throw const FormatException('Empty PDF');
    // Capture identity includes time and snapshot. Repeated captures of the
    // same article get distinct, immutable capture directories. The IR keeps
    // its canonical content revision, including the displayed capture date.
    final captureVersion = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              parsed.revision,
              capture.url.toString(),
              capture.capturedAt.toIso8601String(),
              snapshot,
              mode.name,
              if (capture.pdf != null) sha256.convert(capture.pdf!).toString(),
            ]),
          ),
        )
        .toString();
    final revision = pdf != null ? sha256.convert(capture.pdf!).toString() : parsed.revision;
    final base = 'books/$id/$captureVersion', web = 'web/$id/$captureVersion';
    final files = <String, List<int>>{};
    final json = parsed.toJson();
    final spine = <Map<String, Object?>>[];
    for (final chapter in json['spine'] as List) {
      final bytes = utf8.encode(jsonEncode(chapter)),
          hash = sha256.convert(utf8.encode(jsonEncode(chapter))).toString();
      final path = '$base/chapters/$hash.json';
      files[path] = bytes;
      spine.add({'id': (chapter as Map)['id'], 'path': path, 'sha256': hash});
    }
    final resources = <Map<String, Object?>>[];
    for (final item in json['resources'] as List) {
      final entry = (item as Map).cast<String, Object?>();
      final source = entry['path'] as String;
      final path = '$base/resources/${entry['sha256']}.${source.split('.').last}';
      files[path] = parsed.resources[source]!;
      resources.add({...entry, 'sourcePath': source, 'path': path});
    }
    // Snapshots resolve their own image paths without network or session data.
    for (final entry in capturedResources.entries) {
      files['$web/${entry.key}'] = entry.value;
    }
    final sourceBytes = pdf != null ? capture.pdf! : utf8.encode(markdown ?? sourceHtml);
    final extension = pdf != null
        ? 'pdf'
        : markdown != null
        ? 'md'
        : 'html';
    final source = 'documents/${sha256.convert(sourceBytes)}.$extension';
    files['$web/snapshot.html'] = utf8.encode(snapshot);
    files['$web/resources.json'] = utf8.encode(
      jsonEncode({
        'version': 1,
        'url': capture.url.toString(),
        'capturedAt': capture.capturedAt.toIso8601String(),
        'mode': mode.name,
        'sourceFile': source,
        'snapshotSha256': sha256.convert(utf8.encode(snapshot)).toString(),
        'diagnostics': capture.diagnostics,
        'resources': {for (final e in capturedResources.entries) e.key: sha256.convert(e.value).toString()},
      }),
    );
    final manifest = '$base/manifest.json';
    files[manifest] = utf8.encode(jsonEncode({...json, 'spine': spine, 'resources': resources}));
    files[source] = sourceBytes;
    final document = Document(
      id: id,
      title: title.trim(),
      fileName: pdf != null ? source : manifest,
      sourceFileName: source,
      contentManifest: pdf == null ? manifest : null,
      revision: revision,
      format: DocumentFormat.web,
      layout: pdf != null ? DocumentLayout.fixed : DocumentLayout.reflow,
      pageCount: pdf?.pageCount ?? 0,
      importedAt: previous?.importedAt ?? capture.capturedAt,
      lastReadAt: previous?.lastReadAt,
      features: DocumentContentFeatures(
        text: pdf == null || pdf.pages.any((p) => p.text.trim().isNotEmpty),
        outline: parsed.toc.isNotEmpty,
      ),
      readingPosition: pdf != null
          ? PdfPosition(1)
          : TextReadingPosition(revision: revision, chapterId: 'main', offset: 0),
      origin: DocumentOrigin(
        url: capture.url.toString(),
        capturedAt: capture.capturedAt,
        mode: mode,
        snapshotFile: '$web/snapshot.html',
      ),
    );
    return PreparedWebDocument(
      DocumentPackage(
        document: document,
        files: files,
        expectedRevision: previous?.revision,
        expectedSnapshotFile: previous?.origin?.snapshotFile,
        reconcile: previous == null
            ? null
            : (content) {
                return reconcileWebContent(
                  content,
                  document,
                  parsed.chapters,
                  oldChapters,
                  pdf?.pages,
                  previousPosition: previous.readingPosition,
                );
              },
      ),
      parsed,
      markdown,
      pdf?.preview,
    );
  }
}

/// Reconcile live, editable locators; immutable evidence keeps its old version.
StudySetContent reconcileWebContent(
  StudySetContent content,
  Document document,
  List<bk.BookChapter> chapters,
  Map<String, String> oldChapters,
  List<TranslationPage>? pdf, {
  ReadingPosition? previousPosition,
}) {
  final revision = document.revision!;
  Object? align(Object? value, [bool active = false]) {
    if (value is List) return [for (final item in value) align(item, active)];
    if (value is! Map) return value;
    final map = value.cast<String, Object?>();
    if (map['documentId'] != null) active = map['documentId'] == document.id;
    if (active && map.containsKey('chapterId') && map.containsKey('quote') && map.containsKey('start')) {
      final old = TextAnchor.fromJson(map);
      return (bk.alignTextAnchor(old, chapters, revision) ?? old).toJson();
    }
    if (active && map['type'] == 'text' && map.containsKey('offset')) {
      final source = oldChapters[map['chapterId']];
      final offset = map['offset'] as int;
      if (source != null && offset <= source.length) {
        // A nearby passage supplies context for zero-length positions.
        final before = (offset - 32).clamp(0, source.length), after = (offset + 32).clamp(0, source.length);
        final oldChapter = bk.BookChapter(map['chapterId'] as String, [
          bk.BookBlock(id: 'position', kind: bk.BlockKind.paragraph, start: 0, runs: [bk.InlineRun(source)]),
        ]);
        // If an adjacent insertion broke the surrounding passage, a unique
        // passage on either side can still locate this zero-length position.
        for (final (start, end) in [(before, after), (offset, after), (before, offset)]) {
          if (end <= start) continue;
          final oldAnchor = oldChapter.anchor(start, end, revision: map['revision'] as String);
          final anchor = bk.alignTextAnchor(oldAnchor, chapters, revision);
          if (anchor != null) {
            return {
              ...map,
              'chapterId': anchor.chapterId,
              'offset': anchor.start + offset - oldAnchor.start,
              'revision': revision,
            };
          }
        }
      }
    }
    final next = <String, Object?>{for (final e in map.entries) e.key: align(e.value, active)};
    if (active && map.containsKey('blockId') && next['anchor'] is Map) {
      final anchor = (next['anchor'] as Map).cast<String, Object?>();
      if (anchor['revision'] == revision) {
        for (final chapter in chapters.where((c) => c.id == anchor['chapterId'])) {
          final block = chapter.blocks
              .where((b) => b.start <= (anchor['start'] as int) && b.end >= (anchor['end'] as int))
              .firstOrNull;
          if (block != null) next['blockId'] = block.id;
        }
      }
    }
    if (active && map['pages'] != null && map['quote'] != null && pdf != null) {
      final pages = alignPdfQuote(map['quote'] as String, pdf);
      if (pages != null) next['pages'] = [for (final p in pages) p.toJson()];
    }
    if (active && map['textAnchors'] != null && map['colorIndex'] != null) {
      next['needsReview'] = (next['textAnchors'] as List).any((a) => (a as Map)['revision'] != revision);
    }
    return next;
  }

  final json = content.toJson();
  if (previousPosition is TextReadingPosition) {
    final position = align(previousPosition.toJson(), true) as Map;
    if (position['revision'] == revision) {
      json['documents'] = [
        for (final d in content.documents)
          if (d.id == document.id)
            d.copyWith(readingPosition: ReadingPosition.fromJson(position.cast<String, Object?>())).toJson()
          else
            d.toJson(),
      ];
    }
  }
  for (final key in ['annotations', 'bookmarks', 'marginNotes', 'inkStrokes', 'noteAttachments', 'documentOutlines']) {
    json[key] = align(json[key]);
  }
  // PDF locators carry no text revision. Re-evaluate all annotations so a
  // stale rectangle is explicitly listed instead of appearing on a new page.
  if (pdf != null) {
    json['annotations'] = [
      for (final a in json['annotations'] as List)
        if ((a as Map)['documentId'] == document.id)
          {...a, 'needsReview': alignPdfQuote(a['quote'] as String, pdf) == null}
        else
          a,
    ];
  }
  final restored = StudySetContent.fromJson(json);
  return restored.copyWith(
    translationCaches: [
      for (final cache in restored.translationCaches)
        if (cache.documentId != document.id) cache,
    ],
  );
}

List<AnnotationPage>? alignPdfQuote(String quote, List<TranslationPage> pages) {
  if (quote.trim().isEmpty) return null;
  final raw = pages.map((p) => p.text).join('\n');
  // Selection quotes already use this normalization: visual line breaks,
  // CJK joins and discretionary hyphens must not prevent relocation.
  final text = joinExcerptLines(pages.map((p) => p.text.trim()).join('\n'));
  final target = joinExcerptLines(quote);
  final match = text.indexOf(target);
  if (target.isEmpty || match < 0 || text.indexOf(target, match + 1) >= 0) return null;
  var cursor = 0, start = -1, end = -1;
  for (var i = 0; i < match + target.length; i++) {
    if (text[i].trim().isEmpty) continue;
    final at = raw.indexOf(text[i], cursor);
    if (at < 0) return null;
    if (i == match) start = at;
    if (i == match + target.length - 1) end = at + 1;
    cursor = at + 1;
  }
  if (start < 0 || end <= start) return null;
  var offset = 0;
  final result = <AnnotationPage>[];
  for (final page in pages) {
    final a = (start - offset).clamp(0, page.text.length), b = (end - offset).clamp(0, page.text.length);
    if (b > a) {
      if (page.boxes.length < b) return null;
      final rects = page.boxes.sublist(a, b).where((r) => r.right > r.left && r.top > r.bottom).toList();
      if (rects.isEmpty) return null;
      result.add(AnnotationPage(page: page.page, rects: rects));
    }
    offset += page.text.length + 1;
  }
  return result.isEmpty ? null : result;
}
