import 'package:flutter/material.dart';

import '../theme/mm_theme.dart';

/// macOS form row: right-aligned label column, control on the right.
class MMFormRow extends StatelessWidget {
  const MMFormRow({super.key, required this.label, required this.child, this.labelWidth = 96});

  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              textAlign: TextAlign.right,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: context.mmText.body,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}
