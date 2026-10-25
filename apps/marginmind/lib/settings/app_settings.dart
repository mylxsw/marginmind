import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

enum AppearancePreference { system, light, dark }

enum LanguagePreference { system, zh, en }

class AppSettings {
  const AppSettings({this.appearance = AppearancePreference.system, this.language = LanguagePreference.system});

  final AppearancePreference appearance;
  final LanguagePreference language;

  ThemeMode get themeMode => switch (appearance) {
    AppearancePreference.system => ThemeMode.system,
    AppearancePreference.light => ThemeMode.light,
    AppearancePreference.dark => ThemeMode.dark,
  };

  /// Null means "follow the system language".
  Locale? get locale => switch (language) {
    LanguagePreference.system => null,
    LanguagePreference.zh => const Locale('zh'),
    LanguagePreference.en => const Locale('en'),
  };

  AppSettings copyWith({AppearancePreference? appearance, LanguagePreference? language}) =>
      AppSettings(appearance: appearance ?? this.appearance, language: language ?? this.language);
}

/// Appearance and language, persisted in SharedPreferences.
class SettingsController extends Notifier<AppSettings> {
  static const _appearanceKey = 'settings.appearance';
  static const _languageKey = 'settings.language';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      appearance: _parse(AppearancePreference.values, prefs.getString(_appearanceKey), AppearancePreference.system),
      language: _parse(LanguagePreference.values, prefs.getString(_languageKey), LanguagePreference.system),
    );
  }

  Future<void> setAppearance(AppearancePreference value) async {
    state = state.copyWith(appearance: value);
    await ref.read(sharedPreferencesProvider).setString(_appearanceKey, value.name);
  }

  Future<void> setLanguage(LanguagePreference value) async {
    state = state.copyWith(language: value);
    await ref.read(sharedPreferencesProvider).setString(_languageKey, value.name);
  }

  static T _parse<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
