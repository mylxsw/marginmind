import 'package:flutter/widgets.dart';
import 'package:mm_core/mm_core.dart' show TranslationLanguage, AnnotationLineStyle, MapPalette, MapStructure;
import 'package:mm_design/mm_design.dart';

import '../l10n/generated/app_localizations.dart';

export '../l10n/generated/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension AppLocalizationsX on AppLocalizations {
  String translationLanguageName(TranslationLanguage language) => switch (language) {
    TranslationLanguage.chinese => translationChinese,
    TranslationLanguage.traditionalChinese => translationTraditionalChinese,
    TranslationLanguage.english => translationEnglish,
    TranslationLanguage.japanese => translationJapanese,
    TranslationLanguage.korean => translationKorean,
    TranslationLanguage.french => translationFrench,
    TranslationLanguage.german => translationGerman,
    TranslationLanguage.spanish => translationSpanish,
    TranslationLanguage.portuguese => translationPortuguese,
    TranslationLanguage.italian => translationItalian,
    TranslationLanguage.russian => translationRussian,
    TranslationLanguage.arabic => translationArabic,
  };

  String colorName(MMAnnotationColor color) => switch (color) {
    MMAnnotationColor.yellow => colorYellow,
    MMAnnotationColor.green => colorGreen,
    MMAnnotationColor.blue => colorBlue,
    MMAnnotationColor.pink => colorPink,
    MMAnnotationColor.orange => colorOrange,
    MMAnnotationColor.purple => colorPurple,
    _ => color.hex,
  };

  String mapStructureName(MapStructure structure) => switch (structure) {
    MapStructure.mind => mapStructureMind,
    MapStructure.logic => mapStructureLogic,
    MapStructure.brace => mapStructureBrace,
    MapStructure.tree => mapStructureTree,
  };

  String mapPaletteName(MapPalette palette) => switch (palette) {
    MapPalette.system => mapPaletteSystem,
    MapPalette.rainbow => mapPaletteRainbow,
    MapPalette.fresh => mapPaletteFresh,
    MapPalette.warm => mapPaletteWarm,
    MapPalette.morandi => mapPaletteMorandi,
    MapPalette.ink => mapPaletteInk,
  };

  String lineStyleName(AnnotationLineStyle style) => switch (style) {
    AnnotationLineStyle.solid => lineSolid,
    AnnotationLineStyle.dashed => lineDashed,
    AnnotationLineStyle.dotted => lineDotted,
    AnnotationLineStyle.wavy => lineWavy,
  };

  String inkColorName(MMInkColor color) => switch (color) {
    MMInkColor.red => colorRed,
    MMInkColor.orange => colorOrange,
    MMInkColor.yellow => colorYellow,
    MMInkColor.green => colorGreen,
    MMInkColor.blue => colorBlue,
    MMInkColor.black => colorBlack,
  };

  String inkWidthName(MMInkWidth width) => switch (width) {
    MMInkWidth.thin => inkThin,
    MMInkWidth.medium => inkMedium,
    MMInkWidth.bold => inkBold,
  };

  /// "Just now", "3 days ago", "Last month"…
  String relativeTime(DateTime time, DateTime now) {
    final d = now.difference(time);
    if (d.inMinutes < 1) return relativeJustNow;
    if (d.inHours < 1) return relativeMinutes(d.inMinutes);
    if (d.inDays < 1) return relativeHours(d.inHours);
    if (d.inDays == 1) return relativeYesterday;
    if (d.inDays < 7) return relativeDays(d.inDays);
    if (d.inDays < 30) return relativeWeeks(d.inDays ~/ 7);
    return relativeMonths(d.inDays ~/ 30);
  }

  /// Time until the next review: "10 min", "3 days", "2 mo".
  String reviewInterval(Duration d) {
    if (d.inMinutes < 60) return intervalMinutes(d.inMinutes);
    if (d.inHours < 24) return intervalHours(d.inHours);
    final days = (d.inMinutes / (24 * 60)).round();
    if (days < 30) return intervalDays(days);
    return intervalMonths((days / 30).round());
  }
}
