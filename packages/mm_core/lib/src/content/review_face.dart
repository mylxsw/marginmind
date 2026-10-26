import 'package:meta/meta.dart';

import 'models.dart';
import 'study_set_content.dart';

/// What the front of a review card shows besides the branch path.
enum ReviewPrompt {
  /// The sentence around the excerpt, with the excerpt itself masked.
  cloze,

  /// The user's own title (a question) or the parent topic's title.
  title,

  /// A thumbnail of the source page with the excerpt area covered.
  page,

  /// Nothing to recall from; the path is all there is.
  none,
}

/// The source of an excerpt, for the back of the card.
@immutable
class ReviewSource {
  const ReviewSource({required this.documentId, required this.documentTitle, required this.page});

  final String documentId;
  final String documentTitle;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is ReviewSource &&
      other.documentId == documentId &&
      other.documentTitle == documentTitle &&
      other.page == page;

  @override
  int get hashCode => Object.hash(documentId, documentTitle, page);
}

@immutable
class ReviewFront {
  const ReviewFront({
    required this.path,
    required this.prompt,
    this.title = '',
    this.before = '',
    this.after = '',
    this.maskLength = 0,
    this.page,
    this.areas = const [],
  });

  /// Titles of the ancestors in the map, root omitted.
  final List<String> path;
  final ReviewPrompt prompt;

  /// [ReviewPrompt.title] only.
  final String title;

  /// [ReviewPrompt.cloze] only: text before and after the masked excerpt,
  /// and the excerpt's length in characters (the mask is about as wide).
  final String before;
  final String after;
  final int maskLength;

  /// [ReviewPrompt.page] only: the page to show and the rectangles on it
  /// to cover.
  final int? page;
  final List<PageRect> areas;

  @override
  bool operator ==(Object other) =>
      other is ReviewFront &&
      _listEq(other.path, path) &&
      other.prompt == prompt &&
      other.title == title &&
      other.before == before &&
      other.after == after &&
      other.maskLength == maskLength &&
      other.page == page &&
      _listEq(other.areas, areas);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(path), prompt, title, before, after, maskLength, page, Object.hashAll(areas));
}

@immutable
class ReviewBack {
  const ReviewBack({this.quote = '', this.colorIndex = 0, this.imageFileName, this.notes = const [], this.source});

  /// The full excerpt text; empty for image cards and notes.
  final String quote;

  /// The excerpt's highlight color.
  final int colorIndex;
  final String? imageFileName;

  /// Notes hanging under the card in the map, in map order. For a note
  /// card the first entry is its own text.
  final List<String> notes;
  final ReviewSource? source;

  @override
  bool operator ==(Object other) =>
      other is ReviewBack &&
      other.quote == quote &&
      other.colorIndex == colorIndex &&
      other.imageFileName == imageFileName &&
      _listEq(other.notes, notes) &&
      other.source == source;

  @override
  int get hashCode => Object.hash(quote, colorIndex, imageFileName, Object.hashAll(notes), source);
}

@immutable
class ReviewFace {
  const ReviewFace({required this.front, required this.back});

  final ReviewFront front;
  final ReviewBack back;

  @override
  bool operator ==(Object other) => other is ReviewFace && other.front == front && other.back == back;

  @override
  int get hashCode => Object.hash(front, back);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether [card]'s front needs the text of its source page to be built.
bool needsPageText(Card card, StudySetContent content) {
  if (card.kind != CardKind.excerpt || card.title.trim().isNotEmpty) return false;
  final a = card.annotationId == null ? null : content.annotation(card.annotationId!);
  return a != null && a.quote.trim().isNotEmpty;
}

/// The two sides of [card] for review, from its place in map [mapId].
///
/// [pageText] is the text of the excerpt's first page, when it could be
/// read; without it an untitled excerpt falls back to the page thumbnail.
ReviewFace buildReviewFace(
  Card card,
  StudySetContent content, {
  String mapId = MindMap.defaultId,
  String rootTitle = '',
  String? pageText,
}) {
  final path = [
    for (final t in content.pathOf(card.id, mapId: mapId))
      if (t.trim().isNotEmpty) t.trim(),
  ];
  final notes = [
    for (final n in content.childrenOf(card.id, mapId: mapId))
      if (content.card(n.cardId) case final c? when c.kind == CardKind.note && c.title.trim().isNotEmpty)
        c.title.trim(),
  ];
  final annotation = card.annotationId == null ? null : content.annotation(card.annotationId!);

  if (card.kind == CardKind.note) {
    final parentId = content.node(card.id, mapId: mapId)?.parentId;
    final parent = parentId == null ? null : content.card(parentId);
    var parentTitle = parent?.title.trim() ?? '';
    if (parentTitle.isEmpty && parent != null) {
      final a = parent.annotationId == null ? null : content.annotation(parent.annotationId!);
      parentTitle = a == null ? '' : a.quote.trim();
    }
    if (parent == null) parentTitle = rootTitle.trim();
    // The parent is the last step of the branch the card hangs on.
    return ReviewFace(
      front: ReviewFront(
        path: path,
        prompt: parentTitle.isEmpty ? ReviewPrompt.none : ReviewPrompt.title,
        title: parentTitle,
      ),
      back: ReviewBack(notes: [card.title.trim(), ...notes]),
    );
  }

  final isImage = card.kind == CardKind.image && card.imageFileName != null;
  final doc = annotation == null ? null : content.document(annotation.documentId);
  final source = annotation == null || doc == null
      ? null
      : ReviewSource(documentId: doc.id, documentTitle: doc.title, page: annotation.page);
  final back = ReviewBack(
    quote: isImage ? '' : (annotation?.quote.trim() ?? card.title.trim()),
    colorIndex: annotation?.colorIndex ?? 0,
    imageFileName: isImage ? card.imageFileName : null,
    notes: notes,
    source: source,
  );

  final title = card.title.trim();
  if (title.isNotEmpty) {
    return ReviewFace(
      front: ReviewFront(path: path, prompt: ReviewPrompt.title, title: title),
      back: back,
    );
  }
  final quote = isImage ? '' : (annotation?.quote.trim() ?? '');
  final context = quote.isEmpty || pageText == null ? null : excerptContext(pageText, quote);
  if (context != null) {
    return ReviewFace(
      front: ReviewFront(
        path: path,
        prompt: ReviewPrompt.cloze,
        before: context.before,
        after: context.after,
        maskLength: quote.length,
      ),
      back: back,
    );
  }
  if (annotation != null) {
    return ReviewFace(
      front: ReviewFront(
        path: path,
        prompt: ReviewPrompt.page,
        page: annotation.page,
        areas: annotation.pages.first.rects,
      ),
      back: back,
    );
  }
  return ReviewFace(
    front: ReviewFront(path: path, prompt: ReviewPrompt.none),
    back: back,
  );
}

const _enders = '.!?。！？';

/// The sentence in [pageText] holding [quote], plus one sentence on each
/// side, split at the excerpt: text before it and text after it. Null when
/// [quote] is not found. Whitespace is folded first, since PDF text wraps
/// lines in the middle of sentences.
({String before, String after})? excerptContext(String pageText, String quote) {
  String fold(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  final t = fold(pageText);
  final q = fold(quote).trim();
  if (q.isEmpty) return null;
  final at = t.indexOf(q);
  if (at < 0) return null;
  final end = at + q.length;

  // One sentence back from where the excerpt starts, one forward from where
  // it ends; an excerpt that already ends a sentence adds no more of it.
  var start = _sentenceStart(t, at);
  var back = start;
  while (back > 0 && (t[back - 1] == ' ' || _enders.contains(t[back - 1]))) {
    back--;
  }
  if (back > 0) start = _sentenceStart(t, back);
  var stop = _enders.contains(t[end - 1]) ? end : _sentenceEnd(t, end);
  if (stop < t.length) stop = _sentenceEnd(t, stop);

  return (before: t.substring(start, at).trimLeft(), after: t.substring(end, stop).trimRight());
}

int _sentenceStart(String t, int from) {
  for (var i = from - 1; i >= 0; i--) {
    if (_enders.contains(t[i])) {
      var j = i + 1;
      while (j < from && t[j] == ' ') {
        j++;
      }
      return j;
    }
  }
  return 0;
}

int _sentenceEnd(String t, int from) {
  for (var i = from; i < t.length; i++) {
    if (_enders.contains(t[i])) return i + 1;
  }
  return t.length;
}
