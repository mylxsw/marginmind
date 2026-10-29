/// A small, portable book representation. Layout never changes its text.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mm_core/mm_core.dart' show TextAnchor;
export 'package:mm_core/mm_core.dart' show TextAnchor;

import 'package:archive/archive.dart';
import 'package:characters/characters.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';
import 'package:crypto/crypto.dart';
import 'package:markdown/markdown.dart' as md;

part 'src/contracts.dart';
part 'src/parser.dart';
part 'src/html.dart';
part 'src/css.dart';
part 'src/epub.dart';
part 'src/markdown.dart';
part 'src/mobi.dart';
part 'src/mobi_compression.dart';
part 'src/mobi_index.dart';

enum BlockKind { paragraph, heading, list, quote, code, image, table, rule, footnote }

class InlineRun {
  const InlineRun(
    this.text, {
    this.strong = false,
    this.emphasis = false,
    this.code = false,
    this.link,
    this.resource,
    this.width,
    this.height,
    this.style = const {},
    this.sourcePath,
    this.sourceStart = 0,
    this.sourceEnd = 0,
    this.ruby,
    this.footnoteRef,
    this.remoteUrl,
  });
  final String text;
  final Map<String, String> style;
  final String? sourcePath, ruby, footnoteRef, remoteUrl;
  final int sourceStart, sourceEnd;
  final bool strong, emphasis, code;
  final String? link;
  final String? resource, width, height;
}

class BookCell {
  BookCell(List<InlineRun> runs, {this.rowSpan = 1, this.colSpan = 1}) : runs = List.unmodifiable(runs);
  final int rowSpan, colSpan;
  final List<InlineRun> runs;
  String get text => runs.map((r) => r.text).join();
  int get length => text.length;
}

class BookBlock {
  BookBlock({
    required this.id,
    required this.kind,
    required this.start,
    required List<InlineRun> runs,
    this.level = 1,
    this.resource,
    this.style = const {},
    this.sourcePath = '',
    this.ordered = false,
    this.listStart = 1,
    List<List<BookCell>> rows = const [],
  }) : runs = List.unmodifiable(runs),
       rows = List.unmodifiable(rows.map(List<BookCell>.unmodifiable));
  final String id;
  final BlockKind kind;
  final int start, level;
  final String? resource;
  final Map<String, String> style;
  final String sourcePath;
  final bool ordered;
  final int listStart;
  final List<InlineRun> runs;
  final List<List<BookCell>> rows;
  String get text => runs.map((r) => r.text).join();
  int get end => start + text.length;
}

class BookChapter {
  BookChapter(
    this.id,
    List<BookBlock> blocks, {
    this.elementOffsets = const {},
    this.viewportWidth,
    this.viewportHeight,
    this.structure = const [],
    this.fonts = const [],
  }) : blocks = List.unmodifiable(blocks),
       canonicalText = blocks.map((b) => b.text).join('\n');
  final String id, canonicalText;
  final Map<String, int> elementOffsets;
  final List<BookNode> structure;
  final List<BookFontFace> fonts;
  final double? viewportWidth, viewportHeight;
  List<Map<String, Object>> get sourceMap => [for (final b in blocks) ..._sourceEntries(b.runs, b.start)];
  final List<BookBlock> blocks;

  /// Both edges expand to whole grapheme clusters, including emoji sequences.
  TextAnchor anchor(int start, int end, {String revision = ''}) {
    RangeError.checkValidRange(start, end, canonicalText.length);
    var boundary = 0;
    var a = start, b = end;
    for (final cluster in canonicalText.characters) {
      final next = boundary + cluster.length;
      if (boundary < start && start < next) a = boundary;
      if (boundary < end && end < next) b = next;
      boundary = next;
      if (boundary >= end) break;
    }
    return TextAnchor(
      id,
      a,
      b,
      canonicalText.substring(a, b),
      revision: revision,
      prefix: canonicalText.substring(0, a).characters.takeLast(32).string,
      suffix: canonicalText.substring(b).characters.take(32).join(),
    );
  }

  bool resolves(TextAnchor anchor) =>
      anchor.chapterId == id &&
      anchor.start >= 0 &&
      anchor.end >= anchor.start &&
      anchor.end <= canonicalText.length &&
      canonicalText.substring(anchor.start, anchor.end) == anchor.quote;
}

class Book {
  Book(
    this.title,
    List<BookChapter> chapters,
    Map<String, Uint8List> resources,
    List<String> diagnostics, {
    Map<String, List<String>> metadata = const {},
    List<BookTocEntry> toc = const [],
    this.fixedLayout = false,
    Uint8List? pdf,
  }) : metadata = Map.unmodifiable(metadata.map((k, v) => MapEntry(k, List<String>.unmodifiable(v)))),
       toc = List.unmodifiable(toc),
       pdf = pdf == null ? null : Uint8List.fromList(pdf).asUnmodifiableView(),
       chapters = List.unmodifiable(chapters),
       resources = Map.unmodifiable(resources.map((k, v) => MapEntry(k, Uint8List.fromList(v).asUnmodifiableView()))),
       diagnostics = List.unmodifiable(diagnostics);
  final String title;
  final Map<String, List<String>> metadata;
  final List<BookTocEntry> toc;
  final bool fixedLayout;

  /// AZW4 Print Replica payload; hand this to the PDF importer.
  final Uint8List? pdf;
  int get version => 1;
  String get revision => sha256.convert(utf8.encode(jsonEncode(toJson(includeRevision: false)))).toString();
  Map<String, Object?> toJson({bool includeRevision = true}) => {
    'version': version,
    'normalizationVersion': 1,
    if (includeRevision) 'revision': revision,
    'title': title,
    'metadata': metadata,
    'fixedLayout': fixedLayout,
    'spine': chapters.map(_chapterJson).toList(),
    'toc': toc.map((e) => e.toJson()).toList(),
    'resources': [
      for (final path in (resources.keys.toList()..sort()))
        {
          'path': path,
          'sha256': sha256.convert(resources[path]!).toString(),
          'length': resources[path]!.length,
          'mime': _mime(resources[path]!, path),
        },
    ],
    if (pdf != null) 'pdfSha256': sha256.convert(pdf!).toString(),
  };
  final List<BookChapter> chapters;
  final Map<String, Uint8List> resources;
  final List<String> diagnostics;
}

/// Bounded in-memory EPUB parser. This deliberately reports unsupported markup.
/// EPUB container adapter and shared HTML normalization entry point.
class EpubParser {
  const EpubParser({this.maxBytes = 64 * 1024 * 1024, this.maxEntries = 10000});
  final int maxBytes, maxEntries;

  Book parse(Uint8List bytes) => _guard(() => _epub(bytes, maxBytes, maxEntries));

  BookChapter parseHtml(String id, String source, [List<String>? diagnostics]) =>
      _htmlChapter(id, source, diagnostics ?? []);
}

String _resolve(String base, String href) {
  if (href.contains('\\') || href.startsWith('/') || href.contains('\u0000') || Uri.parse(href).hasScheme) {
    throw FormatException('Unsafe archive reference: $href');
  }
  final path = Uri.parse(base).resolve(href).path;
  if (path.isEmpty || path.startsWith('../') || path.split('/').contains('..')) {
    throw FormatException('Unsafe archive path: $href');
  }
  final decoded = Uri.decodeComponent(path);
  if (decoded.startsWith('/') || decoded.split('/').contains('..') || decoded.contains('\\')) {
    throw FormatException('Unsafe decoded archive path: $href');
  }
  return decoded;
}
