import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import 'annotation_line_style_picker.dart';
import 'annotation_palette.dart';

/// The same compact bar is used for continuous marking and existing annotations.
/// Settings are recognizable previews; their names stay in tooltips/semantics.
class UnderlineStyleToolbar extends StatelessWidget {
  const UnderlineStyleToolbar({
    super.key,
    required this.color,
    required this.style,
    required this.colors,
    required this.onColor,
    required this.onStyle,
    required this.onMore,
    required this.onClose,
  });

  final MMAnnotationColor color;
  final AnnotationLineStyle style;
  final List<MMAnnotationColor> colors;
  final ValueChanged<MMAnnotationColor>? onColor;
  final ValueChanged<AnnotationLineStyle>? onStyle;
  final VoidCallback onMore, onClose;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: MMFloatingToolbar(
      children: [
        for (final swatch in colors)
          MMFloatingToolbarColor(
            color: swatch,
            tooltip: context.l10n.colorName(swatch),
            selected: color == swatch,
            onPressed: onColor == null ? null : () => onColor!(swatch),
          ),
        AnnotationMoreColorsButton(onPressed: onMore),
        const MMToolbarDivider(),
        AnnotationLineStylePicker(value: style, onChanged: onStyle),
        const MMToolbarDivider(),
        MMToolbarButton(icon: MMIcons.close, tooltip: context.l10n.closePanel, onPressed: onClose),
      ],
    ),
  );
}
