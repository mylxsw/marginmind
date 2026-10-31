import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../research/research_controller.dart' show researchPanelProvider;
import '../../research/research_origin.dart' show researchCardTitle;
import '../../research/widgets/research_note_view.dart';
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';
import '../../../settings/settings_window.dart';
import '../assistant_settings.dart';
import 'assistant_conversations.dart';
import 'assistant_composer.dart';
import 'assistant_markdown.dart' show sourceNumbers;
import 'assistant_messages.dart';
import 'assistant_model_menu.dart' show sameModel;
import 'assistant_overlays.dart';

/// Gives a study set window its assistant: the conversation lives as long as
/// the window, so closing the panel or switching documents never stops an
/// answer. Entry points outside the window ask through [assistantUiProvider].
class AssistantScope extends ConsumerStatefulWidget {
  const AssistantScope({super.key, required this.studySetId, required this.child});

  final String studySetId;
  final Widget child;

  @override
  ConsumerState<AssistantScope> createState() => _AssistantScopeState();
}

class _AssistantScopeState extends ConsumerState<AssistantScope> {
  late final _dependencies = ref.read(assistantDependenciesForProvider(widget.studySetId));

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      assistantDependenciesProvider.overrideWithValue(_dependencies),
      assistantControllerProvider.overrideWith(AssistantController.new),
      assistantBackgroundProvider.overrideWith(AssistantBackground.new),
    ],
    child: MMPlatformCapabilities.current.assistant
        ? _AssistantHost(studySetId: widget.studySetId, child: widget.child)
        : widget.child,
  );
}

class _AssistantHost extends ConsumerWidget {
  const _AssistantHost({required this.studySetId, required this.child});

  final String studySetId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listening keeps the conversation alive without rebuilding the window.
    ref.listen(assistantControllerProvider.select((c) => (c.id, c.running, c.title, c.messages.length)), (
      previous,
      next,
    ) {
      if (previous != next) ref.invalidate(assistantConversationsProvider(studySetId));
    });
    ref.listen(assistantBackgroundProvider.select((c) => (c?.id, c?.title, c?.messages.length)), (previous, next) {
      if (previous != next) ref.invalidate(assistantConversationsProvider(studySetId));
    });
    // Undo and redo take a proposal's receipt away or bring it back.
    ref.listen(
      workspaceProvider(studySetId).select((s) => s.content?.assistantReceipts.map((r) => r.proposalId).join('\n')),
      (previous, next) {
        if (previous != next) unawaited(ref.read(assistantControllerProvider.notifier).syncReceipts());
      },
    );
    // Reading a study set only loads model metadata. Credentials are checked
    // when the assistant panel opens or a question is actually requested.
    // An empty conversation follows the default model (it loads after the
    // window opens, and may change in settings); used ones keep theirs.
    ref.listen(assistantDefaultModelProvider, (previous, next) {
      final open = ref.read(assistantControllerProvider);
      if (next == null || open.readOnly || open.messages.isNotEmpty) return;
      if (sameModel(open.model, next) && open.model.endpoint == next.endpoint) return;
      unawaited(ref.read(assistantControllerProvider.notifier).switchModel(next).catchError((Object _) {}));
    });
    ref.listen(assistantUiProvider(studySetId).select((s) => s.request), (_, request) async {
      if (request == null) return;
      ref.read(assistantUiProvider(studySetId).notifier).handled(request.id);
      final l = context.l10n;
      final configured = await ref.read(assistantConfiguredProvider.future).catchError((Object _) => false);
      if (!configured || !context.mounted) return; // The panel shows how to connect.
      assistantSend(ref, studySetId, l, request.text, skill: request.skill);
    });
    return child;
  }
}

/// The right panel's assistant: header, the conversation (or the list of
/// conversations), and the input.
class AssistantPanel extends ConsumerWidget {
  const AssistantPanel({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(assistantUiProvider(studySetId));
    final uiNotifier = ref.read(assistantUiProvider(studySetId).notifier);
    final conversation = ref.watch(assistantControllerProvider);
    final configured = ref.watch(assistantConfiguredProvider).value ?? false;
    final noteId = ref.watch(researchPanelProvider(studySetId).select((s) => s.noteId));
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final header = AssistantHeader(studySetId: studySetId);
    if (noteId != null) {
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
    final source = ui.source;
    final number = source == null
        ? 0
        : conversation.messages
                  .where((m) => m.citations.any((c) => c.marker == source.marker && c.sourceId == source.sourceId))
                  .map((m) => sourceNumbers(m.text, m.citations)[source.sourceId])
                  .nonNulls
                  .firstOrNull ??
              0;

    // Esc, innermost first: the source, then a running answer, then the panel.
    void escape() {
      if (ui.source != null) return uiNotifier.closeSource();
      if (conversation.running) {
        unawaited(ref.read(assistantControllerProvider.notifier).stop());
        return;
      }
      workspace.closePanel();
    }

    final Widget body;
    if (ui.history) {
      body = ConversationHistory(studySetId: studySetId);
    } else if (!configured && conversation.messages.isEmpty) {
      body = const Center(child: SingleChildScrollView(child: ModelSetupCard()));
    } else if (conversation.messages.isEmpty) {
      body = AssistantSuggestions(studySetId: studySetId);
    } else {
      body = AssistantMessageList(key: ValueKey(conversation.id), studySetId: studySetId);
    }
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): escape},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!ui.history && !configured && conversation.messages.isNotEmpty)
                      const ModelSetupCard(inline: true),
                    Expanded(child: body),
                    // Browsing history must not discard the current draft.
                    if (configured && !conversation.readOnly)
                      Visibility(
                        visible: !ui.history,
                        maintainState: true,
                        child: ExcludeFocus(
                          excluding: ui.history,
                          child: AssistantComposer(
                            key: ValueKey(conversation.id),
                            studySetId: studySetId,
                            configured: configured,
                          ),
                        ),
                      ),
                  ],
                ),
                if (source != null)
                  _DrawerTransition(
                    child: SourceDrawer(studySetId: studySetId, citation: source, number: number),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The source drawer comes in from the right (at once with reduced motion).
class _DrawerTransition extends StatelessWidget {
  const _DrawerTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MMAppearance.duration(context, MMMotion.standard),
    curve: MMMotion.layoutCurve,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(24 * (1 - t), 0), child: child),
    ),
    child: child,
  );
}

/// The panel's title, history and new conversation.
class AssistantHeader extends ConsumerWidget {
  const AssistantHeader({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final title = ref.watch(assistantControllerProvider.select((s) => s.title));
    final history = ref.watch(assistantUiProvider(studySetId).select((s) => s.history));
    final ui = ref.read(assistantUiProvider(studySetId).notifier);
    var shown = title.trim().isEmpty ? l.assistant : title.trim();
    if (shown.runes.length > 24) shown = '${String.fromCharCodes(shown.runes.take(24))}…';
    return Container(
      height: context.mmTouchPlatform ? 52 : MMSizes.toolbarGroupHeight + MMSpacing.s,
      padding: const EdgeInsets.only(left: MMSpacing.s + 2, right: MMSpacing.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          // The title takes the free width, so the buttons sit at the right edge.
          Expanded(
            child: Row(
              key: const ValueKey('assistant-title'),
              children: [
                Container(
                  width: MMSpacing.xl,
                  height: MMSpacing.xl,
                  decoration: BoxDecoration(color: c.research, borderRadius: BorderRadius.circular(MMRadii.excerpt)),
                  child: Icon(
                    MMIcons.ai,
                    size: context.mmTouchPlatform ? 16 : context.mmToolbarIcon,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: MMSpacing.s),
                Expanded(
                  child: Text(
                    shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.headline.copyWith(color: c.label),
                  ),
                ),
              ],
            ),
          ),
          MMToolbarButton(
            key: const ValueKey('assistant-history-button'),
            icon: MMIcons.recent,
            tooltip: l.assistantHistory,
            selected: history,
            onPressed: () {
              ref.read(researchPanelProvider(studySetId).notifier).closeNote();
              ui.showHistory(!history);
            },
          ),
          MMIconButton(
            key: const ValueKey('assistant-new'),
            icon: MMIcons.add,
            iconSize: 13,
            tooltip: l.assistantNewConversation,
            onPressed: () => startNewConversation(ref, studySetId),
          ),
          if (context.mmTouchPlatform)
            MMIconButton(
              key: const ValueKey('assistant-close'),
              icon: MMIcons.close,
              tooltip: l.closePanel,
              onPressed: () => ref.read(workspaceProvider(studySetId).notifier).closePanel(),
            ),
        ],
      ),
    );
  }
}

/// A new, empty conversation in the panel.
void startNewConversation(WidgetRef ref, String studySetId) {
  ref.read(researchPanelProvider(studySetId).notifier).closeNote();
  ref.read(assistantUiProvider(studySetId).notifier).showHistory(false);
  unawaited(ref.read(assistantControllerProvider.notifier).newConversation().catchError((Object _) {}));
  ref.read(assistantUiProvider(studySetId).notifier).focus();
}

/// An empty conversation: five questions that fit what is open, sent on click.
class AssistantSuggestions extends ConsumerWidget {
  const AssistantSuggestions({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final auto = ref.watch(assistantAutoContextsProvider(studySetId));
    final ui = ref.watch(assistantUiProvider(studySetId));
    final online = ref.watch(assistantControllerProvider.select((c) => c.online));
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final mapId = ref.watch(workspaceProvider(studySetId).select((s) => s.activeMapId));
    final content = workspace.content;
    final page = auto.where((c) => c.kind == ContextKind.page).firstOrNull;
    final selection = ui.contexts.where((c) => c.kind == ContextKind.selection).firstOrNull;
    var topic = [
      ...ui.contexts,
      ...auto,
    ].where((c) => c.kind == ContextKind.node || c.kind == ContextKind.branch).firstOrNull;
    // No node attached: the latest topic excerpted from the page being read.
    if (topic == null && page != null) {
      final card = content.cards
          .where((c) => content.annotation(c.annotationId ?? '')?.documentId == page.documentId)
          .where((c) => content.annotation(c.annotationId!)!.page == page.page)
          .lastOrNull;
      final parent = card == null ? null : content.node(card.id, mapId: mapId)?.parentId;
      if (parent != null) topic = nodeContext(mapId: mapId, nodeId: parent, title: researchCardTitle(content, parent));
    }
    final suggestions = <(IconData, String, AssistantSkill, List<ContextItem>)>[
      if (page != null) (MMIcons.summarize, l.assistantSuggestSummarize(page.page!), AssistantSkill.summarize, [page]),
      if (topic != null)
        (MMIcons.explain, l.assistantSuggestExplain(topic.displayText), AssistantSkill.explain, [topic]),
      if (page != null && online)
        (MMIcons.verify, l.assistantSuggestVerify(page.page!), AssistantSkill.verify, [page])
      else if (selection != null)
        (MMIcons.translate, l.assistantSuggestTranslate, AssistantSkill.translate, [selection]),
      if (topic != null) (MMIcons.review, l.assistantSuggestQuiz(topic.displayText), AssistantSkill.quiz, [topic]),
      if (page != null) (MMIcons.organize, l.assistantSuggestOrganize, AssistantSkill.organize, [page]),
    ];
    return ListView(
      key: const ValueKey('assistant-suggestions'),
      padding: const EdgeInsets.fromLTRB(MMSpacing.l, MMSpacing.m, MMSpacing.l, MMSpacing.l),
      children: [
        for (final (icon, text, skill, contexts) in suggestions.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _Suggestion(
              icon: icon,
              text: text,
              onPressed: () {
                final notifier = ref.read(assistantUiProvider(studySetId).notifier);
                for (final c in contexts) {
                  if (!c.auto) notifier.addContext(c);
                }
                assistantSend(ref, studySetId, l, skill.prompt(l), skill: skill.name);
              },
            ),
          ),
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.icon, required this.text, required this.onPressed});

  final IconData icon;
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onPressed,
      semanticLabel: text,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MMSpacing.s),
        decoration: BoxDecoration(
          color: s.hovered ? c.researchTint : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: s.hovered ? c.research.withValues(alpha: .16) : c.separator),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c.research),
            const SizedBox(width: MMSpacing.s),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.mmText.body.copyWith(color: c.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet setup state, or an inline notice above an existing conversation.
/// Configuration and credential recovery both lead to the same settings page.
class ModelSetupCard extends ConsumerWidget {
  const ModelSetupCard({super.key, this.inline = false});

  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final credential = ref.watch(assistantCredentialStateProvider).value;
    final needsKey =
        credential == AssistantCredentialState.unavailable || credential == AssistantCredentialState.missingKey;
    final title = needsKey ? l.assistantKeyNeedsAttention : l.assistantSetupHint;
    final action = MMButton(
      key: const ValueKey('assistant-configure-models'),
      label: l.assistantOpenModelSettings,
      variant: MMButtonVariant.secondary,
      onPressed: () => showSettings(context, tab: SettingsTab.models),
    );
    return Container(
      key: const ValueKey('assistant-connect'),
      margin: const EdgeInsets.all(MMSpacing.m),
      padding: EdgeInsets.all(inline ? MMSpacing.s : MMSpacing.l),
      decoration: inline
          ? BoxDecoration(color: c.critical.withValues(alpha: .05), borderRadius: BorderRadius.circular(MMRadii.row))
          : null,
      child: inline
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: MMSpacing.s,
              runSpacing: MMSpacing.xs,
              children: [
                Text(title, style: t.callout.copyWith(color: c.label)),
                action,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(MMIcons.ai, size: 28, color: c.secondaryLabel),
                const SizedBox(height: MMSpacing.m),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: t.body.copyWith(color: c.secondaryLabel),
                ),
                const SizedBox(height: MMSpacing.m),
                action,
              ],
            ),
    );
  }
}
