import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final c in [MMColors.light, MMColors.dark]) {
    group('${c.brightness.name} colors', () {
      test('text tokens reach 4.5:1 on every surface they sit on', () {
        final surfaces = {
          'windowBackground': c.windowBackground,
          'card': c.card,
          'sidebarOpaque': c.sidebarOpaque,
          'canvas': c.canvas,
          'readerBackground': c.readerBackground,
        };
        for (final e in surfaces.entries) {
          expect(contrastRatio(c.label, e.value), greaterThanOrEqualTo(4.5), reason: 'label on ${e.key}');
          expect(
            contrastRatio(c.secondaryLabel, e.value),
            greaterThanOrEqualTo(4.5),
            reason: 'secondaryLabel on ${e.key}',
          );
        }
        // Selected rows / list rows: secondary text on the selection fill.
        final selected = composite(c.selectedRow, c.sidebarOpaque);
        expect(contrastRatio(c.secondaryLabel, selected), greaterThanOrEqualTo(4.5));
      });

      test('white text on accent fill reaches 4.5:1', () {
        expect(contrastRatio(c.onAccent, c.accentFill), greaterThanOrEqualTo(4.5));
      });

      test('withAccent follows the system accent', () {
        const purple = Color(0xFFAF52DE);
        final tinted = c.withAccent(purple);
        expect(tinted.accent, purple);
        expect(tinted.accentTint.a, lessThan(0.3));
        expect(tinted.label, c.label);
      });
    });
  }

  test('annotation colors map from stored indexes and clamp bad data', () {
    expect(MMAnnotationColor.fromIndex(2), MMAnnotationColor.blue);
    expect(MMAnnotationColor.fromIndex(99), MMAnnotationColor.purple);
    expect(MMAnnotationColor.fromIndex(-1), MMAnnotationColor.yellow);
    expect(MMAnnotationColor.yellow.highlight.a, closeTo(0.32, 0.01));
  });

  test('themes carry MMColors and drop ink splashes', () {
    final light = MMTheme.light();
    final dark = MMTheme.dark(systemAccent: const Color(0xFFFF9500));
    expect(light.extension<MMColors>(), MMColors.light);
    expect(dark.extension<MMColors>()!.accent, const Color(0xFFFF9500));
    expect(light.splashFactory, NoSplash.splashFactory);
  });
}
