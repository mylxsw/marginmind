import '../../../shared/assistant_icon.dart';
import '../../../shared/pdf_drop.dart';
import '../workspace_layout.dart';
import 'notices.dart';
import 'workspace_menu.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/app.dart';
import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../../assistant/assistant_entry.dart';
import '../workspace_controller.dart';
import 'map_pane.dart';
import 'reader_pane.dart';
import 'right_panel.dart';
import 'workspace_sidebar.dart';
import 'workspace_toolbar.dart';
import 'workspace_tab_strip.dart';
import 'workspace_tabbed_content.dart';

/// The tab row is window chrome; both sidebars are complete content regions.
class WorkspaceDesktopShell extends ConsumerWidget {
  const WorkspaceDesktopShell({
    super.key,
    required this.studySetId,
    required this.sidebarVisible,
    required this.onShowSidebar,
    required this.onDismissSidebar,
    required this.layout,
  });
  final String studySetId;
  final bool sidebarVisible;
  final VoidCallback onShowSidebar, onDismissSidebar;
  final MMSplitMode layout;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      workspaceProvider(studySetId).select((s) => (s.tabs, s.layout, s.panel, s.splitFraction, s.readerPanelVisible)),
    );

    final state = ref.read(workspaceProvider(studySetId));
    final owner = ref.read(workspaceProvider(studySetId).notifier);
    final c = context.mmColors;
    final touch = MMInput.of(context).touchPlatform;
    final toolbarHeight = touch ? MMSizes.windowTitlebarHeight : MMSizes.desktopWindowTitlebarHeight;
    final documents = state.tabs.active?.kind == WorkspaceTabKind.documentMap;
    final l = context.l10n;
    return MMWindowScaffold.contentBuilder(
      toolbarExtent: toolbarHeight,
      onDragStart: WindowChrome.onDragStart,
      onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
      showsWindowButtons: WindowChrome.showsWindowButtons,
      sidebarVisible: sidebarVisible,
      sidebarOverlay: touch,
      onSidebarDismiss: onDismissSidebar,
      sidebar: WorkspaceSidebar(studySetId: studySetId, onDismiss: onDismissSidebar),
      contentBuilder: (context, constraints) {
        final hasPanel = state.panel != null;
        final panelWidth = math.min(360.0, constraints.maxWidth);
        final inlinePanel = !touch && hasPanel && constraints.maxWidth >= 700;
        final content = Column(
          children: [
            MMToolbar.content(
              semanticLabel: l.workspaceDocumentMapTab,
              height: toolbarHeight,
              child: Container(
                key: const ValueKey('workspace-tab-row'),
                height: toolbarHeight,
                decoration: BoxDecoration(
                  color: touch ? Color.lerp(c.windowBackground, c.sidebarOpaque, .35) : c.windowBackground,
                ),
                foregroundDecoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: c.separator, width: MMSizes.hairline),
                  ),
                ),
                child: CustomMultiChildLayout(
                  delegate: _CenteredTitlebarLayout(),
                  children: [
                    LayoutId(
                      id: _TitlebarSlot.leading,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: switch (MMWindowChrome.maybeOf(context)?.toolbarLeadingInset ?? 0) {
                            final inset when inset > 0 => inset + 8,
                            _ => 0,
                          },
                        ),
                        child: !sidebarVisible || touch
                            ? MMIconButton(
                                key: const ValueKey('workspace-show-sidebar'),
                                icon: MMIcons.sidebar,
                                tooltip: l.showSidebar,
                                onPressed: onShowSidebar,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    LayoutId(
                      id: _TitlebarSlot.title,
                      child: WorkspaceTabStrip(studySetId: studySetId),
                    ),
                    LayoutId(
                      id: _TitlebarSlot.trailing,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (documents) ...[
                            Container(
                              key: const ValueKey('workspace-layout-controls'),
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: c.quaternaryFill,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final entry in [
                                    (MMSplitMode.primary, MMIcons.layoutReader, l.layoutReader),
                                    (MMSplitMode.split, MMIcons.layoutSplit, l.layoutSplit),
                                    (MMSplitMode.secondary, MMIcons.layoutMap, l.layoutMap),
                                  ])
                                    MMIconButton(
                                      key: ValueKey(
                                        'toolbar-layout-${switch (entry.$1) {
                                          MMSplitMode.primary => 'reader',
                                          MMSplitMode.split => 'split',
                                          MMSplitMode.secondary => 'map',
                                        }}',
                                      ),
                                      size: 28,
                                      icon: entry.$2,
                                      tooltip: entry.$3,
                                      selected: _shownLayout(context, constraints, state) == entry.$1,
                                      onPressed: () => owner.setLayout(entry.$1),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (MMPlatformCapabilities.current.assistant && state.panel != RightPanel.assistant) ...[
                            if (documents)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: SizedBox(
                                  height: 18,
                                  child: VerticalDivider(width: 1, thickness: 1, color: c.separator),
                                ),
                              ),
                            MMIconButton(
                              key: const ValueKey('toolbar-assistant'),
                              iconWidget: const AssistantIcon(),
                              iconSize: 18,
                              tooltip: AppShortcuts.tip(l.assistant, AppShortcuts.assistantPanel),
                              selected: state.panel == RightPanel.assistant,
                              color: c.research,
                              onPressed: () => toggleAssistant(ref, studySetId),
                            ),
                          ],
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              // Only the top tab row and sidebar header are window chrome.
              // Content headers must not inherit window drag/zoom callbacks.
              child: MMWindowChrome(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final narrow = box.maxWidth < 700;
                    final hasPanel = state.panel != null;
                    final panelWidth = math.min(360.0, box.maxWidth);
                    final documentMap = LayoutBuilder(
                      builder: (context, panes) {
                        final axis = context.mmTablet && panes.maxHeight > panes.maxWidth
                            ? Axis.vertical
                            : Axis.horizontal;
                        final minReader =
                            (hasPanel ? 300.0 : 420.0) +
                            (state.readerPanelVisible ? MMSizes.readerSidebarMinWidth + MMSizes.dividerHitWidth : 0);
                        final minMap = hasPanel ? 280.0 : 360.0;
                        Widget pane(Widget child, {required bool primary}) => WorkspaceToolbarScope(
                          actions: const [],
                          leading: null,
                          ownsActions: true,
                          ownsLeading: false,
                          useGeometry: false,
                          primary: primary,
                          menuEntries: workspaceMenuEntries(context, ref, studySetId),
                          child: child,
                        );
                        return WorkspaceLayoutGeometryScope(
                          geometry: WorkspaceLayoutGeometry.resolve(
                            size: panes.biggest,
                            mode: layout,
                            axis: axis,
                            fraction: state.splitFraction,
                            minReader: minReader,
                            minMap: minMap,
                            collapseWhenNarrow: true,
                          ),
                          child: ExcerptViewScope(
                            showInMap: owner.showCardInMap,
                            child: MMSplitView(
                              mode: layout,
                              showModeButtons: false,
                              collapseWhenNarrow: true,
                              onModeChanged: owner.setLayout,
                              primaryLabel: l.layoutReader,
                              secondaryLabel: l.layoutMap,
                              splitLabel: l.layoutSplit,
                              fraction: state.splitFraction,
                              axis: axis,
                              minPrimaryWidth: axis == Axis.vertical ? MMSizes.paneMinHeight : minReader,
                              minSecondaryWidth: axis == Axis.vertical ? MMSizes.paneMinHeight : minMap,
                              onFractionChanged: owner.setSplitFraction,
                              primary: PdfDropTarget(
                                label: l.dropToImport,
                                onDrop: (files) async {
                                  final notice = await owner.importDocuments(files);
                                  if (context.mounted) showNotice(context, notice, rootTitle: '');
                                },
                                child: pane(
                                  ReaderPane(studySetId: studySetId, showDocumentTitle: false),
                                  primary: true,
                                ),
                              ),
                              secondary: PdfDropTarget(
                                label: l.dropImage,
                                onDrop: (files) async {
                                  final notice = await owner.importDocuments(files);
                                  if (context.mounted) showNotice(context, notice, rootTitle: '');
                                },
                                onImageDrop: (files) =>
                                    insertImageFiles(context, ref, studySetId, [for (final file in files) file.path]),
                                child: pane(MapPane(studySetId: studySetId), primary: false),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                    final body = WorkspaceTabbedContent(studySetId: studySetId, documentMap: documentMap);
                    if (!touch) return body;
                    final panel = Padding(
                      padding: touch ? const EdgeInsets.fromLTRB(4, 8, 8, 8) : EdgeInsets.zero,
                      child: ClipRRect(
                        key: const ValueKey('workspace-right-sidebar'),
                        borderRadius: touch ? BorderRadius.circular(MMRadii.sidebar) : BorderRadius.zero,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.sidebarOpaque,
                            border: touch
                                ? Border.all(color: c.separator)
                                : Border(left: BorderSide(color: c.separator, width: .5)),
                            borderRadius: touch ? BorderRadius.circular(MMRadii.sidebar) : BorderRadius.zero,
                          ),
                          child: RightPanelView(studySetId: studySetId),
                        ),
                      ),
                    );
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Row(
                            children: [
                              Expanded(child: body),
                              SizedBox(width: hasPanel && !narrow ? panelWidth : 0),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: panelWidth,
                          child: Offstage(offstage: !hasPanel, child: panel),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
        if (touch) return content;
        return Stack(
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(child: content),
                  SizedBox(width: inlinePanel ? panelWidth : 0),
                ],
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: panelWidth,
              child: Offstage(
                offstage: !hasPanel,
                child: ClipRect(
                  key: const ValueKey('workspace-right-sidebar'),
                  child: RightPanelView(studySetId: studySetId),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  MMSplitMode _shownLayout(BuildContext context, BoxConstraints box, WorkspaceState state) {
    final hasPanel = state.panel != null;
    final width = box.maxWidth - (hasPanel && box.maxWidth >= 700 ? math.min(360.0, box.maxWidth) : 0);
    final height =
        box.maxHeight - (context.mmTouchPlatform ? MMSizes.windowTitlebarHeight : MMSizes.desktopWindowTitlebarHeight);
    final vertical = context.mmTablet && height > width;
    return MMSplitView.effectiveMode(
      layout,
      vertical ? height : width,
      vertical
          ? MMSizes.paneMinHeight
          : (hasPanel ? 300.0 : 420.0) +
                (state.readerPanelVisible ? MMSizes.readerSidebarMinWidth + MMSizes.dividerHitWidth : 0),
      vertical ? MMSizes.paneMinHeight : (hasPanel ? 280.0 : 360.0),
    );
  }
}

enum _TitlebarSlot { leading, title, trailing }

/// Measure the side controls first so the tabs stay at the workspace centre,
/// even when the sidebar toggle or assistant changes visibility.
class _CenteredTitlebarLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final sideConstraints = BoxConstraints(maxWidth: size.width / 2, maxHeight: size.height);
    final leading = layoutChild(_TitlebarSlot.leading, sideConstraints);
    final trailing = layoutChild(_TitlebarSlot.trailing, sideConstraints);
    final inset = math.max(leading.width, trailing.width);
    positionChild(_TitlebarSlot.leading, Offset(0, (size.height - leading.height) / 2));
    positionChild(_TitlebarSlot.trailing, Offset(size.width - trailing.width, (size.height - trailing.height) / 2));
    layoutChild(_TitlebarSlot.title, BoxConstraints.tight(Size(math.max(0, size.width - inset * 2), size.height)));
    positionChild(_TitlebarSlot.title, Offset(inset, 0));
  }

  @override
  bool shouldRelayout(_CenteredTitlebarLayout oldDelegate) => false;
}
