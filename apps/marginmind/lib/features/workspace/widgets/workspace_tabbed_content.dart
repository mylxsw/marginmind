import 'workspace_menu.dart';
import 'workspace_toolbar.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/navigation.dart';
import '../../../shared/l10n.dart';
import '../../review/review_screen.dart';
import '../../review/stats_screen.dart';
import '../../study_notes/note_view.dart';
import '../../vocabulary/vocabulary_screen.dart';
import '../workspace_content_host.dart';
import '../workspace_controller.dart';

/// Keep tabs mounted at a usable size: editors, reading and review survive.
class WorkspaceTabbedContent extends ConsumerWidget {
  const WorkspaceTabbedContent({super.key, required this.studySetId, required this.documentMap});
  final String studySetId;
  final Widget documentMap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(workspaceProvider(studySetId).select((s) => s.tabs));

    final state = ref.read(workspaceProvider(studySetId));
    final tabs = state.tabs.open;
    if (tabs.isEmpty) return Center(child: Text(context.l10n.workspaceNoTabs, style: context.mmText.body));
    return WorkspaceContentHost(
      openSource: (sourceId, anchor) =>
          ref.read(workspaceProvider(studySetId).notifier).openAnchorReference(anchor, sourceStudySetId: sourceId),
      child: IndexedStack(
        index: tabs.indexWhere((tab) => tab.id == state.tabs.activeId).clamp(0, tabs.length - 1),
        sizing: StackFit.expand,
        children: [
          for (final tab in tabs)
            TickerMode(
              key: ValueKey('workspace-tab-body-${tab.id}'),
              enabled: tab.id == state.tabs.activeId,
              child: ExcludeFocus(
                excluding: tab.id != state.tabs.activeId,
                child: WorkspaceToolbarScope(
                  actions: const [],
                  leading: null,
                  ownsActions: true,
                  ownsLeading: false,
                  useGeometry: false,
                  menuEntries: workspaceMenuEntries(context, ref, studySetId),
                  child: switch (tab.kind) {
                    WorkspaceTabKind.documentMap => documentMap,
                    WorkspaceTabKind.note => StudyNoteView(studySetId: studySetId, noteId: tab.noteId!),
                    WorkspaceTabKind.vocabulary => VocabularyScreen(
                      embedded: true,
                      route: VocabularyRoute(studySetId: studySetId, returnTo: WorkspaceRoute(studySetId)),
                    ),
                    WorkspaceTabKind.review => ReviewScreen(studySetId: studySetId, embedded: true),
                    WorkspaceTabKind.statistics => StatsScreen(studySetId: studySetId, embedded: true),
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
