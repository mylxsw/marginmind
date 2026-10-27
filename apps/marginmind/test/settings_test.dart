import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_support.dart' show FakeSecrets;
import 'helpers.dart';

void main() {
  test('settings load, change and persist', () async {
    SharedPreferences.setMockInitialValues({'settings.appearance': 'dark'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);

    final settings = container.read(settingsProvider);
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.locale, isNull);

    await container.read(settingsProvider.notifier).setLanguage(LanguagePreference.zh);
    await container.read(settingsProvider.notifier).setAppearance(AppearancePreference.system);
    expect(container.read(settingsProvider).locale, const Locale('zh'));
    expect(prefs.getString('settings.language'), 'zh');
    expect(prefs.getString('settings.appearance'), 'system');
    await container.read(settingsProvider.notifier).setReaderStyle(MMReaderStyle.paper);
    expect(prefs.getString('settings.readerStyle'), 'paper');
    container.invalidate(settingsProvider);
    expect(container.read(settingsProvider).readerStyle, MMReaderStyle.paper);
  });

  test('unknown stored values fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({'settings.appearance': 'sepia', 'settings.language': 'fr'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    expect(container.read(settingsProvider).appearance, AppearancePreference.system);
    expect(container.read(settingsProvider).language, LanguagePreference.system);
  });

  group('settings window', () {
    Future<ProviderContainer> openSettings(WidgetTester tester, {bool? showsGallery}) async {
      final container = await pumpApp(tester, overrides: [assistantSecretsProvider.overrideWithValue(FakeSecrets())]);
      final context = tester.element(find.byType(MMWindowScaffold));
      showMMSheet<void>(
        context: context,
        width: SettingsWindow.width,
        builder: (_) => showsGallery == null ? const SettingsWindow() : SettingsWindow(showsGallery: showsGallery),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('hides the gallery in release builds; Esc closes', (tester) async {
      await openSettings(tester, showsGallery: false);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Component Gallery'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
    });

    testWidgets('opens the gallery in debug builds', (tester) async {
      final container = await openSettings(tester); // tests run in debug mode
      await tester.tap(find.text('Component Gallery'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
      expect(container.read(navigationProvider), isA<GalleryRoute>());
    });

    testWidgets('tabs: general, reading, models and web search', (tester) async {
      final container = await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-tab-models')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-tab-webSearch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-web-search')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-tab-general')));
      await tester.pumpAndSettle();
      // Flutter 3.47 asserts (debug + semantics only) when a sheet closes
      // after a pop-up opened over it; choices come last for that reason.
      await tester.tap(find.byKey(const ValueKey('settings-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文').last);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).language, LanguagePreference.zh);
      await tester.tap(find.byKey(const ValueKey('settings-tab-reading')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-reader-style')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('纸质').last);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).readerStyle, MMReaderStyle.paper);
    });

    testWidgets('the close button closes', (tester) async {
      await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
    });
  });
}
