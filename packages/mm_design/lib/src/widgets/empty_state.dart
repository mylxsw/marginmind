import 'package:flutter/material.dart';

import '../theme/mm_theme.dart';

/// Centered empty / first-run state. With [dropZone] it draws the dashed-free
/// rounded well that signals "drop files here".
class MMEmptyState extends StatelessWidget {
  const MMEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actions = const [],
    this.dropZone = false,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final List<Widget> actions;
  final bool dropZone;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, size: 36, color: c.accent),
          ),
          const SizedBox(height: 16),
        ],
        Text(title, style: t.title2, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              message!,
              style: t.bodySecondary.copyWith(height: 20 / 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: actions),
        ],
      ],
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: dropZone
            ? Container(
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                decoration: BoxDecoration(
                  color: c.quaternaryFill,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.fill, width: 1.5),
                ),
                child: content,
              )
            : content,
      ),
    );
  }
}
