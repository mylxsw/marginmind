import 'dart:math' as math;

import 'package:mm_core/mm_core.dart';

/// PDF text and character geometry, independent of Flutter and the PDF engine.
class ExcerptPageText {
  const ExcerptPageText({required this.page, required this.height, required this.text, required this.rects});
  final int page;
  final double height;
  final String text;
  final List<PageRect> rects;
}

class ExcerptTextSpan {
  const ExcerptTextSpan(this.page, this.start, this.end);
  final int page;
  final int start;
  final int end;
}

class ExcerptTextResult {
  const ExcerptTextResult(this.text, this.pages);
  final String text;
  final List<AnnotationPage> pages;
}

/// Merge horizontally adjacent word boxes on the same baseline. Large gaps
/// (columns), different lines and vertical writing stay separate.
List<PageRect> excerptLineRects(Iterable<PageRect> input) {
  final result = <PageRect>[];
  for (final r in input) {
    if (r.right <= r.left || r.top <= r.bottom) continue;
    final index = result.lastIndexWhere((a) {
      final height = math.min(a.top - a.bottom, r.top - r.bottom);
      return (a.top - r.top).abs() < height * 0.3 &&
          (a.bottom - r.bottom).abs() < height * 0.3 &&
          math.max(a.left, r.left) - math.min(a.right, r.right) <= height * 3;
    });
    if (index < 0) {
      result.add(r);
    } else {
      final a = result[index];
      result[index] = PageRect(
        math.min(a.left, r.left),
        math.max(a.top, r.top),
        math.max(a.right, r.right),
        math.min(a.bottom, r.bottom),
      );
    }
  }
  return result;
}

class _Line {
  _Line(this.start, this.end, this.text, this.bounds);
  final int start;
  final int end;
  final String text;
  final PageRect bounds;
}

List<_Line> _lines(ExcerptPageText page) {
  if (page.rects.length != page.text.length) return [];
  final lines = <_Line>[];
  for (final match in RegExp(r'[^\r\n]+').allMatches(page.text)) {
    final boxes = excerptLineRects([
      for (var i = match.start; i < match.end; i++)
        if (page.text[i].trim().isNotEmpty) page.rects[i],
    ]);
    if (boxes.isEmpty) continue;
    lines.add(
      _Line(
        match.start,
        match.end,
        match[0]!,
        PageRect(
          boxes.map((r) => r.left).reduce(math.min),
          boxes.map((r) => r.top).reduce(math.max),
          boxes.map((r) => r.right).reduce(math.max),
          boxes.map((r) => r.bottom).reduce(math.min),
        ),
      ),
    );
  }
  return lines;
}

/// Compare the unchanged title/path and a page number at either edge. The
/// printed number may have an offset, but must progress with the PDF page.
bool _sameMarginText(String a, int pageA, String b, int pageB) {
  if (a == b) return true;
  List<(String, int)> numbered(String text) {
    // Chapter headings are content, even when a chapter starts on every page.
    if (RegExp(r'^(?:chapter\s+\d+|第\s*\d+\s*章)').hasMatch(text)) return [];
    final result = <(String, int)>[];
    for (final pattern in [
      RegExp(r'^(\d+)(?=\s|$)'),
      RegExp(r'(?:^|\s)(\d+)(?:\s*/\s*\d+)?$'),
      RegExp(r'第\s*(\d+)\s*页$'),
    ]) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final value = match[1]!;
      // group 1 may follow a whitespace prefix or “第”.
      final start = text.indexOf(value, match.start);
      final number = int.tryParse(value);
      if (number != null) result.add((text.replaceRange(start, start + value.length, '#'), number));
    }
    return result;
  }

  final left = numbered(a), right = numbered(b);
  return left.any((x) => right.any((y) => x.$1 == y.$1 && y.$2 - x.$2 == pageB - pageA));
}

/// Uses full neighbouring pages as evidence, never the selected fragment alone.
/// Only geometrically topmost/bottommost lines in the outer 8% with a
/// separated body qualify. Text extraction order is preserved in the quote. At least
/// two distinct pages must agree in text and position. Ambiguity keeps text.
ExcerptTextResult buildExcerptText(List<ExcerptPageText> evidence, List<ExcerptTextSpan> spans) {
  final lines = {for (final page in evidence) page.page: _lines(page)};
  final candidates = <(int, _Line, bool, String, double)>[];
  String signature(String s) {
    final value = s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    // Printed dates repeat independently of the PDF's page number.
    return RegExp(r'\d+[/-]\d+[/-]\d+').hasMatch(value) ? value.replaceAll(RegExp(r'\d+'), '#') : value;
  }

  for (final page in evidence) {
    final onPage = [...lines[page.page]!]..sort((a, b) => b.bounds.top.compareTo(a.bounds.top));
    if (onPage.length < 3 || page.height <= 0) continue;
    for (final top in [true, false]) {
      final line = top ? onPage.first : onPage.last;
      final next = top ? onPage[1] : onPage[onPage.length - 2];
      final gap = top ? line.bounds.bottom - next.bounds.top : next.bounds.bottom - line.bounds.top;
      final inMargin = top ? line.bounds.bottom > page.height * 0.92 : line.bounds.top < page.height * 0.08;
      if (!inMargin || gap < (line.bounds.top - line.bounds.bottom) * 1.5) continue;
      candidates.add((page.page, line, top, signature(line.text), line.bounds.top / page.height));
    }
  }
  final excluded = <(int, int)>{};
  for (final a in candidates) {
    if (candidates.any(
      (b) => a.$1 != b.$1 && a.$3 == b.$3 && _sameMarginText(a.$4, a.$1, b.$4, b.$1) && (a.$5 - b.$5).abs() < 0.015,
    )) {
      excluded.add((a.$1, a.$2.start));
    }
  }
  final pages = <AnnotationPage>[];
  final text = StringBuffer();
  final sorted = [...spans]..sort((a, b) => a.page != b.page ? a.page.compareTo(b.page) : a.start.compareTo(b.start));
  for (final page
      in evidence.where((p) => sorted.any((s) => s.page == p.page)).toList()
        ..sort((a, b) => a.page.compareTo(b.page))) {
    final selected = sorted.where((s) => s.page == page.page);
    final boxes = <PageRect>[];
    _Line? previous;
    for (final line in lines[page.page]!) {
      if (excluded.contains((page.page, line.start))) continue;
      final indices = <int>[
        for (var i = line.start; i < line.end; i++)
          if (selected.any((s) => i >= s.start && i < s.end)) i,
      ];
      if (indices.isEmpty) continue;
      if (text.isNotEmpty) {
        final blank =
            previous != null &&
            (page.text.substring(previous.end, line.start).contains(RegExp(r'\n\s*\n')) ||
                previous.bounds.bottom - line.bounds.top >
                    math.max(previous.bounds.top - previous.bounds.bottom, line.bounds.top - line.bounds.bottom) * 1.2);
        text.write(blank ? '\n\n' : '\n');
      }
      text.write(indices.map((i) => page.text[i]).join());
      boxes.addAll([
        for (final i in indices)
          if (page.text[i].trim().isNotEmpty) page.rects[i],
      ]);
      previous = line;
    }
    final rects = excerptLineRects(boxes);
    if (rects.isNotEmpty) pages.add(AnnotationPage(page: page.page, rects: rects));
  }
  return ExcerptTextResult(joinExcerptLines(text.toString()), pages);
}
