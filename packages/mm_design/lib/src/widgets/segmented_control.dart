import 'package:flutter/material.dart';

import '../foundation/appearance.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';

@immutable
class MMSegment<T> {
  const MMSegment({required this.value, required this.label, this.tooltip});

  final T value;
  final String label;
  final String? tooltip;
}

/// macOS segmented control: the selected segment floats in white (not
/// accent — accent is reserved for selected content).
class MMSegmentedControl<T> extends StatelessWidget {
  const MMSegmentedControl({super.key, required this.segments, required this.value, required this.onChanged});

  final List<MMSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return Container(
      height: MMSizes.segmented,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final seg in segments)
            MMInteractive(
              selected: seg.value == value,
              tooltip: seg.tooltip,
              semanticLabel: seg.label,
              onTap: onChanged == null ? null : () => onChanged!(seg.value),
              builder: (context, s) {
                final on = seg.value == value;
                return AnimatedContainer(
                  duration: MMAppearance.duration(context, MMMotion.standard),
                  curve: MMMotion.standardCurve,
                  height: MMSizes.segmented - 4,
                  constraints: const BoxConstraints(minWidth: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? c.card : (s.hovered ? c.hover : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: on
                        ? [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.06), spreadRadius: 0.5),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(seg.label, style: t.callout.copyWith(fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
                );
              },
            ),
        ],
      ),
    );
  }
}
