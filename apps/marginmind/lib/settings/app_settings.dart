import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../app/providers.dart';

enum AppearancePreference { system, light, dark }

enum LanguagePreference { system, zh, en }

enum AnnotationTool { select, highlight, area }

class AppSettings {
  const AppSettings({
    this.appearance = AppearancePreference.system,
    this.language = LanguagePreference.system,
    this.annotationTool = AnnotationTool.select,
    this.readerStyle = MMReaderStyle.white,
    this.readerSidebarWidth = MMSizes.readerSidebarWidth,
  });

  final AppearancePreference appearance;
  final LanguagePreference language;
  final AnnotationTool annotationTool;
  final MMReaderStyle readerStyle;
  final double readerSidebarWidth;

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
    MMReaderStyle? readerStyle,
    double? readerSidebarWidth,
  }) => AppSettings(
    appearance: appearance ?? this.appearance,
    language: language ?? this.language,
    annotationTool: annotationTool ?? this.annotationTool,
    readerStyle: readerStyle ?? this.readerStyle,
    readerSidebarWidth: readerSidebarWidth ?? this.readerSidebarWidth,
  );
}

/// Application preferences, persisted in SharedPreferences.
class SettingsController extends Notifier<AppSettings> {
  static const _readerStyleKey = 'settings.readerStyle';
  static const _appearanceKey = 'settings.appearance';
  static const _languageKey = 'settings.language';
  static const _annotationToolKey = 'settings.annotationTool';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      readerSidebarWidth: (prefs.getDouble('settings.readerSidebarWidth') ?? MMSizes.readerSidebarWidth).clamp(
        MMSizes.readerSidebarMinWidth,
        MMSizes.readerSidebarMaxWidth,
      ),
      readerStyle: _parse(MMReaderStyle.values, prefs.getString(_readerStyleKey), MMReaderStyle.white),
      annotationTool: _parse(AnnotationTool.values, prefs.getString(_annotationToolKey), AnnotationTool.select),
      appearance: _parse(AppearancePreference.values, prefs.getString(_appearanceKey), AppearancePreference.system),
      language: _parse(LanguagePreference.values, prefs.getString(_languageKey), LanguagePreference.system),
    );
  }

  Future<void> setReaderSidebarWidth(double width, {bool persist = true}) async {
    final value = width.clamp(MMSizes.readerSidebarMinWidth, MMSizes.readerSidebarMaxWidth);
    state = state.copyWith(readerSidebarWidth: value);
    if (persist) await ref.read(sharedPreferencesProvider).setDouble('settings.readerSidebarWidth', value);
  }

  Future<void> setReaderStyle(MMReaderStyle value) async {
    state = state.copyWith(readerStyle: value);
    await ref.read(sharedPreferencesProvider).setString(_readerStyleKey, value.name);
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
