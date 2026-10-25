import 'package:flutter/material.dart';

import '../theme/mm_theme.dart';

/// Thin (4px) determinate progress bar.
class MMProgressBar extends StatelessWidget {
  const MMProgressBar({super.key, required this.value, this.semanticLabel});

  /// 0–1.
  final double value;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Semantics(
      label: semanticLabel,
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: c.fill),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: ColoredBox(color: c.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
