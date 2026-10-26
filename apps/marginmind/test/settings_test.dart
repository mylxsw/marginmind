import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/settings/settings_sheet.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  test('unknown stored values fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({'settings.appearance': 'sepia', 'settings.language': 'fr'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    expect(container.read(settingsProvider).appearance, AppearancePreference.system);
    expect(container.read(settingsProvider).language, LanguagePreference.system);
  });

  group('component gallery button', () {
    Future<ProviderContainer> openSettings(WidgetTester tester, {bool? showsGallery}) async {
      final container = await pumpApp(tester);
      final context = tester.element(find.byType(MMWindowScaffold));
      showMMSheet<void>(
        context: context,
        builder: (_) => showsGallery == null ? const SettingsSheet() : SettingsSheet(showsGallery: showsGallery),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('is hidden in release builds, like its menu item', (tester) async {
      await openSettings(tester, showsGallery: false);
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Component Gallery'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('opens the gallery in debug builds', (tester) async {
      final container = await openSettings(tester); // tests run in debug mode
      await tester.tap(find.text('Component Gallery'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSheet), findsNothing);
      expect(container.read(navigationProvider), isA<GalleryRoute>());
    });
  });
}
