import 'dart:async';

import 'package:mm_platform/mm_platform.dart' show describeShortcut;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../../research/research_controller.dart' show researchPanelProvider;
import '../../workspace/widgets/notices.dart' show showConfirmSheet, showRenameSheet;
import '../../workspace/workspace_controller.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';

/// The saved conversations with the live ones in place of their copies.
List<ConversationSummary> conversationsOf(WidgetRef ref, String studySetId) => mergeLive(
  ref.watch(assistantConversationsProvider(studySetId)).value ?? const [],
  ref.watch(assistantControllerProvider),
  background: ref.watch(assistantBackgroundProvider),
);

/// Shows [id] in the panel (from [origin]); the open conversation stays as it is.
Future<void> openConversation(WidgetRef ref, String studySetId, String id) async {
  final ui = ref.read(assistantUiProvider(studySetId).notifier);
  ui.showHistory(false);
  ref.read(researchPanelProvider(studySetId).notifier).closeNote();
  ref.read(workspaceProvider(studySetId).notifier).openPanel(RightPanel.assistant);
  if (ref.read(assistantControllerProvider).id == id) return;
  try {
    await ref.read(assistantControllerProvider.notifier).openConversation(id);
  } catch (_) {
    // A damaged file stays as it is and the panel keeps the conversation it had.
  }
}

/// The status pill of a conversation row; null when there is nothing to say.
Widget? conversationTrailing(BuildContext context, ConversationSummary s) {
  final c = context.mmColors;
  final l = context.l10n;
  return switch (s.state) {
    ConversationState.running => MMPill(l.assistantRunning, color: c.research, icon: null).withSpinner(c.research),
    ConversationState.unfinished => MMPill(l.assistantUnfinished, color: c.caution),
    ConversationState.failed => MMPill(l.assistantFailed, color: c.critical),
    ConversationState.idle when s.notes > 0 => MMCount(s.notes),
    _ => null,
  };
}

extension on MMPill {
  /// The pill with a 9pt spinner before it: an answer is being written.
  Widget withSpinner(Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 9, height: 9, child: CupertinoActivityIndicator(radius: 4.5, color: color)),
      const SizedBox(width: 3),
      this,
    ],
  );
}

/// Right-click on a conversation: rename, delete (saved notes stay).
void showConversationMenu(
  BuildContext context,
  WidgetRef ref,
  String studySetId,
  ConversationSummary s,
  Offset position,
) {
  final l = context.l10n;
  showMMMenu(
    context,
    position: position,
    entries: [
      MMMenuItem(l.rename, () => renameConversation(context, ref, studySetId, s)),
      MMMenuItem(l.assistantDeleteEllipsis, () => deleteConversation(context, ref, studySetId, s), destructive: true),
    ],
  );
}

Future<void> renameConversation(BuildContext context, WidgetRef ref, String studySetId, ConversationSummary s) async {
  final title = await showRenameSheet(context, title: context.l10n.assistantRenameConversation, initial: s.title);
  if (title == null || title.trim().isEmpty) return;
  try {
    // A live conversation would write its old title back.
    if (!await ref.read(assistantControllerProvider.notifier).rename(title, conversationId: s.id)) {
      await renameSavedConversation(ref.read(assistantArchiveProvider(studySetId)), s.id, title);
    }
  } catch (_) {
    if (context.mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.warning);
  }
  ref.invalidate(assistantConversationsProvider(studySetId));
}

Future<void> deleteConversation(BuildContext context, WidgetRef ref, String studySetId, ConversationSummary s) async {
  final l = context.l10n;
  final ok = await showConfirmSheet(
    context,
    title: l.assistantDeleteTitle,
    message: l.assistantDeleteMessage,
    confirmLabel: l.delete,
  );
  if (!ok) return;
  try {
    // Its answer stops and the open conversation is replaced first, so
    // nothing writes it back.
    final controller = ref.read(assistantControllerProvider.notifier);
    await controller.stopConversation(s.id);
    if (ref.read(assistantControllerProvider).id == s.id) await controller.newConversation();
    await ref.read(assistantArchiveProvider(studySetId)).storage.delete(s.id);
  } catch (_) {
    if (context.mounted) MMHud.show(context, l.somethingWentWrong, icon: MMIcons.warning);
  }
  ref.invalidate(assistantConversationsProvider(studySetId));
}

/// The title dropdown's list of conversations, in place of the messages.
class ConversationHistory extends ConsumerWidget {
  const ConversationHistory({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final list = conversationsOf(ref, studySetId);
    final current = ref.watch(assistantControllerProvider.select((s) => s.id));
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ListView(
      key: const ValueKey('assistant-history'),
      padding: const EdgeInsets.fromLTRB(MMSpacing.s, MMSpacing.m, MMSpacing.s, MMSpacing.l),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: Text(l.assistantHistory, style: t.subheadline.copyWith(color: c.secondaryLabel)),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(l.assistantNoConversations, style: t.footnote.copyWith(color: c.secondaryLabel)),
          ),
        for (final s in list)
          MMContextMenuRegion(
            onSecondaryTapUp: (d) => showConversationMenu(context, ref, studySetId, s, d.globalPosition),
            child: MMInteractive(
              key: ValueKey('history-${s.id}'),
              onTap: () => openConversation(ref, studySetId, s.id),
              selected: s.id == current,
              builder: (context, st) => AnimatedContainer(
                duration: MMMotion.quick,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: MMSpacing.s),
                decoration: BoxDecoration(
                  color: s.id == current ? c.selectedRow : (st.hovered ? c.hover : Colors.transparent),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(MMIcons.conversation, size: 14, color: c.research),
                    const SizedBox(width: MMSpacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title.isEmpty ? l.assistant : s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.body.copyWith(fontWeight: FontWeight.w500, color: c.label),
                          ),
                          Text(
                            [
                              if (s.stamp > 0)
                                DateFormat.MMMd(locale).add_Hm().format(DateTime.fromMicrosecondsSinceEpoch(s.stamp)),
                              l.assistantQuestions(s.questions),
                              if (s.notes > 0) l.assistantHasNote,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.footnote.copyWith(color: c.secondaryLabel),
                          ),
                        ],
                      ),
                    ),
                    ?conversationTrailing(context, s),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The sidebar's "Conversations" group: the five latest, or one row that
/// opens the assistant.
class AssistantSidebarSection extends ConsumerWidget {
  const AssistantSidebarSection({super.key, required this.studySetId, required this.matches});

  final String studySetId;

  /// The sidebar search.
  final bool Function(String text) matches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final l = context.l10n;
    final all = conversationsOf(ref, studySetId);
    final list = all.where((s) => matches(s.title)).take(5).toList();
    final open = ref.watch(workspaceProvider(studySetId).select((s) => s.panel == RightPanel.assistant));
    final current = ref.watch(assistantControllerProvider.select((s) => s.id));
    if (all.isNotEmpty && list.isEmpty) return const SizedBox.shrink();
    return MMSidebarSection(
      title: l.assistantConversations,
      trailing: MMIconButton(
        key: const ValueKey('sidebar-new-conversation'),
        icon: MMIcons.add,
        size: 20,
        iconSize: 12,
        tooltip: l.assistantNewConversation,
        onPressed: () {
          ref.read(assistantUiProvider(studySetId).notifier).showHistory(false);
          unawaited(ref.read(assistantControllerProvider.notifier).newConversation().catchError((Object _) {}));
          askAssistant(ref, studySetId);
        },
      ),
      children: [
        if (all.isEmpty)
          MMSidebarItem(
            key: const ValueKey('sidebar-ask-assistant'),
            icon: MMIcons.ai,
            iconColor: c.research,
            label: l.askAssistantEllipsis,
            // Long elsewhere (three modifiers spelled out): only the Mac shows it.
            trailing: defaultTargetPlatform == TargetPlatform.macOS
                ? Text(describeShortcut(AppShortcuts.assistantPanel), style: context.mmText.footnote)
                : null,
            onTap: () => askAssistant(ref, studySetId),
          ),
        for (final s in list)
          MMSidebarItem(
            key: ValueKey('sidebar-conversation-${s.id}'),
            icon: MMIcons.conversation,
            iconColor: c.research,
            label: s.title.isEmpty ? l.assistant : s.title,
            selected: open && s.id == current,
            trailing: conversationTrailing(context, s),
            onTap: () => openConversation(ref, studySetId, s.id),
            onContextMenu: (position) => showConversationMenu(context, ref, studySetId, s, position),
          ),
      ],
    );
  }
}
