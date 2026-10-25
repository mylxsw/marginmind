import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../foundation/appearance.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';

/// Liquid Glass surface for controls that float above content: toolbar
/// groups, floating map controls, HUDs. Never use it for content (pages,
/// cards) and never stack glass on glass.
///
/// Falls back to an opaque fill when "Reduce transparency" is on.
class MMGlass extends StatelessWidget {
  const MMGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(MMRadii.capsule)),
    this.padding = EdgeInsets.zero,
    this.color,
    this.opaqueColor,
    this.shadows,
    this.blurSigma = 24,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? opaqueColor;
  final List<BoxShadow>? shadows;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final reduce = MMAppearance.reduceTransparencyOf(context);
    final fill = reduce ? (opaqueColor ?? c.glassOpaque) : (color ?? c.glass);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(color: c.hairline, width: 0.5),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (!reduce) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      );
    }
    // Outer-only shadows, so a translucent surface is not darkened from below.
    final outer = [
      for (final s in shadows ?? c.glassShadow)
        BoxShadow(
          color: s.color,
          offset: s.offset,
          blurRadius: s.blurRadius,
          spreadRadius: s.spreadRadius,
          blurStyle: BlurStyle.outer,
        ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: outer),
      child: ClipRRect(borderRadius: borderRadius, child: surface),
    );
  }
}
