import 'package:flutter/material.dart';

/// Explicit phone materials from mobile-redesign.html; legacy glass is unchanged.
enum MMPhoneGlass {
  regular,
  thick;

  double get blur => this == regular ? 10 : 28;
  double get saturation => this == regular ? 1.9 : 1.8;
  double get brightness => this == regular ? 1.03 : 1;
  Color fill(bool dark) => dark
      ? Color.fromRGBO(36, 36, 40, this == regular ? .62 : .84)
      : this == regular
      ? const Color.fromRGBO(255, 255, 255, .46)
      : const Color.fromRGBO(250, 250, 252, .80);
  static Color opaque(bool dark) => dark ? const Color(0xFF1C1C1E) : Colors.white;
  static Color edge(bool dark) => Colors.black.withValues(alpha: dark ? .55 : .07);
  static List<BoxShadow> shadows(bool dark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: dark ? .45 : .10),
      offset: const Offset(0, 8),
      blurRadius: 28,
    ),
    if (!dark) const BoxShadow(color: Color.fromRGBO(0, 0, 0, .06), offset: Offset(0, 1), blurRadius: 3),
  ];
  static Gradient sheen(bool dark) => RadialGradient(
    center: const Alignment(-.4, -1),
    radius: 1.2,
    colors: [
      Colors.white.withValues(alpha: dark ? .06 : .22),
      Colors.white.withValues(alpha: 0),
    ],
    stops: const [0, .6],
  );
  static Gradient rim(bool dark) => LinearGradient(
    begin: const Alignment(-.34, -1),
    end: const Alignment(.34, 1),
    colors: [
      for (final a in [dark ? .28 : .95, dark ? .06 : .35, 0.0, dark ? .06 : .35, dark ? .28 : .95])
        Colors.white.withValues(alpha: a),
    ],
    stops: const [0, .30, .50, .78, 1],
  );
}
