import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/app.dart';
import '../../app/app_commands.dart';
import '../../app/navigation.dart';
import '../../app/phone_tabs.dart';
import '../../app/providers.dart';
import '../../shared/card_image.dart';
import '../../shared/l10n.dart';
import '../../settings/app_settings.dart';
import '../../shared/pdf_drop.dart';
import '../assistant/assistant_entry.dart';
import '../assistant/widgets/assistant_panel.dart';
import 'workspace_controller.dart';
import 'widgets/map_pane.dart';
import 'widgets/notices.dart';
import 'widgets/reader_pane.dart';
import 'widgets/right_panel.dart';
import 'widgets/workspace_sidebar.dart';
import 'workspace_layout.dart';

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

  /// Whether the sidebar drawer of a touch window is out. Touch windows
  /// start with it in, whatever the saved sidebar choice.
  bool _drawer = false;

  void _setDrawer(bool open) {
    if (_drawer != open) setState(() => _drawer = open);
  }

  @override
  void dispose() {
    _searchFocus.dispose();
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
          s.panel,
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

    return AssistantScope(
      studySetId: widget.studySetId,
      child: CardImageScope(
        resolve: controller.imagePath,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final safe = MediaQuery.paddingOf(context);
            final width = constraints.maxWidth - safe.horizontal;
            final height = constraints.maxHeight - safe.vertical;
            final sizeClass = MMSizeClass.resolve(context, Size(width, height));
            controller.panelFloats = sizeClass != MMSizeClass.regular;
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
            // Preserve independent sidebar choices. Narrow windows temporarily
            // hide the sidebar beside the right panel and show one content
            // pane; the toolbar reflects the visible layout. Touch windows
            // keep the sidebar in a drawer.
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
                shown.mode,
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
    final stacked = sizeClass == MMSizeClass.medium;
    // A phone switches panes with its bottom tabs.
    final tabs = compact && showsPhoneTabs(context);
    final split = MMSplitView(
      mode: layout,
      onModeChanged: compact || !canSplit ? null : controller.setLayout,
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
        child: ReaderPane(studySetId: widget.studySetId),
      ),
      secondary: PdfDropTarget(
        label: l.dropImage,
        onDrop: (files) async {
          final notice = await controller.importDocuments(files);
          if (context.mounted) showNotice(context, notice, rootTitle: setTitle);
        },
        onImageDrop: (files) =>
            insertImageFiles(context, ref, widget.studySetId, [for (final file in files) file.path]),
        child: MapPane(studySetId: widget.studySetId),
      ),
    );
    final floating = sizeClass != MMSizeClass.regular;
    final panel = state.panel == null ? null : RightPanelView(studySetId: widget.studySetId);
    return MMWindowScaffold(
      // A compact window has no room beside or over the panes: the panel
      // rises from the bottom.
      sheet: compact && panel != null
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
      toolbar: MMToolbar(
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
          if (MMPlatformCapabilities.current.assistant)
            MMToolbarGroup(
              children: [
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
        ],
      ),
      body: ExcerptViewScope(
        showInMap: compact && layout != MMSplitMode.secondary ? controller.showCardInMap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact && !tabs)
              Padding(
                padding: const EdgeInsets.fromLTRB(MMSpacing.m, 0, MMSpacing.m, MMSpacing.s),
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
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: split),
                        if (panel != null && !floating) SizedBox(width: panelWidth, child: panel),
                      ],
                    ),
                  ),
                  if (panel != null && floating && !compact)
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
