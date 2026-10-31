import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsRole;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../full_translation.dart';
import '../reader_compare.dart';

class FullTranslationCheckpoint extends ConsumerStatefulWidget {
  const FullTranslationCheckpoint({
    super.key,
    required this.studySetId,
    required this.documentId,
    required this.targetLang,
    this.onJumpToPage,
  });

  final String studySetId;
  final String documentId;
  final String targetLang;
  final ValueChanged<int>? onJumpToPage;

  @override
  ConsumerState<FullTranslationCheckpoint> createState() => _FullTranslationCheckpointState();
}

class _FullTranslationCheckpointState extends ConsumerState<FullTranslationCheckpoint> {
  late final TextEditingController _noteController;
  bool _noteOpen = false;
  int _batchSize = 10;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
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

    if (job == null || job.state != TranslationJobState.review) {
      return const SizedBox.shrink();
    }

    if (!_initialized) {
      _initialized = true;
      _batchSize = job.batchSize;
      if (job.note.isNotEmpty) _noteController.text = job.note;
    }

    final bFrom = job.batch.range.from;
    final bTo = job.batch.range.to;
    final nf = bTo + 1;
    final nt = math.min(job.range.to, nf + _batchSize - 1);

    final batchCounts = state.counts(fromPage: bFrom, toPage: bTo);
    final remainEst = estimateFullTranslation(
      paragraphs: state.paragraphs,
      from: nf,
      to: job.range.to,
      targetLang: widget.targetLang,
      values: state.values,
    );

    if (state.checkpointCollapsed) {
      return Semantics(
        container: true,
        role: SemanticsRole.dialog,
        namesRoute: true,
        scopesRoute: true,
        liveRegion: true,
        explicitChildNodes: true,
        label: l.fullTranslationCkptMin(job.batch.index),
        child: MMGlass(
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shadows: c.sheetShadow,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.fullTranslationCkptMin(job.batch.index), style: context.mmText.callout.copyWith(fontSize: 12)),
              const SizedBox(width: 12),
              MMButton(
                label: l.fullTranslationCkptNextBatch(nf, nt),
                variant: MMButtonVariant.primary,
                onPressed: () => controller.continueBatch(batchSize: _batchSize, note: _noteController.text),
              ),
              const SizedBox(width: 6),
              MMIconButton(
                icon: MMIcons.chevronDown,
                tooltip: l.fullTranslationCkptExpandTip,
                onPressed: () => controller.setCheckpointCollapsed(false),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      role: SemanticsRole.dialog,
      namesRoute: true,
      scopesRoute: true,
      liveRegion: true,
      explicitChildNodes: true,
      label: l.fullTranslationCkptBatchDone(job.batch.index),
      child: MMGlass(
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        shadows: c.sheetShadow,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: c.accentTint, shape: BoxShape.circle),
                  child: Center(child: Icon(MMIcons.check, size: 12, color: c.accent)),
                ),
                const SizedBox(width: 8),
                Text(
                  l.fullTranslationCkptBatchDone(job.batch.index),
                  style: context.mmText.callout.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Text(
                  l.fullTranslationCkptPages(bFrom, bTo),
                  style: DefaultTextStyle.of(context).style
                      .merge(context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                ),
                const Spacer(),
                MMIconButton(
                  icon: MMIcons.chevronDown,
                  tooltip: l.fullTranslationCkptCollapseTip,
                  onPressed: () => controller.setCheckpointCollapsed(true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _counted(context, l.fullTranslationDetailParas(batchCounts.total), batchCounts.total, c.secondaryLabel),
                if (batchCounts.reused > 0)
                  _counted(
                    context,
                    '${l.fullTranslationLegendReused} ${batchCounts.reused}',
                    batchCounts.reused,
                    c.secondaryLabel,
                  ),
                if (batchCounts.fail > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _counted(context, l.fullTranslationCkptFailed(batchCounts.fail), batchCounts.fail, c.critical),
                      MMButton(
                        label: l.fullTranslationStripRetry,
                        variant: MMButtonVariant.plain,
                        color: c.critical,
                        onPressed: () => controller.retry(),
                      ),
                    ],
                  ),
                Text.rich(
                  TextSpan(
                    style: DefaultTextStyle.of(context).style
                        .merge(context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                    children: [
                      TextSpan(text: l.fullTranslationTokensUsed),
                      TextSpan(
                        text: formatTokens(job.usage.totalTokens),
                        style: TextStyle(fontWeight: FontWeight.w700, color: c.label),
                      ),
                      const TextSpan(text: ' token'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () {
                  widget.onJumpToPage?.call(bFrom);
                  final pdf = ref.read(readerCompareProvider(widget.studySetId).notifier).pdf(widget.documentId);
                  pdf.jumpToPage(bFrom);
                  controller.setCheckpointCollapsed(true);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(MMIcons.chevronRight, size: 12, color: c.accent),
                    const SizedBox(width: 4),
                    Text(l.fullTranslationCkptFromPage(bFrom), style: context.mmText.callout.copyWith(color: c.accent)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _noteOpen = !_noteOpen),
              child: Row(
                children: [
                  Icon(_noteOpen ? MMIcons.chevronDown : MMIcons.chevronRight, size: 12, color: c.secondaryLabel),
                  const SizedBox(width: 4),
                  Text(
                    '${l.fullTranslationNote}${_noteController.text.isNotEmpty ? l.fullTranslationNoteConfigured : ""}',
                    style: context.mmText.callout.copyWith(color: c.label),
                  ),
                ],
              ),
            ),
            if (_noteOpen) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                maxLines: 2,
                maxLength: 1000,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                style: context.mmText.callout.copyWith(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: l.fullTranslationNotePlaceholder,
                  hintStyle: context.mmText.callout.copyWith(fontSize: 12.5, color: c.secondaryLabel),
                  filled: true,
                  fillColor: c.quaternaryFill,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.fullTranslationNoteHint,
                style: context.mmText.footnote.copyWith(fontSize: 11, color: c.secondaryLabel),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(l.fullTranslationBatchSize, style: context.mmText.callout),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MMSegmentedControl<int>(
                        value: _batchSize,
                        onChanged: (val) => setState(() => _batchSize = val),
                        segments: [
                          for (final s in [5, 10, 20, 50]) MMSegment(value: s, label: l.fullTranslationBatchPages(s)),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  l.fullTranslationCkptRemain(job.range.to - bTo, formatTokens(remainEst.tokens)),
                  style: context.mmText.footnote.copyWith(fontSize: 11, color: c.secondaryLabel),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                MMButton(
                  label: l.fullTranslationActionEnd,
                  onPressed: () {
                    controller.stop();
                  },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MMButton(
                      label: l.fullTranslationCkptTranslateRest,
                      onPressed: () {
                        controller.continueBatch(all: true, note: _noteController.text, batchSize: _batchSize);
                      },
                    ),
                    MMButton(
                      label: l.fullTranslationCkptNextBatch(nf, nt),
                      variant: MMButtonVariant.primary,
                      onPressed: () => controller.continueBatch(batchSize: _batchSize, note: _noteController.text),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Secondary text with its count in the label color, as in "30 段".
  Widget _counted(BuildContext context, String text, int count, Color color) {
    final c = context.mmColors;
    final number = '$count';
    final at = text.indexOf(number);
    final base = DefaultTextStyle.of(context).style.merge(context.mmText.footnote.copyWith(color: color));
    final strong = TextStyle(
      fontWeight: FontWeight.w600,
      color: color == c.critical ? c.critical : c.label,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (at < 0) return Text(text, style: base);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(text: number, style: strong),
          TextSpan(text: text.substring(at + number.length)),
        ],
      ),
    );
  }
}
