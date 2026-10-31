import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/adaptive.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/annotation_colors.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'glass.dart';
import 'control_frame.dart';

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
    final c = context.mmColors;
    final ring = c.card;
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
                  border: c.flat && (color == selected || s.focused)
                      ? Border.all(color: s.focused ? c.accent : color.color, width: 1.5, strokeAlign: 4)
                      : null,
                  boxShadow: c.flat
                      ? null
                      : color == selected || s.focused
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

/// Toolbar button showing the current annotation color; clicking it opens
/// an [MMColorPicker] pop-up below the button. Choosing a color closes the
/// pop-up.
class MMColorMenuButton extends StatelessWidget {
  const MMColorMenuButton({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    required this.tooltip,
    this.compact = false,
  });

  final MMAnnotationColor selected;
  final ValueChanged<MMAnnotationColor> onChanged;
  final String Function(MMAnnotationColor color) labelOf;
  final String tooltip;
  final bool compact;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
    final picked = await showGeneralDialog<MMAnnotationColor>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: MMMotion.popup,
      pageBuilder: (context, _, _) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
        child: FocusScope(
          autofocus: true,
          child: CustomSingleChildLayout(
            delegate: _ColorMenuLayout(origin),
            child: Material(
              type: MaterialType.transparency,
              child: MMGlass(
                borderRadius: BorderRadius.circular(MMRadii.capsuleButton + 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: MMColorPicker(
                  selected: selected,
                  labelOf: labelOf,
                  onChanged: (color) => Navigator.of(context).pop(color),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final dense = compact && !context.mmTouch && !context.mmTablet;
    final size = dense ? const Size(30, 26) : context.mmToolbarButton;
    return MMInteractive(
      onTap: () => _open(context),
      tooltip: tooltip,
      semanticLabel: tooltip,
      builder: (context, s) => MMControlFrame(
        child: AnimatedContainer(
          duration: MMMotion.quick,
          height: context.mmTablet ? MMSizes.tabletControlVisual : size.height,
          constraints: BoxConstraints(minWidth: context.mmTablet ? MMSizes.tabletControlVisual : size.width),
          decoration: BoxDecoration(
            color: s.pressed
                ? c.pressed
                : s.hovered
                ? c.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(context.mmTablet ? 16 : MMRadii.capsuleButton),
          ),
          alignment: Alignment.center,
          child: Container(
            width: dense ? 12 : 14,
            height: dense ? 12 : 14,
            decoration: BoxDecoration(
              color: selected.color,
              shape: BoxShape.circle,
              border: c.flat && s.focused
                  ? Border.all(color: c.accent, width: 2, strokeAlign: BorderSide.strokeAlignOutside)
                  : null,
              boxShadow: c.flat
                  ? null
                  : s.focused
                  ? [BoxShadow(color: c.accent, spreadRadius: 2)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Centers the pop-up under [origin], keeping it inside the window.
class _ColorMenuLayout extends SingleChildLayoutDelegate {
  _ColorMenuLayout(this.origin);

  final Offset origin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final maxX = size.width - child.width - MMSpacing.s;
    final x = (origin.dx - child.width / 2).clamp(MMSpacing.s, maxX < MMSpacing.s ? MMSpacing.s : maxX);
    return Offset(x, origin.dy + MMSpacing.xs);
  }

  @override
  bool shouldRelayout(_ColorMenuLayout old) => old.origin != origin;
}
