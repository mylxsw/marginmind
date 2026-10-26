import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/app.dart';
import '../../app/app_commands.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../shared/card_image.dart';
import '../../shared/l10n.dart';
import '../../settings/app_settings.dart';
import '../../shared/pdf_drop.dart';
import 'workspace_controller.dart';
import 'widgets/map_pane.dart';
import 'widgets/notices.dart';
import 'widgets/reader_pane.dart';
import 'widgets/workspace_sidebar.dart';

/// A study set window: sidebar, unified toolbar, and the source / map split
/// (design canvas artboard 01).
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = workspaceProvider(widget.studySetId);
    ref.listen(focusRequestsProvider, (_, next) {
      if (next?.$1 != FocusTarget.search) return;
      ref.read(provider.notifier).showSidebar();
      // The field takes focus once the sidebar is back in the tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    });

    ref.watch(
      provider.select(
        (s) => (
          s.sidebarVisible,
          s.layout,
          s.splitFraction,
          s.tool,
          s.color,
          s.syncToMap,
          s.activeDocumentId,
          s.readerPanelVisible,
        ),
      ),
    );
    final state = ref.read(provider);
    final minReader = state.readerPanelVisible
        ? ref.watch(settingsProvider.select((s) => s.readerSidebarWidth)) +
              MMSizes.readerContentMinWidth +
              MMSizes.dividerHitWidth
        : MMSizes.readerMinWidth;
    final controller = ref.read(provider.notifier);
    final content = ref.watch(workspaceContentProvider(widget.studySetId));
    final doc = state.activeDocumentId == null ? null : content?.document(state.activeDocumentId!);
    final setTitle = ref.watch(studySetProvider(widget.studySetId).select((s) => s?.title)) ?? '';

    return CardImageScope(
      resolve: controller.imagePath,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Preserve independent sidebar choices. Narrow windows temporarily
          // show one content pane; the toolbar reflects the visible layout.
          final shown = (
            sidebarVisible: state.sidebarVisible,
            mode: MMSplitView.effectiveMode(
              state.layout,
              constraints.maxWidth - (state.sidebarVisible ? MMSizes.sidebarWidth + MMSizes.sidebarInset : 0),
              minReader,
              MMSizes.mapMinWidth,
            ),
          );
          final collapsed = state.sidebarVisible && !shown.sidebarVisible;
          if (collapsed != state.sidebarAutoCollapsed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) controller.setSidebarAutoCollapsed(collapsed);
            });
          }
          return _scaffold(context, state, controller, doc, setTitle, shown.sidebarVisible, shown.mode, minReader);
        },
      ),
    );
  }

  Widget _scaffold(
    BuildContext context,
    WorkspaceState state,
    WorkspaceController controller,
    Document? doc,
    String setTitle,
    bool sidebarVisible,
    MMSplitMode layout,
    double minReader,
  ) {
    final l = context.l10n;
    return MMWindowScaffold(
      sidebarVisible: sidebarVisible,
      onDragStart: WindowChrome.onDragStart,
      onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
      showsWindowButtons: WindowChrome.showsWindowButtons,
      sidebar: WorkspaceSidebar(studySetId: widget.studySetId, searchFocus: _searchFocus),
      toolbar: Consumer(
        builder: (context, ref, _) {
          final page = doc == null
              ? null
              : (ref.watch(readingPagesProvider(widget.studySetId).select((p) => p[doc.id])) ?? doc.lastPage);
          return MMToolbar(
            title: doc?.title ?? setTitle,
            subtitle: doc == null ? null : l.pageNumber(page!),
            leading: sidebarVisible
                ? null
                : MMIconButton(icon: MMIcons.sidebar, tooltip: l.showSidebar, onPressed: controller.showSidebar),
            actions: [
              MMToolbarGroup(
                children: [
                  MMToolbarButton(
                    icon: MMIcons.layoutReader,
                    tooltip: AppShortcuts.tip(l.layoutReader, AppShortcuts.view1),
                    selected: layout == MMSplitMode.primary,
                    onPressed: () => controller.setLayout(MMSplitMode.primary),
                  ),
                  MMToolbarButton(
                    icon: MMIcons.layoutSplit,
                    tooltip: AppShortcuts.tip(l.layoutSplit, AppShortcuts.view2),
                    selected: layout == MMSplitMode.split,
                    onPressed: () => controller.setLayout(MMSplitMode.split),
                  ),
                  MMToolbarButton(
                    icon: MMIcons.layoutMap,
                    tooltip: AppShortcuts.tip(l.layoutMap, AppShortcuts.view3),
                    selected: layout == MMSplitMode.secondary,
                    onPressed: () => controller.setLayout(MMSplitMode.secondary),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      body: PdfDropTarget(
        label: l.dropToImport,
        onDrop: (files) async {
          final notice = await controller.importDocuments(files);
          if (context.mounted) showNotice(context, notice, rootTitle: setTitle);
        },
        child: MMSplitView(
          mode: layout,
          onModeChanged: controller.setLayout,
          primaryLabel: l.layoutReader,
          secondaryLabel: l.layoutMap,
          splitLabel: l.layoutSplit,
          fraction: state.splitFraction,
          minPrimaryWidth: minReader,
          onFractionChanged: controller.setSplitFraction,
          primary: ReaderPane(studySetId: widget.studySetId),
          secondary: MapPane(studySetId: widget.studySetId),
        ),
      ),
    );
  }
}
