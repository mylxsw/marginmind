import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

/// Source chip displaying the document page (e.g. "p.N"), with an optional
/// color dot for multi-document maps.
class MapSourceChip extends StatelessWidget {
  const MapSourceChip({super.key, required this.page, this.documentTitle, this.documentIndex, this.onTap});

  final int page;
  final String? documentTitle;
  final int? documentIndex;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    final brightness = Theme.of(context).brightness;

    return Semantics(
      button: onTap != null,
      label: documentTitle != null ? l.mapSourceSemantics(documentTitle!, page) : l.pageNumber(page),
      child: MMInteractive(
        onTap: onTap,
        builder: (context, state) {
          final hovered = state.hovered || state.pressed;
          final bgColor = hovered ? c.fill : c.quaternaryFill;
          final textColor = hovered ? c.label : c.secondaryLabel;

          return Container(
            height: MMSizes.mapSourceChip,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(MMRadii.mapSourceChip)),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (documentIndex != null) ...[
                  Container(
                    width: MMSizes.mapSourceDot,
                    height: MMSizes.mapSourceDot,
                    decoration: BoxDecoration(
                      color: MMSourceColors.of(brightness, documentIndex!),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                ] else ...[
                  Icon(MMIcons.document, size: 10, color: textColor),
                  const SizedBox(width: 3),
                ],
                Text(
                  l.notePage(page),
                  style: context.mmText.footnote.copyWith(color: textColor, fontWeight: FontWeight.w500, height: 1),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
