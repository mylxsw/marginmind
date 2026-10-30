import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

Object annotationTapGroup(String studySetId) => ValueKey('annotation-tools-$studySetId');

class AnnotationPalettePlacement extends SingleChildLayoutDelegate {
  AnnotationPalettePlacement(this.anchor);
  final Rect anchor;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(8));
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (anchor.left - 6).clamp(8.0, math.max(8, size.width - childSize.width - 8));
    final below = anchor.bottom + 8;
    final y = below + childSize.height <= size.height - 8 ? below : anchor.top - childSize.height - 8;
    return Offset(x.toDouble(), y.clamp(8.0, math.max(8, size.height - childSize.height - 8)).toDouble());
  }

  @override
  bool shouldRelayout(AnnotationPalettePlacement old) => old.anchor != anchor;
}

class AnnotationMoreColorsButton extends StatelessWidget {
  const AnnotationMoreColorsButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors;
    return MMInteractive(
      tooltip: l.moreHighlightColors,
      semanticLabel: l.moreHighlightColors,
      onTap: onPressed,
      builder: (context, s) => Container(
        width: MMSizes.floatingToolbarColor,
        height: context.mmToolbarButton.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.hovered || s.pressed ? c.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(MMRadii.capsuleButton),
          border: s.focused ? Border.all(color: c.accent) : null,
        ),
        child: const AnnotationMoreColorsIcon(),
      ),
    );
  }
}

class AnnotationMoreColorsIcon extends StatelessWidget {
  const AnnotationMoreColorsIcon({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 17,
    height: 17,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: SweepGradient(
        colors: [
          Color(0xFFFFCC00),
          Color(0xFF34C759),
          Color(0xFF007AFF),
          Color(0xFFAF52DE),
          Color(0xFFFF2D55),
          Color(0xFFFFCC00),
        ],
      ),
    ),
    child: const Icon(MMIcons.add, color: Colors.white, size: 13),
  );
}
