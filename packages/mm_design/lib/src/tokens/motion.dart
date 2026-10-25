import 'package:flutter/animation.dart';

abstract final class MMMotion {
  /// Hover, press, color changes.
  static const quick = Duration(milliseconds: 150);

  /// Fold/unfold, selection rings, segmented thumb.
  static const standard = Duration(milliseconds: 200);

  /// Layout switches and sidebar show/hide.
  static const layout = Duration(milliseconds: 320);

  /// Source ↔ card linked highlight.
  static const flash = Duration(milliseconds: 1600);

  /// HUD capsule display time.
  static const hud = Duration(milliseconds: 2400);

  static const Curve quickCurve = Curves.easeOut;
  static const Curve standardCurve = Curves.easeInOut;

  /// Approximates the system spring (response .35, damping .85).
  static const Curve layoutCurve = Curves.easeOutCubic;
}
