import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  test('margin colors follow reading paper, independent of application appearance', () {
    for (final style in MMReaderStyle.values) {
      expect(style.marginFill, style.paperColor);
      expect(style.marginNoteMarker, const Color(0xFFFFD60A));
      expect(style.marginNoteLine.a, greaterThan(0));
      expect(style.marginGuide.a, greaterThan(0));
      expect(style.marginNoteText, style == MMReaderStyle.dark ? const Color(0xFFE5E5EA) : const Color(0xFF3A3A3C));
      for (final color in MMAnnotationColor.values) {
        expect(
          style.marginNoteFill(color),
          style == MMReaderStyle.dark
              ? const Color(0xFF2A2A2C)
              : Color.alphaBlend(color.color.withValues(alpha: .16), style.paperColor),
        );
      }
    }
  });
}
