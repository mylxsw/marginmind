import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../shared/l10n.dart';

/// An icon-only line selector. The previews use the PDF's actual stroke painter.
class AnnotationLineStylePicker extends StatelessWidget {
  const AnnotationLineStylePicker({super.key, required this.value, required this.onChanged});

  final AnnotationLineStyle value;
  final ValueChanged<AnnotationLineStyle>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (final style in AnnotationLineStyle.values)
        MMToolbarPreviewButton(
          key: ValueKey('line-style-${style.name}'),
          tooltip: context.l10n.lineStyleName(style),
          selected: value == style,
          onPressed: onChanged == null ? null : () => onChanged!(style),
          preview: (color) => SizedBox(
            width: 20,
            height: 10,
            child: CustomPaint(
              painter: MMPdfAnnotationLinePainter(color: color, style: style, centered: true),
            ),
          ),
        ),
    ],
  );
}
