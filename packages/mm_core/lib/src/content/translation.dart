import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'models.dart';

/// Original PDF text and character boxes, before crop or viewer transforms.
class TranslationPage {
  TranslationPage(this.page, this.text, List<PageRect> boxes) : boxes = List.unmodifiable(boxes);
  final int page;
  final String text;
  final List<PageRect> boxes;
}

class TranslationParagraph {
  TranslationParagraph({
    required this.documentId,
    required this.page,
    required this.index,
    required this.text,
    required this.fingerprint,
    required List<PageRect> rects,
    this.heading = false,
  }) : rects = List.unmodifiable(rects);
  final String documentId, text, fingerprint;
  final int page, index;
  final bool heading;
  final List<PageRect> rects;
  PageRect get bounds => rects.reduce(
    (a, b) => PageRect(
      math.min(a.left, b.left),
      math.max(a.top, b.top),
      math.max(a.right, b.right),
      math.min(a.bottom, b.bottom),
    ),
  );
}

/// Bump whenever segmentation/normalization changes. Repeated text keeps its
/// own identity; OCR text or geometry changes invalidate the document digest.
const translationSplitVersion = 1;
List<TranslationParagraph> splitTranslationParagraphs(String documentId, List<TranslationPage> pages) {
  final digest = sha256
      .convert(
        utf8.encode(
          jsonEncode([
            for (final p in pages)
              [
                p.page,
                p.text,
                [for (final r in p.boxes) r.toJson()],
              ],
          ]),
        ),
      )
      .toString();
  final result = <TranslationParagraph>[];
  for (final page in pages) {
    final lines = <({String text, PageRect rect})>[];
    var start = 0;
    void line(int end) {
      final text = page.text.substring(start, end).trim();
      final boxes = <PageRect>[
        for (var i = start; i < end && i < page.boxes.length; i++)
          if (page.text[i].trim().isNotEmpty &&
              page.boxes[i].right > page.boxes[i].left &&
              page.boxes[i].top > page.boxes[i].bottom)
            page.boxes[i],
      ];
      if (text.isEmpty || boxes.isEmpty) return;
      final rect = boxes.reduce(
        (a, b) => PageRect(
          math.min(a.left, b.left),
          math.max(a.top, b.top),
          math.max(a.right, b.right),
          math.min(a.bottom, b.bottom),
        ),
      );
      lines.add((text: text, rect: rect));
    }

    // Spaces can have zero-size boxes and glyph ascenders vary within a line.
    // Compare overlapping vertical ranges of actual glyphs, never space boxes.
    PageRect? previous;
    for (var i = 0; i < page.text.length; i++) {
      final explicit = page.text[i] == '\n' || page.text[i] == '\r';
      final rect =
          i < page.boxes.length &&
              page.text[i].trim().isNotEmpty &&
              page.boxes[i].right > page.boxes[i].left &&
              page.boxes[i].top > page.boxes[i].bottom
          ? page.boxes[i]
          : null;
      final wraps =
          rect != null && previous != null && (rect.top < previous.bottom - .5 || rect.bottom > previous.top + .5);
      if (explicit || wraps) {
        line(i);
        start = explicit ? i + 1 : i;
      }
      if (explicit) {
        previous = null;
      } else if (rect != null) {
        previous = rect;
      }
    }
    line(page.text.length);
    var group = <({String text, PageRect rect})>[];
    void flush() {
      if (group.isEmpty) return;
      final text = group.map((l) => l.text).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      final rects = group.map((l) => l.rect).toList();
      // Reflow supplies its own page footer, rather than translating it twice.
      if (text == '${page.page}' && rects.every((r) => r.top < 100)) {
        group = [];
        return;
      }
      final index = result.length;
      final heading =
          group.length == 1 &&
          text.length <= 90 &&
          !RegExp(r'[.!?。！？;；:]$').hasMatch(text) &&
          !RegExp(r'^\d+$').hasMatch(text);
      final fingerprint = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                translationSplitVersion,
                documentId,
                digest,
                page.page,
                index,
                text,
                [for (final r in rects) r.toJson()],
              ]),
            ),
          )
          .toString();
      result.add(
        TranslationParagraph(
          documentId: documentId,
          page: page.page,
          index: index,
          text: text,
          fingerprint: fingerprint,
          rects: rects,
          heading: heading,
        ),
      );
      group = [];
    }

    for (final l in lines) {
      if (group.isNotEmpty) {
        final previous = group.last.rect;
        final height = previous.top - previous.bottom;
        if (previous.bottom - l.rect.top > height * .65 ||
            l.rect.top > previous.top + height ||
            (l.rect.left - group.first.rect.left).abs() > height * 2 ||
            (l.rect.top - l.rect.bottom - height).abs() > height * .3 ||
            group.fold<int>(0, (n, l) => n + l.text.length) + l.text.length > 3000) {
          flush();
        }
      }
      group.add(l);
    }
    flush();
  }
  return List.unmodifiable(result);
}
