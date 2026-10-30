import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_reflow/mm_reflow.dart';

/// Ephemeral geometry in surface coordinates. PDF y is negated so both
/// renderers use top-down coordinates without losing original PDF positions.
class VocabularyHit {
  const VocabularyHit(this.entryId, this.rects, {this.anchor, this.page});
  final String entryId;
  final List<Rect> rects;
  final TextAnchor? anchor;
  final int? page;
  List<PageRect> get pdfRects => [for (final r in rects) PageRect(r.left, -r.top, r.right, -r.bottom)];
}

/// Merge adjacent character boxes on a line, preserving bidi and wrapped gaps.
List<Rect> vocabularyPdfRects(TranslationPage page, int start, int end) {
  final result = <Rect>[];
  for (var i = start; i < math.min(end, page.boxes.length); i++) {
    final b = page.boxes[i];
    if (b.right <= b.left || b.top <= b.bottom || page.text[i].trim().isEmpty) continue;
    final rect = Rect.fromLTRB(b.left, -b.top, b.right, -b.bottom);
    if (result.isNotEmpty) {
      final last = result.last;
      if ((last.center.dy - rect.center.dy).abs() < math.min(last.height, rect.height) / 2 &&
          rect.left >= last.left &&
          rect.left - last.right <= math.max(3, rect.height)) {
        result[result.length - 1] = last.expandToInclude(rect);
        continue;
      }
    }
    result.add(rect);
  }
  return result;
}

List<VocabularyHit> vocabularyPdfHits(TranslationPage page, List<VocabularyMatch> matches) => [
  for (final m in matches)
    if (vocabularyPdfRects(page, m.start, m.end) case final rects when rects.isNotEmpty)
      VocabularyHit(m.entryId, rects, page: page.page),
];

/// Match only paragraph pieces touching the viewport and one screen around it.
/// The caller retains the bounded text/version cache across scroll frames.
List<VocabularyHit> vocabularyReflowHits(
  ChapterLayout layout,
  VocabularyMatchCache cache,
  List<VocabularyEntry> entries,
  int version, {
  int? page,
  double? top,
  double? bottom,
  bool showKnown = false,
}) {
  if (layout.isDisposed) return const [];
  final firstPage = page == null ? null : math.max(0, page - 1);
  final lastPage = page == null ? null : math.min(layout.pages.length - 1, page + 1);
  final from = firstPage == null ? top ?? 0 : layout.pages[firstPage].top;
  final to = lastPage == null ? bottom ?? layout.height : layout.pages[lastPage].bottom;
  final seen = <(int, int)>{};
  final result = <VocabularyHit>[];
  for (final p in layout.pieces) {
    if (p.decorative ||
        p.painter == null ||
        p.rect.bottom < from ||
        p.rect.top > to ||
        !seen.add((p.textStart, p.textEnd))) {
      continue;
    }
    final text = layout.chapter.canonicalText.substring(p.textStart, p.textEnd);
    for (final m in cache.match(text, version: version, entries: entries, showKnown: showKnown)) {
      final anchor = layout.chapter.anchor(p.textStart + m.start, p.textStart + m.end);
      final rects = layout.boxes(anchor, page: page, candidates: [p]).map((b) => b.rect).toList();
      if (rects.isNotEmpty) result.add(VocabularyHit(m.entryId, rects, anchor: anchor));
    }
  }
  return result;
}

/// Space above a line, stopping at preceding text or artwork. Same-line boxes
/// are excluded. Zero is conservative when the preceding line overlaps.
double vocabularyGlossSpace(Rect hit, Iterable<Rect> lines, {double ceiling = 0}) {
  var previous = ceiling;
  for (final line in lines) {
    if (line.top < hit.top - .5 && line.bottom <= hit.center.dy) previous = math.max(previous, line.bottom);
  }
  return math.max(0, hit.top - previous);
}
