import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';
import '../assistant_settings.dart';
import 'assistant_markdown.dart';
import 'assistant_overlays.dart';
import 'assistant_proposal.dart';

/// The conversation: questions and answers, following new text while the
/// list is at its end.
class AssistantMessageList extends ConsumerStatefulWidget {
  const AssistantMessageList({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<AssistantMessageList> createState() => _AssistantMessageListState();
}

class _AssistantMessageListState extends ConsumerState<AssistantMessageList> {
  final _scroll = ScrollController();

  /// Scrolled up more than this, new text no longer pulls the list down.
  static const _follow = 80.0;
  bool _following = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _following = _scroll.position.maxScrollExtent - _scroll.offset <= _follow;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(assistantControllerProvider);
    ref.listen(assistantControllerProvider, (previous, next) {
      final sent = previous == null || next.id != previous.id || next.messages.length != previous.messages.length;
      if (sent) _following = true;
      if (_following) WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd());
    });
    final messages = conversation.messages;
    return SelectionArea(
      child: ListView.builder(
        key: const ValueKey('assistant-messages'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.m, MMSpacing.l, MMSpacing.l),
        itemCount: messages.length,
        itemBuilder: (context, i) {
          final m = messages[i];
          final question = m.role == MessageRole.agent
              ? messages
                    .take(i)
                    .lastWhere((q) => q.role == MessageRole.user && q.requestId == m.requestId, orElse: () => m)
              : m;
          return Padding(
            key: ValueKey(m.id),
            padding: EdgeInsets.only(bottom: i == messages.length - 1 ? 0 : MMSpacing.l),
            child: m.role == MessageRole.user
                ? UserMessage(studySetId: widget.studySetId, message: m)
                : AgentMessage(
                    studySetId: widget.studySetId,
                    message: m,
                    question: question,
                    last: i == messages.length - 1,
                  ),
          );
        },
      ),
    );
  }
}

/// A chip's label for [item] (page and node chips name their target).
String contextLabel(AppLocalizations l, ContextItem item) => switch (item.kind) {
  ContextKind.selection => item.displayText,
  ContextKind.node => l.assistantMapContext(item.displayText),
  ContextKind.branch => l.assistantBranchContext(item.displayText),
  ContextKind.page => l.assistantPageContext(item.displayText, item.page ?? 1),
  ContextKind.document => l.assistantDocumentContext(item.displayText),
  ContextKind.map => l.assistantWholeMap,
};

IconData contextIcon(ContextItem item) => switch (item.kind) {
  ContextKind.selection => MMIcons.highlight,
  ContextKind.page || ContextKind.document => MMIcons.document,
  _ => MMIcons.mindMap,
};

/// Goes to what [item] points at: the passage (flashing) or the node. A HUD
/// says so when it is gone.
Future<void> revealContext(BuildContext context, WidgetRef ref, String studySetId, ContextItem item) async {
  final workspace = ref.read(workspaceProvider(studySetId).notifier);
  final anchor = ref.read(assistantUiProvider(studySetId)).anchors[item.id];
  final SourceAnchor? target = switch (item.kind) {
    ContextKind.selection || ContextKind.page when item.documentId != null =>
      anchor ??
          SourceAnchor(
            target: PdfTarget(
              documentId: item.documentId!,
              pages: [AnnotationPage(page: item.page ?? 1, rects: const [])],
            ),
          ),
    ContextKind.node || ContextKind.branch when item.nodeId != null => SourceAnchor(
      target: CardTarget(cardId: item.nodeId!),
      mapId: item.mapId,
    ),
    _ => null,
  };
  if (target == null) return;
  final layout = ref.read(workspaceProvider(studySetId)).layout;
  if (target.target is PdfTarget && layout == MMSplitMode.secondary) workspace.setLayout(MMSplitMode.split);
  final found = await workspace.revealAnchor(target);
  if (!found && context.mounted) MMHud.show(context, context.l10n.assistantAnchorGone, icon: MMIcons.warning);
}

/// Jumps from a `p.N` citation to the page; to the attached passage when the
/// answer cites the page it is on.
Future<void> revealCitation(
  BuildContext context,
  WidgetRef ref,
  String studySetId,
  Citation citation,
  List<ContextItem> contexts,
) async {
  if (citation.documentId == null || citation.page == null) return;
  final passage = contexts
      .where(
        (c) =>
            c.kind == ContextKind.selection &&
            c.documentId == citation.documentId &&
            c.page == citation.page &&
            ref.read(assistantUiProvider(studySetId)).anchors.containsKey(c.id),
      )
      .firstOrNull;
  await revealContext(
    context,
    ref,
    studySetId,
    passage ??
        ContextItem(
          id: 'cite',
          kind: ContextKind.page,
          documentId: citation.documentId,
          page: citation.page,
          displayText: '',
        ),
  );
}

/// The user's question, with what it was asked about above it.
class UserMessage extends ConsumerWidget {
  const UserMessage({super.key, required this.studySetId, required this.message});

  final String studySetId;
  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final shown = [
      for (final item in message.contexts)
        if (!(item.auto && item.kind == ContextKind.page)) item,
    ];
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: .88,
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final item in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: MMSpacing.xs),
                child: MMInteractive(
                  onTap: () => revealContext(context, ref, studySetId, item),
                  semanticLabel: contextLabel(l, item),
                  builder: (context, s) => AnimatedContainer(
                    duration: MMMotion.quick,
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: s.hovered ? c.fill : c.quaternaryFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3, right: 6),
                          child: Icon(contextIcon(item), size: 12, color: c.icon),
                        ),
                        Flexible(
                          child: item.kind == ContextKind.selection
                              ? Text(
                                  item.displayText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.readingExcerpt.copyWith(fontSize: 12, color: c.excerptText),
                                )
                              : Text(
                                  contextLabel(l, item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.callout.copyWith(color: c.secondaryLabel),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Container(
              key: ValueKey('user-bubble-${message.id}'),
              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
              decoration: BoxDecoration(
                color: c.accentTint,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(
                message.text,
                style: t.body.copyWith(height: 20 / 13, color: c.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An answer: its steps, body, sources, proposals, and what can be done next.
class AgentMessage extends ConsumerWidget {
  const AgentMessage({
    super.key,
    required this.studySetId,
    required this.message,
    required this.question,
    this.last = false,
  });

  final String studySetId;
  final Message message;

  /// The question this answers; its contexts are what the answer cites.
  final Message question;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final m = message;
    final running = m.status == MessageStatus.running;
    final skill = AssistantSkill.values.where((s) => s.name == question.skill).firstOrNull;
    final notOnline = m.status == MessageStatus.done && m.text.isNotEmpty && !m.online && (skill?.online ?? false);
    final numbers = sourceNumbers(m.text, m.citations);
    final content = ref.read(workspaceProvider(studySetId).notifier).content;
    String tooltip(Citation x) => x.external
        ? (x.url == null ? '' : Uri.tryParse(x.url!)?.host ?? x.url!)
        : '${content.document(x.documentId ?? '')?.title ?? ''} · ${l.assistantCurrentPage(x.page ?? 1)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (m.traces.isNotEmpty) TraceBar(key: ValueKey('trace-${m.id}'), message: m),
        if (notOnline)
          Padding(
            padding: const EdgeInsets.only(bottom: MMSpacing.xs),
            child: Row(
              children: [
                Icon(MMIcons.info, size: 12, color: c.secondaryLabel),
                const SizedBox(width: MMSpacing.xs),
                Text(l.assistantNotOnline, style: t.footnote.copyWith(color: c.secondaryLabel)),
              ],
            ),
          ),
        AnswerBody(
          text: m.text,
          citations: m.citations,
          cursor: running,
          tooltipFor: tooltip,
          onLink: (url) => ref.read(assistantLinksProvider).open(url),
          onCitation: (x) => x.external
              ? ref.read(assistantUiProvider(studySetId).notifier).openSource(x)
              : revealCitation(context, ref, studySetId, x, question.contexts),
        ),
        if (!running && numbers.isNotEmpty) SourcesRow(message: m, numbers: numbers, studySetId: studySetId),
        for (final p in m.proposals)
          ProposalCard(key: ValueKey('proposal-${p.proposal.id}'), studySetId: studySetId, view: p),
        if (!running) _Tail(studySetId: studySetId, message: m, question: question),
      ],
    );
  }
}

/// Text and icon for a tool call in the step list.
String stepLabel(AppLocalizations l, String tool) => switch (tool) {
  'read_selection' => l.assistantToolReadSelection,
  'read_pages' => l.assistantToolReadPages,
  'search_study_set' => l.assistantToolSearch,
  'read_branch' => l.assistantToolReadBranch,
  'web_search' => l.assistantToolWebSearch,
  'search_papers' => l.assistantToolPapers,
  'fetch_source' => l.assistantToolFetch,
  'propose_map_edits' => l.assistantToolPropose,
  'activate_skills' || 'deactivate_skills' => l.assistantToolSkills,
  _ => l.assistantToolOther,
};

/// The steps an answer took: open while it is being written, then folded
/// into one line that opens on click.
class TraceBar extends StatefulWidget {
  const TraceBar({super.key, required this.message});

  final Message message;

  @override
  State<TraceBar> createState() => _TraceBarState();
}

class _TraceBarState extends State<TraceBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final m = widget.message;
    final running = m.status == MessageStatus.running;
    final open = running || _open;
    final current = m.traces.lastWhere((s) => s.status == TraceStatus.running, orElse: () => m.traces.last);
    final style = t.callout.copyWith(fontWeight: FontWeight.w400, color: c.secondaryLabel);
    final title = running
        ? stepLabel(l, current.toolName)
        : '${l.assistantSteps(m.traces.length)} · ${m.online ? l.assistantStepsOnline : l.assistantStepsOffline}';
    Widget spinner(double size) => SizedBox(
      width: size,
      height: size,
      child: CupertinoActivityIndicator(radius: size / 2, color: c.research),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: MMSpacing.s),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MMInteractive(
            onTap: running ? null : () => setState(() => _open = !_open),
            enabled: true,
            semanticLabel: title,
            semanticValue: running ? null : (open ? '▾' : '▸'),
            builder: (context, s) => Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (running) spinner(12) else Icon(MMIcons.check, size: 12, color: c.secondaryLabel),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                  ),
                  if (!running) Icon(open ? MMIcons.chevronUp : MMIcons.chevronDown, size: 12, color: c.icon),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: MMAppearance.duration(context, MMMotion.standard),
            curve: MMMotion.standardCurve,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final step in m.traces)
                          SizedBox(
                            height: 20,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  child: switch (step.status) {
                                    TraceStatus.running => spinner(10),
                                    TraceStatus.done => Icon(MMIcons.check, size: 11, color: c.secondaryLabel),
                                    TraceStatus.error => Icon(MMIcons.close, size: 11, color: c.critical),
                                  },
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    stepLabel(l, step.toolName),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: style.copyWith(
                                      color: step.status == TraceStatus.running ? c.research : c.secondaryLabel,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// External sources an answer cites, numbered as in its text.
class SourcesRow extends ConsumerWidget {
  const SourcesRow({super.key, required this.message, required this.numbers, required this.studySetId});

  final Message message;
  final Map<String, int> numbers;
  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final first = {
      for (final x in message.citations.reversed)
        if (x.external) x.sourceId!: x,
    };
    return Padding(
      padding: const EdgeInsets.only(top: MMSpacing.xxs, bottom: MMSpacing.s),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in numbers.entries)
            if (first[e.key] case final citation?)
              MMInteractive(
                onTap: () => ref.read(assistantUiProvider(studySetId).notifier).openSource(citation),
                semanticLabel: '${e.value} ${sourceTitle(citation)}',
                builder: (context, s) => AnimatedContainer(
                  duration: MMMotion.quick,
                  height: 24,
                  padding: const EdgeInsets.only(left: 4, right: 10),
                  decoration: BoxDecoration(
                    color: s.hovered ? c.fill : c.quaternaryFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.separator, width: .5),
                        ),
                        child: Text('${e.value}', style: t.footnote.copyWith(fontSize: 10, height: 1)),
                      ),
                      const SizedBox(width: 6),
                      Icon(sourceIcon(citation), size: 12, color: c.icon),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Text(
                          sourceTitle(citation),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.callout.copyWith(color: s.hovered ? c.label : c.secondaryLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// What an answer ends with: actions when done, or why it is not.
class _Tail extends ConsumerWidget {
  const _Tail({required this.studySetId, required this.message, required this.question});

  final String studySetId;
  final Message message;
  final Message question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final m = message;
    final controller = ref.read(assistantControllerProvider.notifier);
    void retry() => unawaited(controller.retry(m.id).catchError((Object _) {}));
    final copy = _ActionButton(
      key: ValueKey('assistant-copy-${m.id}'),
      icon: MMIcons.copy,
      tooltip: l.copyAction,
      onPressed: m.text.isEmpty
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: copyableAnswer(m.text, m.citations)));
              if (context.mounted) MMHud.show(context, l.copiedHud);
            },
    );
    final regenerate = _ActionButton(
      key: ValueKey('assistant-regenerate-${m.id}'),
      icon: MMIcons.history,
      tooltip: l.assistantRegenerate,
      onPressed: retry,
    );
    // Migrated research: the answer can be copied, nothing else.
    if (ref.watch(assistantControllerProvider.select((c) => c.readOnly))) {
      return Padding(
        padding: const EdgeInsets.only(top: MMSpacing.xxs),
        child: Row(children: [copy]),
      );
    }
    if (m.status == MessageStatus.done || m.status == MessageStatus.stopped) {
      return Padding(
        padding: const EdgeInsets.only(top: MMSpacing.xxs),
        child: Row(
          children: [
            if (m.status == MessageStatus.stopped) ...[
              Text(l.assistantStopped, style: t.footnote.copyWith(color: c.secondaryLabel)),
              const SizedBox(width: MMSpacing.s),
            ],
            if (m.proposals.isEmpty && m.text.isNotEmpty)
              if (m.noteId == null)
                Builder(
                  builder: (context) => _ActionButton(
                    key: ValueKey('assistant-save-${m.id}'),
                    icon: MMIcons.addTopic,
                    label: l.assistantSaveNote,
                    color: c.research,
                    onPressed: () => showSaveNotePopover(context, ref, studySetId, m, question),
                  ),
                )
              else ...[
                _ActionButton(
                  key: ValueKey('assistant-saved-${m.id}'),
                  icon: MMIcons.check,
                  label: l.assistantSavedNote,
                  color: c.positive,
                  onPressed: null,
                  keepColor: true,
                ),
                _ActionButton(
                  label: l.assistantLocate,
                  onPressed: () => ref.read(workspaceProvider(studySetId).notifier).locateNoteCard(m.noteId!),
                ),
              ],
            copy,
            regenerate,
          ],
        ),
      );
    }
    final kind = m.errorKind;
    final (String reason, bool caution, List<Widget> actions) = switch (m.status) {
      MessageStatus.interrupted => (
        l.assistantInterrupted,
        true,
        [_ActionButton(label: l.assistantContinue, color: c.research, onPressed: retry)],
      ),
      _ => switch (kind) {
        ResearchFailureKind.authentication => (
          l.assistantErrorKey,
          false,
          [
            _ActionButton(
              label: l.assistantOpenSettings,
              color: c.research,
              onPressed: () => showAssistantSettings(context, ref),
            ),
          ],
        ),
        ResearchFailureKind.rateLimited => (
          l.assistantErrorService,
          false,
          [_ActionButton(label: l.assistantRetry, color: c.research, onPressed: retry)],
        ),
        ResearchFailureKind.timeout || ResearchFailureKind.budget => (
          l.assistantErrorBudget,
          true,
          [_ActionButton(label: l.assistantContinue, color: c.research, onPressed: retry)],
        ),
        ResearchFailureKind.refusal => (l.assistantErrorRefused, true, [regenerate]),
        ResearchFailureKind.unavailable => (
          l.assistantErrorNetwork,
          false,
          [
            _ActionButton(label: l.assistantRetry, color: c.research, onPressed: retry),
            if (_localModel(ref) case final local?)
              _ActionButton(
                label: l.assistantUseLocal,
                onPressed: () async {
                  await controller.switchModel(local);
                  await controller.setOnline(false);
                  retry();
                },
              ),
          ],
        ),
        _ => (
          l.assistantErrorFailed,
          false,
          [_ActionButton(label: l.assistantRetry, color: c.research, onPressed: retry)],
        ),
      },
    };
    final tint = caution ? c.caution : c.critical;
    return Container(
      key: ValueKey('assistant-status-${m.id}'),
      margin: const EdgeInsets.only(top: MMSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: caution ? .10 : .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(MMIcons.warning, size: 14, color: tint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  reason,
                  style: t.callout.copyWith(fontWeight: FontWeight.w600, color: c.label),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 2, children: actions),
        ],
      ),
    );
  }

  static AssistantModel? _localModel(WidgetRef ref) => ref
      .read(assistantSettingsProvider.notifier)
      .models()
      .where((m) => m.provider == AssistantProvider.ollama && m.localEnabled && m.model.trim().isNotEmpty)
      .firstOrNull;
}

/// A 26pt button of an answer's action row.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    this.icon,
    this.label,
    this.tooltip,
    this.color,
    required this.onPressed,
    this.keepColor = false,
  });

  final IconData? icon;
  final String? label;
  final String? tooltip;
  final Color? color;
  final VoidCallback? onPressed;

  /// A disabled button that shows a state (saved) keeps its color.
  final bool keepColor;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return MMInteractive(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: label ?? tooltip,
      builder: (context, s) {
        final fg = !s.enabled && !keepColor ? c.label.withValues(alpha: .3) : (color ?? c.secondaryLabel);
        return AnimatedContainer(
          duration: MMMotion.quick,
          height: 26,
          constraints: const BoxConstraints(minWidth: 26),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : MMSpacing.s),
          decoration: BoxDecoration(
            color: s.hovered ? (color == c.research ? c.researchTint : c.hover) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, size: 12, color: fg),
              if (icon != null && label != null) const SizedBox(width: MMSpacing.xs),
              if (label != null) Text(label!, style: t.callout.copyWith(color: fg)),
            ],
          ),
        );
      },
    );
  }
}
