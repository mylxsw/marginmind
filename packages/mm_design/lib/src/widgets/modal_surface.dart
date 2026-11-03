import 'package:flutter/material.dart';

import '../theme/mm_theme.dart';
import '../tokens/colors.dart';
import '../tokens/modal.dart';
import 'flat_surface.dart';

/// Shared panel material and control treatment. Descendant glass controls and
/// menus inherit the flat appearance, so the form cannot regain a second blur.
class MMModalSurface extends StatelessWidget {
  const MMModalSurface({super.key, required this.child, required this.borderRadius, this.padding = EdgeInsets.zero});

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.mmColors;
    final style = MMModalStyle(colors);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: borderRadius,
        border: Border.all(color: style.border, width: style.borderWidth),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: MMFlatSurface(
          child: Theme(
            data: theme.copyWith(
              extensions: [
                ...theme.extensions.values.where((value) => value is! MMColors),
                colors.copyWith(flat: true),
              ],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
