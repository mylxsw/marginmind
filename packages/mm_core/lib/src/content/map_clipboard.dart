import 'dart:convert';

import 'models.dart';
import 'study_set_content.dart';

/// A portable, preorder forest. Depth is relative to the copied roots.
class OutlineEntry {
  const OutlineEntry(
    this.depth,
    this.title, {
    this.kind = CardKind.topic,
    this.annotation,
    this.imageFileName,
    this.imagePath,
    this.collapsed = false,
  });
  final int depth;
  final String title;
  final CardKind kind;
  final Annotation? annotation;
  final String? imageFileName;

  /// Where the source package keeps the image, so another study set can
  /// import the file on paste.
  final String? imagePath;
  final bool collapsed;
}

abstract final class MapClipboard {
  static const format = 'io.github.mylxsw.marginmind.nodes';
  static const maxEntries = 10000;

  /// Includes collapsed descendants, and copies overlapping selections once.
  /// [resolveImage] gives the absolute path of a package image.
  static List<OutlineEntry> copy(
    StudySetContent content,
    Iterable<String> selected, {
    String mapId = MindMap.defaultId,
    String Function(String fileName)? resolveImage,
  }) {
    final ids = selected.toSet();
    final result = <OutlineEntry>[];
    final seen = <String>{};
    void walk(String? parent, int? depth) {
      for (final node in content.childrenOf(parent, mapId: mapId)) {
        if (!seen.add(node.cardId)) continue;
        final card = content.card(node.cardId);
        if (card == null) continue;
        final level = depth ?? (ids.contains(card.id) ? 0 : null);
        if (level != null) {
          result.add(
            OutlineEntry(
              level,
              card.title,
              kind: card.kind,
              imageFileName: card.imageFileName,
              imagePath: card.imageFileName == null ? null : resolveImage?.call(card.imageFileName!),
              annotation: content.annotation(card.annotationId ?? ''),
              collapsed: node.collapsed,
            ),
          );
        }
        walk(card.id, level == null ? null : level + 1);
      }
    }

    walk(null, null);
    return result;
  }

  static String toText(List<OutlineEntry> entries) => entries
      .map((e) {
        // An untitled image keeps its line (and so the outline's shape).
        final title = e.title.isNotEmpty
            ? e.title
            : e.kind == CardKind.image && e.imageFileName != null
            ? '![](${e.imageFileName})'
            : (e.annotation?.quote ?? '');
        return '${'\t' * e.depth}${title.replaceAll(RegExp(r'[\r\n]+'), ' ')}';
      })
      .join('\n');

  /// Tabs use four columns. Blank lines are ignored; indentation levels may
  /// skip columns, but never create missing placeholder parents.
  static List<OutlineEntry> fromText(String text) {
    final result = <OutlineEntry>[];
    final indents = <int>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      var columns = 0;
      var offset = 0;
      while (offset < line.length && (line[offset] == ' ' || line[offset] == '\t')) {
        columns += line[offset] == '\t' ? 4 - columns % 4 : 1;
        offset++;
      }
      // Notes can wrap tab-indented text as "* \tChild". Consume the
      // marker's one separator, then count the remaining whitespace as
      // indentation too (without counting the marker's visual width).
      final marker = RegExp(r'^(?:[-+*•◦▪]|\d+[.)])[ \t]').firstMatch(line.substring(offset));
      if (marker != null) {
        offset += marker.end;
        while (offset < line.length && (line[offset] == ' ' || line[offset] == '\t')) {
          columns += line[offset] == '\t' ? 4 - columns % 4 : 1;
          offset++;
        }
      }
      final title = line.substring(offset).trimRight();
      if (title.isEmpty) continue;
      while (indents.isNotEmpty && columns <= indents.last) {
        indents.removeLast();
      }
      if (indents.length > 256 || result.length >= maxEntries) throw const FormatException('Outline too large');
      result.add(OutlineEntry(indents.length, title));
      indents.add(columns);
    }
    return result;
  }

  static String encode(List<OutlineEntry> entries) => jsonEncode({
    'format': format,
    'version': 2,
    'nodes': [
      for (final e in entries)
        {
          'depth': e.depth,
          'title': e.title,
          'kind': e.kind.name,
          'collapsed': e.collapsed,
          if (e.imageFileName != null) 'imageFileName': e.imageFileName,
          if (e.imagePath != null) 'imagePath': e.imagePath,
          if (e.annotation != null) 'annotation': e.annotation!.toJson(),
        },
    ],
  });

  /// Untrusted system clipboard data; callers can fall back to plain text.
  static List<OutlineEntry>? decode(String data) {
    try {
      final json = jsonDecode(data) as Map;
      if (json['format'] != format || (json['version'] != 1 && json['version'] != 2)) return null;
      final nodes = json['nodes'] as List;
      if (nodes.length > maxEntries) return null;
      final result = <OutlineEntry>[];
      var previous = -1;
      for (final raw in nodes) {
        final e = raw as Map;
        final depth = e['depth'] as int;
        if (depth < 0 || depth > previous + 1 || depth > 256) return null;
        result.add(
          OutlineEntry(
            depth,
            e['title'] as String,
            kind: CardKind.values.byName(e['kind'] as String),
            imageFileName: e['imageFileName'] as String?,
            imagePath: e['imagePath'] as String?,
            collapsed: e['collapsed'] as bool,
            annotation: e['annotation'] == null ? null : Annotation.fromJson((e['annotation'] as Map).cast()),
          ),
        );
        previous = depth;
      }
      return result;
    } on Object {
      return null;
    }
  }
}
