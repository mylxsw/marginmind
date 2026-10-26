import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Semantic colors, mapped to NSColor names where macOS has one
/// (see design canvas 02 · 01). Light and dark share token names.
@immutable
class MMColors extends ThemeExtension<MMColors> {
  const MMColors({
    required this.brightness,
    required this.windowBackground,
    required this.sidebar,
    required this.sidebarOpaque,
    required this.readerBackground,
    required this.canvas,
    required this.card,
    required this.page,
    required this.label,
    required this.secondaryLabel,
    required this.icon,
    required this.separator,
    required this.fill,
    required this.quaternaryFill,
    required this.selectedRow,
    required this.hover,
    required this.pressed,
    required this.accent,
    required this.accentFill,
    required this.accentTint,
    required this.onAccent,
    required this.glass,
    required this.glassOpaque,
    required this.glassHighlight,
    required this.hairline,
    required this.line,
    required this.excerptText,
    required this.rootNode,
    required this.onRootNode,
    required this.scrim,
    required this.glassShadow,
    required this.cardShadow,
    required this.sidebarShadow,
    required this.sheetShadow,
  });

  final Brightness brightness;

  /// windowBackgroundColor — window and toolbar.
  final Color windowBackground;

  /// Sidebar glass material.
  final Color sidebar;

  /// Sidebar when "Reduce transparency" is on.
  final Color sidebarOpaque;

  /// Backdrop around PDF pages (like Preview).
  final Color readerBackground;

  /// Mind map canvas.
  final Color canvas;

  /// controlBackgroundColor — cards, selected segment.
  final Color card;

  /// PDF page. Always white: dark mode never inverts the source.
  final Color page;

  final Color label;

  /// Darker than the system's translucent secondaryLabel so it passes 4.5:1.
  final Color secondaryLabel;
  final Color icon;
  final Color separator;

  /// tertiarySystemFill — topic nodes, badges.
  final Color fill;

  /// quaternarySystemFill — search fields, note nodes.
  final Color quaternaryFill;
  final Color selectedRow;
  final Color hover;
  final Color pressed;

  /// controlAccentColor. Follows the system accent when the platform layer
  /// reports one (see [withAccent]).
  final Color accent;

  /// selectedContentBackgroundColor — fills that carry white text.
  final Color accentFill;
  final Color accentTint;
  final Color onAccent;

  /// Floating control glass.
  final Color glass;
  final Color glassOpaque;
  final Color glassHighlight;
  final Color hairline;

  /// Mind map connectors.
  final Color line;
  final Color excerptText;
  final Color rootNode;
  final Color onRootNode;
  final Color scrim;

  final List<BoxShadow> glassShadow;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> sidebarShadow;
  final List<BoxShadow> sheetShadow;

  static const light = MMColors(
    brightness: Brightness.light,
    windowBackground: Color(0xFFFFFFFF),
    sidebar: Color(0xDBF2F2F6),
    sidebarOpaque: Color(0xFFF2F2F6),
    readerBackground: Color(0xFFEDEDF0),
    canvas: Color(0xFFFBFBFD),
    card: Color(0xFFFFFFFF),
    page: Color(0xFFFFFFFF),
    label: Color(0xFF1D1D1F),
    secondaryLabel: Color(0xFF636366),
    icon: Color(0xFF6E6E73),
    separator: Color(0x17000000),
    fill: Color(0x1F787880),
    quaternaryFill: Color(0x14787880),
    selectedRow: Color(0x13000000),
    hover: Color(0x0B000000),
    pressed: Color(0x17000000),
    accent: Color(0xFF007AFF),
    accentFill: Color(0xFF0A66D0),
    accentTint: Color(0x1F007AFF),
    onAccent: Color(0xFFFFFFFF),
    glass: Color(0xC7FFFFFF),
    glassOpaque: Color(0xFFFFFFFF),
    glassHighlight: Color(0xF2FFFFFF),
    hairline: Color(0x14000000),
    line: Color(0x3D3C3C43),
    excerptText: Color(0xFF3A3A3C),
    rootNode: Color(0xFF1D1D1F),
    onRootNode: Color(0xFFFFFFFF),
    scrim: Color(0x1F000000),
    glassShadow: [], // Floating chrome uses a hairline instead of blurred shadows.
    cardShadow: [
      BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0D000000), blurRadius: 14, offset: Offset(0, 4)),
    ],
    sidebarShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 24, offset: Offset(0, 6))],
    sheetShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 60, offset: Offset(0, 24))],
  );

  static const dark = MMColors(
    brightness: Brightness.dark,
    windowBackground: Color(0xFF1E1E1F),
    sidebar: Color(0xDB2C2C2F),
    sidebarOpaque: Color(0xFF2C2C2F),
    readerBackground: Color(0xFF262628),
    canvas: Color(0xFF1C1C1E),
    card: Color(0xFF2C2C2E),
    page: Color(0xFFFFFFFF),
    label: Color(0xFFF5F5F7),
    secondaryLabel: Color(0xFFAEAEB2),
    icon: Color(0xFFAEAEB2),
    separator: Color(0x17FFFFFF),
    fill: Color(0x3D767680),
    quaternaryFill: Color(0x24767680),
    selectedRow: Color(0x1AFFFFFF),
    hover: Color(0x0FFFFFFF),
    pressed: Color(0x1FFFFFFF),
    accent: Color(0xFF0A84FF),
    accentFill: Color(0xFF0A66D0),
    accentTint: Color(0x330A84FF),
    onAccent: Color(0xFFFFFFFF),
    glass: Color(0xC7323235),
    glassOpaque: Color(0xFF323235),
    glassHighlight: Color(0x24FFFFFF),
    hairline: Color(0x80000000),
    line: Color(0x38EBEBF5),
    excerptText: Color(0xFFD1D1D6),
    rootNode: Color(0xFFF5F5F7),
    onRootNode: Color(0xFF1D1D1F),
    scrim: Color(0x40000000),
    glassShadow: [], // Floating chrome uses a hairline instead of blurred shadows.
    cardShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 10, offset: Offset(0, 2))],
    sidebarShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 6))],
    sheetShadow: [BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 24))],
  );

  /// Applies the user's system accent color (System Settings › Appearance).
  MMColors withAccent(Color systemAccent) {
    return copyWith(
      accent: systemAccent,
      accentTint: systemAccent.withValues(alpha: brightness == Brightness.dark ? 0.2 : 0.12),
    );
  }

  @override
  MMColors copyWith({Color? accent, Color? accentFill, Color? accentTint}) {
    return MMColors(
      brightness: brightness,
      windowBackground: windowBackground,
      sidebar: sidebar,
      sidebarOpaque: sidebarOpaque,
      readerBackground: readerBackground,
      canvas: canvas,
      card: card,
      page: page,
      label: label,
      secondaryLabel: secondaryLabel,
      icon: icon,
      separator: separator,
      fill: fill,
      quaternaryFill: quaternaryFill,
      selectedRow: selectedRow,
      hover: hover,
      pressed: pressed,
      accent: accent ?? this.accent,
      accentFill: accentFill ?? this.accentFill,
      accentTint: accentTint ?? this.accentTint,
      onAccent: onAccent,
      glass: glass,
      glassOpaque: glassOpaque,
      glassHighlight: glassHighlight,
      hairline: hairline,
      line: line,
      excerptText: excerptText,
      rootNode: rootNode,
      onRootNode: onRootNode,
      scrim: scrim,
      glassShadow: glassShadow,
      cardShadow: cardShadow,
      sidebarShadow: sidebarShadow,
      sheetShadow: sheetShadow,
    );
  }

  @override
  MMColors lerp(MMColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<BoxShadow> s(List<BoxShadow> a, List<BoxShadow> b) => BoxShadow.lerpList(a, b, t)!;
    return MMColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      windowBackground: c(windowBackground, other.windowBackground),
      sidebar: c(sidebar, other.sidebar),
      sidebarOpaque: c(sidebarOpaque, other.sidebarOpaque),
      readerBackground: c(readerBackground, other.readerBackground),
      canvas: c(canvas, other.canvas),
      card: c(card, other.card),
      page: c(page, other.page),
      label: c(label, other.label),
      secondaryLabel: c(secondaryLabel, other.secondaryLabel),
      icon: c(icon, other.icon),
      separator: c(separator, other.separator),
      fill: c(fill, other.fill),
      quaternaryFill: c(quaternaryFill, other.quaternaryFill),
      selectedRow: c(selectedRow, other.selectedRow),
      hover: c(hover, other.hover),
      pressed: c(pressed, other.pressed),
      accent: c(accent, other.accent),
      accentFill: c(accentFill, other.accentFill),
      accentTint: c(accentTint, other.accentTint),
      onAccent: c(onAccent, other.onAccent),
      glass: c(glass, other.glass),
      glassOpaque: c(glassOpaque, other.glassOpaque),
      glassHighlight: c(glassHighlight, other.glassHighlight),
      hairline: c(hairline, other.hairline),
      line: c(line, other.line),
      excerptText: c(excerptText, other.excerptText),
      rootNode: c(rootNode, other.rootNode),
      onRootNode: c(onRootNode, other.onRootNode),
      scrim: c(scrim, other.scrim),
      glassShadow: s(glassShadow, other.glassShadow),
      cardShadow: s(cardShadow, other.cardShadow),
      sidebarShadow: s(sidebarShadow, other.sidebarShadow),
      sheetShadow: s(sheetShadow, other.sheetShadow),
    );
  }
}

/// WCAG contrast ratio between two opaque colors, used by tests to keep
/// text tokens at 4.5:1 or better.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Composites [top] over an opaque [bottom], for contrast checks.
Color composite(Color top, Color bottom) {
  final a = top.a;
  double ch(double t, double b) => lerpDouble(b, t, a)!;
  return Color.from(alpha: 1, red: ch(top.r, bottom.r), green: ch(top.g, bottom.g), blue: ch(top.b, bottom.b));
}
