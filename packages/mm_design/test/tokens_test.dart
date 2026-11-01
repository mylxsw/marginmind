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

      test('all feature colors share the system accent through theme changes', () {
        for (final accent in [c.accent, const Color(0xFFAF52DE), const Color(0xFFFF9500), const Color(0xFFFFCC00)]) {
          final themed = c.withAccent(accent);
          expect(themed.research, themed.accent);
          expect(themed.vocabulary, themed.accent);
          expect(themed.researchTint, themed.accentTint);
          expect(themed.vocabularyTint, themed.accentTint);
          expect(themed.accentFill, accent);
          expect(themed.researchWash.a, closeTo(themed.accentTint.a / 2, 0.002));
          expect(themed.researchWash.toARGB32() & 0xFFFFFF, accent.toARGB32() & 0xFFFFFF);
          expect(contrastRatio(themed.onAccent, themed.accentFill), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(themed.onResearch, themed.research), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(themed.onVocabulary, themed.vocabulary), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(themed.label, composite(themed.accentTint, themed.card)), greaterThanOrEqualTo(4.5));
          final wash = composite(themed.researchWash, themed.canvas);
          expect(contrastRatio(themed.label, wash), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(themed.secondaryLabel, wash), greaterThanOrEqualTo(4.5));
        }
        final other = c == MMColors.light ? MMColors.dark : MMColors.light;
        for (final t in [0.0, 0.5, 1.0]) {
          final blended = c.lerp(other, t);
          expect(blended.research, blended.accent);
          expect(blended.vocabulary, blended.accent);
          expect(blended.researchTint, blended.accentTint);
          expect(blended.vocabularyTint, blended.accentTint);
          expect(contrastRatio(blended.onResearch, blended.research), greaterThanOrEqualTo(4.5));
        }
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

  test('idea expansion geometry fits together', () {
    // Hover controls sit inside their capsule; the bar clears the map's view
    // controls (12 + 28) and a HUD capsule (no taller than the bar) below it.
    expect(MMSizes.mapDraftControlButton.height, lessThan(MMSizes.mapDraftControls));
    expect(MMSizes.mapDraftTag, lessThan(MMSizes.mapDraftPlaceholder.height));
    expect(MMSpacing.m + MMSizes.segmented, lessThan(MMSizes.ideaBarBottomInset));
    expect(MMHudHost.defaultBottom + MMSizes.ideaBar, lessThanOrEqualTo(MMSizes.ideaBarBottomInset));
    expect(MMSizes.ideaStepperButton.height, lessThan(MMSizes.ideaPlanRow));
    expect(MMSizes.ideaChip, lessThan(MMSizes.ideaPrimaryButton));
    expect(MMSizes.mapWorkingHaloMax, greaterThan(MMSizes.mapWorkingHalo));
    expect(MMSizes.mapDraftDash, greaterThan(MMSizes.mapDraftDashGap));
    expect(MMRadii.mapDraftTag * 2, lessThanOrEqualTo(MMSizes.mapDraftTag));
    expect(MMRadii.ideaSection, lessThan(MMRadii.dropdown));
    expect(MMMotion.pulse, greaterThan(MMMotion.shimmer));
    expect(MMMotion.shimmer, greaterThan(MMMotion.layout));
    for (final icon in [MMIcons.expandIdeas, MMIcons.groupParent, MMIcons.fillSiblings, MMIcons.adjust]) {
      expect(icon.fontFamily, isNotEmpty);
    }
  });

  test('mind map from document geometry fits together', () {
    // The sheet holds its label column; the diff panel leaves the map its
    // minimum width beside it on a regular window.
    expect(MMSizes.mapGenerateLabelWidth * 4, lessThan(MMSizes.mapGenerateSheetWidth));
    expect(MMSizes.mapGenerateSheetWidth, MMSizes.noteSetupSheetWidth);
    expect(
      MMSizes.mapDiffPanelWidth + MMSizes.mapMinWidth,
      lessThanOrEqualTo(MMSizes.windowMinSize.width - MMSizes.sidebarWidth),
    );
    expect(MMSizes.mapUpdatePopoverWidth, lessThan(MMSizes.mapGenerateSheetWidth));
    expect(MMSizes.mapGenerateChapterRow, lessThan(MMSizes.mapGenerateDocumentRow));
    expect(MMSizes.mapDocumentBanner, lessThanOrEqualTo(MMSizes.touchTarget));
    expect(MMSizes.mapEmptyGlyph, lessThan(MMSizes.mapEmptyStateWidth));
    expect(MMRadii.mapEmptyGlyph * 2, lessThan(MMSizes.mapEmptyGlyph));
    // Pill-shaped page chip; the document dot and diff tags fit inside it.
    expect(MMRadii.mapSourceChip * 2, MMSizes.mapSourceChip);
    expect(MMSizes.mapSourceDot, lessThan(MMSizes.mapSourceChip));
    expect(MMSizes.mapDraftTag, lessThan(MMSizes.mapSourceChip));
    expect(MMSizes.mapUpdateBadge + MMSizes.mapUpdateBadgeRing * 2, lessThan(MMSizes.toolbarButton.height / 2));
    expect(MMSizes.mapProtectedBadge, MMSizes.mapSourceChip);
    expect(MMSizes.mapReadingStep.width, greaterThan(MMSizes.mapReadingStep.height));
    expect(MMMotion.breathe, greaterThan(MMMotion.layout));
    expect(MMMotion.breathe, lessThan(MMMotion.pulse));
    for (final icon in [MMIcons.generateMap, MMIcons.mergeIntoMap]) {
      expect(icon.fontFamily, isNotEmpty);
    }
    expect(MMIcons.generateMap, isNot(MMIcons.ai));
    expect(MMIcons.generateMap, isNot(MMIcons.organizeNote));
    expect(MMIcons.generateMap, isNot(MMIcons.organize));

    expect(MMSizes.fullTranslationSheetWidth, 560);
    expect(MMSizes.fullTranslationPanelWidth, 372);
    for (final icon in [
      MMIcons.layers,
      MMIcons.pause,
      MMIcons.play,
      MMIcons.retry,
      MMIcons.wifiOff,
      MMIcons.key,
      MMIcons.recycle,
      MMIcons.skip,
    ]) {
      expect(icon.fontFamily, isNotEmpty);
    }
  });

  test('source document dots are distinct per appearance and cycle', () {
    for (final colors in [MMSourceColors.light, MMSourceColors.dark]) {
      expect(colors.toSet(), hasLength(colors.length));
      for (final color in colors) {
        expect(color.a, 1.0);
      }
    }
    expect(MMSourceColors.light, hasLength(MMSourceColors.dark.length));
    expect(MMSourceColors.of(Brightness.light, 0), MMSourceColors.light.first);
    expect(MMSourceColors.of(Brightness.dark, 1), MMSourceColors.dark[1]);
    expect(MMSourceColors.of(Brightness.light, MMSourceColors.light.length), MMSourceColors.light.first);
  });

  test('themes carry MMColors and drop ink splashes', () {
    final light = MMTheme.light();
    final dark = MMTheme.dark(systemAccent: const Color(0xFFFF9500));
    expect(light.extension<MMColors>(), MMColors.light);
    expect(dark.extension<MMColors>()!.accent, const Color(0xFFFF9500));
    expect(light.splashFactory, NoSplash.splashFactory);
  });
}
