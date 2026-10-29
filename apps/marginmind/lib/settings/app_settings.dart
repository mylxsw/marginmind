import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart' show AnnotationLineStyle;

import '../app/providers.dart';

enum AppearancePreference { system, light, dark }

enum LanguagePreference { system, zh, en }

enum AnnotationTool { select, highlight, area, ink, underline }

enum SelectionTranslationDirection {
  automatic,
  englishToChinese,
  chineseToEnglish;

  String targetLanguage(String text) => switch (this) {
    englishToChinese => 'zh',
    chineseToEnglish => 'en',
    automatic => RegExp(r'[\u3400-\u9fff]').hasMatch(text) ? 'en' : 'zh',
  };
}

class AppSettings {
  const AppSettings({
    this.appearance = AppearancePreference.system,
    this.language = LanguagePreference.system,
    this.annotationTool = AnnotationTool.select,
    this.readerStyle = MMReaderStyle.white,
    this.underlineColor = MMAnnotationColor.blue,
    this.underlineStyle = AnnotationLineStyle.solid,
    this.readerSidebarWidth = MMSizes.readerSidebarWidth,
    this.selectionTranslationDirection = SelectionTranslationDirection.automatic,
  });

  final AppearancePreference appearance;
  final LanguagePreference language;
  final AnnotationTool annotationTool;
  final MMAnnotationColor underlineColor;
  final AnnotationLineStyle underlineStyle;
  final MMReaderStyle readerStyle;
  final double readerSidebarWidth;
  final SelectionTranslationDirection selectionTranslationDirection;

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
    MMAnnotationColor? underlineColor,
    AnnotationLineStyle? underlineStyle,
    MMReaderStyle? readerStyle,
    double? readerSidebarWidth,
    SelectionTranslationDirection? selectionTranslationDirection,
  }) => AppSettings(
    appearance: appearance ?? this.appearance,
    language: language ?? this.language,
    annotationTool: annotationTool ?? this.annotationTool,
    underlineColor: underlineColor ?? this.underlineColor,
    underlineStyle: underlineStyle ?? this.underlineStyle,
    readerStyle: readerStyle ?? this.readerStyle,
    readerSidebarWidth: readerSidebarWidth ?? this.readerSidebarWidth,
    selectionTranslationDirection: selectionTranslationDirection ?? this.selectionTranslationDirection,
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
      underlineColor: MMAnnotationColor.tryParse(prefs.getString('settings.underlineColor')) ?? MMAnnotationColor.blue,
      underlineStyle: _parse(
        AnnotationLineStyle.values,
        prefs.getString('settings.underlineStyle'),
        AnnotationLineStyle.solid,
      ),
      selectionTranslationDirection: _parse(
        SelectionTranslationDirection.values,
        prefs.getString('settings.selectionTranslationDirection'),
        SelectionTranslationDirection.automatic,
      ),
      readerSidebarWidth: (prefs.getDouble('settings.readerSidebarWidth') ?? MMSizes.readerSidebarWidth).clamp(
        MMSizes.readerSidebarMinWidth,
        MMSizes.readerSidebarMaxWidth,
      ),
      readerStyle: _parse(MMReaderStyle.values, prefs.getString(_readerStyleKey), MMReaderStyle.white),
      // The pen is never restored (see WorkspaceController.setTool).
      annotationTool: _parse(
        [
          for (final t in AnnotationTool.values)
            if (t != AnnotationTool.ink) t,
        ],
        prefs.getString(_annotationToolKey),
        AnnotationTool.select,
      ),
      appearance: _parse(AppearancePreference.values, prefs.getString(_appearanceKey), AppearancePreference.system),
      language: _parse(LanguagePreference.values, prefs.getString(_languageKey), LanguagePreference.system),
    );
  }

  Future<void> setUnderlineStyle(MMAnnotationColor color, AnnotationLineStyle style) async {
    state = state.copyWith(underlineColor: color, underlineStyle: style);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('settings.underlineColor', color.name);
    await prefs.setString('settings.underlineStyle', style.name);
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

  Future<void> setSelectionTranslationDirection(SelectionTranslationDirection value) async {
    state = state.copyWith(selectionTranslationDirection: value);
    await ref.read(sharedPreferencesProvider).setString('settings.selectionTranslationDirection', value.name);
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
