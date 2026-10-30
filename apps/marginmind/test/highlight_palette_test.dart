import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/highlight_palette.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('color ranking balances frequency with recency; stable defaults fill empty slots', () {
    final now = DateTime(2026, 10, 29);
    final palette = HighlightPalette(
      usage: {
        MMAnnotationColor.yellow: HighlightColorUse(10, now.subtract(const Duration(days: 70))),
        MMAnnotationColor.blue: HighlightColorUse(2, now),
        MMAnnotationColor.pink: HighlightColorUse(2, now.subtract(const Duration(days: 1))),
      },
    );
    expect(palette.frequent(now), [MMAnnotationColor.blue, MMAnnotationColor.pink, MMAnnotationColor.yellow]);
    expect(const HighlightPalette().frequent(now), MMAnnotationColor.values.take(3));
  });

  test('inline colors follow recency, independent of lifetime frequency', () {
    final now = DateTime(2026, 10, 29);
    final custom = MMAnnotationColor.tryParse('#12A4B8')!;
    final palette = HighlightPalette(
      usage: {
        MMAnnotationColor.yellow: HighlightColorUse(100, now.subtract(const Duration(days: 1))),
        MMAnnotationColor.purple: HighlightColorUse(1, now.subtract(const Duration(minutes: 2))),
        MMAnnotationColor.pink: HighlightColorUse(2, now.subtract(const Duration(minutes: 1))),
        custom: HighlightColorUse(1, now),
      },
    );
    expect(palette.recent(), [custom, MMAnnotationColor.pink, MMAnnotationColor.purple]);
    expect(palette.recent(limit: 4), [
      custom,
      MMAnnotationColor.pink,
      MMAnnotationColor.purple,
      MMAnnotationColor.yellow,
    ]);
    expect(const HighlightPalette().recent(), MMAnnotationColor.values.take(3));
    expect(HighlightPalette(current: custom).recent(), [custom, MMAnnotationColor.yellow, MMAnnotationColor.green]);
  });

  test('picking does not count as use; actual use and current color survive reload', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final controller = container.read(highlightPaletteProvider.notifier);
    await controller.choose(MMAnnotationColor.purple);
    expect(container.read(highlightPaletteProvider).usage, isEmpty);
    await controller.record(MMAnnotationColor.purple);
    await controller.record(MMAnnotationColor.purple);
    container.invalidate(highlightPaletteProvider);
    final restored = container.read(highlightPaletteProvider);
    expect(restored.current, MMAnnotationColor.purple);
    expect(restored.usage[MMAnnotationColor.purple]!.count, 2);
    expect(restored.frequent(DateTime.now()).first, MMAnnotationColor.purple);
    await container
        .read(settingsProvider.notifier)
        .setSelectionTranslationDirection(SelectionTranslationDirection.chineseToEnglish);
    container.invalidate(settingsProvider);
    expect(
      container.read(settingsProvider).selectionTranslationDirection,
      SelectionTranslationDirection.chineseToEnglish,
    );
  });

  test('damaged preference safely restores a usable palette', () async {
    SharedPreferences.setMockInitialValues({'settings.highlightPalette': '{invalid'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    expect(container.read(highlightPaletteProvider).current, MMAnnotationColor.yellow);
  });

  test('custom color, usage and quick access survive preference reload', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final custom = MMAnnotationColor.tryParse('#12A4B8')!;
    await container.read(highlightPaletteProvider.notifier).choose(custom);
    expect(container.read(highlightPaletteProvider).frequent(DateTime.now()), contains(custom));
    expect(container.read(highlightPaletteProvider).usage, isEmpty);
    await container.read(highlightPaletteProvider.notifier).record(custom);
    container.invalidate(highlightPaletteProvider);
    final restored = container.read(highlightPaletteProvider);
    expect(restored.current, custom);
    expect(restored.usage[custom]!.count, 1);
    expect(restored.frequent(DateTime.now()).first, custom);
    expect(restored.recent().first, custom);
  });

  test('translation directions include automatic and explicit overrides', () {
    expect(SelectionTranslationDirection.automatic.targetLanguage('Memory and learning'), 'zh');
    expect(SelectionTranslationDirection.automatic.targetLanguage('阅读 PDF 有助于学习'), 'en');
    expect(SelectionTranslationDirection.englishToChinese.targetLanguage('中文内容'), 'zh');
    expect(SelectionTranslationDirection.chineseToEnglish.targetLanguage('English content'), 'en');
  });
}
