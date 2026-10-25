import 'models.dart';
import 'study_set_content.dart';

/// Turns the main mind map into portable text formats.
///
/// [source] labels where an excerpt comes from (e.g. "Book · p. 3"); the
/// app passes a localized one.
class MapExporter {
  MapExporter(
    this.content, {
    required this.rootTitle,
    this.mapId = MindMap.defaultId,
    String Function(Document doc, int page)? source,
  }) : _source = source ?? ((doc, page) => '${doc.title}, p. $page');

  final StudySetContent content;
  final String rootTitle;
  final String mapId;
  final String Function(Document doc, int page) _source;

  /// Nested Markdown list under a level-1 heading. Topics are bold,
  /// excerpts are quoted with their source, notes are plain text.
  String markdown() {
    final out = StringBuffer('# ${_oneLine(rootTitle)}\n\n');
    void walk(String? parentId, int depth) {
      for (final n in content.childrenOf(parentId, mapId: mapId)) {
        final card = content.card(n.cardId);
        if (card == null) continue;
        out.writeln('${'  ' * depth}- ${_markdownLine(card)}');
        walk(card.id, depth + 1);
      }
    }

    walk(null, 0);
    return out.toString();
  }

  String _markdownLine(Card card) {
    switch (card.kind) {
      case CardKind.topic:
        return '**${_oneLine(card.title)}**';
      case CardKind.image:
        return '![${_oneLine(card.title)}](${card.imageFileName ?? ""})';
      case CardKind.note:
        return _oneLine(card.title);
      case CardKind.excerpt:
        final a = content.annotation(card.annotationId ?? '');
        final doc = a == null ? null : content.document(a.documentId);
        final title = card.title.trim().isEmpty ? '' : '**${_oneLine(card.title)}** — ';
        final quote = a == null ? '' : '“${_oneLine(a.quote)}”';
        final src = doc == null ? '' : ' *(${_source(doc, a!.page)})*';
        return '$title$quote$src';
    }
  }

  /// OPML 2.0 outline (opens in most outliners and mind-map apps). Excerpt
  /// quotes go into the `_note` attribute.
  String opml() {
    final out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<opml version="2.0">')
      ..writeln('  <head><title>${_xml(rootTitle)}</title></head>')
      ..writeln('  <body>')
      ..writeln('    <outline text="${_xml(rootTitle)}">');
    void walk(String? parentId, int depth) {
      for (final n in content.childrenOf(parentId, mapId: mapId)) {
        final card = content.card(n.cardId);
        if (card == null) continue;
        final indent = '  ' * (depth + 3);
        final attrs = _opmlAttributes(card);
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

  String _opmlAttributes(Card card) {
    if (card.kind != CardKind.excerpt) return 'text="${_xml(card.title)}"';
    final a = content.annotation(card.annotationId ?? '');
    final doc = a == null ? null : content.document(a.documentId);
    final quote = a?.quote ?? '';
    final text = card.title.trim().isNotEmpty ? card.title : quote;
    final note = [if (card.title.trim().isNotEmpty) quote, if (doc != null) _source(doc, a!.page)].join('\n');
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
