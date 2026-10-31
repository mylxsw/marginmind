import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../foundation/floating_placement.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/annotation_colors.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'toolbar.dart';
import 'control_frame.dart';
import 'glass.dart';

/// Horizontal glass bar that floats over content next to a selection. Fill it
/// with [MMToolbarButton]s, [MMFloatingToolbarColor]s and [MMToolbarDivider]s;
/// Tab and the arrow keys move focus between them. Place it with
/// [MMFloatingToolbarLayout].
class MMFloatingToolbar extends StatelessWidget {
  const MMFloatingToolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      // A floating surface must cover the content beneath it. Toolbar
      // groups use a translucent control fill in flat workspaces.
      child: FocusTraversalGroup(
        child: MMGlass(
          toolbar: true,
          padding: EdgeInsets.all(context.mmTablet ? 2 : 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// Annotation color dot sized like a toolbar button. The selected dot gets a
/// ring of its own color, like [MMColorPicker].
class MMFloatingToolbarColor extends StatelessWidget {
  const MMFloatingToolbarColor({
    super.key,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final MMAnnotationColor color;

  /// Localized color name, shown in the tooltip and read by screen readers.
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) =>
      MMFloatingToolbarSwatch(color: color.color, tooltip: tooltip, onPressed: onPressed, selected: selected);
}

/// A color dot of any palette (annotation or ink) sized like a toolbar
/// button; the selected dot gets a ring of its own color.
class MMFloatingToolbarSwatch extends StatelessWidget {
  const MMFloatingToolbarSwatch({
    super.key,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final Color color;

  /// Localized color name, shown in the tooltip and read by screen readers.
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      selected: selected,
      tooltip: tooltip,
      semanticLabel: tooltip,
      builder: (context, s) => MMControlFrame(
        child: AnimatedContainer(
          duration: MMMotion.quick,
          width: context.mmTablet
              ? MMSizes.tabletControlVisual
              : (context.mmTouch ? MMSizes.touchTarget : MMSizes.floatingToolbarColor),
          height: context.mmTablet
              ? MMSizes.tabletControlVisual
              : (context.mmTouch ? MMSizes.touchTarget : MMSizes.toolbarButton.height),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.pressed
                ? c.pressed
                : s.hovered
                ? c.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(context.mmTablet ? 16 : MMRadii.capsuleButton),
          ),
          child: !c.flat
              ? Container(
                  width: MMSizes.floatingToolbarDot,
                  height: MMSizes.floatingToolbarDot,
                  decoration: BoxDecoration(
                    color: s.enabled ? color : color.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    boxShadow: selected || s.focused
                        ? [
                            // Painted in order: the outer ring first, then the gap over it.
                            BoxShadow(color: s.focused ? c.accent : color, spreadRadius: 3.5),
                            BoxShadow(color: c.glassOpaque, spreadRadius: 2),
                          ]
                        : null,
                  ),
                )
              : CustomPaint(
                  painter: _ColorRingPainter(selected || s.focused ? (s.focused ? c.accent : color) : null),
                  child: Container(
                    width: MMSizes.floatingToolbarDot,
                    height: MMSizes.floatingToolbarDot,
                    decoration: BoxDecoration(
                      color: s.enabled ? color : color.withValues(alpha: .3),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Stroke width choice: a dot as thick as the stroke, tinted when selected.
class MMFloatingToolbarStrokeWidth extends StatelessWidget {
  const MMFloatingToolbarStrokeWidth({
    super.key,
    required this.width,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  /// Stroke width in points; the dot is `width * 2 + 2` across.
  final double width;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      selected: selected,
      tooltip: tooltip,
      semanticLabel: tooltip,
      builder: (context, s) => MMControlFrame(
        child: AnimatedContainer(
          duration: MMMotion.quick,
          width: context.mmTablet ? MMSizes.tabletControlVisual : MMSizes.floatingToolbarColor,
          height: context.mmTablet ? MMSizes.tabletControlVisual : MMSizes.floatingToolbarColor,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? c.accentTint
                : s.pressed
                ? c.pressed
                : s.hovered
                ? c.hover
                : Colors.transparent,
            shape: BoxShape.circle,
            border: s.focused ? Border.all(color: c.accent, width: 2) : null,
          ),
          child: Container(
            width: width * 2 + 2,
            height: width * 2 + 2,
            decoration: BoxDecoration(color: selected ? c.accent : c.label, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// Fills its parent (e.g. `Positioned.fill` in a `Stack` over the content)
/// and places [child] next to [anchor] with [placeFloatingToolbar]. [anchor]
/// is in this widget's coordinates; rebuild with a new rect and the toolbar
/// follows. Pointer events outside [child] reach the content underneath.
class MMFloatingToolbarLayout extends StatelessWidget {
  const MMFloatingToolbarLayout({
    super.key,
    required this.anchor,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.avoid,
  });

  final Rect anchor;
  final Widget child;

  /// Area of a neighbouring floating control, given this widget's size, that
  /// the toolbar steps aside for (see [placeFloatingToolbar]).
  final Rect Function(Size size)? avoid;

  /// Area along the edges the toolbar must stay out of, such as a window
  /// toolbar overlapping the content.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(delegate: _FloatingToolbarDelegate(anchor, padding, avoid), child: child);
  }
}

class _FloatingToolbarDelegate extends SingleChildLayoutDelegate {
  _FloatingToolbarDelegate(this.anchor, this.padding, this.avoid);

  final Rect anchor;
  final EdgeInsets padding;
  final Rect Function(Size size)? avoid;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => placeFloatingToolbar(
    anchor: anchor,
    size: childSize,
    viewport: padding.deflateRect(Offset.zero & size),
    avoid: avoid?.call(size),
  ).offset;

  @override
  bool shouldRelayout(_FloatingToolbarDelegate oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.padding != padding || oldDelegate.avoid != avoid;
}

class _ColorRingPainter extends CustomPainter {
  const _ColorRingPainter(this.color);
  final Color? color;
  @override
  void paint(Canvas canvas, Size size) {
    if (color != null) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.width / 2 + 2.75,
        Paint()
          ..color = color!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ColorRingPainter oldDelegate) => color != oldDelegate.color;
}
