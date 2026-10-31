import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../map_generation_controller.dart';

String mapGenerationFailureSummary(AppLocalizations l, ResearchFailure? failure) {
  if (failure?.code == 'secret_store') return l.assistantSavedKeyUnavailable;
  if (failure?.code == 'missingModel') return l.assistantSetupHint;
  if (failure?.code == 'missingKey') return l.assistantKeyNeedsAttention;
  if (failure?.code == 'outputTruncated') return l.mapFailureTruncated;
  if (failure?.code == 'noDocumentText') return l.mapFailureDocumentText;
  if (failure?.code == 'noValidMapContent') {
    return failure is MapGenerationFailure && failure.receivedLines == 0 ? l.mapFailureEmpty : l.mapFailureInvalid;
  }
  return switch (failure?.kind) {
    ResearchFailureKind.network => l.assistantErrorNetwork,
    ResearchFailureKind.authentication => l.assistantErrorKey,
    ResearchFailureKind.timeout => l.mapFailureTimeout,
    ResearchFailureKind.budget => l.mapFailureLimit,
    ResearchFailureKind.rateLimited => l.mapFailureRate,
    ResearchFailureKind.invalidRequest => l.mapFailureRequest,
    ResearchFailureKind.refusal => l.assistantErrorRefused,
    ResearchFailureKind.unavailable => l.assistantErrorService,
    ResearchFailureKind.protocol || ResearchFailureKind.toolProtocol => l.mapFailureInvalid,
    _ => l.assistantErrorFailed,
  };
}

String _rejectionLabel(AppLocalizations l, String code) => switch (code) {
  'invalidJson' || 'invalidObject' => l.mapFailureInvalidJson,
  'invalidOperation' || 'unexpectedKeys' || 'missingReason' => l.mapFailureFields,
  'invalidReference' => l.mapFailureReference,
  'invalidTitle' || 'duplicateTitle' => l.mapFailureTitle,
  'invalidParent' || 'unknownParent' || 'unknownNode' => l.mapFailureParent,
  'depthExceeded' => l.mapFailureDepth,
  'invalidAnnotation' => l.mapFailureAnnotation,
  'invalidSource' => l.mapFailureSource,
  'protectedNode' => l.mapFailureProtected,
  'lineSize' => l.mapFailureLineSize,
  _ => l.mapFailureInvalid,
};

/// Only fixed codes, model identifiers and counts enter this report.
/// Provider bodies and source/model text may contain credentials or document data.
String mapGenerationFailureReport(AppLocalizations l, MapGenerationPreview preview) {
  String describe(ResearchFailure failure) {
    final rows = <String>[
      mapGenerationFailureSummary(l, failure),
      '${l.mapFailureCode}: ${failure.kind.name}${failure.code == null ? '' : ' / ${failure.code}'}',
      if (failure.statusCode != null) 'HTTP: ${failure.statusCode}',
    ];
    if (failure is MapGenerationFailure) {
      rows.addAll([
        '${l.mapFailureStage}: ${switch (failure.phase) {
          MapLinePhase.chapter => l.mapFailureChapter,
          MapLinePhase.generation => l.mapFailureBuild,
          MapLinePhase.diff => l.mapFailureUpdate,
        }}',
        '${l.mapFailureModel}: ${failure.model}',
        '${l.mapFailureLines}: ${failure.receivedLines} / ${failure.acceptedLines}',
        if (failure.stopReason != null) '${l.mapFailureStop}: ${failure.stopReason}',
        '${l.mapFailureReasoning}: ${failure.reasoningCharacters}',
        for (final entry in failure.rejections.entries)
          '${l.mapFailureRejected}: ${_rejectionLabel(l, entry.key)} (${entry.key}) × ${entry.value}',
      ]);
    } else {
      rows.add(
        '${l.mapFailureStage}: ${preview.chapterFailures.isNotEmpty ? l.mapFailureChapter : l.mapFailurePrepare}',
      );
    }
    return rows.join('\n');
  }

  return [
    if (preview.failure != null) describe(preview.failure!),
    for (final entry in preview.chapterFailures.entries)
      '${preview.skeletons.where((s) => s.id == entry.key).firstOrNull?.title ?? l.mapFailureChapter}\n${describe(entry.value)}',
  ].join('\n\n');
}

String _failureStage(AppLocalizations l, MapGenerationPreview preview, ResearchFailure failure) =>
    failure is MapGenerationFailure
    ? switch (failure.phase) {
        MapLinePhase.chapter => l.mapFailureChapter,
        MapLinePhase.generation => l.mapFailureBuild,
        MapLinePhase.diff => l.mapFailureUpdate,
      }
    : preview.chapterFailures.isNotEmpty
    ? l.mapFailureChapter
    : l.mapFailurePrepare;

Future<void> showMapGenerationFailure(BuildContext context, MapGenerationPreview preview) => showMMDialog<void>(
  context: context,
  builder: (_) => _MapFailureDialog(preview: preview),
);

class _MapFailureDialog extends StatefulWidget {
  const _MapFailureDialog({required this.preview});
  final MapGenerationPreview preview;

  @override
  State<_MapFailureDialog> createState() => _MapFailureDialogState();
}

class _MapFailureDialogState extends State<_MapFailureDialog> {
  final _scroll = ScrollController();
  bool _copied = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: mapGenerationFailureReport(context.l10n, widget.preview)));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors, t = context.mmText, l = context.l10n;
    final preview = widget.preview;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final failures = <({String title, ResearchFailure failure})>[
      if (preview.failure case final failure?) (title: _failureStage(l, preview, failure), failure: failure),
      for (final entry in preview.chapterFailures.entries)
        (
          title: preview.skeletons.where((s) => s.id == entry.key).firstOrNull?.title ?? l.mapFailureChapter,
          failure: entry.value,
        ),
    ];
    final bottomSheet = MMBottomSheet.contains(context);
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * .82),
        child: Container(
          key: const ValueKey('map-generation-failure-dialog'),
          padding: const EdgeInsets.all(22),
          decoration: bottomSheet
              ? null
              : BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(MMRadii.sheet),
                  border: Border.all(color: c.hairline, width: .5),
                  boxShadow: c.sheetShadow,
                ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.critical.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(MMIcons.warning, size: 18, color: c.critical),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text(l.mapFailureDialogTitle, style: t.title3)),
                        if (preview.request.title.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            preview.request.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.callout.copyWith(color: c.secondaryLabel),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Flexible(
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, entry) in failures.indexed) ...[
                            if (i > 0) const SizedBox(height: 12),
                            _FailureSection(
                              key: ValueKey('map-generation-failure-$i'),
                              title: entry.title,
                              failure: entry.failure,
                              stage: _failureStage(l, preview, entry.failure),
                              index: i,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Divider(height: 1, thickness: .5, color: c.separator),
              const SizedBox(height: 16),
              Flex(
                direction: largeText ? Axis.vertical : Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: largeText ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                children: [
                  Flexible(
                    flex: largeText ? 0 : 1,
                    child: Semantics(
                      liveRegion: true,
                      child: MMButton(
                        key: const ValueKey('map-generation-copy-error-button'),
                        label: _copied ? l.copiedHud : l.mapFailureCopy,
                        icon: _copied ? MMIcons.check : MMIcons.copy,
                        variant: MMButtonVariant.secondary,
                        onPressed: _copy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10, height: 10),
                  MMButton(
                    key: const ValueKey('map-generation-close-error-button'),
                    label: l.closePanel,
                    variant: MMButtonVariant.primary,
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureSection extends StatefulWidget {
  const _FailureSection({
    super.key,
    required this.title,
    required this.failure,
    required this.stage,
    required this.index,
  });
  final String title, stage;
  final ResearchFailure failure;
  final int index;

  @override
  State<_FailureSection> createState() => _FailureSectionState();
}

class _FailureSectionState extends State<_FailureSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors, t = context.mmText, l = context.l10n;
    final failure = widget.failure;
    final details = <(String, String)>[
      (l.mapFailureCode, '${failure.kind.name}${failure.code == null ? '' : ' / ${failure.code}'}'),
      if (failure.statusCode != null) ('HTTP', '${failure.statusCode}'),
      if (failure is MapGenerationFailure) ...[
        (l.mapFailureModel, failure.model),
        (l.mapFailureLines, '${failure.receivedLines} / ${failure.acceptedLines}'),
        if (failure.stopReason != null) (l.mapFailureStop, failure.stopReason!),
        if (failure.reasoningCharacters > 0) (l.mapFailureReasoning, '${failure.reasoningCharacters}'),
        for (final rejection in failure.rejections.entries)
          (l.mapFailureRejected, '${_rejectionLabel(l, rejection.key)} · ${rejection.key} × ${rejection.value}'),
      ],
    ];
    return DecoratedBox(
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(widget.title, style: t.callout.copyWith(color: c.secondaryLabel)),
            ),
            const SizedBox(height: 8),
            Text(
              mapGenerationFailureSummary(l, failure),
              style: t.body.copyWith(fontWeight: FontWeight.w600, height: 1.5),
            ),
            const SizedBox(height: 14),
            _FailureRow(label: l.mapFailureStage, value: widget.stage),
            if (failure is MapGenerationFailure) ...[
              const SizedBox(height: 8),
              _FailureRow(label: l.mapFailureModel, value: failure.model, truncate: true),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                expanded: _expanded,
                child: MMButton(
                  key: ValueKey('map-generation-diagnostics-${widget.index}'),
                  label: l.mapFailureDiagnostics,
                  icon: _expanded ? MMIcons.chevronDown : MMIcons.chevronRight,
                  variant: MMButtonVariant.plain,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Divider(height: 1, thickness: .5, color: c.separator),
              const SizedBox(height: 14),
              for (final (i, row) in details.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                _FailureRow(label: row.$1, value: row.$2, diagnostic: true),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.label, required this.value, this.diagnostic = false, this.truncate = false});
  final String label, value;
  final bool diagnostic, truncate;

  @override
  Widget build(BuildContext context) {
    final t = context.mmText, c = context.mmColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final labelText = Text(label, style: t.footnote.copyWith(color: c.secondaryLabel, height: 1.5));
        final valueText = Text(
          value,
          maxLines: truncate ? 2 : null,
          overflow: truncate ? TextOverflow.ellipsis : TextOverflow.clip,
          style: diagnostic
              ? MMTypography.mono.copyWith(
                  fontSize: 11,
                  color: c.label,
                  height: 1.5,
                  fontFamilyFallback: ['PingFang SC', ...?MMTypography.mono.fontFamilyFallback],
                )
              : t.callout.copyWith(height: 1.5),
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 3), valueText],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 168, child: labelText),
                  const SizedBox(width: 12),
                  Expanded(child: valueText),
                ],
              );
      },
    );
  }
}
