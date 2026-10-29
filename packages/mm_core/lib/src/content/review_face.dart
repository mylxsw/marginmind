import 'dart:convert';

import 'text_anchor.dart';

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'excerpt_lines.dart';
import 'models.dart';
import 'note_format.dart';
import 'research.dart';
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
  const ReviewSource({required this.documentId, required this.documentTitle, int? page, this.textAnchor})
    // Preserve the existing public named page parameter.
    // ignore: prefer_initializing_formals
    : _page = page;
  final TextAnchor? textAnchor;

  final String documentId;
  final String documentTitle;
  final int? _page;
  int get page => _page ?? (throw StateError('Text review source has no page'));

  @override
  bool operator ==(Object other) =>
      other is ReviewSource &&
      other.documentId == documentId &&
      other.documentTitle == documentTitle &&
      other._page == _page &&
      jsonEncode(other.textAnchor?.toJson()) == jsonEncode(textAnchor?.toJson());

  @override
  int get hashCode => Object.hash(documentId, documentTitle, _page, jsonEncode(textAnchor?.toJson()));
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

/// A note on the back of a review card, in its stored format: review shows
/// it formatted like the map does.
@immutable
class ReviewNote {
  const ReviewNote(this.text, [this.format = TextFormat.plain]);

  final String text;
  final TextFormat format;

  @override
  bool operator ==(Object other) => other is ReviewNote && other.text == text && other.format == format;

  @override
  int get hashCode => Object.hash(text, format);

  @override
  String toString() => 'ReviewNote("$text", ${format.name})';
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
  final List<ReviewNote> notes;
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
/// With [pageHeight] a repeated passage is told apart by where it was
/// highlighted. [lastPageText] is the text of the excerpt's last page when
/// it runs past the first.
ReviewFace buildReviewFace(
  Card card,
  StudySetContent content, {
  String mapId = MindMap.defaultId,
  String rootTitle = '',
  String? pageText,
  double? pageHeight,
  String? lastPageText,
}) {
  final path = [
    for (final t in content.pathOf(card.id, mapId: mapId))
      if (t.trim().isNotEmpty) t.trim(),
  ];
  final notes = [
    for (final n in content.childrenOf(card.id, mapId: mapId))
      if (content.card(n.cardId) case final c? when c.kind == CardKind.note && c.title.trim().isNotEmpty)
        ReviewNote(c.title.trim(), c.textFormat),
  ];
  final annotation = card.annotationId == null ? null : content.annotation(card.annotationId!);

  if (card.kind == CardKind.research) {
    final note = content.researchNote(card.researchNoteId ?? '');
    final citations = <ReviewNote>[];
    for (final ref in note?.citations ?? <EvidenceRef>[]) {
      final evidence = content.evidence.where((e) => e.id == ref.evidenceId).firstOrNull;
      if (evidence == null) continue;
      final source = content.researchSources.where((s) => s.id == evidence.sourceId).firstOrNull;
      citations.add(
        ReviewNote(
          '[${citations.length + 1}] ${source?.title ?? evidence.sourceId} · v${evidence.sourceVersion}\n${evidence.quote}\n${source?.url ?? ""}',
        ),
      );
    }
    return ReviewFace(
      front: ReviewFront(path: path, prompt: ReviewPrompt.title, title: note?.question ?? ''),
      back: ReviewBack(notes: [if (note != null) ReviewNote(note.body, note.textFormat), ...citations]),
    );
  }

  if (card.kind == CardKind.note) {
    if (card.body.isNotEmpty) {
      return ReviewFace(
        front: ReviewFront(path: path, prompt: ReviewPrompt.title, title: card.title),
        back: ReviewBack(notes: [ReviewNote(card.body, card.textFormat), ...notes]),
      );
    }
    final parentId = content.node(card.id, mapId: mapId)?.parentId;
    final parent = parentId == null ? null : content.card(parentId);
    var parentTitle = parent == null ? '' : notePlainText(parent.title, parent.textFormat).trim();
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
      back: ReviewBack(notes: [ReviewNote(card.title.trim(), card.textFormat), ...notes]),
    );
  }

  final isImage = card.kind == CardKind.image && card.imageFileName != null;
  final doc = annotation == null ? null : content.document(annotation.documentId);
  final source = annotation == null || doc == null
      ? null
      : ReviewSource(
          documentId: doc.id,
          documentTitle: doc.title,
          page: annotation.isText ? null : annotation.page,
          textAnchor: annotation.textAnchors.firstOrNull,
        );
  final back = ReviewBack(
    quote: isImage
        ? ''
        : card.segments.isNotEmpty
        ? card.segments.map((segment) => segment.text).join('\n')
        : (annotation?.quote.trim() ?? card.title.trim()),
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
  if (isImage && annotation == null) {
    final parentId = content.node(card.id, mapId: mapId)?.parentId;
    final parent = parentId == null ? null : content.card(parentId);
    final parentTitle = parent == null ? rootTitle.trim() : parent.title.trim();
    return ReviewFace(
      front: ReviewFront(
        path: path,
        prompt: parentTitle.isEmpty ? ReviewPrompt.none : ReviewPrompt.title,
        title: parentTitle,
      ),
      back: back,
    );
  }
  final quote = isImage ? '' : (annotation?.quote.trim() ?? '');
  if (annotation?.isText == true) {
    return ReviewFace(
      front: ReviewFront(
        path: path,
        prompt: ReviewPrompt.cloze,
        before: annotation!.textAnchors.first.prefix,
        after: annotation.textAnchors.last.suffix,
        maskLength: quote.length,
      ),
      back: back,
    );
  }
  final top = annotation == null || annotation.pages.isEmpty || annotation.pages.first.rects.isEmpty
      ? null
      : annotation.pages.first.rects.first.top;
  final near = top == null || pageHeight == null || pageHeight <= 0 ? null : 1 - top / pageHeight;
  var context = quote.isEmpty || pageText == null ? null : excerptContext(pageText, quote, near: near);
  if (context == null && quote.isNotEmpty && pageText != null && lastPageText != null) {
    context = excerptContextAcross(pageText, lastPageText, quote, near: near);
  }
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

const _enders = '.!?。！？\n';

/// [text] the way [pageText] and quotes are compared: wrapped lines joined by
/// the same rule the excerpt text was built with, runs of spaces folded.
String _normalize(String text) => joinExcerptLines(text).replaceAll(RegExp(r'[ \t ]+'), ' ');

/// Quotes saved before lines were joined keep a space between CJK
/// characters, so they are matched with all whitespace folded as well.
String _fold(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The sentence in [pageText] holding [quote], plus one sentence on each
/// side, split at the excerpt: text before it and text after it. Null when
/// [quote] is not found. Both are normalized with [joinExcerptLines] first,
/// since PDF text wraps lines in the middle of sentences. When the quote
/// occurs more than once, [near] (0 at the top of the page, 1 at the bottom)
/// picks the occurrence closest to where it was highlighted.
({String before, String after})? excerptContext(String pageText, String quote, {double? near}) {
  var t = _normalize(pageText);
  var q = _normalize(quote).trim();
  if (q.isEmpty) return null;
  var at = _nearest(t, q, near);
  if (at < 0) {
    t = _fold(pageText);
    q = _fold(quote);
    at = _nearest(t, q, near);
    if (at < 0) return null;
  }
  return (before: _before(t, at), after: _after(t, at + q.length));
}

/// How much of a quote's head and tail is looked up on its first and last
/// page: up to [_edge] characters, fewer when only a little of the quote
/// is on that page, but never under [_minEdge].
const _edge = 24;
const _minEdge = 6;

/// [excerptContext] for a quote that runs from [firstPage] onto a later page
/// ending with [lastPage]. The page breaks carry running headers and footers
/// the quote left out, so the text before it is found from the quote's head
/// on the first page and the text after it from its tail on the last.
({String before, String after})? excerptContextAcross(String firstPage, String lastPage, String quote, {double? near}) {
  for (final norm in [_normalize, _fold]) {
    final q = norm(quote).trim();
    if (q.isEmpty) return null;
    final first = norm(firstPage), last = norm(lastPage);
    final shortest = math.min(_minEdge, q.length);
    var at = -1, end = -1;
    for (var n = math.min(_edge, q.length); n >= shortest && at < 0; n--) {
      at = _nearest(first, q.substring(0, n), near);
    }
    for (var n = math.min(_edge, q.length); n >= shortest && end < 0; n--) {
      final i = last.indexOf(q.substring(q.length - n));
      if (i >= 0) end = i + n;
    }
    if (at >= 0 && end >= 0) return (before: _before(first, at), after: _after(last, end));
  }
  return null;
}

/// One sentence back from where the excerpt starts at [at] in [t].
String _before(String t, int at) {
  var start = _sentenceStart(t, at);
  var back = start;
  while (back > 0 && (t[back - 1] == ' ' || _enders.contains(t[back - 1]))) {
    back--;
  }
  if (back > 0) start = _sentenceStart(t, back);
  return t.substring(start, at).trimLeft();
}

/// One sentence forward from where the excerpt ends at [end] in [t]; an
/// excerpt that already ends a sentence adds no more of it.
String _after(String t, int end) {
  var stop = end > 0 && _enders.contains(t[end - 1]) ? end : _sentenceEnd(t, end);
  if (stop < t.length) stop = _sentenceEnd(t, stop);
  return t.substring(end, stop).trimRight();
}

/// Where [q] occurs in [t], the occurrence closest to the [near] fraction of
/// the text when there are several; -1 when absent.
int _nearest(String t, String q, double? near) {
  var best = t.indexOf(q);
  if (best < 0 || near == null) return best;
  final target = near.clamp(0.0, 1.0) * t.length;
  for (var i = t.indexOf(q, best + 1); i >= 0; i = t.indexOf(q, i + 1)) {
    if ((i - target).abs() < (best - target).abs()) best = i;
  }
  return best;
}

final _wordChar = RegExp(r'[0-9A-Za-z]');

/// Whether a sentence ends at [i] in [t]. A period inside a number or a
/// section label such as “7.5” does not.
bool _endsAt(String t, int i) =>
    _enders.contains(t[i]) && (t[i] != '.' || i + 1 == t.length || !_wordChar.hasMatch(t[i + 1]));

int _sentenceStart(String t, int from) {
  for (var i = from - 1; i >= 0; i--) {
    if (_endsAt(t, i)) {
      var j = i + 1;
      while (j < from && (t[j] == ' ' || t[j] == '\n')) {
        j++;
      }
      return j;
    }
  }
  return 0;
}

int _sentenceEnd(String t, int from) {
  for (var i = from; i < t.length; i++) {
    if (_endsAt(t, i)) return i + 1;
  }
  return t.length;
}
