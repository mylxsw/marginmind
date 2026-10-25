import 'package:flutter/material.dart';

import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/annotation_colors.dart';

/// Row of the six annotation colors (Finder-tag style). The selected dot
/// gets a ring of its own color.
class MMColorPicker extends StatelessWidget {
  const MMColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    this.dotSize = 16,
  });

  final MMAnnotationColor selected;
  final ValueChanged<MMAnnotationColor> onChanged;

  /// Localized color name, shown in tooltips and read by screen readers.
  final String Function(MMAnnotationColor color) labelOf;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    final ring = context.mmColors.card;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in MMAnnotationColor.values)
          MMInteractive(
            onTap: () => onChanged(color),
            selected: color == selected,
            tooltip: labelOf(color),
            semanticLabel: labelOf(color),
            builder: (context, s) => Container(
              width: dotSize + 10,
              height: dotSize + 10,
              alignment: Alignment.center,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: color.color,
                  shape: BoxShape.circle,
                  boxShadow: color == selected || s.focused
                      ? [BoxShadow(color: color.color, spreadRadius: 3.5), BoxShadow(color: ring, spreadRadius: 2)]
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
