import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_research/mm_research.dart';

import '../../../shared/l10n.dart';
import '../../workspace/workspace_controller.dart';
import '../research_answer.dart';
import '../research_controller.dart';
import '../research_drafts.dart';
import '../research_intents.dart';
import '../research_origin.dart';
import '../research_providers.dart';
import '../research_settings.dart';
import 'research_note_view.dart';
import 'research_reading.dart';
import 'research_settings_sheet.dart';
import 'research_sources.dart';
import 'research_widgets.dart';
import 'save_note_sheet.dart';

/// The research panel (design 4.2): where the research started, its
/// question, how far it got, and its answer, sources and saved notes.
class ResearchPanel extends ConsumerWidget {
  const ResearchPanel({super.key, required this.studySetId, required this.onClose});

  final String studySetId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(researchPanelProvider(studySetId));
    final header = _PanelHeader(onClose: onClose);
    if (panel.noteId case final noteId?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: ResearchNoteView(
              studySetId: studySetId,
              noteId: noteId,
              onBack: ref.read(researchPanelProvider(studySetId).notifier).closeNote,
            ),
          ),
        ],
      );
    }
    final sessionId = panel.sessionId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: sessionId == null
              ? _StartPage(studySetId: studySetId)
              : _SessionView(key: ValueKey(sessionId), studySetId: studySetId, sessionId: sessionId),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    return Container(
      height: MMSizes.toolbarGroupHeight + MMSpacing.s,
      padding: const EdgeInsets.only(left: MMSpacing.l, right: MMSpacing.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          Icon(MMIcons.research, size: 13, color: c.research),
          const SizedBox(width: MMSpacing.xs + 1),
          Expanded(
            child: Text(l.research, style: context.mmText.subheadline.copyWith(color: c.research)),
          ),
          MMIconButton(
            icon: MMIcons.settings,
            tooltip: l.researchSettings,
            iconSize: 13,
            onPressed: () => showResearchSettingsSheet(context),
          ),
          MMIconButton(icon: MMIcons.close, tooltip: l.closePanel, iconSize: 13, onPressed: onClose),
        ],
      ),
    );
  }
}

/// Nothing selected: how to start, and the research kept for later.
class _StartPage extends ConsumerWidget {
  const _StartPage({required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final sessions = ref.watch(researchSessionsProvider(studySetId)).value ?? const [];
    final later = [
      for (final s in sessions)
        if (s.status == 'draft' && ResearchDrafts.of(s).later) s,
    ];
    final panel = ref.read(researchPanelProvider(studySetId).notifier);
    return ListView(
      padding: const EdgeInsets.all(MMSpacing.l),
      children: [
        const SizedBox(height: MMSpacing.xl),
        Icon(MMIcons.research, size: 32, color: c.research),
        const SizedBox(height: MMSpacing.m),
        Text(
          l.researchEmptyTitle,
          textAlign: TextAlign.center,
          style: t.headline.copyWith(color: c.secondaryLabel),
        ),
        if (later.isNotEmpty) ...[
          const SizedBox(height: MMSpacing.xxl),
          ResearchFieldLabel(l.researchLater),
          for (final s in later)
            _Card(
              key: ValueKey('later-${s.id}'),
              children: [
                Text(s.question, style: t.headline),
                const SizedBox(height: MMSpacing.s),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: MMButton(
                    label: l.researchContinue,
                    icon: MMIcons.research,
                    onPressed: () {
                      panel.show(s.id);
                      unawaited(panel.run(s.id));
                    },
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

class _SessionView extends ConsumerWidget {
  const _SessionView({super.key, required this.studySetId, required this.sessionId});

  final String studySetId;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (studySetId: studySetId, sessionId: sessionId);
    final value = ref.watch(researchSessionProvider(key));
    final panel = ref.watch(researchPanelProvider(studySetId));
    return switch (value) {
      AsyncData(:final value) => _Session(studySetId: studySetId, value: value, panel: panel),
      AsyncError() => MMEmptyState(icon: MMIcons.warning, title: context.l10n.somethingWentWrong),
      _ => const Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
    };
  }
}

class _Session extends ConsumerWidget {
  const _Session({required this.studySetId, required this.value, required this.panel});

  final String studySetId;
  final ResearchSessionState value;
  final ResearchPanelState panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final session = value.session;
    final drafts = value.drafts;
    final settings = ref.watch(researchSettingsProvider);
    final reading = panel.readingSourceId;
    final saved = ref
        .watch(workspaceContentProvider(studySetId).select((c) => c?.researchNotes))
        ?.where((n) => n.sessionId == session.id)
        .length;
    final showComposer =
        reading == null &&
        panel.tab == ResearchTab.answer &&
        settings.aiConfigured &&
        AnswerTurn.all(session.history).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.m, MMSpacing.l, MMSpacing.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OriginCard(studySetId: studySetId, session: session),
              const SizedBox(height: MMSpacing.m),
              _QuestionField(
                key: ValueKey('question-${session.id}'),
                question: session.question,
                onCommit: (text) => ref.read(researchPanelProvider(studySetId).notifier).rename(session.id, text),
              ),
              const SizedBox(height: MMSpacing.s),
              _RunLine(studySetId: studySetId, value: value, progress: panel.progress[session.id]),
            ],
          ),
        ),
        if (reading == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(MMSpacing.l, 0, MMSpacing.l, MMSpacing.s),
            child: _Tabs(
              value: panel.tab,
              labels: {
                ResearchTab.answer: l.researchTabAnswer,
                ResearchTab.sources: value.sources.isEmpty
                    ? l.researchTabSources
                    : '${l.researchTabSources} ${value.sources.length}',
                ResearchTab.saved: (saved ?? 0) + drafts.clips.length == 0
                    ? l.researchTabSaved
                    : '${l.researchTabSaved} ${(saved ?? 0) + drafts.clips.length}',
              },
              onChanged: ref.read(researchPanelProvider(studySetId).notifier).setTab,
            ),
          ),
        Container(height: 0.5, color: context.mmColors.separator),
        Expanded(
          child: reading != null
              ? ResearchReading(
                  key: ValueKey('reading-$reading'),
                  studySetId: studySetId,
                  value: value,
                  sourceId: reading,
                  focusParagraphId: panel.focusParagraphId,
                )
              : switch (panel.tab) {
                  ResearchTab.answer => _AnswerView(studySetId: studySetId, value: value, panel: panel),
                  ResearchTab.sources => ResearchSources(studySetId: studySetId, value: value, panel: panel),
                  ResearchTab.saved => _SavedView(studySetId: studySetId, value: value),
                },
        ),
        if (showComposer) _Composer(studySetId: studySetId, value: value),
      ],
    );
  }
}

/// Where the research started; clicking goes back there.
class _OriginCard extends ConsumerWidget {
  const _OriginCard({required this.studySetId, required this.session});

  final String studySetId;
  final ResearchSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final content = ref.watch(workspaceContentProvider(studySetId));
    final anchor = session.anchor;
    if (anchor == null || content == null) return const SizedBox.shrink();
    final (String text, String place, IconData icon, bool fromMap) = switch (anchor.target) {
      PdfTarget(:final documentId, :final pages, :final quote) => (
        quote,
        content.document(documentId) == null
            ? l.researchOriginGone
            : '${content.document(documentId)!.title} · ${l.pageNumber(pages.first.page)}',
        MMIcons.document,
        false,
      ),
      CardTarget(:final cardId) => (
        researchCardTitle(content, cardId),
        content.node(cardId, mapId: anchor.mapId ?? MindMap.defaultId) == null
            ? l.researchOriginGone
            : (content.map(anchor.mapId ?? MindMap.defaultId)?.title.isNotEmpty ?? false)
            ? content.map(anchor.mapId ?? MindMap.defaultId)!.title
            : l.mainMap,
        MMIcons.mindMap,
        true,
      ),
    };
    return MMInteractive(
      key: const ValueKey('research-origin'),
      tooltip: l.researchBackToOrigin,
      semanticLabel: l.researchBackToOrigin,
      onTap: () async {
        final ok = await ref.read(workspaceProvider(studySetId).notifier).revealAnchor(anchor);
        if (!ok && context.mounted) MMHud.show(context, l.researchOriginGone, icon: MMIcons.info);
      },
      builder: (context, s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
        decoration: BoxDecoration(
          color: s.hovered ? c.fill : c.quaternaryFill,
          borderRadius: BorderRadius.circular(MMRadii.field + 2),
        ),
        child: Row(
          children: [
            Icon(MMIcons.undo, size: 12, color: c.icon),
            const SizedBox(width: MMSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: fromMap ? t.headline : t.readingExcerpt,
                  ),
                  const SizedBox(height: MMSpacing.xxs),
                  Row(
                    children: [
                      Icon(icon, size: 10, color: c.secondaryLabel),
                      const SizedBox(width: MMSpacing.xs),
                      Expanded(
                        child: Text(
                          place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.footnote.copyWith(color: c.secondaryLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The research question in large text, edited where it is shown.
class _QuestionField extends StatefulWidget {
  const _QuestionField({super.key, required this.question, required this.onCommit});

  final String question;
  final Future<void> Function(String) onCommit;

  @override
  State<_QuestionField> createState() => _QuestionFieldState();
}

class _QuestionFieldState extends State<_QuestionField> {
  late final _controller = TextEditingController(text: widget.question);
  final _focus = FocusNode(debugLabel: 'ResearchQuestion');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_QuestionField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.question != _controller.text) _controller.text = widget.question;
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _controller.text = widget.question;
    } else if (text != widget.question) {
      unawaited(widget.onCommit(text));
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs, vertical: MMSpacing.xxs),
      decoration: BoxDecoration(
        color: _focus.hasFocus ? c.quaternaryFill : null,
        borderRadius: BorderRadius.circular(MMRadii.excerpt),
      ),
      child: MMInlineTextField(
        controller: _controller,
        focusNode: _focus,
        style: context.mmText.title3.copyWith(height: 22 / 15),
        multiline: true,
        semanticLabel: context.l10n.researchQuestion,
        onSubmitted: _focus.unfocus,
        onCancel: () {
          _controller.text = widget.question;
          _focus.unfocus();
        },
      ),
    );
  }
}

/// How far the research got: its stages and Cancel while running; the
/// method, time and sources used when done; the reason and Retry otherwise.
class _RunLine extends ConsumerWidget {
  const _RunLine({required this.studySetId, required this.value, required this.progress});

  final String studySetId;
  final ResearchSessionState value;
  final ResearchProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final session = value.session;
    final panel = ref.read(researchPanelProvider(studySetId).notifier);
    final blocked = ref.watch(researchPanelProvider(studySetId).select((s) => s.blocked[session.id]));
    final method = value.drafts.method;
    final running = progress != null || session.status == 'running';
    Widget button(String label, VoidCallback onPressed, {IconData? icon, Key? key}) =>
        MMButton(key: key, label: label, icon: icon, variant: MMButtonVariant.secondary, onPressed: onPressed);
    // The state on the left, the next step on the right.
    Widget state(Widget pill) => Expanded(
      child: Align(alignment: AlignmentDirectional.centerStart, child: pill),
    );
    Future<void> retry() async {
      final block = await panel.retry(session.id);
      if (block != null && context.mounted) _showBlock(context, block);
    }

    final List<Widget> children;
    if (running) {
      final stage = progress?.stage ?? ResearchStage.answer;
      final label = switch (stage) {
        ResearchStage.search => l.researchStageSearch,
        ResearchStage.answer => method == ResearchMethod.web ? l.researchStageWebAnswer : l.researchStageAnswer,
        ResearchStage.read => l.researchStageRead(progress!.done, progress!.total),
      };
      children = [
        SizedBox.square(dimension: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.research)),
        const SizedBox(width: MMSpacing.s),
        Expanded(
          child: Text(label, style: t.callout.copyWith(color: c.research)),
        ),
        button(l.cancel, () => panel.cancel(session.id), icon: MMIcons.stop, key: const ValueKey('research-cancel')),
      ];
    } else if (blocked != null) {
      children = [
        state(MMPill(blocked == ResearchBlock.noWeb ? l.researchNoWeb : l.researchNoAi, color: c.caution)),
        button(l.researchSetUpAi, () => showResearchSettingsSheet(context)),
      ];
    } else {
      children = switch (session.status) {
        'failed' => [
          state(MMPill(researchError(l, value.error), color: c.critical, icon: MMIcons.warning)),
          button(l.researchRetry, retry, key: const ValueKey('research-retry')),
        ],
        'cancelled' => [
          state(MMPill(l.researchCancelled)),
          button(l.researchRestart, retry, key: const ValueKey('research-retry')),
        ],
        'interrupted' => [
          state(MMPill(l.researchInterrupted, color: c.caution)),
          button(l.researchRetry, retry, key: const ValueKey('research-retry')),
        ],
        'draft' when value.drafts.later => [
          state(MMPill(l.researchLater, icon: MMIcons.later)),
          button(l.researchStart, retry, key: const ValueKey('research-retry')),
        ],
        _ => [
          Flexible(
            child: MMPill(
              methodLabel(l, method),
              color: method == ResearchMethod.web ? c.research : null,
              icon: methodIcon(method),
            ),
          ),
          const SizedBox(width: MMSpacing.s),
          Flexible(
            child: Text(
              [
                if (session.status == 'done')
                  l.researchDoneAt(
                    DateFormat.Hm(Localizations.localeOf(context).toLanguageTag())
                        .format(value.drafts.doneAt ?? session.updatedAt),
                  ),
                if (method == ResearchMethod.web) l.researchUsedSources(_usedSources(value).length),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.footnote.copyWith(color: c.secondaryLabel),
            ),
          ),
        ],
      };
    }
    return SizedBox(height: 30, child: Row(children: children));
  }
}

/// Sources cited by any answer of the session.
Set<String> _usedSources(ResearchSessionState value) => {
  for (final turn in AnswerTurn.all(value.session.history))
    for (final p in turn.points)
      for (final cite in p.cites) cite.sourceId,
};

void _showBlock(BuildContext context, ResearchBlock block) => MMHud.show(
  context,
  block == ResearchBlock.noWeb ? context.l10n.researchNoWeb : context.l10n.researchNoAi,
  icon: MMIcons.info,
);

class _Tabs extends StatelessWidget {
  const _Tabs({required this.value, required this.labels, required this.onChanged});

  final ResearchTab value;
  final Map<ResearchTab, String> labels;
  final ValueChanged<ResearchTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return Container(
      height: MMSizes.segmented,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final tab in ResearchTab.values)
            Expanded(
              child: MMInteractive(
                key: ValueKey('research-tab-${tab.name}'),
                selected: tab == value,
                semanticLabel: labels[tab],
                onTap: () => onChanged(tab),
                builder: (context, s) => AnimatedContainer(
                  duration: MMMotion.quick,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tab == value ? c.card : (s.hovered ? c.hover : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: tab == value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[tab]!,
                    style: t.callout.copyWith(fontWeight: tab == value ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The answer as checkable points, with the method it came from (design 4.3).
class _AnswerView extends ConsumerWidget {
  const _AnswerView({required this.studySetId, required this.value, required this.panel});

  final String studySetId;
  final ResearchSessionState value;
  final ResearchPanelState panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final session = value.session;
    final drafts = value.drafts;
    final settings = ref.watch(researchSettingsProvider);
    final controller = ref.read(researchPanelProvider(studySetId).notifier);
    final turns = AnswerTurn.all(session.history);
    final running = panel.progress.containsKey(session.id) || session.status == 'running';

    if (turns.isEmpty) {
      if (running) return _Placeholder(text: l.researchAnswering);
      if (panel.blocked[session.id] != null || (!settings.aiConfigured && drafts.method != ResearchMethod.search)) {
        return MMEmptyState(
          icon: MMIcons.ai,
          title: l.researchNoAiTitle,
          actions: [
            MMButton(label: l.researchViewSources, onPressed: () => controller.setTab(ResearchTab.sources)),
            MMButton(
              label: l.researchSetUpAi,
              variant: MMButtonVariant.primary,
              color: c.research,
              onPressed: () => showResearchSettingsSheet(context),
            ),
          ],
        );
      }
      if (session.status == 'failed') {
        return MMEmptyState(icon: MMIcons.offline, title: researchError(l, value.error));
      }
      if (drafts.method == ResearchMethod.search || session.history.isEmpty) {
        final chosen = drafts.chosen.where((id) => value.sources.any((s) => s.id == id && s.versions.isNotEmpty));
        return MMEmptyState(
          icon: MMIcons.search,
          title: l.researchNoAnswerSearch,
          actions: [
            if (settings.aiConfigured)
              MMButton(
                key: const ValueKey('answer-from-chosen'),
                label: l.researchAnswerFromChosen(chosen.length),
                icon: MMIcons.ai,
                variant: MMButtonVariant.primary,
                color: c.research,
                onPressed: chosen.isEmpty
                    ? null
                    : () async {
                        final block = await controller.answerFromChosen(session.id);
                        if (block != null && context.mounted) _showBlock(context, block);
                      },
              )
            else
              MMButton(label: l.researchViewSources, onPressed: () => controller.setTab(ResearchTab.sources)),
          ],
        );
      }
      return MMEmptyState(icon: MMIcons.research, title: l.researchNoAnswer);
    }

    final last = turns.last;
    final used = _usedSources(value);
    final failed = value.sources.where((s) => s.readState == ResearchReadState.failed.name).length;
    final checked = [
      for (final turn in turns)
        for (final p in turn.points)
          if (drafts.checked.contains(p.key)) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.m, MMSpacing.l, MMSpacing.l),
            children: [
              _ModeBadge(
                method: last.method,
                count: last.method == 'sources' ? _turnSources(session.history[last.index]).length : used.length,
                fromMap: session.anchor?.target is CardTarget,
                onSources: () => controller.setTab(ResearchTab.sources),
              ),
              for (final turn in turns) ...[
                if (turn.index > 0 && turn.question != session.question)
                  Padding(
                    padding: const EdgeInsets.only(top: MMSpacing.l, bottom: MMSpacing.xs),
                    child: Row(
                      children: [
                        Icon(MMIcons.send, size: 11, color: c.research),
                        const SizedBox(width: MMSpacing.xs),
                        Expanded(
                          child: Text(turn.question, style: t.headline.copyWith(color: c.research)),
                        ),
                      ],
                    ),
                  ),
                for (final section in turn.sections) ...[
                  if (section.heading.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: MMSpacing.m, bottom: MMSpacing.xs),
                      child: Text(section.heading, style: t.subheadline.copyWith(color: c.secondaryLabel)),
                    ),
                  for (final point in section.points)
                    _PointRow(
                      key: ValueKey('point-${point.key}'),
                      studySetId: studySetId,
                      value: value,
                      point: point,
                      expectsSource: turn.method == 'web' && !section.openQuestions,
                    ),
                ],
              ],
              if (failed > 0 && last.method == 'web')
                Padding(
                  padding: const EdgeInsets.only(top: MMSpacing.m),
                  child: Row(
                    children: [
                      Icon(MMIcons.warning, size: 12, color: c.caution),
                      const SizedBox(width: MMSpacing.xs),
                      Expanded(
                        child: Text(
                          l.researchFailedSources(failed),
                          style: t.footnote.copyWith(color: c.secondaryLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              if (running)
                Padding(
                  padding: const EdgeInsets.only(top: MMSpacing.m),
                  child: _Placeholder(text: l.researchAnswering, compact: true),
                ),
            ],
          ),
        ),
        _SaveBar(
          count: checked.length,
          onClear: () => controller.clearChecked(session.id),
          onSave: checked.isEmpty
              ? null
              : () => showSaveNoteSheet(
                  context,
                  studySetId: studySetId,
                  sessionId: session.id,
                  points: [for (final p in checked) p],
                ),
        ),
      ],
    );
  }
}

Set<String> _turnSources(Map<String, Object?> turn) => {
  for (final d in turn['documents'] as List? ?? const [])
    if (d is Map && d['sourceId'] is String) d['sourceId'] as String,
};

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.method, required this.count, required this.fromMap, required this.onSources});

  final String method;
  final int count;
  final bool fromMap;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final (IconData icon, String text, Color tint, String? action) = switch (method) {
      'web' => (MMIcons.web, l.researchBadgeWeb(count), c.research, l.researchViewSources),
      'sources' => (MMIcons.paper, l.researchBadgeSources(count), c.research, null),
      _ => (MMIcons.offline, l.researchBadgeOffline, c.caution, null),
    };
    return ResearchNotice(
      key: ValueKey('mode-badge-$method'),
      icon: icon,
      text: text,
      color: tint,
      action: action,
      onAction: action == null ? null : onSources,
    );
  }
}

/// One answer point: check box, text (as the user edited it), citations,
/// and on hover Edit / Ask / Save.
class _PointRow extends ConsumerStatefulWidget {
  const _PointRow({
    super.key,
    required this.studySetId,
    required this.value,
    required this.point,
    required this.expectsSource,
  });

  final String studySetId;
  final ResearchSessionState value;
  final AnswerPoint point;

  /// A web answer's point is expected to cite something.
  final bool expectsSource;

  @override
  ConsumerState<_PointRow> createState() => _PointRowState();
}

class _PointRowState extends ConsumerState<_PointRow> {
  bool _hovered = false;
  TextEditingController? _editing;

  @override
  void dispose() {
    _editing?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final value = widget.value;
    final point = widget.point;
    final sessionId = value.session.id;
    final drafts = value.drafts;
    final controller = ref.read(researchPanelProvider(widget.studySetId).notifier);
    final edited = drafts.edits[point.key];
    final checked = drafts.checked.contains(point.key);
    final quote = [for (final cite in point.cites) ?value.evidence.where((e) => e.id == cite.evidenceId).firstOrNull]
        .firstOrNull;
    final editing = _editing;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: MMSpacing.xs),
        padding: const EdgeInsets.all(MMSpacing.s),
        decoration: BoxDecoration(
          color: checked ? c.researchTint : (_hovered ? c.hover : null),
          borderRadius: BorderRadius.circular(MMRadii.field),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: MMCheckbox(
                key: ValueKey('check-${point.key}'),
                value: checked,
                color: c.research,
                semanticLabel: edited ?? point.text,
                onChanged: (_) => controller.toggleChecked(sessionId, point.key),
              ),
            ),
            const SizedBox(width: MMSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (editing != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        MMTextField(
                          key: ValueKey('edit-${point.key}'),
                          controller: editing,
                          maxLines: 6,
                          minLines: 2,
                          autofocus: true,
                          semanticLabel: l.researchEditPoint,
                        ),
                        const SizedBox(height: MMSpacing.xs),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MMButton(
                              label: l.cancel,
                              variant: MMButtonVariant.plain,
                              onPressed: () => setState(() {
                                _editing = null;
                                editing.dispose();
                              }),
                            ),
                            MMButton(
                              key: ValueKey('edit-save-${point.key}'),
                              label: l.save,
                              onPressed: () async {
                                final text = editing.text.trim() == point.text ? '' : editing.text;
                                setState(() => _editing = null);
                                await controller.editPoint(sessionId, point.key, text);
                                editing.dispose();
                              },
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    Text.rich(
                      TextSpan(
                        style: t.body.copyWith(height: 20 / 13),
                        children: [
                          TextSpan(text: edited ?? point.text),
                          for (final cite in point.cites)
                            if (value.numberOf(cite.sourceId) > 0)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: CiteBadge(
                                  number: value.numberOf(cite.sourceId),
                                  title: value.sources.firstWhere((s) => s.id == cite.sourceId).title,
                                  onTap: () => controller.openReading(
                                    cite.sourceId,
                                    paragraphId: evidenceParagraph(value.evidence, cite),
                                  ),
                                ),
                              ),
                          if (edited != null)
                            TextSpan(
                              text: ' · ${l.researchEdited}',
                              style: t.footnote.copyWith(color: c.secondaryLabel),
                            ),
                          if (point.cites.isEmpty && widget.expectsSource)
                            TextSpan(
                              text: ' · ${l.researchNoSourceBasis}',
                              style: t.footnote.copyWith(color: c.caution),
                            ),
                        ],
                      ),
                    ),
                  if (quote != null) ...[
                    const SizedBox(height: MMSpacing.s - 2),
                    Container(
                      padding: const EdgeInsets.only(left: MMSpacing.s + 2),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: c.research, width: 2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(quote.quote, maxLines: 4, overflow: TextOverflow.ellipsis, style: t.readingExcerpt),
                          const SizedBox(height: MMSpacing.xxs),
                          Text(
                            l.researchQuoteFrom(value.numberOf(quote.sourceId)),
                            style: t.footnote.copyWith(color: c.secondaryLabel),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_hovered && editing == null)
                    Padding(
                      padding: const EdgeInsets.only(top: MMSpacing.xs),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _PointAction(
                            label: l.researchEditPoint,
                            onTap: () => setState(() => _editing = TextEditingController(text: edited ?? point.text)),
                          ),
                          _PointAction(
                            label: l.researchAskPoint,
                            onTap: () => ref
                                .read(_composerDraftProvider(sessionId).notifier)
                                .put(l.researchAskAbout(edited ?? point.text)),
                          ),
                          _PointAction(
                            label: l.researchSavePoint,
                            onTap: () => showSaveNoteSheet(
                              context,
                              studySetId: widget.studySetId,
                              sessionId: sessionId,
                              points: [point],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointAction extends StatelessWidget {
  const _PointAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MMInteractive(
    onTap: onTap,
    semanticLabel: label,
    builder: (context, s) => Container(
      margin: const EdgeInsets.only(left: MMSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: 2),
      decoration: BoxDecoration(
        color: s.hovered ? context.mmColors.fill : context.mmColors.quaternaryFill,
        borderRadius: BorderRadius.circular(MMRadii.row),
      ),
      child: Text(label, style: context.mmText.footnote),
    ),
  );
}

/// "N selected · Save as Research Note…", fixed under the answer.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.count, required this.onClear, required this.onSave});

  final int count;
  final VoidCallback onClear;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l, vertical: MMSpacing.s),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          if (count > 0) ...[
            Expanded(
              child: Text(l.researchChecked(count), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.callout),
            ),
            MMButton(label: l.researchClearChecked, variant: MMButtonVariant.plain, onPressed: onClear),
            const SizedBox(width: MMSpacing.s),
          ] else
            const Spacer(),
          MMButton(
            key: const ValueKey('research-save-note'),
            label: l.researchSaveNote,
            variant: MMButtonVariant.primary,
            color: c.research,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Padding(
      padding: EdgeInsets.all(compact ? 0 : MMSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in compact ? const [0.7] : const [0.9, 0.7, 0.84, 0.6])
            FractionallySizedBox(
              widthFactor: w,
              child: Container(
                height: 12,
                margin: const EdgeInsets.only(bottom: MMSpacing.s + 2),
                decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(6)),
              ),
            ),
          Text(text, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
        ],
      ),
    );
  }
}

/// Text waiting in a session's follow-up box ("Ask" on a point puts it there).
class _ComposerDraft extends Notifier<String?> {
  _ComposerDraft(this.sessionId);

  final String sessionId;

  @override
  String? build() => null;

  void put(String? text) => state = text;
}

final _composerDraftProvider = NotifierProvider.family<_ComposerDraft, String?, String>(_ComposerDraft.new);

/// Follow-up questions in the same research (design 4.2 item 5).
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.studySetId, required this.value});

  final String studySetId;
  final ResearchSessionState value;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'ResearchFollowUp');

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final block = await ref
        .read(researchPanelProvider(widget.studySetId).notifier)
        .followUp(widget.value.session.id, text);
    if (block != null && mounted) _showBlock(context, block);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final sessionId = widget.value.session.id;
    ref.listen(_composerDraftProvider(sessionId), (_, next) {
      if (next == null) return;
      _controller.text = next;
      _focus.requestFocus();
      ref.read(_composerDraftProvider(sessionId).notifier).put(null);
    });
    final web = widget.value.drafts.method == ResearchMethod.web && ref.watch(researchSettingsProvider).webAvailable;
    final busy =
        ref.watch(researchPanelProvider(widget.studySetId).select((s) => s.progress.containsKey(sessionId))) ||
        widget.value.session.status == 'running';
    return Container(
      padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.s, MMSpacing.l, MMSpacing.m),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.separator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: MMTextField(
                  key: const ValueKey('research-followup'),
                  controller: _controller,
                  focusNode: _focus,
                  maxLines: 4,
                  minLines: 1,
                  placeholder: l.researchFollowUpPlaceholder,
                  semanticLabel: l.researchFollowUpPlaceholder,
                ),
              ),
              const SizedBox(width: MMSpacing.s),
              MMIconButton(
                key: const ValueKey('research-send'),
                icon: MMIcons.send,
                tooltip: l.researchSend,
                color: c.research,
                onPressed: busy ? null : _send,
              ),
            ],
          ),
          const SizedBox(height: MMSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MMPill(
              web ? l.researchCanUseWeb : l.researchOffline,
              icon: web ? MMIcons.web : MMIcons.offline,
              color: web ? c.research : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips waiting to become a note, and the notes saved from this research.
class _SavedView extends ConsumerWidget {
  const _SavedView({required this.studySetId, required this.value});

  final String studySetId;
  final ResearchSessionState value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final content = ref.watch(workspaceContentProvider(studySetId)) ?? StudySetContent.empty;
    final clips = value.drafts.clips;
    final notes = [
      for (final n in content.researchNotes)
        if (n.sessionId == value.session.id) n,
    ];
    final controller = ref.read(researchPanelProvider(studySetId).notifier);
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    if (clips.isEmpty && notes.isEmpty) {
      return MMEmptyState(icon: MMIcons.addNote, title: l.researchNothingSaved);
    }
    final activeMap = ref.watch(workspaceProvider(studySetId).select((s) => s.activeMapId));
    return ListView(
      padding: const EdgeInsets.all(MMSpacing.l),
      children: [
        if (clips.isNotEmpty) ...[
          ResearchFieldLabel(l.researchClipsTitle),
          for (final clip in clips)
            _Card(
              key: ValueKey('clip-${clip.evidence.id}'),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text('“${clip.evidence.quote}”', style: t.readingExcerpt)),
                    MMIconButton(
                      icon: MMIcons.close,
                      tooltip: l.remove,
                      size: 20,
                      iconSize: 9,
                      onPressed: () => controller.removeClip(value.session.id, clip.evidence.id),
                    ),
                  ],
                ),
                const SizedBox(height: MMSpacing.xs),
                Text(
                  [
                    clip.sourceTitle,
                    if (clip.evidence.locator.paragraphId != null) '¶',
                    if (clip.evidence.acquisition == EvidenceAcquisition.userPaste) l.researchPasted,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.footnote.copyWith(color: c.secondaryLabel),
                ),
              ],
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MMButton(
              key: const ValueKey('save-clips'),
              label: l.researchNoteFromClips,
              variant: MMButtonVariant.primary,
              color: c.research,
              onPressed: () =>
                  showSaveNoteSheet(context, studySetId: studySetId, sessionId: value.session.id, clips: clips),
            ),
          ),
          const SizedBox(height: MMSpacing.l),
        ],
        if (notes.isNotEmpty) ResearchFieldLabel(l.researchSavedNotes),
        for (final note in notes)
          _Card(
            key: ValueKey('saved-${note.id}'),
            onTap: () => controller.showNote(note.id),
            children: [
              Text(note.title, style: t.headline),
              if (note.body.isNotEmpty) ...[
                const SizedBox(height: MMSpacing.xs),
                Text(note.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.footnote),
              ],
              const SizedBox(height: MMSpacing.s),
              Wrap(
                spacing: MMSpacing.xs,
                runSpacing: MMSpacing.xs,
                children: [
                  for (final a in content.noteAttachments)
                    if (a.noteId == note.id)
                      switch (a.target) {
                        PdfTarget(:final pages) => _AttachmentChip(
                          icon: MMIcons.document,
                          label: l.researchInSource(pages.first.page),
                          onTap: () => workspace.revealNoteInSource(note.id),
                        ),
                        CardTarget(:final cardId) when content.node(cardId, mapId: activeMap) != null =>
                          _AttachmentChip(
                            icon: MMIcons.mindMap,
                            label: l.researchInMap(_parentTitle(content, cardId, activeMap, l)),
                            onTap: () => workspace.locateNoteCard(note.id),
                          ),
                        _ => const SizedBox.shrink(),
                      },
                  _AttachmentChip(icon: MMIcons.link, label: l.researchCitations(note.citations.length)),
                ],
              ),
            ],
          ),
      ],
    );
  }

  static String _parentTitle(StudySetContent content, String cardId, String mapId, AppLocalizations l) {
    final parent = content.node(cardId, mapId: mapId)?.parentId;
    if (parent == null) return content.map(mapId)?.title.isNotEmpty ?? false ? content.map(mapId)!.title : l.mainMap;
    return content.card(parent)?.title ?? '';
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: 2),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(MMRadii.row)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: c.icon),
          const SizedBox(width: MMSpacing.xs),
          Text(label, style: context.mmText.footnote),
        ],
      ),
    );
    if (onTap == null) return chip;
    return MMInteractive(onTap: onTap, semanticLabel: label, builder: (context, s) => chip);
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.children, this.onTap});

  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    Widget box(bool hovered) => Container(
      margin: const EdgeInsets.only(bottom: MMSpacing.s),
      padding: const EdgeInsets.all(MMSpacing.m),
      decoration: BoxDecoration(
        color: hovered ? c.hover : c.card,
        borderRadius: BorderRadius.circular(MMRadii.card - 2),
        border: Border.all(color: c.separator),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
    if (onTap == null) return box(false);
    return MMInteractive(onTap: onTap, isButton: false, builder: (context, s) => box(s.hovered));
  }
}
