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
    required this.research,
    required this.researchTint,
    required this.researchWash,
    required this.onResearch,
    required this.vocabulary,
    required this.vocabularyTint,
    required this.positive,
    required this.caution,
    required this.critical,
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

  /// Shared workspace backdrop — window, toolbar, PDF surround and mind map.
  final Color windowBackground;

  /// Sidebar glass material.
  final Color sidebar;

  /// Sidebar when "Reduce transparency" is on.
  final Color sidebarOpaque;

  /// PDF surround; shares the window backdrop, independent of page colors.
  final Color readerBackground;

  /// Mind map canvas; shares the window backdrop.
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

  /// Research: the research panel, research notes and their entry points.
  /// Fixed, unlike [accent], so research stays apart from selection.
  final Color research;

  /// [research] at 12% / 20%: research card wash, selected research controls.
  final Color researchTint;

  /// [research] at 6% / 10%: AI draft nodes and the idea expansion section,
  /// lighter than [researchTint] so a draft never reads as a selection.
  final Color researchWash;

  /// Text and icons on a solid [research] fill (white / near-black): white on
  /// the lighter dark-mode research falls below 4.5:1.
  final Color onResearch;

  /// Fixed vocabulary hue; the light shade meets 4.5:1 on white.
  final Color vocabulary;

  /// Text on a solid vocabulary action; dark teal needs dark ink.
  Color get onVocabulary => brightness == Brightness.dark ? light.label : onAccent;

  /// Vocabulary wash at 12% / 16%.
  final Color vocabularyTint;

  /// Status text on a 12% wash of itself: done / partial / failed (e.g. a
  /// source's reading state). Apple's increased-contrast system green,
  /// orange and red, so the text reads at 4.5:1.
  final Color positive;
  final Color caution;
  final Color critical;

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

  // Keep all workspace surfaces on the same base under floating glass.
  static const _lightBackground = Color(0xFFFFFFFF);
  static const _darkBackground = Color(0xFF1E1E1F);

  static const light = MMColors(
    brightness: Brightness.light,
    windowBackground: _lightBackground,
    sidebar: Color(0xDBF2F2F6),
    sidebarOpaque: Color(0xFFF2F2F6),
    readerBackground: _lightBackground,
    canvas: _lightBackground,
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
    research: Color(0xFF5E5CE6),
    researchTint: Color(0x1F5E5CE6),
    researchWash: Color(0x0F5E5CE6),
    onResearch: Color(0xFFFFFFFF),
    vocabulary: Color(0xFF0D8480),
    vocabularyTint: Color(0x1F0D8480),
    positive: Color(0xFF248A3D),
    caution: Color(0xFFC93400),
    critical: Color(0xFFD70015),
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
    windowBackground: _darkBackground,
    sidebar: Color(0xDB2C2C2F),
    sidebarOpaque: Color(0xFF2C2C2F),
    readerBackground: _darkBackground,
    canvas: _darkBackground,
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
    research: Color(0xFF7D7AFF),
    researchTint: Color(0x337D7AFF),
    researchWash: Color(0x1A7D7AFF),
    onResearch: Color(0xFF1E1E1F),
    vocabulary: Color(0xFF40C8C0),
    vocabularyTint: Color(0x2940C8C0),
    positive: Color(0xFF30D158),
    caution: Color(0xFFFF9F0A),
    critical: Color(0xFFFF453A),
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
      research: research,
      researchTint: researchTint,
      researchWash: researchWash,
      onResearch: onResearch,
      vocabulary: vocabulary,
      vocabularyTint: vocabularyTint,
      positive: positive,
      caution: caution,
      critical: critical,
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
      research: c(research, other.research),
      researchTint: c(researchTint, other.researchTint),
      researchWash: c(researchWash, other.researchWash),
      onResearch: c(onResearch, other.onResearch),
      vocabulary: c(vocabulary, other.vocabulary),
      vocabularyTint: c(vocabularyTint, other.vocabularyTint),
      positive: c(positive, other.positive),
      caution: c(caution, other.caution),
      critical: c(critical, other.critical),
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
