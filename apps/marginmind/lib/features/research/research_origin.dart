import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

/// A piece of context the launcher can send to the AI. The selection (or
/// node) itself is always sent; the others can be switched off.
enum ResearchContextKind { selection, before, after, chapter, node, path, children }

class ResearchContextPart {
  const ResearchContextPart(this.kind, this.text, {this.on = true});

  final ResearchContextKind kind;
  final String text;

  /// Sent unless switched off on the launcher.
  final bool on;

  bool get required => kind == ResearchContextKind.selection || kind == ResearchContextKind.node;
}

/// Where a research starts: a passage of a document or a node of a map. The
/// anchor is fixed when the research is created; later selections never
/// change it.
class ResearchOrigin {
  const ResearchOrigin({
    required this.anchor,
    required this.text,
    required this.fromMap,
    required this.documentTitle,
    required this.page,
    required this.path,
    this.parts = const [],
  });

  final SourceAnchor anchor;

  /// The selected passage, or the node's title.
  final String text;
  final bool fromMap;

  /// Document and page of a passage (empty / 0 for a node).
  final String documentTitle;
  final int page;

  /// Titles from the map's root down to (excluding) the node.
  final List<String> path;
  final List<ResearchContextPart> parts;

  PdfTarget? get pdf => anchor.target is PdfTarget ? anchor.target as PdfTarget : null;
  String? get cardId => anchor.target is CardTarget ? (anchor.target as CardTarget).cardId : null;
}

/// How much text around a selection counts as its neighbouring passage.
const _neighbourLength = 220;

/// The research origin of selected text on a page. [pageText] gives the
/// text of a page (null when the PDF has none); the passages before and
/// after the selection and the chapter it is in become optional context.
Future<ResearchOrigin> pdfOrigin({
  required Document document,
  required List<AnnotationPage> pages,
  required String quote,
  Future<String?> Function(int page)? pageText,
  List<MMPdfOutlineItem> outline = const [],
}) async {
  final page = pages.first.page;
  final text = pageText == null ? null : await pageText(page);
  var before = '', after = '';
  if (text != null) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    final needle = quote.replaceAll(RegExp(r'\s+'), ' ').trim();
    final at = needle.isEmpty ? -1 : flat.indexOf(needle.substring(0, needle.length.clamp(0, 24)));
    if (at >= 0) {
      before = _tail(flat.substring(0, at));
      final end = (at + needle.length).clamp(0, flat.length);
      after = _head(flat.substring(end));
    }
  }
  final chapter = _chapter(outline, page);
  return ResearchOrigin(
    anchor: SourceAnchor(
      target: PdfTarget(
        documentId: document.id,
        pages: pages,
        quote: quote,
        context: [before, after].where((s) => s.isNotEmpty).join(' … '),
      ),
    ),
    text: quote.trim(),
    fromMap: false,
    documentTitle: document.title,
    page: page,
    path: const [],
    parts: [
      ResearchContextPart(ResearchContextKind.selection, quote.trim()),
      if (before.isNotEmpty) ResearchContextPart(ResearchContextKind.before, before),
      if (after.isNotEmpty) ResearchContextPart(ResearchContextKind.after, after),
      if (chapter.isNotEmpty) ResearchContextPart(ResearchContextKind.chapter, chapter),
    ],
  );
}

String _tail(String text) {
  final value = text.trim();
  if (value.length <= _neighbourLength) return value;
  final cut = value.substring(value.length - _neighbourLength);
  final sentence = cut.indexOf(RegExp(r'[。！？.!?]\s*'));
  return (sentence >= 0 && sentence < cut.length - 1 ? cut.substring(sentence + 1) : cut).trim();
}

String _head(String text) {
  final value = text.trim();
  if (value.length <= _neighbourLength) return value;
  final cut = value.substring(0, _neighbourLength);
  final sentence = cut.lastIndexOf(RegExp(r'[。！？.!?]'));
  return (sentence > 0 ? cut.substring(0, sentence + 1) : cut).trim();
}

/// "Chapter › Section" for [page]: the deepest outline entries starting at
/// or before it.
String _chapter(List<MMPdfOutlineItem> outline, int page) {
  final titles = <String>[];
  var level = outline;
  while (level.isNotEmpty) {
    final item = level.where((i) => i.page <= page).lastOrNull;
    if (item == null) break;
    titles.add(item.title.trim());
    level = item.children;
  }
  return titles.where((t) => t.isNotEmpty).join(' › ');
}

/// The research origin of a node: its title, the path above it, and
/// (switched off by default) the text of the cards under it.
ResearchOrigin nodeOrigin(StudySetContent content, String cardId, String mapId, {required String rootTitle}) {
  final card = content.card(cardId)!;
  String titleOf(Card c) => switch (c.kind) {
    CardKind.research => content.researchNote(c.researchNoteId ?? '')?.title ?? '',
    CardKind.excerpt when c.title.isEmpty => content.annotation(c.annotationId ?? '')?.quote ?? '',
    _ => c.title,
  };
  final path = <String>[];
  var parent = content.node(cardId, mapId: mapId)?.parentId;
  final seen = <String>{};
  while (parent != null && seen.add(parent)) {
    final c = content.card(parent);
    if (c == null) break;
    path.insert(0, titleOf(c));
    parent = content.node(parent, mapId: mapId)?.parentId;
  }
  path.insert(0, rootTitle);
  final children = [
    for (final n in content.childrenOf(cardId, mapId: mapId))
      if (content.card(n.cardId) case final c? when c.kind != CardKind.image) titleOf(c),
  ].where((t) => t.trim().isNotEmpty).join('\n');
  final title = titleOf(card).trim();
  return ResearchOrigin(
    anchor: SourceAnchor(
      target: CardTarget(cardId: cardId),
      mapId: mapId,
    ),
    text: title,
    fromMap: true,
    documentTitle: '',
    page: 0,
    path: path,
    parts: [
      ResearchContextPart(ResearchContextKind.node, title),
      ResearchContextPart(ResearchContextKind.path, path.join(' › ')),
      if (children.isNotEmpty) ResearchContextPart(ResearchContextKind.children, children, on: false),
    ],
  );
}

/// What a card is called where it is listed by name: its title, the note
/// title for a research card, or the excerpt it was made from.
String researchCardTitle(StudySetContent content, String cardId) {
  final card = content.card(cardId);
  if (card == null) return '';
  if (card.kind == CardKind.research) return content.researchNote(card.researchNoteId ?? '')?.title ?? '';
  if (card.title.isEmpty) return content.annotation(card.annotationId ?? '')?.quote ?? '';
  return card.title;
}
