import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../full_translation.dart';
import 'full_translation_panel.dart';
import 'full_translation_sheet.dart';

class FullTranslationCapsule extends ConsumerWidget {
  const FullTranslationCapsule({
    super.key,
    required this.studySetId,
    required this.documentId,
    required this.targetLang,
  });

  final String studySetId;
  final String documentId;
  final String targetLang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final l = context.l10n;
    final state = ref.watch(fullTranslationProvider((studySetId, documentId, targetLang)));
    final job = state.job;

    if (job == null) {
      return Semantics(
        button: true,
        label: l.fullTranslationCapsule,
        child: Tooltip(
          message: l.fullTranslationMenu,
          child: GestureDetector(
            onTap: () => showFullTranslationSheet(
              context,
              studySetId: studySetId,
              documentId: documentId,
              targetLang: targetLang,
            ),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: c.quaternaryFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(MMIcons.layers, size: 12, color: c.secondaryLabel),
                  const SizedBox(width: 4),
                  Text(
                    l.fullTranslationCapsule,
                    style: context.mmText.footnote.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final counts = state.counts();
    final pct = counts.pct;
    final pagesDone = counts.pagesDone;
    final pagesTotal = counts.pagesTotal;
    final fail = counts.fail;

    Color bg = c.quaternaryFill;
    Widget leading = const SizedBox.shrink();
    String text = '';
    String semanticLabel = '';

    switch (job.state) {
      case TranslationJobState.running:
        bg = c.quaternaryFill;
        leading = SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            value: pct > 0 ? (pct / 100).clamp(0.0, 1.0) : null,
            strokeWidth: 1.5,
            color: c.accent,
          ),
        );
        text = job.mode == TranslationMode.batch
            ? l.fullTranslationCapsuleRunning(pct, job.batch.index, pagesDone, pagesTotal)
            : l.fullTranslationCapsuleRunningAll(pct, pagesDone, pagesTotal);
        semanticLabel = l.fullTranslationCapsuleA11y(pct, job.batch.index, pagesDone, pagesTotal);
        break;
      case TranslationJobState.review:
        bg = c.accentTint;
        leading = Icon(MMIcons.check, size: 12, color: c.accent);
        text = l.fullTranslationCapsuleReview(job.batch.index);
        semanticLabel = text;
        break;
      case TranslationJobState.paused:
        bg = c.quaternaryFill;
        leading = Icon(MMIcons.pause, size: 12, color: c.secondaryLabel);
        text = l.fullTranslationCapsulePaused(pagesDone, pagesTotal);
        semanticLabel = text;
        break;
      case TranslationJobState.offline:
        bg = c.caution.withValues(alpha: 0.09);
        leading = Icon(MMIcons.wifiOff, size: 12, color: c.caution);
        text = l.fullTranslationCapsuleOffline;
        semanticLabel = text;
        break;
      case TranslationJobState.budget:
        bg = c.caution.withValues(alpha: 0.09);
        leading = Icon(MMIcons.warning, size: 12, color: c.caution);
        text = l.fullTranslationCapsuleBudget;
        semanticLabel = text;
        break;
      case TranslationJobState.error:
        bg = c.critical.withValues(alpha: 0.08);
        leading = Icon(MMIcons.warning, size: 12, color: c.critical);
        text = l.fullTranslationCapsuleError;
        semanticLabel = text;
        break;
      case TranslationJobState.done:
        if (fail > 0) {
          bg = c.caution.withValues(alpha: 0.09);
          leading = Icon(MMIcons.check, size: 12, color: c.caution);
          text = l.fullTranslationCapsuleDoneFailed(fail);
        } else {
          bg = c.positive.withValues(alpha: 0.10);
          leading = Icon(MMIcons.check, size: 12, color: c.positive);
          text = l.fullTranslationCapsuleDone;
        }
        semanticLabel = text;
        break;
      case TranslationJobState.stopped:
        bg = c.quaternaryFill;
        leading = Icon(MMIcons.stop, size: 12, color: c.secondaryLabel);
        text = l.fullTranslationCapsuleStopped(pagesDone, pagesTotal);
        semanticLabel = text;
        break;
    }

    return Semantics(
      button: true,
      label: semanticLabel.isNotEmpty ? semanticLabel : text,
      child: Builder(
        builder: (capsuleContext) => GestureDetector(
          key: const ValueKey('full-translation-capsule'),
          onTap: () => showFullTranslationPanel(
            capsuleContext,
            studySetId: studySetId,
            documentId: documentId,
            targetLang: targetLang,
          ),
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: 5),
                Text(
                  text,
                  style: context.mmText.footnote.copyWith(
                    fontWeight: FontWeight.w500,
                    color: job.state == TranslationJobState.offline ||
                            job.state == TranslationJobState.budget
                        ? c.caution
                        : job.state == TranslationJobState.error
                        ? c.critical
                        : (job.state == TranslationJobState.done && fail == 0)
                        ? c.positive
                        : c.label,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
