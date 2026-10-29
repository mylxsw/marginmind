import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import 'study_set_cover.dart';

/// "Continue Learning" row item: last position, progress and cards due.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.set, required this.onOpen});

  final StudySet set;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final position = set.lastPosition;
    return MMInteractive(
      onTap: onOpen,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(s.hovered ? c.hover : Colors.transparent, c.quaternaryFill),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: StudySetCover(
                color: MMAnnotationColor.fromIndex(set.colorIndex),
                documentCount: set.documentCount,
                height: 64,
                compact: true,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(set.title, style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    position == null
                        ? l.libraryNoDocumentsYet
                        : position.position is TextReadingPosition
                        ? position.documentTitle
                        : l.libraryLastPosition(position.documentTitle, position.page),
                    style: t.footnote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(child: MMProgressBar(value: set.progress)),
                      const SizedBox(width: 8),
                      Text('${(set.progress * 100).round()}%', style: t.footnote),
                    ],
                  ),
                ],
              ),
            ),
            if (set.dueCount > 0) ...[const SizedBox(width: 10), MMBadge(l.dueBadge(set.dueCount), prominent: true)],
          ],
        ),
      ),
    );
  }
}
