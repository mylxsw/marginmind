import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../foundation/appearance.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import 'control_frame.dart';
import 'flat_surface.dart';

/// Surface for controls that float above content: toolbar
/// groups, floating map controls, HUDs. Never use it for content (pages,
/// cards) and never stack glass on glass.
///
/// Phones and tablets share the compact, opaque iPad control surface.
/// Pointer platforms keep their existing blur and accessibility fallback.
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
    this.toolbar = false,
    this.controlGroup = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? opaqueColor;
  final List<BoxShadow>? shadows;
  final double blurSigma;

  /// A 36-point painted capsule around 44-point touch cells on tablets.
  final bool toolbar;
  final bool controlGroup;

  @override
  Widget build(BuildContext context) {
    if (MMFlatSurface.of(context)) {
      final c = context.mmColors;
      final decoration = BoxDecoration(
        color: controlGroup ? c.quaternaryFill : (opaqueColor ?? color ?? c.surface).withValues(alpha: 1),
        borderRadius: borderRadius,
        border: controlGroup ? null : Border.all(color: c.border, width: MMSizes.hairline),
      );
      if (toolbar && context.mmTouchPlatform) {
        return MMControlGroupScope(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(top: 4, bottom: 4, child: DecoratedBox(decoration: decoration)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MMToolbarSpacing.inset),
                child: child,
              ),
            ],
          ),
        );
      }
      return DecoratedBox(
        decoration: decoration,
        child: Padding(padding: padding, child: child),
      );
    }
    if (context.mmTouchPlatform) {
      final c = context.mmColors;
      final surface = BoxDecoration(
        color: opaqueColor ?? color ?? c.glassOpaque,
        borderRadius: toolbar ? BorderRadius.circular(MMRadii.capsule) : borderRadius,
        border: Border.all(color: c.hairline, width: .5),
        boxShadow: shadows,
      );
      if (toolbar) {
        const inset = (MMSizes.touchTarget - MMSizes.tabletToolbarVisual) / 2;
        return MMControlGroupScope(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                top: inset,
                bottom: inset,
                child: DecoratedBox(decoration: surface),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MMToolbarSpacing.inset),
                child: child,
              ),
            ],
          ),
        );
      }
      return DecoratedBox(
        decoration: surface,
        child: Padding(padding: padding, child: child),
      );
    }
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
    if (!reduce && blurSigma > 0) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: _outer(shadows ?? c.glassShadow)),
      child: ClipRRect(borderRadius: borderRadius, child: surface),
    );
  }
}

/// Outer-only shadows, so a translucent surface is not darkened from below.
List<BoxShadow> _outer(List<BoxShadow> shadows) => [
  for (final s in shadows)
    BoxShadow(
      color: s.color,
      offset: s.offset,
      blurRadius: s.blurRadius,
      spreadRadius: s.spreadRadius,
      blurStyle: BlurStyle.outer,
    ),
];

/// The mobile glass material: the backdrop blurred with raised saturation,
/// a lighter fill, a soft sheen from the top and a rim that catches light
/// on the upper edge. An explicit opt-in material; shared controls use
/// the opaque phone/tablet surface in [MMGlass].
///
/// Inside another [MMLiquidGlass] or an [MMGlassBar] it skips the backdrop
/// and only tints. With "Reduce transparency" it is an opaque fill.
class MMLiquidGlass extends StatelessWidget {
  const MMLiquidGlass({
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

  /// How much the backdrop's saturation rises under the blur.
  static const double saturation = 1.8;

  /// Share of the default glass fill's opacity the mobile material keeps,
  /// so more of the content shows through. An explicit color is kept.
  static const double fillOpacity = 0.7;

  /// Whether [context] lies on a glass surface already.
  static bool onGlass(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_GlassScope>() != null;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    if (MMFlatSurface.of(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: (opaqueColor ?? color ?? c.surface).withValues(alpha: 1),
          borderRadius: borderRadius,
          border: Border.all(color: c.border, width: MMSizes.hairline),
        ),
        child: Padding(padding: padding, child: child),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduce = MMAppearance.reduceTransparencyOf(context);
    final nested = onGlass(context);
    final fill = reduce
        ? (opaqueColor ?? c.glassOpaque)
        : nested
        ? (dark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.55))
        : (color ?? c.glass.withValues(alpha: c.glass.a * fillOpacity));

    Widget surface = CustomPaint(
      foregroundPainter: reduce ? null : _RimPainter(borderRadius: borderRadius, dark: dark),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: borderRadius,
          border: Border.all(color: c.hairline, width: 0.5),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: borderRadius, gradient: reduce ? null : _sheen(dark)),
          child: Padding(
            padding: padding,
            child: _GlassScope(child: child),
          ),
        ),
      ),
    );
    if (!reduce && !nested && blurSigma > 0) {
      surface = BackdropFilter(filter: liquidFilter(blurSigma), child: surface);
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: _outer(shadows ?? c.glassShadow)),
      child: ClipRRect(borderRadius: borderRadius, child: surface),
    );
  }

  /// The backdrop filter of the mobile material: saturation raised, then
  /// blurred by [sigma].
  static ImageFilter liquidFilter(double sigma) => ImageFilter.compose(
    outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    inner: ColorFilter.matrix(saturationMatrix(saturation)),
  );

  /// A color matrix scaling saturation by [s] around Rec. 709 luminance.
  static List<double> saturationMatrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return [
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  static Gradient _sheen(bool dark) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.white.withValues(alpha: dark ? 0.08 : 0.22),
      Colors.white.withValues(alpha: 0),
    ],
    stops: const [0, 0.6],
  );
}

/// The glass background of a bar along a window edge, such as the toolbar
/// of a touch window: the mobile material without rounded corners, with a
/// hairline toward the content. Glass inside it only tints.
class MMGlassBar extends StatelessWidget {
  const MMGlassBar({super.key, required this.child, this.blurSigma = 24});

  final Widget child;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final reduce = MMAppearance.reduceTransparencyOf(context);
    final flat = MMFlatSurface.of(context);
    final fill = reduce || flat ? c.windowBackground : c.windowBackground.withValues(alpha: 0.62);
    final bar = DecoratedBox(
      key: const ValueKey('mm-glass-bar'),
      decoration: BoxDecoration(
        color: fill,
        border: Border(bottom: BorderSide(color: c.separator, width: 0.5)),
      ),
      child: _GlassScope(child: child),
    );
    if (reduce || flat || blurSigma <= 0) return bar;
    return ClipRect(
      child: BackdropFilter(
        filter: context.mmTouchPlatform
            ? ImageFilter.blur(sigmaX: 12, sigmaY: 12)
            : MMLiquidGlass.liquidFilter(blurSigma),
        child: bar,
      ),
    );
  }
}

class _GlassScope extends InheritedWidget {
  const _GlassScope({required super.child});

  @override
  bool updateShouldNotify(_GlassScope oldWidget) => false;
}

/// The light-catching rim of [MMLiquidGlass]: bright along the top edge,
/// fading down the sides.
class _RimPainter extends CustomPainter {
  _RimPainter({required this.borderRadius, required this.dark});

  final BorderRadius borderRadius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: dark ? 0.32 : 0.9),
          Colors.white.withValues(alpha: dark ? 0.06 : 0.2),
          Colors.white.withValues(alpha: dark ? 0.12 : 0.4),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(rect);
    canvas.drawRRect(borderRadius.toRRect(rect).deflate(0.5), paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.borderRadius != borderRadius || old.dark != dark;
}
