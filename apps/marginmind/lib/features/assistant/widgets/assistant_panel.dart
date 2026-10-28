import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../../research/research_controller.dart' show researchPanelProvider;
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
import 'assistant_model_menu.dart';
import 'assistant_prompt_bar.dart';
import '../../../app/providers.dart';
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
    child: _AssistantHost(studySetId: widget.studySetId, child: widget.child),
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
class AssistantPanel extends ConsumerStatefulWidget {
  const AssistantPanel({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends ConsumerState<AssistantPanel> {
  bool _voiceActive = false;

  @override
  Widget build(BuildContext context) {
    final studySetId = widget.studySetId;
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
    } else if (conversation.messages.isEmpty) {
      body = configured ? const SizedBox.shrink() : const Center(child: ModelSetupCard());
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
                    if (!ui.history && configured && !conversation.readOnly)
                      AssistantPromptBar(studySetId: studySetId, enabled: !_voiceActive),
                    if (!ui.history && !configured && conversation.messages.isNotEmpty)
                      const ModelSetupCard(inline: true),
                    if (ui.history || conversation.messages.isNotEmpty || !configured)
                      Expanded(key: const ValueKey('assistant-body'), child: body),
                    // Keep one composer, moving it within this Column after the
                    // first answer. Its draft and voice session retain identity.
                    if (!ui.history && configured && !conversation.readOnly)
                      AssistantComposer(
                        key: const ValueKey('assistant-composer'),
                        studySetId: studySetId,
                        configured: true,
                        onVoiceActiveChanged: (active) {
                          if (mounted && _voiceActive != active) setState(() => _voiceActive = active);
                        },
                      ),
                    if (!ui.history && configured && conversation.messages.isEmpty)
                      const Spacer(key: ValueKey('assistant-empty-space')),
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

/// The panel's top row: the conversation's title (opening the list of
/// conversations), then new conversation, settings and close.
class AssistantHeader extends ConsumerWidget {
  const AssistantHeader({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final title = ref.watch(assistantControllerProvider.select((s) => s.title));
    final modelLabel = conversationModelLabel(ref, ref.watch(assistantControllerProvider.select((s) => s.model)));
    final history = ref.watch(assistantUiProvider(studySetId).select((s) => s.history));
    final ui = ref.read(assistantUiProvider(studySetId).notifier);
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final shown = l.assistant;
    return Container(
      height: MMSizes.toolbarGroupHeight + MMSpacing.s,
      padding: const EdgeInsets.only(left: MMSpacing.s + 2, right: MMSpacing.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          // The title takes the free width, so the buttons sit at the right edge.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: MMInteractive(
                key: const ValueKey('assistant-title'),
                onTap: () {
                  ref.read(researchPanelProvider(studySetId).notifier).closeNote();
                  ui.showHistory(!history);
                },
                semanticLabel: shown,
                semanticValue: title.isEmpty ? l.assistantHistory : '${l.assistantHistory} · $title',
                tooltip: title.isEmpty ? l.assistantHistory : title,
                builder: (context, s) => AnimatedContainer(
                  duration: MMMotion.quick,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: s.hovered ? c.hover : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(MMIcons.ai, size: MMSpacing.xl, color: c.research),
                      const SizedBox(width: MMSpacing.s),
                      Flexible(
                        child: Text(
                          shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.headline.copyWith(color: c.label),
                        ),
                      ),
                      const SizedBox(width: MMSpacing.xs),
                      Icon(history ? MMIcons.chevronUp : MMIcons.chevronDown, size: 11, color: c.icon),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Builder(
            builder: (button) => MMIconButton(
              key: const ValueKey('assistant-menu'),
              icon: MMIcons.more,
              iconSize: 16,
              tooltip: l.assistantMoreActions,
              onPressed: () {
                final conversation = ref.read(assistantControllerProvider);
                final anchor = boundsOf(button);
                showMMMenu(
                  context,
                  position: anchor.bottomLeft,
                  entries: [
                    MMMenuItem(l.assistantNewConversation, () => startNewConversation(ref, studySetId)),
                    const MMMenuDivider(),
                    MMMenuItem(
                      '${l.assistantModel} · $modelLabel',
                      () => unawaited(showModelMenu(context, ref, anchor)),
                    ),
                    MMMenuItem(l.assistantOnline, () {
                      final online = !conversation.online;
                      unawaited(ref.read(sharedPreferencesProvider).setBool(assistantOnlineKey(studySetId), online));
                      unawaited(ref.read(assistantControllerProvider.notifier).setOnline(online));
                    }, checked: conversation.online),
                    const MMMenuDivider(),
                    MMMenuItem(l.assistantOpenModelSettings, () => showSettings(context, tab: SettingsTab.models)),
                  ],
                );
              },
            ),
          ),
          MMIconButton(
            key: const ValueKey('assistant-close'),
            icon: MMIcons.close,
            iconSize: 13,
            tooltip: AppShortcuts.tip(l.closePanel, AppShortcuts.assistantPanel),
            onPressed: workspace.closePanel,
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
