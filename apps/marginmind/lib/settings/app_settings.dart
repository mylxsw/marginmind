import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

enum AppearancePreference { system, light, dark }

enum LanguagePreference { system, zh, en }

enum AnnotationTool { select, highlight, area }

class AppSettings {
  const AppSettings({
    this.appearance = AppearancePreference.system,
    this.language = LanguagePreference.system,
    this.annotationTool = AnnotationTool.select,
  });

  final AppearancePreference appearance;
  final LanguagePreference language;
  final AnnotationTool annotationTool;

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

  AppSettings copyWith({
    AppearancePreference? appearance,
    LanguagePreference? language,
    AnnotationTool? annotationTool,
  }) => AppSettings(
    appearance: appearance ?? this.appearance,
    language: language ?? this.language,
    annotationTool: annotationTool ?? this.annotationTool,
  );
}

/// Application preferences, persisted in SharedPreferences.
class SettingsController extends Notifier<AppSettings> {
  static const _appearanceKey = 'settings.appearance';
  static const _languageKey = 'settings.language';
  static const _annotationToolKey = 'settings.annotationTool';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      annotationTool: _parse(AnnotationTool.values, prefs.getString(_annotationToolKey), AnnotationTool.select),
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

  Future<void> setAnnotationTool(AnnotationTool value) async {
    state = state.copyWith(annotationTool: value);
    await ref.read(sharedPreferencesProvider).setString(_annotationToolKey, value.name);
  }

  static T _parse<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
