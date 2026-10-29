import 'dart:convert';

import 'models.dart';
import 'note_format.dart';
import 'research.dart';
import 'study_set_content.dart';

/// Turns a mind map into portable text formats.
///
/// [source] labels where an excerpt comes from (e.g. "Book · p. 3");
/// [summary] names a summary line and [relationsTitle] heads the list of
/// relations in Markdown. The app passes localized ones.
class MapExporter {
  MapExporter(
    this.content, {
    required this.rootTitle,
    this.mapId = MindMap.defaultId,
    String Function(Document doc, int page)? source,
    String Function(String label)? summary,
    this.relationsTitle = 'Relationships',
    this.researchNoteLabel = '研究笔记',
    this.sourceLabel = '出处',
  }) : _source = source ?? ((doc, page) => '${doc.title}, p. $page'),
       _summary = summary ?? ((label) => label.isEmpty ? 'Summary' : 'Summary: $label');

  final StudySetContent content;
  final String rootTitle;
  final String mapId;

  /// A snapshot shared by text and visual export. Folded descendants are included.
  static StudySetContent scope(StudySetContent content, String mapId, String? branchId) {
    if (branchId == null) return content;
    if (content.node(branchId, mapId: mapId) == null) {
      throw ArgumentError.value(branchId, 'branchId', 'Not in the map');
    }
    final ids = content.branch(branchId, mapId: mapId);
    return content.copyWith(
      nodes: [
        for (final n in content.nodes)
          if (n.mapId == mapId && ids.contains(n.cardId)) n.copyWith(toRoot: n.cardId == branchId, collapsed: false),
      ],
      relations: [
        for (final r in content.relationsOf(mapId))
          if (ids.contains(r.fromId) && ids.contains(r.toId)) r,
      ],
      summaries: [
        for (final (s, range) in content.summariesOf(mapId))
          if (range.every(ids.contains) && (s.parentId == null || ids.contains(s.parentId))) s,
      ],
    );
  }

  final String relationsTitle;
  final String researchNoteLabel;
  final String sourceLabel;
  final String Function(Document doc, int page) _source;
  final String Function(String label) _summary;

  late final _summaries = content.summariesOf(mapId);
  late final _relations = content.relationsOf(mapId);

  /// Nested Markdown list under a level-1 heading. Topics are bold,
  /// excerpts are quoted with their source, notes are plain text; a
  /// formatted note keeps its Markdown, one line per note line.
  String markdown() {
    final out = StringBuffer('# ${_oneLine(rootTitle)}\n\n');
    void walk(String? parentId, int depth) {
      for (final n in content.childrenOf(parentId, mapId: mapId)) {
        final card = content.card(n.cardId);
        if (card == null) continue;
        if (card.kind == CardKind.note && card.textFormat == TextFormat.markdown) {
          _markdownNote(out, card.title, depth);
        } else {
          out.writeln('${'  ' * depth}- ${_markdownLine(card).replaceAll('\n', '\n${'  ' * (depth + 1)}')}');
        }
        if (card.body.isNotEmpty) {
          for (final line in card.body.split('\n')) {
            out.writeln('${'  ' * (depth + 1)}$line');
          }
        }
        if (card.kind == CardKind.research) {
          for (final line in _researchBody(card).split('\n')) {
            out.writeln('${'  ' * (depth + 1)}$line');
          }
        }
        walk(card.id, depth + 1);
        // A summary follows the last sibling it covers.
        for (final (summary, range) in _summaries) {
          if (summary.parentId == parentId && range.last == card.id) {
            out.writeln('${'  ' * depth}- *${_oneLine(_summary(summary.label))}*');
          }
        }
      }
    }

    walk(null, 0);
    if (_relations.isNotEmpty) {
      out.writeln('\n## ${_oneLine(relationsTitle)}\n');
      for (final r in _relations) {
        final label = r.label.isEmpty ? '' : ' — ${_oneLine(r.label)}';
        out.writeln('- ${_name(r.fromId)} → ${_name(r.toId)}$label');
      }
    }
    return out.toString();
  }

  /// A formatted note as written: its first line is the list item, later
  /// lines continue it. A line break between two text lines stays a break.
  void _markdownNote(StringBuffer out, String text, int depth) {
    final lines = text.trim().split('\n');
    final blocks = NoteDocument.parse(text.trim(), TextFormat.markdown).blocks;
    for (var i = 0; i < lines.length; i++) {
      final paragraphFollows =
          blocks[i].kind == NoteBlockKind.paragraph &&
          i + 1 < lines.length &&
          blocks[i + 1].kind == NoteBlockKind.paragraph &&
          lines[i].trim().isNotEmpty &&
          lines[i + 1].trim().isNotEmpty;
      final line = '${lines[i].trimRight()}${paragraphFollows ? r'\' : ''}';
      out.writeln(i == 0 ? '${'  ' * depth}- $line' : (line.isEmpty ? '' : '${'  ' * (depth + 1)}$line'));
    }
  }

  /// How a card is referred to in a relation: its title, else its quote or
  /// image file.
  String _name(String cardId) {
    final card = content.card(cardId);
    if (card == null) return '';
    if (card.title.trim().isNotEmpty) return _oneLine(notePlainText(card.title, card.textFormat));
    return _oneLine(
      card.kind == CardKind.excerpt ? content.segmentsOf(card).map((s) => s.text).join('\n') : card.imageFileName ?? '',
    );
  }

  String _markdownLine(Card card) {
    switch (card.kind) {
      case CardKind.research:
        final note = content.researchNote(card.researchNoteId ?? '');
        return '$researchNoteLabel：${_oneLine(note?.title ?? card.title)}';
      case CardKind.topic:
        return '**${_oneLine(card.title)}**';
      case CardKind.image:
        final a = content.annotation(card.annotationId ?? '');
        final doc = a == null ? null : content.document(a.documentId);
        final src = doc == null ? '' : ' *(${_annotationSource(doc, a!)})*';
        return '![${_oneLine(card.title)}](${card.imageFileName ?? ""})$src';
      case CardKind.note:
        return _oneLine(card.title);
      case CardKind.excerpt:
        final title = card.title.trim().isEmpty ? '' : '**${_oneLine(card.title)}** — ';
        final paragraphs = content
            .segmentsOf(card)
            .map((segment) {
              final a = content.annotation(segment.annotationId ?? '');
              final doc = a == null ? null : content.document(a.documentId);
              final src = doc == null ? '' : ' *(${_annotationSource(doc, a!)})*';
              return '“${_oneLine(segment.text)}”$src';
            })
            .join('\n');
        return '$title$paragraphs';
    }
  }

  /// OPML 2.0 outline (opens in most outliners and mind-map apps). Excerpt
  /// quotes go into the `_note` attribute. Relations and summaries use
  /// custom attributes other apps ignore: cards they refer to carry
  /// `_mmId`, a relation's source carries `_mmRelations` (JSON
  /// `[{"to", "label"}]`) and a parent carries `_mmSummaries` (JSON
  /// `[{"from", "to", "label"}]`) for summaries of its children.
  String opml() {
    final out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<opml version="2.0">')
      ..writeln('  <head><title>${_xml(rootTitle)}</title></head>')
      ..writeln('  <body>')
      ..writeln('    <outline text="${_xml(rootTitle)}"${_marks(null)}>');
    void walk(String? parentId, int depth) {
      for (final n in content.childrenOf(parentId, mapId: mapId)) {
        final card = content.card(n.cardId);
        if (card == null) continue;
        final indent = '  ' * (depth + 3);
        final attrs = '${_opmlAttributes(card)}${_marks(card.id)}';
        final children = content.childrenOf(card.id, mapId: mapId);
        if (children.isEmpty) {
          out.writeln('$indent<outline $attrs/>');
        } else {
          out.writeln('$indent<outline $attrs>');
          walk(card.id, depth + 1);
          out.writeln('$indent</outline>');
        }
      }
    }

    walk(null, 0);
    out
      ..writeln('    </outline>')
      ..writeln('  </body>')
      ..writeln('</opml>');
    return out.toString();
  }

  late final _referenced = {
    for (final r in _relations) ...[r.fromId, r.toId],
    for (final (s, _) in _summaries) ...[s.fromId, s.toId],
  };

  /// Custom attributes for relations and summaries ([cardId] null = root).
  String _marks(String? cardId) {
    final relations = [
      for (final r in _relations)
        if (r.fromId == cardId) {'to': r.toId, if (r.label.isNotEmpty) 'label': r.label},
    ];
    final summaries = [
      for (final (s, _) in _summaries)
        if (s.parentId == cardId) {'from': s.fromId, 'to': s.toId, if (s.label.isNotEmpty) 'label': s.label},
    ];
    return [
      if (cardId != null && _referenced.contains(cardId)) ' _mmId="${_xml(cardId)}"',
      if (relations.isNotEmpty) ' _mmRelations="${_xml(jsonEncode(relations))}"',
      if (summaries.isNotEmpty) ' _mmSummaries="${_xml(jsonEncode(summaries))}"',
    ].join();
  }

  String _annotationSource(Document doc, Annotation annotation) =>
      annotation.isText ? '${doc.title} · ${annotation.textAnchors.first.chapterId}' : _source(doc, annotation.page);

  String _researchBody(Card card) {
    final note = content.researchNote(card.researchNoteId ?? '');
    if (note == null) return '';
    final lines = <String>[note.body];
    for (final ref in note.citations) {
      final evidence = content.evidence.where((e) => e.id == ref.evidenceId).firstOrNull;
      final source = content.researchSources.where((s) => s.id == evidence?.sourceId).firstOrNull;
      if (source != null) lines.add('${source.title} · ${source.url} · ${source.fetchedAt.toIso8601String()}');
    }
    for (final a in content.noteAttachments.where((a) => a.noteId == note.id)) {
      if (a.target case TextTarget(:final documentId, :final textAnchors)) {
        final doc = content.document(documentId);
        if (doc != null) {
          for (final anchor in textAnchors) {
            lines.add('$sourceLabel：${doc.title} · ${anchor.chapterId}');
          }
        }
      }
      if (a.target case PdfTarget(:final documentId, :final pages)) {
        final doc = content.document(documentId);
        if (doc != null) {
          for (final page in pages) {
            lines.add('$sourceLabel：${_source(doc, page.page)}');
          }
        }
      }
    }
    return lines.join('\n');
  }

  String _opmlAttributes(Card card) {
    if (card.kind == CardKind.research) {
      final note = content.researchNote(card.researchNoteId ?? '');
      return 'text="${_xml(note?.title ?? card.title)}" _note="${_xml(_researchBody(card))}"';
    }
    if (card.kind == CardKind.image) {
      // An untitled image is named by its package file; the source is a note.
      final a = content.annotation(card.annotationId ?? '');
      final doc = a == null ? null : content.document(a.documentId);
      final text = card.title.trim().isNotEmpty ? card.title : (card.imageFileName ?? '');
      return 'text="${_xml(text)}"${doc == null ? '' : ' _note="${_xml(_annotationSource(doc, a!))}"'}';
    }
    // Formatting has no place in OPML: a note's text without its markup.
    if (card.kind == CardKind.note) {
      final body = card.body.isEmpty ? '' : ' _note="${_xml(notePlainText(card.body, card.textFormat))}"';
      return 'text="${_xml(notePlainText(card.title, card.textFormat))}"$body';
    }
    if (card.kind != CardKind.excerpt) return 'text="${_xml(card.title)}"';
    final quote = content.segmentsOf(card).map((s) => s.text).join('\n');
    final text = card.title.trim().isNotEmpty ? card.title : quote;
    final sources = {
      for (final segment in content.segmentsOf(card))
        if (content.annotation(segment.annotationId ?? '') case final annotation?)
          if (content.document(annotation.documentId) case final document?) _annotationSource(document, annotation),
    };
    final note = [if (card.title.trim().isNotEmpty) quote, ...sources].join('\n');
    return 'text="${_xml(text)}"${note.isEmpty ? '' : ' _note="${_xml(note)}"'}';
  }

  static String _oneLine(String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll('\n', '&#10;');
}
