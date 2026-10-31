import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../foundation/interactive.dart';
import '../tokens/metrics.dart';
import '../theme/mm_theme.dart';
import '../tokens/motion.dart';
import 'control_frame.dart';

enum MMButtonVariant {
  /// Accent fill with white text. At most one per view.
  primary,

  /// Neutral fill.
  secondary,

  /// Text only, for low-emphasis actions in bars.
  plain,
}

/// Capsule push button (height 30, radius 15).
class MMButton extends StatelessWidget {
  const MMButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = MMButtonVariant.secondary,
    this.icon,
    this.autofocus = false,
    this.color,
    this.foregroundColor,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final MMButtonVariant variant;

  /// A secondary button whose text is critical, such as "Stop" next to a
  /// primary action.
  final bool destructive;
  final IconData? icon;
  final bool autofocus;

  /// A primary button's fill in place of the accent, for a feature color
  /// (research); a plain button's text (accent links, destructive actions).
  /// Secondary buttons ignore it.
  final Color? color;

  /// Text and icon on a primary feature fill, when white lacks contrast.
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return MMInteractive(
      onTap: onPressed,
      autofocus: autofocus,
      semanticLabel: label,
      builder: (context, s) {
        final (Color bg, Color fg) = switch (variant) {
          MMButtonVariant.primary => (color ?? c.accentFill, foregroundColor ?? c.onAccent),
          MMButtonVariant.secondary => (c.fill, destructive ? c.critical : c.label),
          MMButtonVariant.plain => (s.hovered ? c.hover : Colors.transparent, color ?? c.label),
        };
        final pressedOverlay = s.pressed ? Colors.black.withValues(alpha: 0.12) : Colors.transparent;
        return MMControlFrame(
          child: AnimatedOpacity(
            duration: MMMotion.quick,
            opacity: s.enabled ? 1 : 0.4,
            child: Container(
              height: context.mmTouchPlatform ? MMSizes.tabletControlVisual : 30,
              padding: EdgeInsets.symmetric(horizontal: variant == MMButtonVariant.plain ? 12 : 16),
              foregroundDecoration: c.flat && s.focused
                  ? BoxDecoration(
                      border: Border.all(color: c.accent, width: 2, strokeAlign: BorderSide.strokeAlignOutside),
                      borderRadius: BorderRadius.circular(15),
                    )
                  : null,
              decoration: BoxDecoration(
                color: Color.alphaBlend(pressedOverlay, bg),
                borderRadius: BorderRadius.circular(context.mmTouchPlatform ? MMSizes.tabletControlVisual / 2 : 15),
                boxShadow: c.flat
                    ? null
                    : s.focused
                    ? [BoxShadow(color: (color ?? c.accent).withValues(alpha: 0.5), spreadRadius: 3)]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: context.mmTouchPlatform ? 16 : 14, color: fg),
                    const SizedBox(width: 6),
                  ],
                  // A label wider than the room it is given ends in an ellipsis.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.headline.copyWith(
                        color: fg,
                        fontWeight: variant == MMButtonVariant.primary ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small square icon button used inside panels and sidebars (28×28).
class MMIconButton extends StatelessWidget {
  const MMIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 28,
    this.iconSize = 16,
    this.color,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final double iconSize;
  final Color? color;
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
          width: context.mmTouchPlatform && size <= MMSizes.touchTarget ? MMSizes.tabletControlVisual : size,
          height: context.mmTouchPlatform && size <= MMSizes.touchTarget ? MMSizes.tabletControlVisual : size,
          decoration: BoxDecoration(
            color: s.pressed ? c.pressed : (s.hovered ? c.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(context.mmTouchPlatform ? MMRadii.row : size / 3.5),
          ),
          child: Icon(
            icon,
            size: context.mmTouchPlatform && iconSize < MMSizes.tabletToolbarIcon
                ? MMSizes.tabletToolbarIcon
                : iconSize,
            color: s.enabled ? (color ?? (selected ? c.accent : c.icon)) : c.icon.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
