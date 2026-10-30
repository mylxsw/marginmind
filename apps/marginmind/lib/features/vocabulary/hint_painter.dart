import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'hint_geometry.dart';

/// Decorations only: this painter is never part of document/annotation exports.
class VocabularyHintPainter extends CustomPainter {
  VocabularyHintPainter({
    required this.hits,
    required this.entries,
    required this.color,
    required this.knownColor,
    required this.tint,
    required this.glossStyle,
    this.lines = const [],
    this.gloss = false,
    this.flashEntry,
    this.flashOnly = false,
  });
  final List<VocabularyHit> hits;
  final Map<String, VocabularyEntry> entries;
  final Color color, knownColor, tint;
  final TextStyle glossStyle;
  final List<Rect> lines;
  final bool gloss, flashOnly;
  final String? flashEntry;
  @override
  void paint(Canvas canvas, Size size) {
    final labels = <Rect>[];
    for (final hit in hits) {
      final e = entries[hit.entryId];
      if (e == null || (flashOnly && flashEntry != e.id)) continue;
      final ink = e.status == VocabularyStatus.known ? knownColor : color;
      for (final rect in hit.rects) {
        if (flashEntry == e.id) canvas.drawRect(rect, Paint()..color = tint);
        if (flashOnly) continue;
        canvas.save();
        canvas.translate(rect.left, rect.top);
        MMPdfAnnotationLinePainter(color: ink, style: AnnotationLineStyle.dotted).paint(canvas, rect.size);
        canvas.restore();
      }
      if (flashOnly || !gloss || e.gloss.isEmpty || hit.rects.isEmpty) continue;
      final rect = hit.rects.first;
      final text = TextPainter(
        text: TextSpan(
          text: String.fromCharCodes(e.gloss.runes.take(8)),
          style: glossStyle.copyWith(fontSize: MMSizes.vocabularyGlossSize, color: ink),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final label = Rect.fromLTWH(rect.left, rect.top - text.height - MMSpacing.xxs, text.width, text.height);
      if (vocabularyGlossSpace(rect, lines) >= text.height + MMSpacing.xxs &&
          label.right <= size.width &&
          !labels.any((r) => r.overlaps(label))) {
        text.paint(canvas, label.topLeft);
        labels.add(label);
      }
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(VocabularyHintPainter oldDelegate) => true;
}
