import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';

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

Future<void> showMapGenerationFailure(BuildContext context, MapGenerationPreview preview) {
  final l = context.l10n;
  final report = mapGenerationFailureReport(l, preview);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.mapFailureDetails),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .6),
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('map-generation-copy-error-button'),
          onPressed: () => Clipboard.setData(ClipboardData(text: report)),
          child: Text(l.mapFailureCopy),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.closePanel)),
      ],
    ),
  );
}
