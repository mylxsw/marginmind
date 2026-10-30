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

      test('research labels reach 4.5:1 on the window and keep their own hue', () {
        expect(contrastRatio(c.research, c.windowBackground), greaterThanOrEqualTo(4.5));
        expect(c.researchTint.toARGB32() & 0xFFFFFF, c.research.toARGB32() & 0xFFFFFF);
        expect(c.researchTint.a, lessThan(0.3));
        final tinted = c.withAccent(const Color(0xFFFF9500));
        expect(tinted.research, c.research, reason: 'the system accent never recolors research');
        expect(c.lerp(c, 0.5).research, c.research);
      });

      test('vocabulary contrast, tint and fixed hue survive theme changes', () {
        expect(contrastRatio(c.vocabulary, c.windowBackground), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.label, composite(c.vocabularyTint, c.card)), greaterThanOrEqualTo(4.5));
        expect(c.vocabularyTint.toARGB32() & 0xFFFFFF, c.vocabulary.toARGB32() & 0xFFFFFF);
        expect(c.vocabularyTint.a, closeTo(c.brightness == Brightness.light ? 0.12 : 0.16, 0.002));
        final tinted = c.withAccent(const Color(0xFFFF9500));
        expect(tinted.vocabulary, c.vocabulary);
        expect(tinted.vocabularyTint, c.vocabularyTint);
        expect(c.lerp(c, 0.5).vocabulary, c.vocabulary);
        expect(c.lerp(c, 0.5).vocabularyTint, c.vocabularyTint);
        expect(MMIcons.vocabulary.fontFamily, isNotEmpty);
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

  group('mind map palettes', () {
    test('six palettes in the offered order, found by their stored names', () {
      expect(MMMapPalette.values.map((p) => p.name), ['system', 'rainbow', 'fresh', 'warm', 'morandi', 'ink']);
      for (final p in MMMapPalette.values) {
        expect(MMMapPalette.byName(p.name), same(p));
      }
      expect(MMMapPalette.byName('unknown'), same(MMMapPalette.system));
    });

    test('the system palette is the current look', () {
      for (final c in [MMColors.light, MMColors.dark]) {
        final m = MMMapPalette.system.of(c.brightness);
        expect(m.root, c.rootNode);
        expect(m.onRoot, c.onRootNode);
        expect(m.branch(0), isNull);
        expect(m.line(3, c), c.line);
        expect(m.topicFill(0, c), Color.alphaBlend(c.fill, c.canvas));
        expect(m.topicText(0, c), c.label);
        expect(m.topicBorder(0), isNull);
        expect(m.summary, isNull);
      }
    });

    for (final c in [MMColors.light, MMColors.dark]) {
      for (final p in MMMapPalette.values) {
        test('${p.name} ${c.brightness.name}: text reaches 4.5:1 on every fill', () {
          final m = p.of(c.brightness);
          expect(contrastRatio(m.onRoot, m.root), greaterThanOrEqualTo(4.5), reason: 'center topic');
          if (m.summary case final summary?) {
            expect(contrastRatio(m.onSummary!, summary), greaterThanOrEqualTo(4.5), reason: 'summary');
          }
          for (var i = 0; i < m.branches.length + 1; i++) {
            final fill = m.topicFill(i, c);
            expect(fill.a, 1, reason: 'topic fills are opaque');
            expect(
              contrastRatio(m.topicText(i, c), fill),
              greaterThanOrEqualTo(4.5),
              reason: 'first-level topic of branch $i',
            );
          }
        });
      }
    }

    test('branches cycle and set the first-level topic style', () {
      final rainbow = MMMapPalette.rainbow.light;
      expect(rainbow.branch(6), rainbow.branch(0));
      expect(rainbow.topicFill(1, MMColors.light), rainbow.branches[1]);
      expect(rainbow.line(1, MMColors.light), rainbow.branches[1]);

      final fresh = MMMapPalette.fresh.dark;
      expect(
        fresh.topicFill(0, MMColors.dark),
        Color.alphaBlend(fresh.branches[0].withValues(alpha: 0.34), MMColors.dark.canvas),
      );
      expect(fresh.topicText(0, MMColors.dark), MMColors.dark.label);

      final ink = MMMapPalette.ink.light;
      expect(ink.topicFill(2, MMColors.light), MMColors.light.canvas);
      expect(ink.topicBorder(2), ink.branches.single);
      expect(MMMapPalette.ink.dark.branch(4), const Color(0xFFD1D1D6));
    });
  });

  test('annotation colors map from stored indexes and clamp bad data', () {
    expect(MMAnnotationColor.fromIndex(2), MMAnnotationColor.blue);
    expect(MMAnnotationColor.fromIndex(99), MMAnnotationColor.purple);
    expect(MMAnnotationColor.fromIndex(-1), MMAnnotationColor.yellow);
    expect(MMAnnotationColor.yellow.highlight.a, closeTo(0.32, 0.01));
  });

  test('arbitrary RGB colors keep a stable storage ID and preserve preset IDs', () {
    for (final rgb in [0x000000, 0xFFFFFF, 0x12A4B8, 0x020406]) {
      final custom = MMAnnotationColor.fromColor(Color(0xFF000000 | rgb));
      expect(custom.isCustom, isTrue);
      expect(MMAnnotationColor.fromIndex(custom.index), custom);
      expect(MMAnnotationColor.tryParse(custom.hex), custom);
      expect(custom.color.toARGB32(), 0xFF000000 | rgb);
    }
    expect(MMAnnotationColor.fromColor(const Color(0xFFFFCC00)), MMAnnotationColor.yellow);
    expect(MMAnnotationColor.yellow.index, 0);
    expect(MMAnnotationColor.purple.index, 5);
    expect(MMAnnotationColor.tryParse('#12a4b8')!.hex, '#12A4B8');
    expect(MMAnnotationColor.tryParse('#ABC'), isNull);
    expect(MMAnnotationColor.tryParse('#GGGGGG'), isNull);
    expect(MMAnnotationColor.tryParse('yellow'), MMAnnotationColor.yellow);
  });

  test('themes carry MMColors and drop ink splashes', () {
    final light = MMTheme.light();
    final dark = MMTheme.dark(systemAccent: const Color(0xFFFF9500));
    expect(light.extension<MMColors>(), MMColors.light);
    expect(dark.extension<MMColors>()!.accent, const Color(0xFFFF9500));
    expect(light.splashFactory, NoSplash.splashFactory);
  });
}
