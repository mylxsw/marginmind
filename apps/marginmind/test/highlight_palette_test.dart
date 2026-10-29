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

  test('translation directions include automatic and explicit overrides', () {
    expect(SelectionTranslationDirection.automatic.targetLanguage('Memory and learning'), 'zh');
    expect(SelectionTranslationDirection.automatic.targetLanguage('阅读 PDF 有助于学习'), 'en');
    expect(SelectionTranslationDirection.englishToChinese.targetLanguage('中文内容'), 'zh');
    expect(SelectionTranslationDirection.chineseToEnglish.targetLanguage('English content'), 'en');
  });
}
