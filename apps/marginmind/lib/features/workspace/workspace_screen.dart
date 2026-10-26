import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/app.dart';
import '../../app/app_commands.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../shared/card_image.dart';
import '../../shared/l10n.dart';
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
      if (!ref.read(provider).sidebarVisible) ref.read(provider.notifier).toggleSidebar();
      _searchFocus.requestFocus();
    });

    final l = context.l10n;
    ref.watch(
      provider.select(
        (s) => (s.sidebarVisible, s.layout, s.splitFraction, s.tool, s.color, s.syncToMap, s.activeDocumentId),
      ),
    );
    final state = ref.read(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(workspaceContentProvider(widget.studySetId));
    final doc = state.activeDocumentId == null ? null : content?.document(state.activeDocumentId!);
    final setTitle = ref.watch(studySetProvider(widget.studySetId).select((s) => s?.title)) ?? '';

    return CardImageScope(
      resolve: controller.imagePath,
      child: MMWindowScaffold(
        sidebarVisible: state.sidebarVisible,
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
              subtitle: doc == null ? null : '$setTitle · ${l.pageNumber(page!)}',
              leading: state.sidebarVisible
                  ? null
                  : MMIconButton(icon: MMIcons.sidebar, tooltip: l.showSidebar, onPressed: controller.toggleSidebar),
              actions: [
                _AnnotationTools(state: state, controller: controller),
                MMToolbarGroup(
                  children: [
                    MMToolbarButton(
                      icon: MMIcons.layoutReader,
                      tooltip: AppShortcuts.tip(l.layoutReader, AppShortcuts.view1),
                      selected: state.layout == MMSplitMode.primary,
                      onPressed: () => controller.setLayout(MMSplitMode.primary),
                    ),
                    MMToolbarButton(
                      icon: MMIcons.layoutSplit,
                      tooltip: AppShortcuts.tip(l.layoutSplit, AppShortcuts.view2),
                      selected: state.layout == MMSplitMode.split,
                      onPressed: () => controller.setLayout(MMSplitMode.split),
                    ),
                    MMToolbarButton(
                      icon: MMIcons.layoutMap,
                      tooltip: AppShortcuts.tip(l.layoutMap, AppShortcuts.view3),
                      selected: state.layout == MMSplitMode.secondary,
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
            mode: state.layout,
            fraction: state.splitFraction,
            onFractionChanged: controller.setSplitFraction,
            primary: ReaderPane(studySetId: widget.studySetId),
            secondary: MapPane(studySetId: widget.studySetId),
          ),
        ),
      ),
    );
  }
}

class _AnnotationTools extends StatelessWidget {
  const _AnnotationTools({required this.state, required this.controller});

  final WorkspaceState state;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    MMToolbarButton tool(IconData icon, String label, AnnotationTool value) => MMToolbarButton(
      icon: icon,
      tooltip: switch (value) {
        AnnotationTool.highlight => AppShortcuts.tip(label, AppShortcuts.toggleAnnotationTool),
        AnnotationTool.area => AppShortcuts.tip(label, AppShortcuts.toggleAreaTool),
        AnnotationTool.select => label,
      },
      selected: state.tool == value,
      onPressed: () => controller.setTool(value),
    );
    return MMToolbarGroup(
      children: [
        tool(MMIcons.select, l.toolSelect, AnnotationTool.select),
        tool(MMIcons.highlight, l.toolHighlight, AnnotationTool.highlight),
        tool(MMIcons.areaSelect, l.toolArea, AnnotationTool.area),
        const MMToolbarDivider(),
        for (final color in MMAnnotationColor.values)
          _ColorDot(
            color: color,
            label: l.colorName(color),
            selected: state.color == color,
            onPressed: () => controller.setColor(color),
          ),
        const MMToolbarDivider(),
        MMToolbarButton(
          icon: MMIcons.syncToMap,
          tooltip: state.syncToMap ? l.syncToMapOn : l.syncToMapOff,
          selected: state.syncToMap,
          onPressed: controller.toggleSyncToMap,
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.label, required this.selected, required this.onPressed});

  final MMAnnotationColor color;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ring = context.mmColors.windowBackground;
    return MMInteractive(
      onTap: onPressed,
      selected: selected,
      tooltip: label,
      semanticLabel: label,
      builder: (context, s) => SizedBox(
        width: 24,
        height: 30,
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color.color,
              shape: BoxShape.circle,
              boxShadow: selected || s.focused
                  ? [BoxShadow(color: color.color, spreadRadius: 3.5), BoxShadow(color: ring, spreadRadius: 2)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
