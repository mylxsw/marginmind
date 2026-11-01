import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import 'model_route_picker.dart';

/// Shared, presentation-only pieces for AI features: the short reason a model
/// cannot run, a run's state capsule and the models a run actually used.
/// Task setup panels, error cards and run panels render resolver/runtime
/// results with these; none of them decides capability or matches names.

/// What a feature calls itself in settings, menus and run lists.
String aiTaskName(AppLocalizations l, TaskType type) => switch (type) {
  TaskType.selectionTranslate => l.aiTaskSelectionTranslate,
  TaskType.wordLookup => l.aiTaskWordLookup,
  TaskType.titleGenerate => l.aiTaskTitleGenerate,
  TaskType.assistantChat => l.aiTaskAssistantChat,
  TaskType.conversationSummarize => l.aiTaskConversationSummarize,
  TaskType.documentSummarize => l.aiTaskDocumentSummarize,
  TaskType.documentTranslate => l.aiTaskDocumentTranslate,
  TaskType.mapExpand => l.aiTaskMapExpand,
  TaskType.mapGenerate => l.aiTaskMapGenerate,
  TaskType.research => l.aiTaskResearch,
  TaskType.studyNotes => l.aiTaskStudyNotes,
  TaskType.reviewCards => l.aiTaskReviewCards,
};

/// The row/panel phrase for a resolver issue; null when there is nothing to
/// say (ready, or no model yet — the placeholder already says so).
String? routingIssueText(AppLocalizations l, RoutingIssue issue, {String? failureCode}) => switch (issue) {
  RoutingIssue.none || RoutingIssue.unset => null,
  RoutingIssue.deleted => l.aiTasksIssueDeleted,
  RoutingIssue.modelOff => l.aiTasksIssueModelOff,
  RoutingIssue.serviceOff => l.aiTasksIssueServiceOff,
  RoutingIssue.serviceRemoved => l.aiTasksIssueServiceRemoved,
  RoutingIssue.secretUnavailable => l.aiTasksIssueConnection,
  RoutingIssue.thinkingAlwaysOn => l.aiTasksIssueThinking,
  RoutingIssue.unknown => null,
  RoutingIssue.invalidConfiguration => l.aiTasksIssueInvalid,
  RoutingIssue.capabilityMissing => switch (failureCode?.split(':').first) {
    'tools' => l.aiTasksIssueTools,
    'structuredOutput' => l.aiTasksIssueStructured,
    'context' => l.aiTasksIssueContext,
    _ => l.aiTasksIssueUnsupported,
  },
};

/// Whether the issue stops the feature until the user changes something.
/// Matches resolver admission: only a ready route can dispatch a task.
bool routingIssueBlocks(RoutingIssue issue) => !{RoutingIssue.none, RoutingIssue.unknown}.contains(issue);

/// Whether a reference no longer resolves to an enabled model.
bool routingIssueInvalid(RoutingIssue issue) =>
    {RoutingIssue.deleted, RoutingIssue.modelOff, RoutingIssue.serviceOff, RoutingIssue.serviceRemoved}.contains(issue);

/// One line under a row: an 11pt warning, the phrase, at most one plain action.
/// Announced when it appears or changes, without taking focus.
class RoutingIssueLine extends StatelessWidget {
  const RoutingIssueLine({
    super.key,
    required this.text,
    this.critical = true,
    this.action,
    this.onAction,
    this.busy = false,
    this.onCancel,
    this.actionKey,
  });

  final String text;
  final bool critical;
  final String? action;
  final VoidCallback? onAction;
  final Key? actionKey;

  /// A running check replaces the action with a spinner; tapping it cancels.
  final bool busy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final color = critical ? c.critical : c.caution;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        children: [
          Icon(MMIcons.warning, size: 11, color: color),
          const SizedBox(width: MMSpacing.xs),
          Expanded(
            child: Text(text, style: t.footnote.copyWith(color: color)),
          ),
          if (busy)
            MMInteractive(
              key: actionKey,
              onTap: onCancel,
              semanticLabel: MaterialLocalizations.of(context).cancelButtonLabel,
              builder: (context, _) =>
                  const SizedBox(width: 24, height: 20, child: Center(child: CupertinoActivityIndicator(radius: 6))),
            )
          else if (action != null)
            MMButton(key: actionKey, label: action!, variant: MMButtonVariant.plain, onPressed: onAction),
        ],
      ),
    );
  }
}

/// The models a run was frozen with, phases joined by “→”, named by the
/// [routeModelLabel] rule. Never the settings' current value.
String runModelsLabel(AssistantServices catalog, List<RunContext> phases) {
  final names = <String>[];
  for (final phase in phases) {
    final name = routeModelLabel(
      catalog,
      phase.config.model,
      serviceLabel: phase.serviceDisplayName.isEmpty ? null : phase.serviceDisplayName,
      modelLabel: phase.modelDisplayName.isEmpty ? null : phase.modelDisplayName,
    );
    if (names.isEmpty || names.last != name) names.add(name);
  }
  return names.join(' → ');
}

/// A run's state as a 24pt capsule, in the full-translation palette.
/// [done]/[total] count the feature's [unit]s (paragraphs, sections, …).
class RunStatusCapsule extends StatelessWidget {
  const RunStatusCapsule({
    super.key,
    required this.status,
    this.done,
    this.total,
    this.unfinished,
    this.unit = '',
    this.progress,
  });

  final RunStatus status;
  final int? done, total, unfinished;
  final String unit;

  /// 0–1 while running; null leaves the ring indeterminate.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final l = context.l10n;
    final counted = done != null && total != null;
    final (String text, Color fill, Color fg, IconData? icon) = switch (status) {
      RunStatus.created ||
      RunStatus.validating ||
      RunStatus.running => (progress == null ? '' : '${(progress! * 100).round()}%', c.quaternaryFill, c.label, null),
      RunStatus.awaitingUser => (l.aiTasksRunAwaiting, c.accentTint, c.accent, null),
      RunStatus.paused => (
        counted ? l.aiTasksRunPausedCount(done!, total!) : l.aiTasksRunPaused,
        c.quaternaryFill,
        c.secondaryLabel,
        null,
      ),
      RunStatus.interrupted => (
        counted ? l.aiTasksRunInterruptedCount(done!, total!) : l.aiTasksRunInterrupted,
        c.caution.withValues(alpha: .09),
        c.caution,
        MMIcons.warning,
      ),
      RunStatus.partial => (
        l.aiTasksRunPartial(unfinished ?? 0, unit),
        c.caution.withValues(alpha: .09),
        c.caution,
        MMIcons.warning,
      ),
      RunStatus.failed => (l.aiTasksRunFailed, c.critical.withValues(alpha: .08), c.critical, MMIcons.warning),
      RunStatus.cancelled => (
        counted ? l.aiTasksRunStoppedCount(done!, total!) : l.aiTasksRunStopped,
        c.quaternaryFill,
        c.secondaryLabel,
        null,
      ),
      RunStatus.completed => (l.aiTasksRunCompleted, c.positive.withValues(alpha: .10), c.positive, MMIcons.check),
    };
    final running = {RunStatus.created, RunStatus.validating, RunStatus.running}.contains(status);
    return Semantics(
      label: running ? '${((progress ?? 0) * 100).round()}%' : text,
      excludeSemantics: true,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (running)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(value: progress, strokeWidth: 1.6, color: c.accent),
              )
            else if (icon != null)
              Icon(icon, size: 11, color: fg),
            if (text.isNotEmpty) ...[
              if (running || icon != null) const SizedBox(width: MMSpacing.xs),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.mmText.footnote.copyWith(color: fg, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
