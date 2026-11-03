import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

Object annotationTapGroup(String studySetId) => ValueKey('annotation-tools-$studySetId');

class AnnotationPalettePlacement extends SingleChildLayoutDelegate {
  AnnotationPalettePlacement(this.anchor, {this.insets = EdgeInsets.zero});
  factory AnnotationPalettePlacement.of(BuildContext context, Rect anchor) {
    final safe = MediaQuery.viewPaddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return AnnotationPalettePlacement(anchor, insets: safe.copyWith(bottom: math.max(safe.bottom, keyboard)));
  }
  final Rect anchor;
  final EdgeInsets insets;
  Rect _bounds(Size size) => Rect.fromLTRB(
    insets.left + MMSpacing.s,
    insets.top + MMSpacing.s,
    math.max(insets.left + MMSpacing.s, size.width - insets.right - MMSpacing.s),
    math.max(insets.top + MMSpacing.s, size.height - insets.bottom - MMSpacing.s),
  );
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final bounds = _bounds(constraints.biggest);
    return BoxConstraints(maxWidth: bounds.width, maxHeight: bounds.height);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = _bounds(size);
    final x = (anchor.left - MMSpacing.xs).clamp(bounds.left, math.max(bounds.left, bounds.right - childSize.width));
    final below = anchor.bottom + MMSpacing.s;
    final y = below + childSize.height <= bounds.bottom ? below : anchor.top - childSize.height - MMSpacing.s;
    return Offset(x.toDouble(), y.clamp(bounds.top, math.max(bounds.top, bounds.bottom - childSize.height)).toDouble());
  }

  @override
  bool shouldRelayout(AnnotationPalettePlacement old) => old.anchor != anchor || old.insets != insets;
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
