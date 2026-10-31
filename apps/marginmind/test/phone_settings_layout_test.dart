import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';

import 'phone_layout_test.dart' show pumpPhone;

void main() {
  for (final width in [320.0, 390.0]) {
    for (final language in [LanguagePreference.en, LanguagePreference.zh]) {
      testWidgets('phone settings $width ${language.name}: all sections and large text stay usable', (tester) async {
        final container = await pumpPhone(tester, (
          name: 'small phone',
          size: Size(width, 700),
          safe: const EdgeInsets.only(top: 20, bottom: 20),
          platform: TargetPlatform.iOS,
        ));
        container.read(settingsProvider.notifier).setLanguage(language);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        showSettings(tester.element(find.byType(AppShell)));
        await tester.pumpAndSettle();
        final sections = find.byKey(const ValueKey('settings-sections'));
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
        }
        final close = find.byKey(const ValueKey('settings-close'));
        expect(tester.getSize(close).height, greaterThanOrEqualTo(MMSizes.touchTarget));
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('settings-window')), findsNothing);
      });
    }
  }
}
