import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/vocabulary/hint_controls.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_support.dart' show FakeSecrets;
import 'helpers.dart';
import 'vocabulary_screenshots.dart' show loadVocabularyScreenshotFonts;

Future<void> captureReadingSettings(WidgetTester tester, String name) async {
  final output = Platform.environment['MM_SCREENSHOTS'];
  if (output == null) return;
  final bounds = tester.getRect(find.byKey(const ValueKey('settings-window')));
  final view = tester.binding.renderViews.first;
  final image = (await tester.runAsync(() => (view.debugLayer! as OffsetLayer).toImage(bounds, pixelRatio: 2)))!;
  try {
    final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    });
  } finally {
    image.dispose();
  }
}

Future<int> previewInk(WidgetTester tester) async {
  final bounds = tester.getRect(find.byKey(const ValueKey('vocabulary-hint-preview')));
  final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
  final image = (await tester.runAsync(() => layer.toImage(bounds, pixelRatio: 2)))!;
  try {
    final bytes = (await tester.runAsync(() => image.toByteData()))!;
    var count = 0;
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i + 1) > bytes.getUint8(i) + 30 && bytes.getUint8(i + 2) > bytes.getUint8(i) + 30) count++;
    }
    return count;
  } finally {
    image.dispose();
  }
}

Future<ProviderContainer> openReadingSettings(
  WidgetTester tester, {
  Size size = const Size(1280, 820),
  bool dark = true,
  bool chinese = true,
}) async {
  final container = await pumpApp(
    tester,
    size: size,
    prefs: {
      'settings.appearance': dark ? 'dark' : 'light',
      'settings.language': chinese ? 'zh' : 'en',
      'settings.readerStyle': 'dark',
    },
    overrides: [assistantSecretsProvider.overrideWithValue(FakeSecrets())],
  );
  showSettings(tester.element(find.byType(MMWindowScaffold)), tab: SettingsTab.reading, showsGallery: false);
  await tester.pumpAndSettle();
  return container;
}

/// Runs against both the widget renderer and the macOS window.
Future<void> verifyReadingSettingsFlow(WidgetTester tester, {String prefix = 'reading'}) async {
  final container = await openReadingSettings(tester);
  expect(tester.getSize(find.byKey(const ValueKey('settings-window'))), SettingsWindow.readingSize);
  final modes = find.byKey(const ValueKey('settings-vocabulary-hints'));
  final preview = find.byType(VocabularyHintPreview);
  VocabularyHintMode mode() => tester.widget<VocabularyHintPreview>(preview).mode;
  expect(mode(), VocabularyHintMode.underline);
  expect(find.byType(MMSegmentedControl<VocabularyHintMode>), findsNothing);
  expect(find.text('在正文中标记已收录的生词'), findsNothing);
  expect(find.text('深色'), findsOneWidget);
  expect(find.text('自动（中英互译）'), findsOneWidget);
  expect(tester.getRect(find.byType(MMSettingsGroup).last).top - tester.getRect(modes).bottom, greaterThan(50));
  final underlineInk = await previewInk(tester);
  expect(underlineInk, greaterThan(0));
  await captureReadingSettings(tester, '$prefix-dark-underline');

  // Close controls precede menu checks because of Flutter 3.47's existing
  // debug semantics assertion when a dialog closes after a popup was used.
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byType(SettingsWindow), findsNothing);
  showSettings(tester.element(find.byType(MMWindowScaffold)), tab: SettingsTab.reading, showsGallery: false);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-close')));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsWindow), findsNothing);
  showSettings(tester.element(find.byType(MMWindowScaffold)), tab: SettingsTab.reading, showsGallery: false);
  await tester.pumpAndSettle();

  Focus.of(tester.element(find.text('仅下划线'))).requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.pumpAndSettle();
  expect(find.text('关闭'), findsOneWidget);
  expect(find.text('显示释义'), findsOneWidget);
  expect(find.byIcon(MMIcons.check), findsOneWidget);
  await captureReadingSettings(tester, '$prefix-dark-dropdown');
  await tester.tap(find.text('显示释义').last);
  await tester.pumpAndSettle();
  expect(mode(), VocabularyHintMode.gloss);
  expect(container.read(vocabularyHintProvider).mode, VocabularyHintMode.gloss);
  expect((await SharedPreferences.getInstance()).getString('vocabulary.hintMode'), 'gloss');
  expect(await previewInk(tester), greaterThan(underlineInk), reason: 'meaning adds visible text above the underline');
  await captureReadingSettings(tester, '$prefix-dark-gloss');

  await tester.tap(modes);
  await tester.pumpAndSettle();
  await tester.tap(find.text('关闭').last);
  await tester.pumpAndSettle();
  expect(mode(), VocabularyHintMode.off);
  expect(await previewInk(tester), 0, reason: 'off removes every vocabulary decoration');
  await captureReadingSettings(tester, '$prefix-dark-off');
  container.invalidate(vocabularyHintProvider);
  await tester.pumpAndSettle();
  expect(mode(), VocabularyHintMode.off, reason: 'reloading preferences preserves the saved setting');

  await tester.tap(modes);
  await tester.pumpAndSettle();
  await tester.tap(find.text('仅下划线').last);
  await tester.pumpAndSettle();
  expect(mode(), VocabularyHintMode.underline);

  await tester.tap(find.byKey(const ValueKey('settings-reader-style')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('纸质').last);
  await tester.pumpAndSettle();
  expect(container.read(settingsProvider).readerStyle, MMReaderStyle.paper);
  await tester.tap(find.byKey(const ValueKey('settings-selection-translation')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('英文 → 中文').last);
  await tester.pumpAndSettle();
  expect(
    container.read(settingsProvider).selectionTranslationDirection,
    SelectionTranslationDirection.englishToChinese,
  );
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    await loadVocabularyScreenshotFonts();
    await (FontLoader('Songti SC')..addFont(
          Future.value(ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Songti.ttc').readAsBytesSync())),
        ))
        .load();
  });
  testWidgets(
    'reading preview, persistence, keyboard and preference menus',
    verifyReadingSettingsFlow,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  for (final chinese in [true, false]) {
    for (final dark in [true, false]) {
      testWidgets('reading layout ${chinese ? 'zh' : 'en'} ${dark ? 'dark' : 'light'}', (tester) async {
        await openReadingSettings(tester, chinese: chinese, dark: dark);
        await captureReadingSettings(tester, 'reading-${chinese ? 'zh' : 'en'}-${dark ? 'dark' : 'light'}');
        for (final size in [const Size(700, 500), const Size(600, 400)]) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(MMWindowScaffold));
          showMMDialog<void>(
            context: context,
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: size),
              child: const SettingsWindow(initialTab: SettingsTab.reading, showsGallery: false),
            ),
          );
          await tester.pumpAndSettle();
          final window = tester.getRect(find.byKey(const ValueKey('settings-window')));
          expect(window.width, lessThanOrEqualTo(size.width));
          expect(window.height, lessThanOrEqualTo(size.height));
          expect(find.byType(VocabularyHintPreview), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await captureReadingSettings(tester, 'reading-${chinese ? 'zh' : 'en'}-${dark ? 'dark' : 'light'}-narrow');
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }
}
