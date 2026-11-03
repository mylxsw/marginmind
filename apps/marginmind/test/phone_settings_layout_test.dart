import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final language in [LanguagePreference.en, LanguagePreference.zh]) {
      testWidgets('phone settings $width ${language.name}: all sections and large text stay usable', (tester) async {
        // Isolate settings from demo library cards at large text sizes.
        final container = await pumpApp(
          tester,
          sets: const [],
          size: Size(width, 700),
          overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
        );
        tester.view.padding = const FakeViewPadding(top: 20, bottom: 20);
        container.read(settingsProvider.notifier).setLanguage(language);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        showSettings(tester.element(find.byType(AppShell)));
        await tester.pumpAndSettle();
        final sections = find.byKey(const ValueKey('phone-settings-sections'));
        final labels = language == LanguagePreference.zh
            ? ['阅读', '模型', '网页搜索', '语音输入', '通用']
            : ['Reading', 'Models', 'Web Search', 'Voice Input', 'General'];
        for (final label in labels) {
          final segment = find.descendant(of: sections, matching: find.text(label));
          await tester.ensureVisible(segment);
          await tester.pumpAndSettle();
          await tester.tap(segment);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          await tester.tap(find.byKey(const ValueKey('phone-settings-back')));
          await tester.pumpAndSettle();
        }
        expect(find.descendant(of: find.byType(SettingsWindow), matching: find.byIcon(MMIcons.close)), findsNothing);
        await tester.tapAt(const Offset(2, 100));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('settings-window')), findsNothing);
      });
    }
  }
}
