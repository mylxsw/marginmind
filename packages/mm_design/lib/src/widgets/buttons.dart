import 'package:flutter/material.dart';

import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/motion.dart';

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
  });

  final String label;
  final VoidCallback? onPressed;
  final MMButtonVariant variant;
  final IconData? icon;
  final bool autofocus;

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
          MMButtonVariant.primary => (c.accentFill, c.onAccent),
          MMButtonVariant.secondary => (c.fill, c.label),
          MMButtonVariant.plain => (s.hovered ? c.hover : Colors.transparent, c.label),
        };
        final pressedOverlay = s.pressed ? Colors.black.withValues(alpha: 0.12) : Colors.transparent;
        return AnimatedOpacity(
          duration: MMMotion.quick,
          opacity: s.enabled ? 1 : 0.4,
          child: Container(
            height: 30,
            padding: EdgeInsets.symmetric(horizontal: variant == MMButtonVariant.plain ? 12 : 16),
            decoration: BoxDecoration(
              color: Color.alphaBlend(pressedOverlay, bg),
              borderRadius: BorderRadius.circular(15),
              boxShadow: s.focused ? [BoxShadow(color: c.accent.withValues(alpha: 0.5), spreadRadius: 3)] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
                Text(
                  label,
                  style: t.headline.copyWith(
                    color: fg,
                    fontWeight: variant == MMButtonVariant.primary ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
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
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: s.pressed ? c.pressed : (s.hovered ? c.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(size / 3.5),
        ),
        child: Icon(icon, size: iconSize, color: s.enabled ? (color ?? c.icon) : c.icon.withValues(alpha: 0.3)),
      ),
    );
  }
}
