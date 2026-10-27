import 'package:flutter/material.dart';

import '../foundation/interactive.dart';
import '../icons/mm_icons.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';

/// A square checkbox with its label; the whole row toggles. [color] fills
/// the checked box (the accent by default).
class MMCheckbox extends StatelessWidget {
  const MMCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.color,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final Color? color;

  /// Names a box shown without [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final tint = color ?? c.accent;
    return MergeSemantics(
      child: Semantics(
        checked: value,
        child: MMInteractive(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          semanticLabel: label ?? semanticLabel,
          builder: (context, s) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: MMMotion.quick,
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: value ? tint : c.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: value ? tint : c.line, width: 1),
                  boxShadow: s.focused ? [BoxShadow(color: tint.withValues(alpha: 0.4), spreadRadius: 2)] : null,
                ),
                child: value ? const Icon(MMIcons.check, size: 11, color: Colors.white) : null,
              ),
              if (label != null) ...[
                const SizedBox(width: MMSpacing.s),
                Flexible(
                  child: Text(
                    label!,
                    style: context.mmText.body.copyWith(color: s.enabled ? c.label : c.secondaryLabel),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small on / off switch (macOS "mini" size).
class MMSwitch extends StatelessWidget {
  const MMSwitch({super.key, required this.value, required this.onChanged, required this.semanticLabel, this.color});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Semantics(
      toggled: value,
      child: MMInteractive(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        semanticLabel: semanticLabel,
        builder: (context, s) => AnimatedContainer(
          duration: MMMotion.quick,
          width: 28,
          height: 16,
          padding: const EdgeInsets.all(2),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: value ? (color ?? c.accent) : c.fill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Opacity(
            opacity: s.enabled ? 1 : 0.5,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short status or kind label on a tint of its own color: "Full text",
/// "Failed to read", "External".
class MMPill extends StatelessWidget {
  const MMPill(this.label, {super.key, this.color, this.icon});

  final String label;

  /// Text color; the pill is filled with it at 12%. Secondary text on a
  /// neutral fill when null.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final fg = color ?? c.secondaryLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color == null ? c.quaternaryFill : fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MMRadii.row),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 10, color: fg), const SizedBox(width: 3)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.mmText.footnote.copyWith(color: fg, height: 16 / 11),
            ),
          ),
        ],
      ),
    );
  }
}
