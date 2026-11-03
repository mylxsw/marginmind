import 'package:flutter/material.dart';

import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import 'buttons.dart';

/// Shared title and separator for phone sheets. The outer
/// sheet alone paints the material, border and rounded corners.
class MMPhoneSheetHeader extends StatelessWidget {
  const MMPhoneSheetHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.leading,
    this.actions = const [],
    this.closeKey,
    this.closeLabel,
    this.showClose = false,
  });

  final String title;
  final VoidCallback onClose;
  final Widget? leading;
  final List<Widget> actions;
  final Key? closeKey;
  final String? closeLabel;
  final bool showClose;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: MMSizes.phoneSheetHeader),
    padding: const EdgeInsets.only(left: MMSpacing.l, right: MMSpacing.s, bottom: MMSpacing.s),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: context.mmColors.separator, width: MMSizes.hairline),
      ),
    ),
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: MMSpacing.s)],
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.mmText.title3.copyWith(color: context.mmColors.label, fontWeight: FontWeight.w600),
          ),
        ),
        ...actions,
        if (showClose)
          MMModalCloseButton(
            key: closeKey,
            iconSize: MMSizes.phoneMenuIcon,
            tooltip: closeLabel ?? MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
          ),
      ],
    ),
  );
}
