import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

String workspaceTabTitle(BuildContext context, WorkspaceState state, WorkspaceTab tab) => switch (tab.kind) {
  WorkspaceTabKind.documentMap => context.l10n.workspaceDocumentMapTab,
  WorkspaceTabKind.note => state.content?.studyNote(tab.noteId ?? '')?.title ?? context.l10n.notesTitle,
  WorkspaceTabKind.vocabulary => context.l10n.vocabularyTitle,
  WorkspaceTabKind.review => context.l10n.review,
};

class WorkspaceTabStrip extends ConsumerStatefulWidget {
  const WorkspaceTabStrip({super.key, required this.studySetId});
  final String studySetId;
  @override
  ConsumerState<WorkspaceTabStrip> createState() => _WorkspaceTabStripState();
}

class _WorkspaceTabStripState extends ConsumerState<WorkspaceTabStrip> {
  final _keys = <String, GlobalKey>{};
  String? _lastActive;
  double? _lastWidth;
  String get studySetId => widget.studySetId;
  @override
  Widget build(BuildContext context) {
    ref.watch(workspaceProvider(studySetId).select((s) => s.tabs));
    ref.watch(workspaceContentProvider(studySetId));
    final state = ref.read(workspaceProvider(studySetId));
    final owner = ref.read(workspaceProvider(studySetId).notifier);
    final c = context.mmColors;
    _keys.removeWhere((id, _) => !state.tabs.open.any((tab) => tab.id == id));
    for (final tab in state.tabs.open) {
      _keys.putIfAbsent(tab.id, () => GlobalKey());
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        if (_lastActive != state.tabs.activeId || _lastWidth != bounds.maxWidth) {
          _lastActive = state.tabs.activeId;
          _lastWidth = bounds.maxWidth;
          final key = _keys[_lastActive];
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = key?.currentContext;
            if (mounted && target != null) {
              Scrollable.ensureVisible(
                target,
                alignment: .5,
                duration: MMAppearance.duration(context, MMMotion.standard),
              );
            }
          });
        }
        return SingleChildScrollView(
          key: const ValueKey('workspace-main-tabs'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tab in state.tabs.open)
                MMInteractive(
                  key: ValueKey('workspace-tab-${tab.id}'),
                  selected: tab.id == state.tabs.activeId,
                  semanticLabel: workspaceTabTitle(context, state, tab),
                  tooltip: workspaceTabTitle(context, state, tab),
                  onTap: () => owner.activateTab(tab),
                  builder: (context, interaction) => Container(
                    key: _keys[tab.id],
                    constraints: const BoxConstraints(maxWidth: 210, minHeight: 44),
                    padding: const EdgeInsets.only(left: MMSpacing.m, right: MMSpacing.xs),
                    decoration: BoxDecoration(
                      color: interaction.hovered ? c.hover : null,
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: tab.id == state.tabs.activeId ? c.accent : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          switch (tab.kind) {
                            WorkspaceTabKind.documentMap => MMIcons.document,
                            WorkspaceTabKind.note => MMIcons.studyNote,
                            WorkspaceTabKind.vocabulary => MMIcons.vocabulary,
                            WorkspaceTabKind.review => MMIcons.review,
                          },
                          size: 15,
                          color: tab.id == state.tabs.activeId ? c.accent : c.secondaryLabel,
                        ),
                        const SizedBox(width: MMSpacing.s),
                        Flexible(
                          child: Text(
                            workspaceTabTitle(context, state, tab),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.mmText.body,
                          ),
                        ),
                        MMIconButton(
                          key: ValueKey('close-workspace-tab-${tab.id}'),
                          icon: MMIcons.close,
                          iconSize: 12,
                          size: context.mmTouchPlatform ? 44 : 28,
                          tooltip: '${context.l10n.closeTab} · ${workspaceTabTitle(context, state, tab)}',
                          onPressed: () => owner.closeTab(tab.id),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
