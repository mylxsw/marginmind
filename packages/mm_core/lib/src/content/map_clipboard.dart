import 'dart:convert';

import 'models.dart';
import 'research.dart';
import 'study_set_content.dart';

/// A portable, preorder forest. Depth is relative to the copied roots.
class OutlineEntry {
  const OutlineEntry(
    this.depth,
    this.title, {
    this.kind = CardKind.topic,
    this.body = '',
    this.annotation,
    this.imageFileName,
    this.imagePath,
    this.collapsed = false,
    this.width,
    this.textFormat = TextFormat.plain,
    this.imageOrigin,
    this.researchNoteId,
    this.researchNotes = const [],
    this.evidence = const [],
    this.sources = const [],
    this.pdfAttachments = const [],
    this.snapshots = const {},
    this.tags = const [],
  });
  final double? width;
  final TextFormat textFormat;
  final String? imageOrigin;
  final String? researchNoteId;
  final List<ResearchNote> researchNotes;
  final List<Evidence> evidence;
  final List<ResearchSource> sources;
  final List<NoteAttachment> pdfAttachments;
  final Map<String, String> snapshots;
  final List<String> tags;
  final int depth;
  final String title;
  final String body;
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
    Map<String, String> snapshots = const {},
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
          final noteIds = {
            if (card.researchNoteId != null) card.researchNoteId!,
            for (final a in content.noteAttachments)
              if (a.target is CardTarget && (a.target as CardTarget).cardId == card.id) a.noteId,
          };
          final notes = [
            for (final n in content.researchNotes)
              if (noteIds.contains(n.id)) n,
          ];
          final evidenceIds = {
            for (final n in notes)
              for (final ref in n.citations) ref.evidenceId,
          };
          final evidence = [
            for (final e in content.evidence)
              if (evidenceIds.contains(e.id)) e,
          ];
          final sourceIds = {for (final e in evidence) e.sourceId};
          final sources = [
            for (final source in content.researchSources)
              if (sourceIds.contains(source.id)) source,
          ];
          final files = {
            for (final source in sources)
              for (final v in source.versions) v.snapshotFile,
          };
          result.add(
            OutlineEntry(
              level,
              card.title,
              kind: card.kind,
              body: card.body,
              width: node.width,
              textFormat: card.textFormat,
              imageOrigin: card.imageOrigin,
              researchNoteId: card.researchNoteId,
              researchNotes: notes,
              evidence: evidence,
              sources: sources,
              pdfAttachments: [
                for (final a in content.noteAttachments)
                  if (noteIds.contains(a.noteId) && (a.target is PdfTarget || a.target is TextTarget)) a,
              ],
              snapshots: {
                for (final file in files)
                  if (snapshots.containsKey(file)) file: snapshots[file]!,
              },
              tags: card.tags,
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
            : e.kind == CardKind.research
            ? (e.researchNotes.where((n) => n.id == e.researchNoteId).firstOrNull?.title ?? '')
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
    'version': 3,
    'nodes': [
      for (final e in entries)
        {
          'depth': e.depth,
          if (e.width != null) 'width': e.width,
          'textFormat': e.textFormat.name,
          if (e.imageOrigin != null) 'imageOrigin': e.imageOrigin,
          if (e.researchNoteId != null) 'researchNoteId': e.researchNoteId,
          'researchNotes': [for (final n in e.researchNotes) n.toJson()],
          'evidence': [for (final v in e.evidence) v.toJson()],
          'sources': [for (final v in e.sources) v.toJson()],
          'pdfAttachments': [for (final v in e.pdfAttachments) v.toJson()],
          'snapshots': e.snapshots,
          'title': e.title,
          if (e.body.isNotEmpty) 'body': e.body,
          'kind': e.kind.name,
          'collapsed': e.collapsed,
          if (e.tags.isNotEmpty) 'tags': e.tags,
          if (e.imageFileName != null) 'imageFileName': e.imageFileName,
          if (e.imagePath != null) 'imagePath': e.imagePath,
          if (e.annotation != null) 'annotation': e.annotation!.toJson(),
        },
    ],
  });

  /// Untrusted system clipboard data; callers can fall back to plain text.
  static List<OutlineEntry>? decode(String data) {
    try {
      if (data.length > 32 * 1024 * 1024) return null;
      final json = jsonDecode(data) as Map;
      if (json['format'] != format || ![1, 2, 3].contains(json['version'])) return null;
      final nodes = json['nodes'] as List;
      if (nodes.length > maxEntries) return null;
      final result = <OutlineEntry>[];
      var previous = -1;
      for (final raw in nodes) {
        final e = raw as Map;
        final depth = e['depth'] as int;
        if (depth < 0 || depth > previous + 1 || depth > 256) return null;
        final width = (e['width'] as num?)?.toDouble();
        if (width != null && (!width.isFinite || width <= 0)) return null;
        result.add(
          OutlineEntry(
            depth,
            e['title'] as String,
            width: (e['width'] as num?)?.toDouble(),
            textFormat: TextFormat.values.byName(e['textFormat'] as String? ?? 'plain'),
            imageOrigin: e['imageOrigin'] as String?,
            researchNoteId: e['researchNoteId'] as String?,
            researchNotes: [
              for (final v in e['researchNotes'] as List? ?? []) ResearchNote.fromJson((v as Map).cast()),
            ],
            evidence: [for (final v in e['evidence'] as List? ?? []) Evidence.fromJson((v as Map).cast())],
            sources: [for (final v in e['sources'] as List? ?? []) ResearchSource.fromJson((v as Map).cast())],
            pdfAttachments: [
              for (final v in e['pdfAttachments'] as List? ?? []) NoteAttachment.fromJson((v as Map).cast()),
            ],
            snapshots: ((e['snapshots'] as Map?) ?? {}).cast<String, String>(),
            body: e['body'] as String? ?? '',
            kind: CardKind.values.byName(e['kind'] as String),
            tags: List.unmodifiable(((e['tags'] as List?) ?? const []).cast<String>()),
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
