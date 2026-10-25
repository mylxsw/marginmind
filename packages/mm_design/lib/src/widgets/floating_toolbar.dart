import 'package:flutter/material.dart';

import '../foundation/appearance.dart';
import '../foundation/floating_placement.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/annotation_colors.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'toolbar.dart';

/// Horizontal glass bar that floats over content next to a selection. Fill it
/// with [MMToolbarButton]s, [MMFloatingToolbarColor]s and [MMToolbarDivider]s;
/// Tab and the arrow keys move focus between them. Place it with
/// [MMFloatingToolbarLayout].
class MMFloatingToolbar extends StatelessWidget {
  const MMFloatingToolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MMAppearance.duration(context, MMMotion.quick),
      curve: MMMotion.quickCurve,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: FocusTraversalGroup(child: MMToolbarGroup(children: children)),
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
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      selected: selected,
      tooltip: tooltip,
      semanticLabel: tooltip,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        width: MMSizes.floatingToolbarColor,
        height: MMSizes.toolbarButton.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.pressed
              ? c.pressed
              : s.hovered
              ? c.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MMRadii.capsuleButton),
        ),
        child: Container(
          width: MMSizes.floatingToolbarDot,
          height: MMSizes.floatingToolbarDot,
          decoration: BoxDecoration(
            color: s.enabled ? color.color : color.color.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            boxShadow: selected || s.focused
                ? [
                    // Painted in order: the outer ring first, then the gap over it.
                    BoxShadow(color: s.focused ? c.accent : color.color, spreadRadius: 3.5),
                    BoxShadow(color: c.glassOpaque, spreadRadius: 2),
                  ]
                : null,
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
  const MMFloatingToolbarLayout({super.key, required this.anchor, required this.child, this.padding = EdgeInsets.zero});

  final Rect anchor;
  final Widget child;

  /// Area along the edges the toolbar must stay out of, such as a window
  /// toolbar overlapping the content.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(delegate: _FloatingToolbarDelegate(anchor, padding), child: child);
  }
}

class _FloatingToolbarDelegate extends SingleChildLayoutDelegate {
  _FloatingToolbarDelegate(this.anchor, this.padding);

  final Rect anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      placeFloatingToolbar(anchor: anchor, size: childSize, viewport: padding.deflateRect(Offset.zero & size)).offset;

  @override
  bool shouldRelayout(_FloatingToolbarDelegate oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.padding != padding;
}
