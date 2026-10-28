import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_assistant/mm_assistant.dart' show PolicyHook, AssistantModel, AssistantProvider;
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';
import '../../../settings/settings_window.dart';
import '../assistant_services.dart';
import 'assistant_markdown.dart';
import 'assistant_model_menu.dart';
import 'assistant_overlays.dart';
import 'assistant_proposal.dart';
import 'assistant_permission.dart';

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
    this.compact = false,
    this.onSource,
  });

  final String studySetId;
  final Message message;

  /// The question this answers; its contexts are what the answer cites.
  final Message question;
  final bool last;
  final bool compact;
  final ValueChanged<Citation>? onSource;

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
        if ((!compact && (m.traces.isNotEmpty || (m.startedAt != null && m.endedAt != null))) || running)
          ActivityTimeline(key: ValueKey('trace-${m.id}'), message: m),
        for (final permission in m.permissions)
          ReadPermissionCard(key: ValueKey(permission.request.id), messageId: m.id, view: permission),
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
          cursor: running && !m.waitingForPermission,
          conclusion: skill == AssistantSkill.verify,
          tooltipFor: tooltip,
          onLink: (url) => ref.read(assistantLinksProvider).open(url),
          onCitation: (x) => x.external
              ? (onSource ?? ref.read(assistantUiProvider(studySetId).notifier).openSource)(x)
              : revealCitation(context, ref, studySetId, x, question.contexts),
        ),
        if (!running && numbers.isNotEmpty)
          SourcesRow(message: m, numbers: numbers, studySetId: studySetId, onSource: onSource),
        for (final p in m.proposals)
          ProposalCard(key: ValueKey('proposal-${p.proposal.id}'), studySetId: studySetId, view: p),
        if (!running && (!compact || (m.status != MessageStatus.done && m.status != MessageStatus.stopped)))
          _Tail(studySetId: studySetId, message: m, question: question),
      ],
    );
  }
}

/// The name of a tool call in the process: what it did, in words; an
/// unknown tool by its own name.
String stepLabel(AppLocalizations l, String tool) => switch (PolicyHook.normalizeName(tool)) {
  'read_selection' => l.assistantToolReadSelection,
  'read_pages' => l.assistantToolReadPages,
  'search_study_set' => l.assistantToolSearch,
  'read_branch' => l.assistantToolReadBranch,
  'web_search' => l.assistantToolWebSearch,
  'search_papers' => l.assistantToolPapers,
  'fetch_source' => l.assistantToolFetch,
  'propose_map_edits' => l.assistantToolPropose,
  'activate_skills' || 'deactivate_skills' => l.assistantToolSkills,
  _ => tool,
};

IconData stepIcon(String tool) => switch (PolicyHook.normalizeName(tool)) {
  'read_selection' => MMIcons.highlight,
  'read_pages' || 'search_study_set' => MMIcons.document,
  'read_branch' || 'propose_map_edits' => MMIcons.mindMap,
  'web_search' || 'fetch_source' => MMIcons.web,
  'search_papers' => MMIcons.paper,
  _ => MMIcons.ai,
};

/// How an answer was worked out: what the model said between its steps and
/// what it did, in turn. Open while it is written (the current step
/// shimmers); then one line, “Worked for N s”, that opens on click.
class ActivityTimeline extends StatefulWidget {
  const ActivityTimeline({super.key, required this.message});

  final Message message;

  @override
  State<ActivityTimeline> createState() => _ActivityTimelineState();
}

class _ActivityTimelineState extends State<ActivityTimeline> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final m = widget.message;
    final running = m.status == MessageStatus.running;
    final steps = m.activity;
    final failures = steps
        .where((s) => s.narration == null && s.status == TraceStatus.error)
        .fold(0, (n, s) => n + s.count);
    final expandable = steps.isNotEmpty;
    final open = expandable && (running || _open);
    final style = t.callout.copyWith(fontWeight: FontWeight.w400);
    final current = steps.lastOrNull;
    final waiting = running && m.waitingForPermission;
    final title = waiting
        ? l.assistantPermissionWaiting
        : running
        ? (current == null ? l.assistantThinking : current.narration ?? stepLabel(l, current.toolName))
        : l.assistantWorkedFor(m.elapsedSeconds < 1 ? 1 : m.elapsedSeconds);
    return Padding(
      padding: const EdgeInsets.only(bottom: MMSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MMInteractive(
            key: ValueKey('timeline-${m.id}'),
            onTap: running || !expandable ? null : () => setState(() => _open = !_open),
            semanticLabel: title,
            semanticValue: running || !expandable ? null : (open ? '▾' : '▸'),
            builder: (context, s) {
              final fg = s.hovered ? c.label : c.secondaryLabel;
              return Row(
                children: [
                  Flexible(
                    child: running && !waiting
                        ? Shimmer(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style.copyWith(color: c.secondaryLabel),
                            ),
                          )
                        : Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(color: fg),
                          ),
                  ),
                  if (failures > 0)
                    Text(
                      ' · ${l.assistantToolFailures(failures)}',
                      key: const ValueKey('timeline-failures'),
                      style: style.copyWith(color: c.caution),
                    ),
                  if (!running && expandable) ...[
                    const SizedBox(width: 2),
                    Icon(open ? MMIcons.chevronDown : MMIcons.chevronRight, size: 11, color: fg),
                  ],
                ],
              );
            },
          ),
          AnimatedSize(
            duration: MMAppearance.duration(context, MMMotion.standard),
            curve: MMMotion.standardCurve,
            alignment: Alignment.topCenter,
            child: open
                ? Container(
                    margin: const EdgeInsets.only(top: 6, left: 3),
                    padding: const EdgeInsets.only(left: MMSpacing.m),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: c.separator)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final step in steps) _TimelineRow(step: step, waiting: waiting)],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, this.waiting = false});

  final TraceStep step;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    if (step.narration case final words?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          words,
          style: t.callout.copyWith(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.65, color: c.label),
        ),
      );
    }
    final failed = step.status == TraceStatus.error;
    final label = '${stepLabel(l, step.toolName)}${step.count > 1 ? ' ×${step.count}' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SizedBox(
              width: 14,
              child: switch (step.status) {
                TraceStatus.running =>
                  waiting
                      ? Icon(MMIcons.info, size: 13, color: c.research)
                      : CupertinoActivityIndicator(radius: 5, color: c.research),
                TraceStatus.done => Icon(stepIcon(step.toolName), size: 13, color: c.secondaryLabel),
                TraceStatus.error => Icon(MMIcons.close, size: 12, color: c.critical),
                TraceStatus.denied => Icon(MMIcons.close, size: 12, color: c.secondaryLabel),
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: t.callout.copyWith(fontWeight: FontWeight.w400, color: failed ? c.critical : c.secondaryLabel),
                ),
                if ((failed || step.status == TraceStatus.denied) && step.reason != null)
                  Text(step.reason!, style: t.mono.copyWith(fontSize: 10.5, color: c.secondaryLabel)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A light sweeping across [child] while work is under way; still when
/// motion is reduced.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MMAppearance.reduceMotionOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sweep.isAnimating) return widget.child;
    final light = context.mmColors.label;
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final x = -1.0 + 3 * _sweep.value;
          return LinearGradient(
            begin: Alignment(x - .6, 0),
            end: Alignment(x + .6, 0),
            colors: [Colors.transparent, light.withValues(alpha: .9), Colors.transparent],
          ).createShader(rect);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// External sources an answer cites, numbered as in its text.
class SourcesRow extends ConsumerWidget {
  const SourcesRow({super.key, required this.message, required this.numbers, required this.studySetId, this.onSource});

  final Message message;
  final Map<String, int> numbers;
  final String studySetId;
  final ValueChanged<Citation>? onSource;

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
                onTap: () => (onSource ?? ref.read(assistantUiProvider(studySetId).notifier).openSource)(citation),
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
      // An answer that already is (or proposes) map edits needs no second pass.
      final organizes = m.text.isNotEmpty && m.proposals.isEmpty && question.skill != AssistantSkill.organize.name;
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
            if (organizes)
              _ActionButton(
                key: ValueKey('assistant-organize-${m.id}'),
                icon: MMIcons.organize,
                tooltip: l.assistantSkillOrganize,
                onPressed: controller.busy
                    ? null
                    : () => unawaited(
                        controller
                            .send(
                              AssistantSkill.organize.prompt(l),
                              contexts: question.contexts,
                              skill: AssistantSkill.organize.name,
                            )
                            .catchError((Object _) {}),
                      ),
              ),
            regenerate,
          ],
        ),
      );
    }
    final kind = m.errorKind;
    final primary = c.research;
    final (String reason, bool caution, List<Widget> actions) = switch (m.status) {
      MessageStatus.interrupted => (
        l.assistantInterrupted,
        true,
        [_ActionButton(label: l.assistantContinue, color: primary, onPressed: retry)],
      ),
      _ => switch (kind) {
        _ when m.diagnostics?.failure == 'secret_store' => (
          l.assistantModelUnavailableTitle,
          false,
          [
            _ActionButton(
              key: const ValueKey('assistant-open-settings'),
              label: l.assistantConfigureModels,
              color: primary,
              onPressed: () => showSettings(context, tab: SettingsTab.models),
            ),
          ],
        ),
        ResearchFailureKind.authentication => (
          l.assistantErrorKey,
          false,
          [
            _ActionButton(
              key: const ValueKey('assistant-open-settings'),
              label: l.assistantOpenSettings,
              color: primary,
              onPressed: () => showSettings(context, tab: SettingsTab.models),
            ),
          ],
        ),
        ResearchFailureKind.rateLimited || ResearchFailureKind.unavailable => (
          l.assistantErrorService,
          false,
          [_ActionButton(label: l.assistantRetry, color: primary, onPressed: retry)],
        ),
        ResearchFailureKind.timeout || ResearchFailureKind.budget => (
          l.assistantErrorBudget,
          true,
          [_ActionButton(label: l.assistantContinue, color: primary, onPressed: retry)],
        ),
        ResearchFailureKind.toolProtocol || ResearchFailureKind.loop => (
          l.assistantErrorToolProtocol,
          true,
          [
            _ActionButton(
              key: ValueKey('assistant-no-tools-${m.id}'),
              label: l.assistantAnswerWithoutTools,
              color: primary,
              onPressed: () => unawaited(controller.retry(m.id, tools: false).catchError((Object _) {})),
            ),
            Builder(
              builder: (button) => _ActionButton(
                key: ValueKey('assistant-switch-model-${m.id}'),
                label: l.assistantSwitchModel,
                onPressed: () => showModelMenu(button, ref, boundsOf(button), retryMessageId: m.id),
              ),
            ),
            _ActionButton(
              key: ValueKey('assistant-copy-diagnostics-${m.id}'),
              label: l.assistantCopyDiagnostics,
              onPressed: () => _copyDiagnostics(context, ref, m),
            ),
          ],
        ),
        ResearchFailureKind.refusal => (l.assistantErrorRefused, true, [regenerate]),
        ResearchFailureKind.network => (
          l.assistantErrorNetwork,
          false,
          [
            _ActionButton(label: l.assistantRetry, color: primary, onPressed: retry),
            if (_localModel(ref) case final local?)
              _ActionButton(
                key: ValueKey('assistant-use-local-${m.id}'),
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
          [_ActionButton(label: l.assistantRetry, color: primary, onPressed: retry)],
        ),
      },
    };
    return _StatusBlock(
      key: ValueKey('assistant-status-${m.id}'),
      message: m,
      reason: reason,
      caution: caution,
      actions: actions,
      details: m.status == MessageStatus.error ? diagnosticRows(l, ref, m) : const [],
      onCopy: () => _copyDiagnostics(context, ref, m),
    );
  }

  static void _copyDiagnostics(BuildContext context, WidgetRef ref, Message m) {
    final l = context.l10n;
    unawaited(Clipboard.setData(ClipboardData(text: diagnosticText(diagnosticRows(l, ref, m)))));
    MMHud.show(context, l.copiedHud);
  }

  /// The first local model, unless the conversation already uses one.
  static AssistantModel? _localModel(WidgetRef ref) {
    if (ref.read(assistantControllerProvider).model.provider == AssistantProvider.ollama) return null;
    return ref
        .read(assistantServicesProvider)
        .value
        ?.enabledModels
        .where((m) => m.provider == AssistantProvider.ollama && m.localEnabled)
        .firstOrNull;
  }
}

/// The facts of a failed answer, for details and bug reports: model and
/// service, host, HTTP status, failed tools, why it stopped, request ID.
/// Never the key, the question, the source text or a provider's message.
List<(String, String)> diagnosticRows(AppLocalizations l, WidgetRef ref, Message m) {
  final d = m.diagnostics;
  if (d == null) return const [];
  final service = ref
      .read(assistantServicesProvider)
      .value
      ?.services
      .where((s) => Uri.tryParse(s.endpoint)?.host == d.host)
      .firstOrNull;
  final failed = <String, int>{};
  for (final tool in d.tools) {
    if (tool.status == TraceStatus.error) failed[tool.toolName] = (failed[tool.toolName] ?? 0) + tool.count;
  }
  return [
    (l.assistantDiagnosticModel, [d.model, ?service?.name].join(' · ')),
    if (d.host.isNotEmpty) (l.assistantDiagnosticHost, d.host),
    if (d.httpStatus != null) (l.assistantDiagnosticStatus, '${d.httpStatus}'),
    if (failed.isNotEmpty)
      (l.assistantDiagnosticTools, [for (final e in failed.entries) '${e.key} ×${e.value}'].join(', ')),
    if (d.failure ?? m.errorKind?.name case final why?) (l.assistantDiagnosticReason, why),
    (l.assistantDiagnosticRequest, d.requestId),
  ];
}

String diagnosticText(List<(String, String)> rows) => [for (final (k, v) in rows) '$k: $v'].join('\n');

/// The block an answer ends with when it failed: the reason in bold, its
/// details on request, and what can be done next.
class _StatusBlock extends StatefulWidget {
  const _StatusBlock({
    super.key,
    required this.message,
    required this.reason,
    required this.caution,
    required this.actions,
    required this.details,
    required this.onCopy,
  });

  final Message message;
  final String reason;
  final bool caution;
  final List<Widget> actions;
  final List<(String, String)> details;
  final VoidCallback onCopy;

  @override
  State<_StatusBlock> createState() => _StatusBlockState();
}

class _StatusBlockState extends State<_StatusBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final tint = widget.caution ? c.caution : c.critical;
    return Container(
      margin: const EdgeInsets.only(top: MMSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: widget.caution ? .10 : .08),
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
                  widget.reason,
                  style: t.callout.copyWith(fontWeight: FontWeight.w600, color: c.label),
                ),
              ),
              if (widget.details.isNotEmpty)
                MMInteractive(
                  key: ValueKey('assistant-details-${widget.message.id}'),
                  onTap: () => setState(() => _open = !_open),
                  semanticLabel: l.assistantDetails,
                  semanticValue: _open ? '▾' : '▸',
                  builder: (context, s) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.assistantDetails,
                        style: t.footnote.copyWith(color: s.hovered ? c.label : c.secondaryLabel),
                      ),
                      const SizedBox(width: 2),
                      Icon(_open ? MMIcons.chevronDown : MMIcons.chevronRight, size: 10, color: c.secondaryLabel),
                    ],
                  ),
                ),
            ],
          ),
          if (_open && widget.details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Table(
                    key: const ValueKey('assistant-details-table'),
                    columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
                    children: [
                      for (final (k, v) in widget.details)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: MMSpacing.m, bottom: 2),
                              child: Text(k, style: t.footnote.copyWith(color: c.secondaryLabel)),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(v, style: t.mono.copyWith(fontSize: 11, color: c.label)),
                            ),
                          ],
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _ActionButton(
                      key: ValueKey('assistant-copy-details-${widget.message.id}'),
                      icon: MMIcons.copy,
                      label: l.assistantCopyDiagnostics,
                      onPressed: widget.onCopy,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 2, children: widget.actions),
        ],
      ),
    );
  }
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
