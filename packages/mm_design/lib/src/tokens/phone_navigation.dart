import 'package:flutter/material.dart';

/// Navigation geometry and motion from scenes 1, 8 and 10 of the mobile prototype.
abstract final class MMPhoneNavigation {
  static const rowHeight = 46.0;
  static const groupRadius = 14.0;
  static const titleSize = 24.0;
  static const rowTextSize = 15.5;
  static const headerInset = 18.0;
  static const iconSize = 22.0;
  static const edgeWidth = 20.0;
  static const swipeDistance = 80.0;
  static const swipeVelocity = 400.0;
  static const ratingHeight = 58.0;
  static const progressHeight = 4.0;
  static const tabIconSize = 20.0;
  static const tabLabelGap = 2.0;
  static const tabDuration = Duration(milliseconds: 420);
  static const drawerDuration = Duration(milliseconds: 380);
  static const tabCurve = Cubic(.3, 1.35, .45, 1);
  static const drawerCurve = Cubic(.25, 1, .35, 1);

  static Color background(bool dark) => dark ? const Color(0xFF0E0E10) : const Color(0xFFF2F2F7);

  /// An opaque local lens keeps accent text legible over saturated covers.
  static Color selectedAccent(Color accent, bool dark) {
    final background = lens(dark).computeLuminance();
    for (var step = 0; step <= 100; step++) {
      final color = Color.lerp(accent, dark ? Colors.white : Colors.black, step / 100)!;
      final luminance = color.computeLuminance();
      final contrast =
          (luminance > background ? luminance + .05 : background + .05) /
          (luminance > background ? background + .05 : luminance + .05);
      if (contrast >= 4.5) return color;
    }
    return dark ? Colors.white : Colors.black;
  }

  static Color lens(bool dark) => dark ? const Color(0xFF343438) : const Color(0xFFF8FAFF);
}
