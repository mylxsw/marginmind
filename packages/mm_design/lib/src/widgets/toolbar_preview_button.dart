import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'control_frame.dart';

/// A toolbar choice with a visual preview instead of an icon or label.
/// Uses the same dimensions, interaction states and focus ring as toolbar buttons.
class MMToolbarPreviewButton extends StatelessWidget {
  const MMToolbarPreviewButton({
    super.key,
    required this.tooltip,
    required this.preview,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final Widget Function(Color foreground) preview;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      tooltip: tooltip,
      semanticLabel: tooltip,
      selected: selected,
      onTap: onPressed,
      builder: (context, s) => MMControlFrame(
        child: AnimatedContainer(
          duration: MMMotion.quick,
          width: context.mmTouchPlatform ? MMSizes.tabletControlVisual : context.mmToolbarButton.width,
          height: context.mmTouchPlatform ? MMSizes.tabletControlVisual : context.mmToolbarButton.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? c.accentTint
                : s.pressed
                ? c.pressed
                : s.hovered
                ? c.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(context.mmTouchPlatform ? 16 : MMRadii.capsuleButton),
            border: s.focused ? Border.all(color: c.accent, width: 2) : null,
          ),
          child: preview(
            !s.enabled
                ? c.label.withValues(alpha: 0.3)
                : selected
                ? c.accent
                : c.label,
          ),
        ),
      ),
    );
  }
}
