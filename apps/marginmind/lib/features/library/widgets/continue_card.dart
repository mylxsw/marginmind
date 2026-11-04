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
    final phone = MMInput.of(context).phone;
    return MMInteractive(
      onTap: onOpen,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        padding: const EdgeInsets.all(12),
        constraints: phone ? const BoxConstraints(minHeight: MMSizes.phoneContinueCardMinHeight) : null,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          set.title,
                          style: t.headline,
                          maxLines: phone ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  ...[
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
                  ],
                  const SizedBox(height: 9),
                  LayoutBuilder(
                    builder: (context, bounds) {
                      final due = l.dueBadge(set.dueCount);
                      final progress = '${(set.progress * 100).round()}%';
                      double measure(String text, TextStyle style) {
                        final painter = TextPainter(
                          text: TextSpan(text: text, style: style),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout();
                        final width = painter.width;
                        painter.dispose();
                        return width;
                      }

                      final hasDue = phone && set.dueCount > 0;
                      final stacked =
                          hasDue &&
                          bounds.maxWidth -
                                  measure(due, t.subheadline) -
                                  MMSpacing.m -
                                  MMSpacing.s * 2 -
                                  measure(progress, t.footnote) <
                              MMSizes.touchTarget;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (stacked) ...[
                            Align(alignment: Alignment.centerLeft, child: MMBadge(due)),
                            const SizedBox(height: MMSpacing.s),
                          ],
                          Row(
                            children: [
                              if (hasDue && !stacked) ...[
                                Flexible(child: MMBadge(due)),
                                const SizedBox(width: MMSpacing.s),
                              ],
                              Expanded(child: MMProgressBar(value: set.progress)),
                              const SizedBox(width: MMSpacing.s),
                              Text(progress, style: t.footnote),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            if (!phone && set.dueCount > 0) ...[
              const SizedBox(width: 10),
              MMBadge(l.dueBadge(set.dueCount), prominent: true),
            ],
          ],
        ),
      ),
    );
  }
}
