import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

/// A4 points; text is measured once and sent through the existing vector PDF
/// encoder. Each page owns its footer and the footnotes referenced on that page.
class NotePdf {
  static const width = 595.28, height = 841.89, margin = 48.0;
  static Map<String, Object?> scene(NoteRichDocument document) {
    final pages = <List<Map<String, Object?>>>[];
    var commands = <Map<String, Object?>>[], footnotes = <String>[];
    var y = 76.0, reserved = 0.0, index = 0;
    List<String> lines(String value, double size, {bool serif = false}) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(fontSize: size, fontFamily: serif ? 'Songti SC' : null),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - margin * 2 - 20);
      final result = <String>[];
      for (final metric in painter.computeLineMetrics()) {
        final offset = painter.getPositionForOffset(Offset(metric.left + metric.width / 2, metric.baseline));
        final range = painter.getLineBoundary(offset);
        result.add(value.substring(range.start, range.end).replaceAll('\n', ''));
      }
      painter.dispose();
      return result;
    }

    Map<String, Object?> text(
      String value,
      double x,
      double top,
      double size, {
      bool serif = false,
      bool bold = false,
    }) => {
      'type': 'text',
      'text': value,
      'x': x,
      'y': top,
      'fontSize': size,
      'serif': serif,
      'bold': bold,
      'color': 0xff222222,
    };
    Map<String, Object?> box(double x, double top, double w, double h, int color) => {
      'type': 'box',
      'rect': [x, top, w, h],
      'radius': 0.0,
      'color': color,
    };
    void finish() {
      // The running title is a single bounded line, including very long titles.
      commands.add(text(lines(document.title, 9).firstOrNull ?? '', margin, 32, 9));
      commands.add(text('${pages.length + 1}', width / 2, height - 30, 9));
      var top = height - 56 - reserved;
      if (footnotes.isNotEmpty) commands.add(box(margin, top - 6, 100, .5, 0xff999999));
      for (final line in footnotes) {
        commands.add(text(line, margin, top, 9));
        top += 13;
      }
      pages.add(commands);
      commands = [];
      footnotes = [];
      y = 76;
      reserved = 0;
    }

    for (final p in document.paragraphs) {
      final quote = p.kind == NoteParagraphKind.quote;
      final size = p.kind == NoteParagraphKind.title
          ? 20.0
          : p.kind == NoteParagraphKind.heading
          ? 14.0
          : 11.0;
      var value =
          '${p.ai.isEmpty ? '' : '${p.ai}: '}${p.kind == NoteParagraphKind.point
              ? '• '
              : p.kind == NoteParagraphKind.action
              ? '☐ '
              : ''}${p.text}';
      var noteLines = <String>[];
      if (quote && document.citations == NoteCitationStyle.footnote) {
        value = '[${++index}] $value';
        noteLines = lines('[$index] ${p.citation ?? ''}', 9);
      }
      // Exceptionally long source names still fit: their footnote continues on
      // dedicated pages before the quote, rather than overflowing the footer.
      while (noteLines.length > 35) {
        if (y > 76) finish();
        footnotes = noteLines.take(35).toList();
        reserved = footnotes.length * 13;
        finish();
        noteLines = noteLines.skip(35).toList();
      }
      final needed = noteLines.length * 13.0;
      final keepNext = p.kind == NoteParagraphKind.heading ? 11 * 1.6 + 10 : 0;
      if (y + size * 1.6 + keepNext > height - 64 - reserved - needed) finish();
      footnotes.addAll(noteLines);
      reserved += needed;
      for (final line in lines(value, size, serif: quote)) {
        final lineHeight = size * 1.6;
        if (y + lineHeight > height - 64 - reserved) finish();
        if (p.kind == NoteParagraphKind.own) {
          commands.add(box(margin, y - 2, width - margin * 2, lineHeight, 0xfffff3c4));
        }
        if (quote) {
          commands.add(
            box(margin, y - 2, 3, lineHeight, int.parse('ff${noteHighlightHex(p.colorIndex).substring(1)}', radix: 16)),
          );
        }
        commands.add(
          text(
            line,
            margin + (quote ? 14 : 0),
            y,
            size,
            serif: quote,
            bold: p.kind == NoteParagraphKind.title || p.kind == NoteParagraphKind.heading,
          ),
        );
        y += lineHeight;
      }
      if (quote && document.citations == NoteCitationStyle.inline) {
        for (final line in lines('— ${p.citation ?? ''}', 9)) {
          if (y + 14 > height - 64 - reserved) finish();
          commands.add(text(line, margin + 14, y, 9));
          y += 14;
        }
      }
      y += 10;
    }
    finish();
    return {'width': width, 'height': height, 'pages': pages};
  }

  static Future<Uint8List> encode(NoteRichDocument document) => const NativeMapExport().pdf(scene(document));
}
