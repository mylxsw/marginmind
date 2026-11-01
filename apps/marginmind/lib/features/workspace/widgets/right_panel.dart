import 'workspace_tab_strip.dart';
import 'reference_content.dart';
import 'tag_content_pane.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../assistant/widgets/assistant_panel.dart';
import '../workspace_controller.dart';
import 'card_details.dart';

/// The right panel: the assistant or the selected card's details, one at a time.
/// Esc closes it unless a field inside uses the key first.
///
/// It appears and goes at once, like the split view's layouts: while its
/// width animated, the panes beside it would pass through the narrow-window
/// fallbacks (the map briefly hidden).
class RightPanelView extends ConsumerStatefulWidget {
  const RightPanelView({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<RightPanelView> createState() => _RightPanelViewState();
}

class _RightPanelViewState extends ConsumerState<RightPanelView> {
  bool _assistantOpened = false;
  String get studySetId => widget.studySetId;
  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final provider = workspaceProvider(studySetId);
    final (panel, referenceAssistant) = ref.watch(provider.select((s) => (s.panel, s.tabs.current.referenceAssistant)));
    final showReference = panel == RightPanel.reference || (panel == RightPanel.assistant && referenceAssistant);
    final showAssistant = panel == RightPanel.assistant && !referenceAssistant;
    final controller = ref.read(provider.notifier);
    _assistantOpened |= showAssistant;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): controller.closePanel},
      child: FocusTraversalGroup(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.mmTouchPlatform ? c.sidebarOpaque : c.workspaceChrome,
            border: Border(left: BorderSide(color: c.separator)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: !showReference,
                child: TickerMode(
                  enabled: showReference,
                  child: ExcludeFocus(
                    excluding: !showReference,
                    child: _OwnedReferences(studySetId: studySetId),
                  ),
                ),
              ),
              if (_assistantOpened)
                Offstage(
                  offstage: !showAssistant,
                  child: TickerMode(
                    enabled: showAssistant,
                    child: ExcludeFocus(
                      excluding: !showAssistant,
                      child: AssistantPanel(studySetId: studySetId),
                    ),
                  ),
                ),
              if (panel == RightPanel.tags) Focus(autofocus: true, child: TagContentPane(studySetId: studySetId)),
              if (panel == RightPanel.details) CardDetails(studySetId: studySetId),
            ],
          ),
        ),
      ),
    );
  }
}

/// The panel's top row: what it shows, in [color], and a close button.
class RightPanelHeader extends StatelessWidget {
  const RightPanelHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.onClose,
    this.color,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;

  /// Defaults to the secondary label color.
  final Color? color;

  /// Shown before the close button.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final tint = color ?? c.secondaryLabel;
    return Container(
      height: MMSizes.toolbarGroupHeight + MMSpacing.s,
      padding: const EdgeInsets.only(left: MMSpacing.l, right: MMSpacing.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: MMSpacing.xs + 1),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.subheadline.copyWith(color: tint),
            ),
          ),
          ...actions,
          MMIconButton(icon: MMIcons.close, tooltip: context.l10n.closePanel, iconSize: 13, onPressed: onClose),
        ],
      ),
    );
  }
}

/// Inactive owners stay mounted so switching tabs preserves reference position.
class _OwnedReferences extends ConsumerWidget {
  const _OwnedReferences({required this.studySetId});
  final String studySetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(workspaceProvider(studySetId).select((s) => s.tabs));
    ref.watch(workspaceContentProvider(studySetId));
    final state = ref.read(workspaceProvider(studySetId));
    final tabs = state.tabs;
    final owners = tabs.open.where((tab) => tabs.contexts[tab.id]?.reference != null).toList();
    final index = owners.indexWhere((tab) => tab.id == tabs.activeId);
    if (owners.isEmpty) return const SizedBox.shrink();
    return Offstage(
      offstage: index < 0,
      child: IndexedStack(
        index: index < 0 ? 0 : index,
        sizing: StackFit.expand,
        children: [
          for (final tab in owners)
            TickerMode(
              key: ValueKey('owned-reference-${tab.id}'),
              enabled: tab.id == tabs.activeId,
              child: ExcludeFocus(
                excluding: tab.id != tabs.activeId,
                child: ReferenceContent(
                  key: ObjectKey(tabs.contexts[tab.id]!.reference!),
                  studySetId: studySetId,
                  reference: tabs.contexts[tab.id]!.reference!,
                  ownerTabId: tab.id,
                  ownerTitle: tab.kind == WorkspaceTabKind.documentMap
                      ? state.content?.document(state.activeDocumentId ?? '')?.title ??
                            workspaceTabTitle(context, state, tab)
                      : workspaceTabTitle(context, state, tab),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
