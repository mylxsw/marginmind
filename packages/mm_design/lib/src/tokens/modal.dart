import 'package:flutter/material.dart';

import 'colors.dart';
import 'metrics.dart';

/// One material for app-owned panels, including UIKit presentations.
/// Content stays opaque; floating page controls may still use glass.
class MMModalStyle {
  const MMModalStyle(this.colors);

  final MMColors colors;

  // Content panels belong to the page palette. Floating-control glass has a
  // brighter opaque fallback and must not become the background of a form.
  Color get background => colors.windowBackground;
  Color get border => colors.border;
  double get radius => MMRadii.phoneSheet;
  double get borderWidth => MMSizes.hairline;

  Map<String, Object> toNativeMap() => {
    'background': background.toARGB32(),
    'border': border.toARGB32(),
    'card': colors.card.toARGB32(),
    'label': colors.label.toARGB32(),
    'secondaryLabel': colors.secondaryLabel.toARGB32(),
    'accent': colors.accent.toARGB32(),
    'critical': colors.critical.toARGB32(),
    'radius': radius,
    'borderWidth': borderWidth,
  };

  static Map<String, Object> get nativeConfiguration => {
    'light': const MMModalStyle(MMColors.light).toNativeMap(),
    'dark': const MMModalStyle(MMColors.dark).toNativeMap(),
  };
}
