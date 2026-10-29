/// A small, portable book representation. Layout never changes its text.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:characters/characters.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

enum BlockKind { paragraph, heading, list, quote, code, image, table }

class InlineRun {
  const InlineRun(this.text, {this.strong = false, this.emphasis = false, this.code = false, this.link});
  final String text;
  final bool strong, emphasis, code;
  final String? link;
}

class BookBlock {
  BookBlock({
    required this.id,
    required this.kind,
    required this.start,
    required List<InlineRun> runs,
    this.level = 1,
    this.resource,
    List<List<String>> rows = const [],
  }) : runs = List.unmodifiable(runs),
       rows = List.unmodifiable(rows.map(List<String>.unmodifiable));
  final String id;
  final BlockKind kind;
  final int start, level;
  final String? resource;
  final List<InlineRun> runs;
  final List<List<String>> rows;
  String get text => runs.map((r) => r.text).join();
  int get end => start + text.length;
}

class TextAnchor {
  const TextAnchor(this.chapterId, this.start, this.end, this.quote);
  final String chapterId, quote;
  final int start, end;
  Map<String, Object> toJson() => {'chapter': chapterId, 'start': start, 'end': end, 'quote': quote};
}

class BookChapter {
  BookChapter(this.id, List<BookBlock> blocks)
    : blocks = List.unmodifiable(blocks),
      canonicalText = blocks.map((b) => b.text).join('\n');
  final String id, canonicalText;
  final List<BookBlock> blocks;

  /// Both edges expand to whole grapheme clusters, including emoji sequences.
  TextAnchor anchor(int start, int end) {
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
    return TextAnchor(id, a, b, canonicalText.substring(a, b));
  }

  bool resolves(TextAnchor anchor) =>
      anchor.chapterId == id &&
      anchor.start >= 0 &&
      anchor.end >= anchor.start &&
      anchor.end <= canonicalText.length &&
      canonicalText.substring(anchor.start, anchor.end) == anchor.quote;
}

class Book {
  Book(this.title, List<BookChapter> chapters, Map<String, Uint8List> resources, List<String> diagnostics)
    : chapters = List.unmodifiable(chapters),
      resources = Map.unmodifiable(resources),
      diagnostics = List.unmodifiable(diagnostics);
  final String title;
  final List<BookChapter> chapters;
  final Map<String, Uint8List> resources;
  final List<String> diagnostics;
}

/// Bounded in-memory EPUB parser. This deliberately reports unsupported markup.
/// Production CSS, nav/NCX and MOBI adapters extend this IR in GUL-574.
class EpubParser {
  const EpubParser({this.maxBytes = 64 * 1024 * 1024, this.maxEntries = 10000});
  final int maxBytes, maxEntries;

  Book parse(Uint8List bytes) {
    if (bytes.length > maxBytes) throw const FormatException('EPUB exceeds compressed size limit');
    final zip = ZipDecoder().decodeBytes(bytes);
    if (zip.length > maxEntries) throw const FormatException('Too many ZIP entries');
    var size = 0;
    final files = <String, Uint8List>{};
    for (final entry in zip) {
      if (!entry.isFile) continue;
      final name = _resolve('', entry.name);
      if (files.containsKey(name)) throw FormatException('Duplicate ZIP path: $name');
      size += entry.size;
      if (size > maxBytes) throw const FormatException('EPUB exceeds expanded size limit');
      files[name] = entry.content;
    }
    String read(String path) {
      final data = files[path];
      if (data == null) throw FormatException('Missing EPUB member: $path');
      return utf8.decode(data);
    }

    final container = XmlDocument.parse(read('META-INF/container.xml'));
    final rootfiles = container.descendants.whereType<XmlElement>().where((e) => e.name.local == 'rootfile');
    if (rootfiles.isEmpty) throw const FormatException('Missing EPUB rootfile');
    final opfPath = _resolve('', rootfiles.first.getAttribute('full-path') ?? '');
    final opf = XmlDocument.parse(read(opfPath));
    final manifest = <String, String>{};
    for (final item in opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'item')) {
      manifest[item.getAttribute('id')!] = _resolve(opfPath, item.getAttribute('href')!);
    }
    final diagnostics = <String>['Prototype: publisher CSS, nav/NCX and fixed layout are not implemented'];
    final chapters = <BookChapter>[];
    for (final item in opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'itemref')) {
      final path = manifest[item.getAttribute('idref')];
      if (path == null) throw const FormatException('Missing spine item');
      chapters.add(parseHtml(path, read(path), diagnostics));
    }
    if (chapters.isEmpty) throw const FormatException('Empty EPUB spine');
    final title =
        opf.descendants.whereType<XmlElement>().where((e) => e.name.local == 'title').firstOrNull?.innerText ?? '';
    return Book(title, chapters, files, diagnostics);
  }

  BookChapter parseHtml(String id, String source, [List<String>? diagnostics]) {
    final body = html.parse(source).body!;
    final blocks = <BookBlock>[];
    var offset = 0;
    void add(
      BlockKind kind,
      List<InlineRun> runs, {
      int level = 1,
      String? resource,
      List<List<String>> rows = const [],
    }) {
      if (runs.every((r) => r.text.trim().isEmpty)) return;
      final block = BookBlock(
        id: '$id#b${blocks.length}',
        kind: kind,
        start: offset,
        runs: runs,
        level: level,
        resource: resource,
        rows: rows,
      );
      blocks.add(block);
      offset = block.end + 1;
    }

    void visit(dom.Node node) {
      if (node is dom.Text) {
        final text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isNotEmpty) add(BlockKind.paragraph, [InlineRun(text)]);
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName!;
      if (const {'script', 'style', 'head', 'noscript'}.contains(tag) || node.attributes.containsKey('hidden')) return;
      if (tag == 'img' || tag == 'image') {
        final src = node.attributes['src'] ?? node.attributes['href'] ?? node.attributes['xlink:href'];
        if (src != null) {
          try {
            add(BlockKind.image, [const InlineRun('\uFFFC')], resource: _resolve(id, src));
          } on FormatException {
            diagnostics?.add('Unsupported image URL: $src');
          }
        }
        return;
      }
      if (tag == 'table') {
        final rows = node
            .querySelectorAll('tr')
            .map(
              (row) => row.children
                  .where((c) => c.localName == 'td' || c.localName == 'th')
                  .map((c) => c.text.replaceAll(RegExp(r'\s+'), ' ').trim())
                  .toList(),
            )
            .where((r) => r.isNotEmpty)
            .toList();
        add(BlockKind.table, [InlineRun(rows.map((r) => r.join('\t')).join('\n'))], rows: rows);
        for (final image in node.querySelectorAll('img,image')) {
          visit(image);
        }
        if (node.querySelector('img,image') != null) {
          diagnostics?.add('Table images placed after table: $id');
        }
        return;
      }
      final kind = switch (tag) {
        'p' => BlockKind.paragraph,
        'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' => BlockKind.heading,
        'li' => BlockKind.list,
        'blockquote' => BlockKind.quote,
        'pre' => BlockKind.code,
        _ => null,
      };
      // Image-only paragraphs must remain image blocks, not empty text.
      if (kind != null) {
        final runs = _inline(node, preserve: kind == BlockKind.code);
        add(kind, runs, level: tag.startsWith('h') ? int.tryParse(tag.substring(1)) ?? 1 : 1);
        for (final img in node.querySelectorAll('img,image')) {
          visit(img);
        }
      } else {
        for (final child in node.nodes) {
          visit(child);
        }
      }
    }

    for (final node in body.nodes) {
      visit(node);
    }
    return BookChapter(id, blocks);
  }
}

List<InlineRun> _inline(dom.Element root, {required bool preserve}) {
  final result = <InlineRun>[];
  var previousWhitespace = true;
  void walk(dom.Node node, bool strong, bool emphasis, bool code, String? link) {
    if (node is dom.Text) {
      var text = node.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      if (!preserve) {
        text = text.replaceAll(RegExp(r'[ \t\n\f]+'), ' ');
        if (previousWhitespace && text.startsWith(' ')) text = text.substring(1);
      }
      if (text.isNotEmpty) {
        result.add(InlineRun(text, strong: strong, emphasis: emphasis, code: code, link: link));
        previousWhitespace = text.endsWith(' ') || text.endsWith('\n');
      }
    } else if (node is dom.Element) {
      if (const {'script', 'style', 'img', 'image', 'rt'}.contains(node.localName)) return;
      if (node.localName == 'br') {
        result.add(const InlineRun('\n'));
        previousWhitespace = true;
        return;
      }
      for (final child in node.nodes) {
        walk(
          child,
          strong || const {'b', 'strong'}.contains(node.localName),
          emphasis || const {'em', 'i'}.contains(node.localName),
          code || node.localName == 'code',
          node.localName == 'a' ? node.attributes['href'] : link,
        );
      }
    }
  }

  walk(root, false, false, preserve, null);
  if (!preserve && result.isNotEmpty) {
    final last = result.removeLast();
    result.add(
      InlineRun(last.text.trimRight(), strong: last.strong, emphasis: last.emphasis, code: last.code, link: last.link),
    );
  }
  return result;
}

String _resolve(String base, String href) {
  if (href.contains('\\') || href.startsWith('/') || Uri.parse(href).hasScheme) {
    throw FormatException('Unsafe archive reference: $href');
  }
  final path = Uri.parse(base).resolve(href).path;
  if (path.isEmpty || path.startsWith('../') || path.split('/').contains('..')) {
    throw FormatException('Unsafe archive path: $href');
  }
  final decoded = Uri.decodeFull(path);
  if (decoded.startsWith('/') || decoded.split('/').contains('..') || decoded.contains('\\')) {
    throw FormatException('Unsafe decoded archive path: $href');
  }
  return decoded;
}
