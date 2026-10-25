import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Builds Material [ThemeData] that carries [MMColors] and macOS behavior:
/// no ink splashes, compact density, system font, quiet tooltips.
abstract final class MMTheme {
  static ThemeData light({Color? systemAccent}) => _build(MMColors.light, systemAccent);

  static ThemeData dark({Color? systemAccent}) => _build(MMColors.dark, systemAccent);

  static ThemeData _build(MMColors base, Color? systemAccent) {
    final c = systemAccent == null ? base : base.withAccent(systemAccent);
    final text = MMTextStyles(c);
    final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: c.brightness).copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      surface: c.windowBackground,
      onSurface: c.label,
      outline: c.separator,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.windowBackground,
      canvasColor: c.windowBackground,
      dividerColor: c.separator,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: c.hover,
      focusColor: c.accentTint,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textTheme: TextTheme(
        titleLarge: text.title2,
        titleMedium: text.title3,
        titleSmall: text.headline,
        bodyLarge: text.body,
        bodyMedium: text.body,
        bodySmall: text.footnote,
        labelLarge: text.headline,
        labelMedium: text.callout,
        labelSmall: text.subheadline,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accent.withValues(alpha: 0.28),
        selectionHandleColor: c.accent,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 700),
        textStyle: MMTypography.footnote.copyWith(color: c.label),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.hairline, width: 0.5),
          boxShadow: c.glassShadow,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.3)),
      ),
      extensions: [c],
    );
  }
}

/// Text styles resolved against the current colors.
class MMTextStyles {
  const MMTextStyles(this.colors);

  final MMColors colors;

  TextStyle get largeTitle => MMTypography.largeTitle.copyWith(color: colors.label);
  TextStyle get title2 => MMTypography.title2.copyWith(color: colors.label);
  TextStyle get title3 => MMTypography.title3.copyWith(color: colors.label);
  TextStyle get headline => MMTypography.headline.copyWith(color: colors.label);
  TextStyle get body => MMTypography.body.copyWith(color: colors.label);
  TextStyle get bodySecondary => MMTypography.body.copyWith(color: colors.secondaryLabel);
  TextStyle get callout => MMTypography.callout.copyWith(color: colors.label);
  TextStyle get subheadline => MMTypography.subheadline.copyWith(color: colors.secondaryLabel);
  TextStyle get footnote => MMTypography.footnote.copyWith(color: colors.secondaryLabel);
  TextStyle get readingBody => MMTypography.readingBody.copyWith(color: const Color(0xFF1D1D1F));
  TextStyle get readingExcerpt => MMTypography.readingExcerpt.copyWith(color: colors.excerptText);
  TextStyle get mono => MMTypography.mono.copyWith(color: colors.secondaryLabel);
}

extension MMThemeContext on BuildContext {
  MMColors get mmColors => Theme.of(this).extension<MMColors>() ?? MMColors.light;

  MMTextStyles get mmText => MMTextStyles(mmColors);
}
