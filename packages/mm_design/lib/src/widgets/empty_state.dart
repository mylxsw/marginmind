import 'package:flutter/material.dart';

import '../theme/mm_theme.dart';

/// Centered empty / first-run state: an optional icon, title and message,
/// then actions. Keep it to what the layout cannot say on its own.
class MMEmptyState extends StatelessWidget {
  const MMEmptyState({super.key, this.title, this.message, this.icon, this.actions = const []});

  final String? title;
  final String? message;
  final IconData? icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final blocks = <Widget>[
      if (icon != null)
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(18)),
          child: Icon(icon, size: 36, color: c.accent),
        ),
      if (title != null) Text(title!, style: t.title2, textAlign: TextAlign.center),
      if (message != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            message!,
            style: t.bodySecondary.copyWith(height: 20 / 13),
            textAlign: TextAlign.center,
          ),
        ),
      if (actions.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: actions),
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < blocks.length; i++) ...[if (i > 0) SizedBox(height: _gapBefore(blocks, i)), blocks[i]],
          ],
        ),
      ),
    );
  }

  /// 16 under the icon, 8 between title and message, 18 above the actions.
  double _gapBefore(List<Widget> blocks, int i) {
    if (i == blocks.length - 1 && actions.isNotEmpty) return 18;
    if (i == 1 && icon != null) return 16;
    return 8;
  }
}
