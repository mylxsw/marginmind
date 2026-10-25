import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
