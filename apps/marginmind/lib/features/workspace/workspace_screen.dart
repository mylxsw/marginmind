import '../../shared/assistant_icon.dart';
import 'widgets/workspace_desktop_shell.dart';
import 'widgets/workspace_tabbed_content.dart';
import 'widgets/workspace_tab_strip.dart';
import 'widgets/workspace_history_controls.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/app.dart';
import '../../app/app_commands.dart';
import '../../app/navigation.dart';
import 'workspace_chrome_controller.dart';
import 'phone_reader_controls_controller.dart';
import 'widgets/phone_more_sheet.dart';
import 'widgets/phone_reader_controls.dart';
import 'reader_crop.dart';
import '../../app/providers.dart';
import '../../shared/card_image.dart';
import '../../shared/l10n.dart';
import '../../settings/app_settings.dart';
import '../../shared/pdf_drop.dart';
import '../assistant/assistant_entry.dart';
import '../assistant/widgets/assistant_panel.dart';
import 'workspace_controller.dart';
import 'widgets/full_translation_notifications.dart';
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
  final _paneChrome = WorkspacePaneChromeController();
  final _chrome = WorkspaceChromeController();
  late final PhoneReaderControlsController _phoneControls;
  bool _phoneCompact = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    _phoneControls = PhoneReaderControlsController(
      initiallyDockedRight: prefs.getBool('phoneReader.dockRight') ?? true,
      initiallyArmed: ref.read(workspaceProvider(widget.studySetId)).tool != AnnotationTool.select,
      onDockChanged: (right) => prefs.setBool('phoneReader.dockRight', right),
    );
    _phoneControls.addListener(_phoneControlsChanged);
    _chrome.onReadingScroll = () {
      if (_phoneCompact) _phoneControls.onReadingScroll();
    };
  }

  void _phoneControlsChanged() {
    if (_phoneCompact && _phoneControls.interacting) {
      _chrome.hold(
        _phoneControls,
        reveal: _phoneControls.slot == PhoneReaderSlot.tools || _phoneControls.slot == PhoneReaderSlot.scrub,
      );
    } else {
      _chrome.release(_phoneControls);
    }
  }

  /// Whether the sidebar drawer of a touch window is out. Touch windows
  /// start with it in, whatever the saved sidebar choice.
  bool _drawer = false;
  double _tabletPanelFraction = .38;

  void _setDrawer(bool open) {
    if (_drawer != open) setState(() => _drawer = open);
  }

  @override
  void dispose() {
    _paneChrome.dispose();
    _phoneControls.dispose();
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = workspaceProvider(widget.studySetId);
    final touchPlatform = MMInput.of(context).touchPlatform;
    _phoneCompact = usePhoneReaderControls(context);
    Widget surface(Widget child) => MMFlatSurface(child: child);
    // On touch the sidebar commands (and the drawer's own hide button) move
    // the drawer; opening a document puts it away.
    ref.listen(provider.select((s) => s.sidebarVisible), (_, _) {
      if (touchPlatform) _setDrawer(!_drawer);
    });
    ref.listen(provider.select((s) => s.activeDocumentId), (_, _) {
      if (touchPlatform) _setDrawer(false);
    });
    ref.listen(provider.select((s) => s.activeNoteId), (_, _) {
      if (touchPlatform) _setDrawer(false);
    });
    ref.listen(provider.select((s) => s.noteReference), (_, next) {
      if (touchPlatform && next != null) _setDrawer(false);
    });
    ref.listen(provider.select((s) => (s.tabs.activeId, s.panel)), (_, next) {
      if (touchPlatform && (next.$2 != null || next.$1 != null)) _setDrawer(false);
    });
    ref.listen(provider.select((s) => s.tagFilter), (_, next) {
      if (touchPlatform && next != null) _setDrawer(false);
    });
    ref.listen(settingsProvider.select((s) => s.betaFeaturesEnabled), (_, enabled) {
      if (!enabled) {
        final owner = ref.read(provider.notifier);
        final current = ref.read(provider);
        for (final tab in current.tabs.open) {
          if (tab.kind == WorkspaceTabKind.note) owner.closeTab(tab.id);
        }
        if (current.tabs.current.reference?.kind == WorkspaceReferenceKind.note) {
          owner.closePanel();
        }
      }
    });

    ref.watch(
      provider.select(
        (s) => (
          s.activeNoteId,
          s.tabs,
          s.noteReference,
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
    listenFullTranslationNotifications(
      context,
      ref,
      widget.studySetId,
      content?.documents.map((d) => d.id) ?? const [],
      documentTitleOf: (id) => content?.document(id)?.title ?? id,
    );
    final noteOpen = content?.studyNote(state.activeNoteId ?? '') != null;
    final doc = state.activeDocumentId == null ? null : content?.document(state.activeDocumentId!);
    final setTitle = ref.watch(studySetProvider(widget.studySetId).select((s) => s?.title)) ?? '';

    final media = MediaQuery.of(context);
    final geometry = (media.size, state.layout, state.activeDocumentId);
    final holds = <String>{
      if (!touchPlatform || media.accessibleNavigation) 'accessibility',
      if (media.viewInsets.bottom > 0) 'keyboard',
      if (_drawer) 'drawer',
      if (state.panel != null || noteOpen) 'panel',
      if (state.pending != null ||
          (!_phoneCompact && state.tool != AnnotationTool.select) ||
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
      _phoneControls.reset(state.activeDocumentId, armed: state.tool != AnnotationTool.select);
      _phoneControlsChanged();
      _chrome.reset(geometry);
    });
    return PhoneReaderWorkspaceScope(
      controls: _phoneControls,
      chrome: _chrome,
      child: MMPopupActivity(
        onChanged: (owner, open) => open ? _chrome.hold(owner) : _chrome.release(owner),
        child: Theme(
          data: Theme.of(context).copyWith(extensions: [context.mmColors.copyWith(flat: true)]),
          child: WorkspacePaneChromeScope(
            controller: _paneChrome,
            child: surface(
              AssistantScope(
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
                        layout: noteOpen ? MMSplitMode.primary : state.layout,
                        panelOpen: state.panel != null,
                        preservePanes: true,
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
                          noteOpen ? MMSplitMode.primary : shown.mode,
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
    final state = ref.read(workspaceProvider(widget.studySetId));
    if (state.noteReference != null) {
      controller.closeNoteReference();
      return true;
    }
    if (state.panel != null) {
      controller.closePanel();
      return true;
    }
    if (state.tabs.active?.kind != WorkspaceTabKind.documentMap) {
      controller.activateTab(WorkspaceTab.documents);
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
    final noteOpen = state.content?.studyNote(state.activeNoteId ?? '') != null;
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
    if (tablet && !noteOpen) {
      layout = tabletLayout.mode;
      controller.onePane = layout != MMSplitMode.split;
      canSplit = true;
    }
    final stacked = tablet ? tabletLayout.splitAxis == Axis.vertical : sizeClass == MMSizeClass.medium;
    final phone = MMInput.of(context).phone;
    if (!phone) {
      return WorkspaceDesktopShell(
        studySetId: widget.studySetId,
        sidebarVisible: touchPlatform ? _drawer : sidebarVisible,
        onShowSidebar: touchPlatform ? () => _setDrawer(true) : controller.showSidebar,
        onDismissSidebar: touchPlatform ? () => _setDrawer(false) : controller.toggleSidebar,
        layout: layout,
      );
    }
    final phoneDrawer = phone && compact;
    final mergedToolbar = !compact || touchPlatform;
    final betaEnabled = ref.watch(settingsProvider.select((s) => s.betaFeaturesEnabled));
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
      Widget? badge,
    }) => MMToolbarItem(
      id: id,
      priority: priority,
      child: MMToolbarButton(
        key: ValueKey('toolbar-$id'),
        icon: icon,
        iconWidget: id == 'assistant' ? const AssistantIcon() : null,
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
              'assistant' => MMIcons.ai,
              'layout-reader' => MMReaderIcons.layoutReader,
              'layout-split' => MMIcons.compare,
              _ => icon,
            }, size: MMSizes.dropdownIcon),
            const SizedBox(width: MMSpacing.s),
            Expanded(child: Text(label)),
            if (badge != null) ...[const SizedBox(width: MMSpacing.xs), badge],
            if (selected) const Icon(MMIcons.check, size: MMSizes.dropdownIcon),
          ],
        ),
      ),
    );
    final globalActions = <MMToolbarItem>[
      if (!noteOpen)
        action(
          'layout-reader',
          MMIcons.layoutReader,
          AppShortcuts.tip(l.layoutReader, AppShortcuts.view1),
          () => controller.setLayout(MMSplitMode.primary),
          selected: layout == MMSplitMode.primary,
        ),
      if (!noteOpen && canSplit)
        action(
          'layout-split',
          MMIcons.layoutSplit,
          AppShortcuts.tip(l.layoutSplit, AppShortcuts.view2),
          () => controller.setLayout(MMSplitMode.split),
          selected: layout == MMSplitMode.split,
        ),
      if (!noteOpen)
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
      if (betaEnabled && noteOpen) ...[
        MMDropdownItem(
          value: state.activeDocumentId == null ? null : () => controller.showNoteReference(NoteReference.document),
          enabled: state.activeDocumentId != null,
          icon: MMIcons.document,
          child: Text(l.paneSource),
        ),
        MMDropdownItem(
          value: () => controller.showNoteReference(NoteReference.map),
          icon: MMIcons.mindMap,
          child: Text(l.paneMap),
        ),
      ],
      if (betaEnabled)
        action(
          'organize-note',
          MMIcons.organizeNote,
          AppShortcuts.tip(l.organizeNotes, AppShortcuts.organizeStudyNote),
          () => showNoteSetupSheet(context, ref, widget.studySetId),
          badge: const MMBetaBadge(),
        ).menuEntry,
    ];
    Widget paneChrome(Widget child, {required bool primary}) => !mergedToolbar && !noteOpen
        ? child
        : WorkspaceToolbarScope(
            actions: phone && !noteOpen ? const [] : globalActions,
            menuEntries: phone && !noteOpen ? const [] : globalMenuEntries,
            primary: primary,
            leading: phone && !noteOpen ? null : leading,
            ownsLeading: (noteOpen || !phone) && (primary || layout == MMSplitMode.secondary),
            ownsActions: primary
                ? stacked || layout == MMSplitMode.primary
                : !stacked || layout == MMSplitMode.secondary,
            child: child,
          );
    final split = WorkspaceTabbedContent(
      studySetId: widget.studySetId,
      documentMap: MMSplitView(
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
          child: paneChrome(ReaderPane(studySetId: widget.studySetId, showDocumentTitle: false), primary: true),
        ),
        secondary: PdfDropTarget(
          label: l.dropImage,
          onDrop: (files) async {
            final notice = await controller.importDocuments(files);
            if (context.mounted) showNotice(context, notice, rootTitle: setTitle);
          },
          onImageDrop: (files) =>
              insertImageFiles(context, ref, widget.studySetId, [for (final file in files) file.path]),
          child: paneChrome(MapPane(studySetId: widget.studySetId), primary: false),
        ),
      ),
    );
    final floating = sizeClass != MMSizeClass.regular;
    final paneSwitch = !noteOpen && compact && !mergedToolbar;
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
        WorkspaceHistoryControls(studySetId: widget.studySetId, compact: true),
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
        if (MMPlatformCapabilities.current.assistant)
          MMToolbarButton(
            key: const ValueKey('toolbar-assistant'),
            iconWidget: const AssistantIcon(),
            tint: context.mmColors.research,
            tooltip: AppShortcuts.tip(l.assistant, AppShortcuts.assistantPanel),
            selected: state.panel == RightPanel.assistant,
            onPressed: () => toggleAssistant(ref, widget.studySetId),
          ),
        if (globalMenuEntries.isNotEmpty)
          MMDropdownButton<VoidCallback>(
            key: const ValueKey('workspace-more'),
            tooltip: l.moreTools,
            itemBuilder: (_) => globalMenuEntries,
            onSelected: (command) => command(),
          ),
      ],
    );
    final body = ExcerptViewScope(
      showInMap: noteOpen
          ? controller.revealNoteCard
          : compact && layout != MMSplitMode.secondary
          ? controller.showCardInMap
          : null,
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
              if (phone) SizedBox(height: 44, child: WorkspaceTabStrip(studySetId: widget.studySetId)),
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
    if (mergedToolbar || noteOpen) {
      final scaffold = MMWindowScaffold.contentBuilder(
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
        sidebarVisible: phoneDrawer
            ? false
            : touchPlatform
            ? _drawer
            : sidebarVisible,
        sidebarOverlay: touchPlatform,
        onSidebarDismiss: () => _setDrawer(false),
        onDragStart: WindowChrome.onDragStart,
        onTitleDoubleTap: WindowChrome.onTitleDoubleTap,
        showsWindowButtons: WindowChrome.showsWindowButtons,
        sidebar: phoneDrawer ? null : WorkspaceSidebar(studySetId: widget.studySetId),
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
          child: phone && !noteOpen
              ? usePhoneReaderControls(context)
                    ? Stack(
                        children: [
                          Positioned.fill(
                            child: MMChromeInsets(
                              insets: const EdgeInsets.only(
                                top: MMSizes.phoneWorkspaceToolbarHeight,
                                bottom: MMSizes.phoneToolBarHeight + MMPhoneReaderLayout.bottom,
                              ),
                              child: body,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: PhoneReaderTopControls(
                              leading: SizedBox.square(
                                dimension: MMSizes.phoneTopControl,
                                child: MMIconButton(
                                  icon: MMIcons.sidebar,
                                  tooltip: l.showSidebar,
                                  size: context.mmToolbarIcon,
                                  onPressed: () => _setDrawer(true),
                                ),
                              ),
                              mode: layout == MMSplitMode.secondary ? MMSplitMode.secondary : MMSplitMode.primary,
                              onMode: (mode) {
                                _chrome.reveal();
                                controller.setLayout(mode);
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  WorkspaceHistoryControls(studySetId: widget.studySetId, compact: true),
                                  if (MMPlatformCapabilities.current.assistant)
                                    SizedBox.square(
                                      dimension: MMSizes.phoneTopControl,
                                      child: MMToolbarButton(
                                        key: const ValueKey('toolbar-assistant'),
                                        iconWidget: const AssistantIcon(),
                                        tooltip: l.assistant,
                                        tint: context.mmColors.research,
                                        onPressed: () => toggleAssistant(ref, widget.studySetId),
                                      ),
                                    ),
                                  SizedBox.square(
                                    dimension: MMSizes.phoneTopControl,
                                    child: MMToolbarButton(
                                      key: const ValueKey('phone-workspace-more'),
                                      tooltip: l.moreTools,
                                      icon: MMIcons.more,
                                      onPressed: () {
                                        _phoneControls.collapseTools();
                                        _phoneControls.closeScrub();
                                        showPhoneMoreSheet(
                                          context,
                                          studySetId: widget.studySetId,
                                          paneChrome: _paneChrome,
                                          onOpened: () => _chrome.hold('phone-more-sheet'),
                                          onClosed: () => _chrome.release('phone-more-sheet'),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Stack(
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
                                      WorkspaceHistoryControls(studySetId: widget.studySetId, compact: true),
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
                                          iconWidget: const AssistantIcon(),
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
                                          if (betaEnabled)
                                            MMDropdownItem(
                                              icon: MMIcons.organizeNote,
                                              key: const ValueKey('workspace-command-organize-note'),
                                              value: () => showNoteSetupSheet(context, ref, widget.studySetId),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Flexible(child: Text(l.organizeNotes)),
                                                  const SizedBox(width: MMSpacing.xs),
                                                  const MMBetaBadge(),
                                                ],
                                              ),
                                            ),
                                          MMDropdownItem(
                                            enabled: ref.read(studySetProvider(widget.studySetId)) != null,
                                            value: () => controller.activateTab(WorkspaceTab.review),
                                            icon: MMIcons.review,
                                            child: Text(l.review),
                                          ),
                                          MMDropdownItem(
                                            value: () => controller.activateTab(WorkspaceTab.vocabulary),
                                            icon: MMIcons.vocabulary,
                                            child: Text(l.vocabularyTitle),
                                          ),
                                          MMDropdownItem(
                                            value: () => ref.read(navigationProvider.notifier).showLibrary(),
                                            icon: MMIcons.library,
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
      return phoneDrawer ? _phoneDrawer(context, scaffold) : scaffold;
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
      sidebar: WorkspaceSidebar(studySetId: widget.studySetId),
      toolbar: toolbar,
      body: body,
    );
  }

  Widget _phoneDrawer(BuildContext context, Widget child) => MMPhoneDrawer(
    open: _drawer,
    onChanged: _setDrawer,
    dismissLabel: context.l10n.phoneNavigationCloseDrawer,
    drawer: WorkspaceSidebar(studySetId: widget.studySetId, onDismiss: () => _setDrawer(false)),
    child: child,
  );
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
