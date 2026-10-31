import 'package:flutter/animation.dart';

abstract final class MMMotion {
  static const double chromeHideDistance = 24;
  static const double chromeRevealDistance = 8;

  /// Menus and anchored popovers appear fully visible in their first frame.
  static const popup = Duration.zero;

  /// Hover, press, color changes.
  static const quick = Duration(milliseconds: 150);

  /// Fold/unfold, selection rings, segmented thumb.
  static const standard = Duration(milliseconds: 200);

  /// Layout switches and sidebar show/hide.
  static const layout = Duration(milliseconds: 320);

  /// Selection held at the viewport edge, then continuous auto-scroll ticks.
  static const selectionEdge = Duration(milliseconds: 600);
  static const selectionScroll = Duration(milliseconds: 50);

  /// Source ↔ card linked highlight.
  static const flash = Duration(milliseconds: 1600);

  /// One beat of the ring around a topic the AI is expanding.
  static const pulse = Duration(milliseconds: 1400);

  /// One sweep of the placeholder draft shown before the first one arrives.
  static const shimmer = Duration(milliseconds: 1100);

  /// HUD capsule display time.
  static const hud = Duration(milliseconds: 2400);

  /// One breath of the chapter skeleton being read (mind map from a
  /// document): opacity 1 → 0.4 → 1.
  static const breathe = Duration(milliseconds: 1200);

  static const Curve quickCurve = Curves.easeOut;
  static const Curve standardCurve = Curves.easeInOut;

  /// Approximates the system spring (response .35, damping .85).
  static const Curve layoutCurve = Curves.easeOutCubic;
}
