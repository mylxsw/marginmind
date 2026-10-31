import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../../app/providers.dart';
import '../full_translation.dart';
import '../reader_compare.dart';
import '../workspace_controller.dart';
import 'notices.dart';
import 'full_translation_sheet.dart';

Future<void> showFullTranslationPanel(
  BuildContext context, {
  required String studySetId,
  required String documentId,
  required String targetLang,
}) async {
  final renderBox = context.findRenderObject() as RenderBox?;
  final offset = renderBox?.localToGlobal(Offset.zero);
  final size = renderBox?.size;

  final media = MediaQuery.sizeOf(context);
  final panelWidth = math.min(MMSizes.fullTranslationPanelWidth, math.max(1.0, media.width - 32));
  double left = offset != null ? offset.dx - (panelWidth - (size?.width ?? 0)) / 2 : (media.width - panelWidth) / 2;
  left = left.clamp(16.0, media.width - panelWidth - 16.0);
  final double top = (offset != null && (size?.height ?? 0) < 80 ? offset.dy + (size?.height ?? 0) + 8 : 80.0).clamp(
    16.0,
    math.max(16.0, media.height - 420),
  );

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (dialogContext, _, _) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => Navigator.of(dialogContext).pop()),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: math.max(1, media.height - top - 16)),
                child: SingleChildScrollView(
                  child: FullTranslationPanel(studySetId: studySetId, documentId: documentId, targetLang: targetLang),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class FullTranslationPanel extends ConsumerStatefulWidget {
  const FullTranslationPanel({super.key, required this.studySetId, required this.documentId, required this.targetLang});

  final String studySetId;
  final String documentId;
  final String targetLang;

  @override
  ConsumerState<FullTranslationPanel> createState() => _FullTranslationPanelState();
}

class _FullTranslationPanelState extends ConsumerState<FullTranslationPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    final state = ref.watch(fullTranslationProvider((widget.studySetId, widget.documentId, widget.targetLang)));
    final controller = ref.read(
      fullTranslationProvider((widget.studySetId, widget.documentId, widget.targetLang)).notifier,
    );
    final job = state.job;
    if (job == null) return const SizedBox.shrink();

    final counts = state.counts();
    final documentPages =
        ref.watch(workspaceContentProvider(widget.studySetId))?.document(widget.documentId)?.pageCount ?? 0;
    final pageCount = math.max(state.pageCount, documentPages);
    final currentReading = state.currentReadingPage ?? 1;

    String stateLine = '';
    switch (job.state) {
      case TranslationJobState.running:
        stateLine = job.mode == TranslationMode.batch
            ? l.fullTranslationStateRunningBatch(job.batch.index, job.batch.range.from, job.batch.range.to)
            : l.fullTranslationStateRunningAll;
        break;
      case TranslationJobState.review:
        stateLine = l.fullTranslationStateReview(job.batch.index);
        break;
      case TranslationJobState.paused:
        stateLine = l.fullTranslationStatePaused;
        break;
      case TranslationJobState.offline:
        stateLine = l.fullTranslationStateOffline;
        break;
      case TranslationJobState.budget:
        stateLine = l.fullTranslationStateBudget;
        break;
      case TranslationJobState.error:
        stateLine = l.fullTranslationStateError;
        break;
      case TranslationJobState.done:
        stateLine = l.fullTranslationStateDone;
        break;
      case TranslationJobState.stopped:
        stateLine = l.fullTranslationStateStopped;
        break;
    }

    final elapsedSeconds = math.max(0, ref.read(clockProvider)().toUtc().difference(job.createdAt).inSeconds);
    final elapsedMinutes = elapsedSeconds ~/ 60;
    final elapsedRemainingSeconds = elapsedSeconds % 60;

    final isLive = job.state == TranslationJobState.running || job.state == TranslationJobState.offline;
    final isPausedOrError =
        job.state == TranslationJobState.paused ||
        job.state == TranslationJobState.budget ||
        job.state == TranslationJobState.error;

    return MMGlass(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      shadows: c.sheetShadow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.fullTranslationPanelTitle,
                    style: context.mmText.callout.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${job.sourceLang == 'zh' || (job.sourceLang == null && widget.targetLang == 'en') ? l.languageCodeZh : l.languageCodeEn} → ${widget.targetLang == "zh" ? l.languageCodeZh : l.languageCodeEn}',
                    style: DefaultTextStyle.of(context).style
                        .merge(context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                  ),
                ],
              ),
              Text(stateLine, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
            ],
          ),
          const SizedBox(height: 12),
          _buildGrid(context, state, controller, pageCount, currentReading, c, l),
          const SizedBox(height: 10),
          _buildLegend(context, c, l),
          const SizedBox(height: 12),
          _buildStats(context, counts, job, c, l),
          const SizedBox(height: 12),
          _buildDetails(context, state, counts, job, elapsedMinutes, elapsedRemainingSeconds, c, l),
          const SizedBox(height: 14),
          _buildActions(context, controller, job, counts, isLive, isPausedOrError, c, l),
        ],
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    FullTranslationState state,
    FullTranslationController controller,
    int pageCount,
    int currentReading,
    MMColors c,
    AppLocalizations l,
  ) {
    final job = state.job!;
    final cells = <Widget>[];
    final pages = state.pageStates;

    for (var p = 1; p <= pageCount; p++) {
      final pageNum = p;
      final ps = pages[pageNum] ?? TranslationPageState.skipped;
      final inRange = state.inRange(pageNum);
      final isBatchBoundary =
          job.mode == TranslationMode.batch &&
          inRange &&
          (pageNum - job.range.from) % job.batchSize == 0 &&
          pageNum != job.range.from;
      final isCurrent = pageNum == currentReading;

      String pageStateLabel = switch (ps) {
        TranslationPageState.done => l.fullTranslationLegendDone,
        TranslationPageState.reused => l.fullTranslationLegendReused,
        TranslationPageState.running => l.fullTranslationLegendRunning,
        TranslationPageState.queued => l.fullTranslationLegendQueued,
        TranslationPageState.failed || TranslationPageState.partial => l.fullTranslationLegendFailed,
        TranslationPageState.skipped => l.fullTranslationLegendSkipped,
        TranslationPageState.none => l.fullTranslationPlaceholderUntranslated,
      };

      cells.add(
        Semantics(
          button: true,
          label: l.fullTranslationGridCell(pageNum, pageStateLabel),
          child: Tooltip(
            message: l.fullTranslationGridCell(pageNum, pageStateLabel),
            child: GestureDetector(
              onTap: () {
                final pdf = ref.read(readerCompareProvider(widget.studySetId).notifier).pdf(widget.documentId);
                pdf.jumpToPage(pageNum);
                controller.setCurrentReadingPage(pageNum);
              },
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Opacity(
                    opacity: inRange ? 1.0 : 0.35,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2.5),
                        border: Border(
                          left: isBatchBoundary ? BorderSide(color: c.label, width: 2.0) : BorderSide.none,
                        ),
                      ),
                      child: _buildCellContent(ps, c),
                    ),
                  ),
                  if (isCurrent)
                    Positioned(
                      bottom: -5,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 16,
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      childAspectRatio: 3 / 4,
      children: cells,
    );
  }

  Widget _buildCellContent(TranslationPageState ps, MMColors c) {
    switch (ps) {
      case TranslationPageState.done:
        return Container(
          decoration: BoxDecoration(color: c.positive, borderRadius: BorderRadius.circular(2.5)),
        );
      case TranslationPageState.reused:
        return Container(
          decoration: BoxDecoration(
            color: c.positive.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(2.5),
          ),
        );
      case TranslationPageState.running:
        return AnimatedBuilder(
          animation: _breathe,
          builder: (context, _) => Container(
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.6 + 0.4 * _breathe.value),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        );
      case TranslationPageState.queued:
        return Container(
          decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(2.5)),
        );
      case TranslationPageState.failed:
        return Container(
          decoration: BoxDecoration(color: c.critical, borderRadius: BorderRadius.circular(2.5)),
        );
      case TranslationPageState.partial:
        return ClipRRect(
          borderRadius: BorderRadius.circular(2.5),
          child: Column(
            children: [
              Expanded(child: Container(color: c.positive)),
              Expanded(child: Container(color: c.critical)),
            ],
          ),
        );
      case TranslationPageState.skipped:
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2.5),
            border: Border.all(color: c.hairline, width: 1),
          ),
        );
      case TranslationPageState.none:
        return Container(
          decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(2.5)),
        );
    }
  }

  Widget _buildLegend(BuildContext context, MMColors c, AppLocalizations l) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _legendItem(c.positive, l.fullTranslationLegendDone, c, context),
        _legendItem(c.positive.withValues(alpha: 0.55), l.fullTranslationLegendReused, c, context),
        _legendItem(c.accent, l.fullTranslationLegendRunning, c, context),
        _legendItem(c.accent.withValues(alpha: 0.22), l.fullTranslationLegendQueued, c, context),
        _legendItem(c.critical, l.fullTranslationLegendFailed, c, context),
        _legendItem(Colors.transparent, l.fullTranslationLegendSkipped, c, context, border: true),
      ],
    );
  }

  Widget _legendItem(Color color, String text, MMColors c, BuildContext context, {bool border = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: border ? Border.all(color: c.secondaryLabel, width: 1) : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(text, style: context.mmText.footnote.copyWith(fontSize: 10.5, color: c.secondaryLabel)),
      ],
    );
  }

  Widget _buildStats(
    BuildContext context,
    FullTranslationCounts counts,
    TranslationJob job,
    MMColors c,
    AppLocalizations l,
  ) {
    return Row(
      children: [
        Expanded(
          child: _statBox(
            context,
            richValue: Text.rich(
              TextSpan(
                style: DefaultTextStyle.of(context).style
                    .merge(context.mmText.callout.copyWith(fontWeight: FontWeight.w700, color: c.label)),
                children: [
                  TextSpan(text: '${counts.done}'),
                  TextSpan(
                    text: ' / ${counts.total}',
                    style: context.mmText.footnote.copyWith(color: c.secondaryLabel, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
            label: l.fullTranslationStatParas,
            c: c,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _statBox(
            context,
            richValue: Text.rich(
              TextSpan(
                style: DefaultTextStyle.of(context).style
                    .merge(context.mmText.callout.copyWith(fontWeight: FontWeight.w700, color: c.label)),
                children: [
                  TextSpan(text: formatTokens(job.usage.totalTokens)),
                  TextSpan(
                    text: ' token',
                    style: context.mmText.footnote.copyWith(color: c.secondaryLabel, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
            label: l.fullTranslationStatEstToken(formatTokens(job.estimateTokens)),
            c: c,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _statBox(
            context,
            richValue: Text(
              '${counts.fail}',
              style: context.mmText.callout.copyWith(
                fontWeight: FontWeight.w700,
                color: counts.fail > 0 ? c.critical : c.label,
              ),
            ),
            label: l.fullTranslationStatFailed,
            c: c,
          ),
        ),
      ],
    );
  }

  Widget _statBox(BuildContext context, {required Widget richValue, required String label, required MMColors c}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          richValue,
          const SizedBox(height: 2),
          Text(label, style: context.mmText.footnote.copyWith(fontSize: 10.5, color: c.secondaryLabel)),
        ],
      ),
    );
  }

  Widget _buildDetails(
    BuildContext context,
    FullTranslationState state,
    FullTranslationCounts counts,
    TranslationJob job,
    int minutes,
    int seconds,
    MMColors c,
    AppLocalizations l,
  ) {
    var skippedCount = 0;
    for (final p in state.paragraphs) {
      if (state.inRange(p.page) && translationSkipReason(p, widget.targetLang) != null) {
        skippedCount++;
      }
    }

    return Column(
      children: [
        _detailRow(l.fullTranslationDetailReused, l.fullTranslationDetailParas(counts.reused), c, context),
        const SizedBox(height: 4),
        _detailRow(
          l.fullTranslationDetailDedup,
          l.fullTranslationDetailParas(math.max(0, counts.done - counts.reused - job.usage.requests)),
          c,
          context,
        ),
        const SizedBox(height: 4),
        _detailRow(l.fullTranslationDetailSkipped, l.fullTranslationDetailItems(skippedCount), c, context),
        const SizedBox(height: 4),
        _detailRow(
          l.fullTranslationDetailModelCalls,
          l.fullTranslationDetailCalls(job.model.isNotEmpty ? job.model : 'AI', job.usage.requests),
          c,
          context,
        ),
        const SizedBox(height: 4),
        _detailRow(l.fullTranslationDetailElapsed, l.fullTranslationDetailTime(minutes, seconds), c, context),
      ],
    );
  }

  Widget _detailRow(String label, String value, MMColors c, BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: context.mmText.footnote.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(
    BuildContext context,
    FullTranslationController controller,
    TranslationJob job,
    FullTranslationCounts counts,
    bool isLive,
    bool isPausedOrError,
    MMColors c,
    AppLocalizations l,
  ) {
    if (isLive) {
      return Row(
        children: [
          MMButton(label: l.fullTranslationActionStop, color: c.critical, onPressed: () => controller.stop()),
          const Spacer(),
          MMButton(icon: MMIcons.pause, label: l.fullTranslationActionPause, onPressed: () => controller.pause()),
        ],
      );
    }

    if (isPausedOrError) {
      return Row(
        children: [
          MMButton(label: l.fullTranslationActionStop, color: c.critical, onPressed: () => controller.stop()),
          const Spacer(),
          MMButton(
            icon: MMIcons.play,
            label: l.fullTranslationActionResume,
            variant: MMButtonVariant.primary,
            onPressed: () => controller.resume(),
          ),
        ],
      );
    }

    if (job.state == TranslationJobState.review) {
      return Row(
        children: [
          MMButton(label: l.fullTranslationActionEnd, color: c.critical, onPressed: () => controller.stop()),
          const Spacer(),
          MMButton(
            label: l.fullTranslationActionNextBatch,
            variant: MMButtonVariant.primary,
            onPressed: () => controller.continueBatch(),
          ),
        ],
      );
    }

    return Row(
      children: [
        MMButton(
          label: l.fullTranslationActionClear,
          onPressed: () async {
            final ok = await showConfirmSheet(
              context,
              title: l.fullTranslationClearTitle,
              message: l.fullTranslationClearMessage,
              confirmLabel: l.remove,
            );
            if (ok && context.mounted) {
              final nav = Navigator.of(context);
              await controller.removeTranslations();
              if (nav.mounted) {
                nav.pop();
                MMHud.show(nav.context, l.translationRemoved);
              }
            }
          },
        ),
        const Spacer(),
        if (counts.fail > 0)
          MMButton(
            icon: MMIcons.retry,
            label: l.fullTranslationActionRetryFailed(counts.fail),
            onPressed: () => controller.retry(),
          ),
        if (job.state == TranslationJobState.stopped)
          MMButton(
            label: l.fullTranslationActionContinueTranslation,
            variant: MMButtonVariant.primary,
            onPressed: () {
              final navigator = Navigator.of(context);
              final ownerContext = navigator.context;
              navigator.pop();
              showFullTranslationSheet(
                ownerContext,
                studySetId: widget.studySetId,
                documentId: widget.documentId,
                targetLang: widget.targetLang,
              );
            },
          ),
      ],
    );
  }
}
