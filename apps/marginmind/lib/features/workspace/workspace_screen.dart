import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/app.dart';
import '../../app/app_commands.dart';
import '../../app/navigation.dart';
import 'workspace_chrome_controller.dart';
import 'reader_crop.dart';
import '../../app/providers.dart';
import '../../shared/card_image.dart';
import '../../shared/l10n.dart';
import '../../settings/app_settings.dart';
import '../../shared/pdf_drop.dart';
import '../assistant/assistant_entry.dart';
import '../assistant/widgets/assistant_panel.dart';
import 'workspace_controller.dart';
import '../study_notes/note_view.dart';
import '../study_notes/note_setup_sheet.dart';
import 'widgets/map_pane.dart';
import 'widgets/workspace_toolbar.dart';
import 'widgets/notices.dart';
import 'widgets/reader_pane.dart';
import 'widgets/right_panel.dart';
import 'widgets/tablet_workspace_panes.dart';
import 'widgets/workspace_sidebar.dart';
import 'workspace_layout.dart';
import 'workspace_pane_chrome_controller.dart';

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
  final _paneChrome = WorkspacePaneChromeController();
  final _chrome = WorkspaceChromeController();

  /// Whether the sidebar drawer of a touch window is out. Touch windows
  /// start with it in, whatever the saved sidebar choice.
  bool _drawer = false;
  double _tabletPanelFraction = .38;

  void _setDrawer(bool open) {
    if (_drawer != open) setState(() => _drawer = open);
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _paneChrome.dispose();
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = workspaceProvider(widget.studySetId);
    final touchPlatform = MMInput.of(context).touchPlatform;
    ref.listen(focusRequestsProvider, (_, next) {
      if (next?.$1 != FocusTarget.search) return;
      touchPlatform ? _setDrawer(true) : ref.read(provider.notifier).showSidebar();
      // The field takes focus once the sidebar is back in the tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    });
    // On touch the sidebar commands (and the drawer's own hide button) move
    // the drawer; opening a document puts it away.
    ref.listen(provider.select((s) => s.sidebarVisible), (_, _) {
      if (touchPlatform) _setDrawer(!_drawer);
    });
    ref.listen(provider.select((s) => s.activeDocumentId), (_, _) {
      if (touchPlatform) _setDrawer(false);
    });
    ref.listen(provider.select((s) => s.tagFilter), (_, next) {
      if (touchPlatform && next != null) _setDrawer(false);
    });

    ref.watch(
      provider.select(
        (s) => (
          s.activeNoteId,
          s.sidebarVisible,
          s.layout,
          s.splitFraction,
          s.tool,
          s.color,
          s.syncToMap,
          s.activeDocumentId,
          s.readerPanelVisible,
          s.panel,
          s.pending,
          s.findVisible,
          s.editingCardId,
          s.editingMarkId,
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

    final media = MediaQuery.of(context);
    final geometry = (media.size, state.layout, state.activeDocumentId);
    final holds = <String>{
      if (!touchPlatform || media.accessibleNavigation) 'accessibility',
      if (media.viewInsets.bottom > 0) 'keyboard',
      if (_drawer) 'drawer',
      if (state.panel != null) 'panel',
      if (state.pending != null ||
          state.tool != AnnotationTool.select ||
          state.findVisible ||
          state.editingCardId != null ||
          state.editingMarkId != null ||
          ref.watch(readerCropProvider(widget.studySetId)).editing)
        'editing',
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final reason in ['accessibility', 'keyboard', 'drawer', 'panel', 'editing']) {
        holds.contains(reason) ? _chrome.hold(reason) : _chrome.release(reason);
      }
      _chrome.reset(geometry);
    });
    return WorkspaceChromeScope(
      controller: _chrome,
      child: MMPopupActivity(
        onChanged: (owner, open) => open ? _chrome.hold(owner) : _chrome.release(owner),
        child: Theme(
          data: Theme.of(context).copyWith(extensions: [context.mmColors.copyWith(flat: true)]),
          child: WorkspacePaneChromeScope(
            controller: _paneChrome,
            child: MMFlatSurface(
              child: AssistantScope(
                studySetId: widget.studySetId,
                child: CardImageScope(
                  resolve: controller.imagePath,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final safe = MediaQuery.paddingOf(context);
                      final width = constraints.maxWidth - safe.horizontal;
                      final height = constraints.maxHeight - safe.vertical;
                      final sizeClass = MMSizeClass.resolve(context, Size(width, height));
                      controller.panelFloats = context.mmTablet || sizeClass != MMSizeClass.regular;
                      // A landscape phone is too short to stack the panes.
                      final canSplit =
                          sizeClass != MMSizeClass.medium ||
                          MMSplitView.effectiveMode(
                                MMSplitMode.split,
                                height - MMSizes.toolbarHeight,
                                MMSizes.paneMinHeight,
                                MMSizes.paneMinHeight,
                              ) ==
                              MMSplitMode.split;
                      controller.onePane = sizeClass == MMSizeClass.compact || !canSplit;
                      // The assistant keeps the user's sidebar and pane choices. Other
                      // panels may temporarily hide them in narrow windows; the toolbar
                      // reflects the visible layout. Touch windows use a sidebar drawer.
                      final shown = resolveWorkspaceLayout(
                        windowWidth: width,
                        sidebarVisible: state.sidebarVisible && !touchPlatform,
                        layout: state.layout,
                        panelOpen: state.panel != null,
                        preservePanes: state.panel == RightPanel.assistant,
                        minReader: minReader,
                        sizeClass: sizeClass,
                        windowHeight: height - MMSizes.toolbarHeight,
                      );
                      controller.onePane =
                          controller.onePane || (state.layout == MMSplitMode.split && shown.mode != MMSplitMode.split);
                      final collapsed = !touchPlatform && state.sidebarVisible && !shown.sidebarVisible;
                      if (collapsed != state.sidebarAutoCollapsed) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) controller.setSidebarAutoCollapsed(collapsed);
                        });
                      }
                      return MMBackHandler(
                        onBack: () => _back(controller, touchPlatform),
                        child: _scaffold(
                          context,
                          state,
                          controller,
                          doc,
                          setTitle,
                          shown.sidebarVisible,
                          state.content?.studyNote(state.activeNoteId ?? '') != null &&
                                  state.layout == MMSplitMode.split &&
                                  shown.mode == MMSplitMode.primary
                              ? MMSplitMode.secondary
                              : shown.mode,
                          minReader,
                          shown.panelWidth,
                          sizeClass,
                          touchPlatform,
                          canSplit,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// System back closes the sidebar drawer, then the right panel.
  bool _back(WorkspaceController controller, bool touchPlatform) {
    if (touchPlatform && _drawer) {
      _setDrawer(false);
      return true;
    }
    if (ref.read(workspaceProvider(widget.studySetId)).panel != null) {
      controller.closePanel();
      return true;
    }
    return false;
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
    double panelWidth,
    MMSizeClass sizeClass,
    bool touchPlatform,
    bool canSplit,
  ) {
    final l = context.l10n;
    final compact = sizeClass == MMSizeClass.compact;
    final tablet = context.mmTablet;
    final media = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final tabletLayout = resolveTabletWorkspaceLayout(
      size: Size(
        media.width - safe.horizontal,
        media.height - safe.vertical - MMSizes.toolbarHeight - MediaQuery.viewInsetsOf(context).bottom,
      ),
      layout: state.layout,
      panelOpen: state.panel != null,
      isLandscape: media.width - safe.horizontal > media.height - safe.vertical,
      panelFraction: _tabletPanelFraction,
      minReader: minReader,
    );
    if (tablet) {
      layout = tabletLayout.mode;
      controller.onePane = layout != MMSplitMode.split;
      canSplit = true;
    }
    final stacked = tablet ? tabletLayout.splitAxis == Axis.vertical : sizeClass == MMSizeClass.medium;
    final phone = MMInput.of(context).phone;
    final mergedToolbar = !compact || touchPlatform;
    final leading = sidebarVisible && !touchPlatform
        ? null
        : MMIconButton(
            icon: MMIcons.sidebar,
            tooltip: l.showSidebar,
            size: context.mmToolbarIcon,
            onPressed: touchPlatform ? () => _setDrawer(true) : controller.showSidebar,
          );
    MMToolbarItem action(
      String id,
      IconData icon,
      String label,
      VoidCallback invoke, {
      bool selected = false,
      Color? tint,
      int priority = 0,
    }) => MMToolbarItem(
      id: id,
      priority: priority,
      child: MMToolbarButton(
        key: ValueKey('toolbar-$id'),
        icon: icon,
        tooltip: label,
        selected: selected,
        tint: tint,
        onPressed: invoke,
      ),
      menuEntry: MMDropdownItem<VoidCallback>(
        key: ValueKey('workspace-command-$id'),
        value: invoke,
        child: Row(
          children: [
            Icon(switch (id) {
              'layout-reader' => MMReaderIcons.layoutReader,
              'layout-split' => MMIcons.compare,
              'assistant' => MMReaderIcons.assistant,
              _ => icon,
            }, size: MMSizes.dropdownIcon),
            const SizedBox(width: MMSpacing.s),
            Expanded(child: Text(label)),
            if (selected) const Icon(MMIcons.check, size: MMSizes.dropdownIcon),
          ],
        ),
      ),
    );
    final globalActions = <MMToolbarItem>[
      action(
        'layout-reader',
        MMIcons.layoutReader,
        AppShortcuts.tip(l.layoutReader, AppShortcuts.view1),
        () => controller.setLayout(MMSplitMode.primary),
        selected: layout == MMSplitMode.primary,
      ),
      if (canSplit)
        action(
          'layout-split',
          MMIcons.layoutSplit,
          AppShortcuts.tip(l.layoutSplit, AppShortcuts.view2),
          () => controller.setLayout(MMSplitMode.split),
          selected: layout == MMSplitMode.split,
        ),
      action(
        'layout-map',
        MMIcons.layoutMap,
        AppShortcuts.tip(l.layoutMap, AppShortcuts.view3),
        () => controller.setLayout(MMSplitMode.secondary),
        selected: layout == MMSplitMode.secondary,
      ),
      if (MMPlatformCapabilities.current.assistant)
        action(
          'assistant',
          MMIcons.ai,
          AppShortcuts.tip(l.assistant, AppShortcuts.assistantPanel),
          () => toggleAssistant(ref, widget.studySetId),
          selected: state.panel == RightPanel.assistant,
          tint: context.mmColors.research,
          priority: 80,
        ),
    ];
    final globalMenuEntries = <PopupMenuEntry<VoidCallback>>[
      action(
        'organize-note',
        MMIcons.organizeNote,
        AppShortcuts.tip(l.organizeNotes, AppShortcuts.organizeStudyNote),
        () => showNoteSetupSheet(context, ref, widget.studySetId),
      ).menuEntry,
    ];
    Widget paneChrome(Widget child, {required bool primary}) => !mergedToolbar
        ? child
        : WorkspaceToolbarScope(
            actions: phone ? const [] : globalActions,
            menuEntries: phone ? const [] : globalMenuEntries,
            primary: primary,
            leading: phone ? null : leading,
            ownsLeading: !phone && (primary || layout == MMSplitMode.secondary),
            ownsActions: primary
                ? stacked || layout == MMSplitMode.primary
                : !stacked || layout == MMSplitMode.secondary,
            child: child,
          );
    final split = MMSplitView(
      mode: layout,
      showModeButtons: !mergedToolbar,
      onModeChanged: (!tablet && compact) || !canSplit ? null : controller.setLayout,
      primaryLabel: l.layoutReader,
      secondaryLabel: l.layoutMap,
      splitLabel: l.layoutSplit,
      fraction: state.splitFraction,
      axis: stacked ? Axis.vertical : Axis.horizontal,
      minPrimaryWidth: stacked ? MMSizes.paneMinHeight : minReader,
      minSecondaryWidth: stacked ? MMSizes.paneMinHeight : MMSizes.mapMinWidth,
      collapseWhenNarrow: stacked || state.panel != RightPanel.assistant,
      onFractionChanged: controller.setSplitFraction,
      primary: PdfDropTarget(
        label: l.dropToImport,
        onDrop: (files) async {
          final notice = await controller.importDocuments(files);
          if (context.mounted) showNotice(context, notice, rootTitle: setTitle);
        },
        child: paneChrome(ReaderPane(studySetId: widget.studySetId), primary: true),
      ),
      secondary: PdfDropTarget(
        label: l.dropImage,
        onDrop: (files) async {
          final notice = await controller.importDocuments(files);
          if (context.mounted) showNotice(context, notice, rootTitle: setTitle);
        },
        onImageDrop: (files) =>
            insertImageFiles(context, ref, widget.studySetId, [for (final file in files) file.path]),
        child: paneChrome(
          state.content?.studyNote(state.activeNoteId ?? '') != null
              ? StudyNoteView(studySetId: widget.studySetId, noteId: state.activeNoteId!)
              : MapPane(studySetId: widget.studySetId),
          primary: false,
        ),
      ),
    );
    final floating = sizeClass != MMSizeClass.regular;
    final paneSwitch = compact && !mergedToolbar;
    final panel = state.panel == null ? null : RightPanelView(studySetId: widget.studySetId);
    Widget compactSwitcher(double top) => Padding(
      padding: EdgeInsets.fromLTRB(MMSpacing.m, top, MMSpacing.m, MMSpacing.s),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: MMSizes.paneSwitchMaxWidth),
          child: MMSegmentedControl<MMSplitMode>(
            key: const ValueKey('workspace-pane-switch'),
            expand: true,
            segments: [
              MMSegment(value: MMSplitMode.primary, label: l.paneSource),
              MMSegment(value: MMSplitMode.secondary, label: l.paneMap),
            ],
            value: layout == MMSplitMode.secondary ? MMSplitMode.secondary : MMSplitMode.primary,
            onChanged: controller.setLayout,
          ),
        ),
      ),
    );
    final toolbar = MMToolbar(
      title: doc?.title ?? setTitle,
      leading: sidebarVisible && !touchPlatform
          ? null
          : MMIconButton(
              icon: MMIcons.sidebar,
              tooltip: l.showSidebar,
              size: context.mmToolbarIcon,
              onPressed: touchPlatform ? () => _setDrawer(true) : controller.showSidebar,
            ),
      actions: [
        if (!compact)
          MMToolbarGroup(
            children: [
              MMToolbarButton(
                icon: MMIcons.layoutReader,
                tooltip: AppShortcuts.tip(l.layoutReader, AppShortcuts.view1),
                selected: layout == MMSplitMode.primary,
                onPressed: () => controller.setLayout(MMSplitMode.primary),
              ),
              if (canSplit)
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
        MMToolbarGroup(
          children: [
            if (MMPlatformCapabilities.current.assistant)
              MMToolbarButton(
                key: const ValueKey('toolbar-assistant'),
                icon: MMIcons.ai,
                tint: context.mmColors.research,
                tooltip: AppShortcuts.tip(l.assistant, AppShortcuts.assistantPanel),
                selected: state.panel == RightPanel.assistant,
                onPressed: () => toggleAssistant(ref, widget.studySetId),
              ),
          ],
        ),
        MMDropdownButton<VoidCallback>(
          key: const ValueKey('workspace-more'),
          tooltip: l.moreTools,
          itemBuilder: (_) => globalMenuEntries,
          onSelected: (command) => command(),
        ),
      ],
    );
    final body = ExcerptViewScope(
      showInMap: compact && layout != MMSplitMode.secondary ? controller.showCardInMap : null,
      child: Builder(
        builder: (context) {
          // The panes run on beneath a touch window's glass chrome; the pane
          // switch and the right panel stay clear of it.
          final chrome = MMChromeInsets.of(context);
          if (tablet) {
            final panes = TabletWorkspacePanes(
              content: split,
              panel: panel,
              axis: tabletLayout.panelAxis,
              extent: tabletLayout.panelExtent,
              onResize: (delta) => setState(() {
                final height = (media.height - safe.vertical - MMSizes.toolbarHeight).clamp(1.0, double.infinity);
                _tabletPanelFraction = (_tabletPanelFraction + delta / height).clamp(.25, .6);
              }),
            );
            if (!paneSwitch) return panes;
            return Column(
              children: [
                compactSwitcher(chrome.top),
                Expanded(child: MMChromeInsets.remove(context, removeTop: true, child: panes)),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (paneSwitch) compactSwitcher(chrome.top),
              Expanded(
                child: MMChromeInsets.remove(
                  context,
                  removeTop: paneSwitch,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: split),
                            if (panel != null && !floating)
                              Padding(
                                padding: EdgeInsets.only(top: chrome.top, bottom: chrome.bottom),
                                child: SizedBox(width: panelWidth, child: panel),
                              ),
                          ],
                        ),
                      ),
                      if (panel != null && floating && !compact)
                        Positioned.fill(
                          top: chrome.top,
                          bottom: chrome.bottom,
                          child: Stack(
                            children: [
                              MMDrawer(
                                open: true,
                                end: true,
                                inset: MMSpacing.s,
                                width: panelWidth,
                                onDismiss: controller.closePanel,
                                child: _FloatingPanel(child: panel),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (mergedToolbar) {
      return MMWindowScaffold.contentBuilder(
        // A compact window has no room beside or over the panes: the panel
        // rises from the bottom.
        sheet: !tablet && compact && panel != null
            ? MMBottomSheet(
                key: const ValueKey('workspace-panel-sheet'),
                expand: true,
                scrim: true,
                onDismiss: controller.closePanel,
                child: panel,
              )
            : null,
        sidebarVisible: touchPlatform ? _drawer : sidebarVisible,
        sidebarOverlay: touchPlatform,
        onSidebarDismiss: () => _setDrawer(false),
        onDragStart: WindowChrome.onDragStart,
        onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
        showsWindowButtons: WindowChrome.showsWindowButtons,
        sidebar: WorkspaceSidebar(studySetId: widget.studySetId, searchFocus: _searchFocus),
        contentBuilder: (context, constraints) => WorkspaceLayoutGeometryScope(
          geometry: WorkspaceLayoutGeometry.resolve(
            size: constraints.biggest,
            mode: layout,
            axis: stacked ? Axis.vertical : Axis.horizontal,
            fraction: state.splitFraction,
            minReader: minReader,
            sidebarExtent: (media.width - safe.horizontal - constraints.maxWidth).clamp(0.0, double.infinity),
            panelExtent: panel == null
                ? 0
                : tablet
                ? tabletLayout.panelExtent
                : floating
                ? 0
                : panelWidth,
            panelAxis: tablet ? tabletLayout.panelAxis : Axis.horizontal,
            tablet: tablet,
            collapseWhenNarrow: stacked || state.panel != RightPanel.assistant,
          ),
          child: phone
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: MMChromeInsets(
                        insets: const EdgeInsets.only(
                          top: MMSizes.phoneWorkspaceToolbarHeight,
                          bottom: MMSizes.thumbDock + 30,
                        ),
                        child: body,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: WorkspaceChromeBar(
                        child: SizedBox(
                          height: MMSizes.phoneWorkspaceToolbarHeight,
                          child: Container(
                            color: context.mmColors.windowBackground,
                            foregroundDecoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: context.mmColors.separator, width: MMSizes.hairline),
                              ),
                            ),
                            child: Row(
                              children: [
                                ?leading,
                                Expanded(
                                  child: MMSegmentedControl<MMSplitMode>(
                                    key: const ValueKey('workspace-pane-switch'),
                                    expand: true,
                                    segments: [
                                      MMSegment(value: MMSplitMode.primary, label: l.paneSource),
                                      MMSegment(value: MMSplitMode.secondary, label: l.paneMap),
                                    ],
                                    value: layout == MMSplitMode.secondary
                                        ? MMSplitMode.secondary
                                        : MMSplitMode.primary,
                                    onChanged: controller.setLayout,
                                  ),
                                ),
                                if (MMPlatformCapabilities.current.assistant)
                                  MMToolbarButton(
                                    key: const ValueKey('toolbar-assistant'),
                                    icon: MMIcons.ai,
                                    tooltip: l.assistant,
                                    tint: context.mmColors.research,
                                    onPressed: () => toggleAssistant(ref, widget.studySetId),
                                  ),
                                MMDropdownButton<VoidCallback>(
                                  key: const ValueKey('phone-workspace-more'),
                                  tooltip: l.moreTools,
                                  onOpened: () => _chrome.hold('phone-menu'),
                                  onClosed: () => _chrome.release('phone-menu'),
                                  onSelected: (action) => action(),
                                  itemBuilder: (_) => [
                                    MMDropdownItem(
                                      key: const ValueKey('workspace-command-organize-note'),
                                      value: () => showNoteSetupSheet(context, ref, widget.studySetId),
                                      child: Text(l.organizeNotes),
                                    ),
                                    MMDropdownItem(
                                      enabled: ref.read(studySetProvider(widget.studySetId)) != null,
                                      value: () => ref.read(navigationProvider.notifier).startReview(widget.studySetId),
                                      child: Text(l.review),
                                    ),
                                    MMDropdownItem(
                                      value: () => ref
                                          .read(navigationProvider.notifier)
                                          .showVocabulary(studySetId: widget.studySetId),
                                      child: Text(l.vocabularyTitle),
                                    ),
                                    MMDropdownItem(
                                      value: () => ref.read(navigationProvider.notifier).showLibrary(),
                                      child: Text(l.librarySection),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : body,
        ),
      );
    }
    return MMWindowScaffold(
      extendBody: true,
      // A compact window has no room beside or over the panes: the panel
      // rises from the bottom.
      sheet: !tablet && compact && panel != null
          ? MMBottomSheet(
              key: const ValueKey('workspace-panel-sheet'),
              expand: true,
              scrim: true,
              onDismiss: controller.closePanel,
              child: panel,
            )
          : null,
      sidebarVisible: touchPlatform ? _drawer : sidebarVisible,
      sidebarOverlay: touchPlatform,
      onSidebarDismiss: () => _setDrawer(false),
      onDragStart: WindowChrome.onDragStart,
      onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
      showsWindowButtons: WindowChrome.showsWindowButtons,
      sidebar: WorkspaceSidebar(studySetId: widget.studySetId, searchFocus: _searchFocus),
      toolbar: toolbar,
      body: body,
    );
  }
}

/// The right panel floating over the panes: a rounded, shadowed card.
class _FloatingPanel extends StatelessWidget {
  const _FloatingPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    const radius = BorderRadius.all(Radius.circular(MMRadii.sidebar));
    return DecoratedBox(
      key: const ValueKey('workspace-floating-panel'),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          for (final s in c.sidebarShadow) BoxShadow(color: s.color, offset: s.offset, blurRadius: s.blurRadius),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
