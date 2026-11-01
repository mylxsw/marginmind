import 'dart:ui' show Locale;

import 'package:flutter/material.dart' show ThemeMode, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/mm_core.dart' show AnnotationLineStyle, DocumentFormat;

import '../app/providers.dart';
import 'app_icon.dart';

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

enum ReaderFont { original, serif, sans }

@immutable
class ReadingSettings {
  const ReadingSettings({
    this.size = MMReaderTypography.defaultSize,
    this.lineHeight = 1,
    this.font = ReaderFont.original,
    this.paged = false,
  });
  final int size, lineHeight;
  final ReaderFont font;
  final bool paged;
  ReadingSettings copyWith({int? size, int? lineHeight, ReaderFont? font, bool? paged}) => ReadingSettings(
    size: (size ?? this.size).clamp(0, MMReaderTypography.fontSizes.length - 1),
    lineHeight: (lineHeight ?? this.lineHeight).clamp(0, MMReaderTypography.lineHeights.length - 1),
    font: font ?? this.font,
    paged: paged ?? this.paged,
  );
  static bool isArticle(DocumentFormat format) => format == DocumentFormat.markdown || format == DocumentFormat.web;
  @override
  bool operator ==(Object other) =>
      other is ReadingSettings &&
      other.size == size &&
      other.lineHeight == lineHeight &&
      other.font == font &&
      other.paged == paged;
  @override
  int get hashCode => Object.hash(size, lineHeight, font, paged);
}

class AppSettings {
  const AppSettings({
    this.mapFollowDocument = true,
    this.betaFeaturesEnabled = false,
    this.bookReading = const ReadingSettings(),
    this.articleReading = const ReadingSettings(font: ReaderFont.serif, paged: false),
    this.appearance = AppearancePreference.system,
    this.language = LanguagePreference.system,
    this.appIcon = AppIconPreference.paperArc,
    this.assistantIcon = MMAssistantPalette.iris,
    this.annotationTool = AnnotationTool.select,
    this.readerStyle = MMReaderStyle.white,
    this.underlineColor = MMAnnotationColor.blue,
    this.underlineStyle = AnnotationLineStyle.solid,
    this.readerSidebarWidth = MMSizes.readerSidebarWidth,
    this.selectionTranslationDirection = SelectionTranslationDirection.automatic,
  });

  final bool mapFollowDocument;
  final bool betaFeaturesEnabled;
  final ReadingSettings bookReading, articleReading;
  ReadingSettings reading(DocumentFormat format) => ReadingSettings.isArticle(format) ? articleReading : bookReading;
  final AppearancePreference appearance;
  final LanguagePreference language;
  final AppIconPreference appIcon;
  final MMAssistantPalette assistantIcon;
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
    bool? mapFollowDocument,
    bool? betaFeaturesEnabled,
    ReadingSettings? bookReading,
    ReadingSettings? articleReading,
    AppearancePreference? appearance,
    LanguagePreference? language,
    AppIconPreference? appIcon,
    MMAssistantPalette? assistantIcon,
    AnnotationTool? annotationTool,
    MMAnnotationColor? underlineColor,
    AnnotationLineStyle? underlineStyle,
    MMReaderStyle? readerStyle,
    double? readerSidebarWidth,
    SelectionTranslationDirection? selectionTranslationDirection,
  }) => AppSettings(
    mapFollowDocument: mapFollowDocument ?? this.mapFollowDocument,
    betaFeaturesEnabled: betaFeaturesEnabled ?? this.betaFeaturesEnabled,
    bookReading: bookReading ?? this.bookReading,
    articleReading: articleReading ?? this.articleReading,
    appearance: appearance ?? this.appearance,
    language: language ?? this.language,
    appIcon: appIcon ?? this.appIcon,
    assistantIcon: assistantIcon ?? this.assistantIcon,
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
  static const betaFeaturesEnabledKey = 'settings.betaFeaturesEnabled';
  static const _readerStyleKey = 'settings.readerStyle';
  static const _appearanceKey = 'settings.appearance';
  static const _languageKey = 'settings.language';
  static const _annotationToolKey = 'settings.annotationTool';
  static const assistantIconKey = 'settings.assistantIcon';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    ReadingSettings reading(String key, {bool article = false}) => ReadingSettings(
      size: (prefs.getInt('$key.size') ?? MMReaderTypography.defaultSize).clamp(
        0,
        MMReaderTypography.fontSizes.length - 1,
      ),
      lineHeight: (prefs.getInt('$key.lineHeight') ?? 1).clamp(0, MMReaderTypography.lineHeights.length - 1),
      font: _parse(ReaderFont.values, prefs.getString('$key.font'), article ? ReaderFont.serif : ReaderFont.original),
      paged: prefs.getBool('$key.paged') ?? false,
    );
    return AppSettings(
      mapFollowDocument: prefs.getBool('settings.mapFollowDocument') ?? true,
      betaFeaturesEnabled: prefs.getBool(betaFeaturesEnabledKey) ?? false,
      bookReading: reading('settings.reading.book'),
      articleReading: reading('settings.reading.article', article: true).font == ReaderFont.original
          ? reading('settings.reading.article', article: true).copyWith(font: ReaderFont.serif)
          : reading('settings.reading.article', article: true),
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
      appIcon: AppIconPreference.parse(prefs.getString(appIconPreferenceKey)),
      assistantIcon: _parse(MMAssistantPalette.values, prefs.getString(assistantIconKey), MMAssistantPalette.iris),
    );
  }

  Future<void> usePhoneReadingDefault(DocumentFormat format) async {
    final key = ReadingSettings.isArticle(format) ? 'settings.reading.article' : 'settings.reading.book';
    if (!ref.read(sharedPreferencesProvider).containsKey('$key.size')) {
      await setReading(format, state.reading(format).copyWith(size: MMReaderTypography.defaultSizePhone));
    }
  }

  Future<void> setReading(DocumentFormat format, ReadingSettings value) async {
    value = value.copyWith();
    final article = ReadingSettings.isArticle(format);
    if (article && value.font == ReaderFont.original) value = value.copyWith(font: ReaderFont.serif);
    state = state.copyWith(bookReading: article ? null : value, articleReading: article ? value : null);
    final prefs = ref.read(sharedPreferencesProvider);
    final key = article ? 'settings.reading.article' : 'settings.reading.book';
    await prefs.setInt('$key.size', value.size);
    await prefs.setInt('$key.lineHeight', value.lineHeight);
    await prefs.setString('$key.font', value.font.name);
    await prefs.setBool('$key.paged', value.paged);
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

  Future<void> setMapFollowDocument(bool value) async {
    state = state.copyWith(mapFollowDocument: value);
    await ref.read(sharedPreferencesProvider).setBool('settings.mapFollowDocument', value);
  }

  Future<void> setBetaFeaturesEnabled(bool value) async {
    state = state.copyWith(betaFeaturesEnabled: value);
    await ref.read(sharedPreferencesProvider).setBool(betaFeaturesEnabledKey, value);
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

  Future<void> setAssistantIcon(MMAssistantPalette value) async {
    state = state.copyWith(assistantIcon: value);
    await ref.read(sharedPreferencesProvider).setString(assistantIconKey, value.name);
  }

  Future<void> setLanguage(LanguagePreference value) async {
    state = state.copyWith(language: value);
    await ref.read(sharedPreferencesProvider).setString(_languageKey, value.name);
  }

  bool _changingAppIcon = false;

  Future<void> setAppIcon(AppIconPreference value) async {
    if (_changingAppIcon || value == state.appIcon) return;
    _changingAppIcon = true;
    final previous = state.appIcon;
    final service = ref.read(appIconServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      await service.apply(value);
      try {
        final saved = await prefs.setString(appIconPreferenceKey, value.name);
        if (!saved) throw StateError('Could not save the icon preference');
      } catch (_) {
        try {
          await service.apply(previous);
        } finally {
          // SharedPreferences updates its in-memory cache before its disk write.
          // Restore that cache too, even if the failed write never reached disk.
          await prefs.setString(appIconPreferenceKey, previous.name);
        }
        rethrow;
      }
      if (ref.mounted) state = state.copyWith(appIcon: value);
    } finally {
      _changingAppIcon = false;
    }
  }

  Future<void> setAnnotationTool(AnnotationTool value) async {
    state = state.copyWith(annotationTool: value);
    await ref.read(sharedPreferencesProvider).setString(_annotationToolKey, value.name);
  }

  static T _parse<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
