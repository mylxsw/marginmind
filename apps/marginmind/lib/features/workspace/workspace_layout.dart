import 'package:flutter/widgets.dart';
import 'package:mm_design/mm_design.dart';

/// Tablet pane fitting is independent of the global toolbar width class.
/// A companion panel consumes real space and never blocks the document.
({Axis splitAxis, Axis panelAxis, MMSplitMode mode, double panelExtent}) resolveTabletWorkspaceLayout({
  required Size size,
  required MMSplitMode layout,
  required bool panelOpen,
  bool? isLandscape,
  double panelFraction = .38,
  double minReader = MMSizes.readerMinWidth,
}) {
  // A software keyboard reduces available height but does not rotate the iPad.
  final landscape = isLandscape ?? size.width > size.height;
  final panelAxis = landscape && size.width >= minReader + 320 + 8 ? Axis.horizontal : Axis.vertical;
  final panelRoom = (size.height - 200).clamp(160.0, double.infinity);
  final minPanel = panelRoom.clamp(160.0, 240.0);
  final extent = !panelOpen
      ? 0.0
      : panelAxis == Axis.horizontal
      ? (size.width * .32).clamp(320.0, 380.0)
      : (size.height * panelFraction).clamp(minPanel, panelRoom);
  final divider = panelOpen ? 8.0 : 0.0;
  final width = size.width - (panelAxis == Axis.horizontal ? extent + divider : 0);
  final height = size.height - (panelAxis == Axis.vertical ? extent + divider : 0);
  final axis = landscape ? Axis.horizontal : Axis.vertical;
  return (
    splitAxis: axis,
    panelAxis: panelAxis,
    panelExtent: extent,
    mode: MMSplitView.effectiveMode(
      layout,
      axis == Axis.horizontal ? width : height,
      axis == Axis.horizontal ? minReader : MMSizes.paneMinHeight,
      axis == Axis.horizontal ? MMSizes.mapMinWidth : MMSizes.paneMinHeight,
    ),
  );
}

/// What a workspace window of [windowWidth] shows: the sidebar, the source /
/// map split and the right panel ([panelWidth] 0 when [panelOpen] is false).
///
/// The right panel is 400 wide while the sidebar (if [sidebarVisible]) and
/// the panes of [layout] still fit beside it. A narrower window collapses the
/// sidebar first and gives the panel 360; whatever is left follows
/// [MMSplitView.effectiveMode], so a split that still does not fit shows the
/// source alone. With [preservePanes], the assistant instead shares the
/// available width between the chosen panes and keeps the sidebar choice,
/// leaving visibility to the user.
/// Nothing here changes the user's saved choices.
///
/// Below [MMSizeClass.regular] the sidebar is a drawer (never beside the
/// content) and the panel floats over it, at most 400 wide. [MMSizeClass.medium]
/// stacks the source above the map while both fit [windowHeight];
/// [MMSizeClass.compact] shows one pane, the source for a split.
({bool sidebarVisible, MMSplitMode mode, double panelWidth}) resolveWorkspaceLayout({
  required double windowWidth,
  required bool sidebarVisible,
  required MMSplitMode layout,
  required bool panelOpen,
  bool preservePanes = false,
  double minReader = MMSizes.readerMinWidth,
  double minMap = MMSizes.mapMinWidth,
  MMSizeClass sizeClass = MMSizeClass.regular,
  double windowHeight = double.infinity,
}) {
  if (sizeClass != MMSizeClass.regular) {
    final floating = (windowWidth - MMSpacing.s * 2).clamp(0.0, MMSizes.rightPanelWidth);
    return (
      sidebarVisible: false,
      mode: sizeClass == MMSizeClass.compact
          ? (layout == MMSplitMode.split ? MMSplitMode.primary : layout)
          : MMSplitView.effectiveMode(layout, windowHeight, MMSizes.paneMinHeight, MMSizes.paneMinHeight),
      panelWidth: panelOpen ? floating : 0,
    );
  }
  const sidebar = MMSizes.sidebarWidth + MMSizes.sidebarInset;
  ({bool sidebarVisible, MMSplitMode mode, double panelWidth}) fit(bool showSidebar, double panel) => (
    sidebarVisible: showSidebar,
    mode: preservePanes
        ? layout
        : MMSplitView.effectiveMode(layout, windowWidth - (showSidebar ? sidebar : 0) - panel, minReader, minMap),
    panelWidth: panel,
  );
  if (!panelOpen) return fit(sidebarVisible, 0);
  final needed = switch (layout) {
    MMSplitMode.primary => minReader,
    MMSplitMode.secondary => minMap,
    MMSplitMode.split => minReader + minMap + 1,
  };
  if (windowWidth - (sidebarVisible ? sidebar : 0) - MMSizes.rightPanelWidth >= needed) {
    return fit(sidebarVisible, MMSizes.rightPanelWidth);
  }
  return fit(preservePanes && sidebarVisible, MMSizes.rightPanelNarrowWidth);
}

/// Pane and header rectangles in the scaffold's content coordinate space.
/// The scaffold has already removed its actual animated sidebar width.
@immutable
class WorkspaceLayoutGeometry {
  const WorkspaceLayoutGeometry({
    required this.sidebarExtent,
    required this.contentRect,
    required this.panelRect,
    required this.readerRect,
    required this.mapRect,
    required this.split,
    this.headerHeight = MMSizes.paneHeaderHeight,
  });
  final double sidebarExtent;
  final double headerHeight;
  final Rect contentRect, panelRect, readerRect, mapRect;
  final MMSplitGeometry split;
  Rect get readerHeaderRect => Rect.fromLTWH(readerRect.left, readerRect.top, readerRect.width, headerHeight);
  Rect get mapHeaderRect =>
      mapRect.isEmpty ? Rect.zero : Rect.fromLTWH(mapRect.left, mapRect.top, mapRect.width, headerHeight);

  factory WorkspaceLayoutGeometry.resolve({
    required Size size,
    required MMSplitMode mode,
    required Axis axis,
    required double fraction,
    required double minReader,
    double minMap = MMSizes.mapMinWidth,
    double sidebarExtent = 0,
    double panelExtent = 0,
    Axis panelAxis = Axis.horizontal,
    bool tablet = false,
    bool collapseWhenNarrow = true,
  }) {
    final verticalPanel = panelAxis == Axis.vertical;
    final available = verticalPanel ? size.height : size.width;
    final panel = panelExtent.clamp(0.0, (available - (tablet ? 44 : 0)).clamp(0.0, double.infinity));
    final gap = panel > 0 && tablet ? MMSpacing.s : 0.0;
    final content = Rect.fromLTWH(
      0,
      0,
      (size.width - (verticalPanel ? 0 : panel + gap)).clamp(0.0, double.infinity),
      (size.height - (verticalPanel ? panel + gap : 0)).clamp(0.0, double.infinity),
    );
    final panelRect = panel == 0
        ? Rect.zero
        : verticalPanel
        ? Rect.fromLTWH(8, size.height - panel, size.width - 16, panel)
        : Rect.fromLTWH(
            size.width - panel,
            tablet ? 8 : 0,
            panel,
            (size.height - (tablet ? 16 : 0)).clamp(0.0, double.infinity),
          );
    final split = MMSplitView.resolveGeometry(
      extent: axis == Axis.vertical ? content.height : content.width,
      mode: mode,
      axis: axis,
      fraction: fraction,
      minPrimary: axis == Axis.vertical ? MMSizes.paneMinHeight : minReader,
      minSecondary: axis == Axis.vertical ? MMSizes.paneMinHeight : minMap,
      collapseWhenNarrow: collapseWhenNarrow,
    );
    final both = split.effectiveMode == MMSplitMode.split;
    final reader = split.effectiveMode == MMSplitMode.secondary
        ? Rect.zero
        : !both
        ? content
        : axis == Axis.vertical
        ? Rect.fromLTWH(0, 0, content.width, split.primaryExtent)
        : Rect.fromLTWH(0, 0, split.primaryExtent, content.height);
    final map = split.effectiveMode == MMSplitMode.primary
        ? Rect.zero
        : !both
        ? content
        : axis == Axis.vertical
        ? Rect.fromLTWH(0, split.primaryExtent + split.dividerExtent, content.width, split.secondaryExtent)
        : Rect.fromLTWH(split.primaryExtent + split.dividerExtent, 0, split.secondaryExtent, content.height);
    return WorkspaceLayoutGeometry(
      sidebarExtent: sidebarExtent,
      contentRect: content,
      panelRect: panelRect,
      readerRect: reader,
      mapRect: map,
      split: split,
      headerHeight: tablet ? MMSizes.tabletPaneHeaderHeight : MMSizes.paneHeaderHeight,
    );
  }
}

class WorkspaceLayoutGeometryScope extends InheritedWidget {
  const WorkspaceLayoutGeometryScope({super.key, required this.geometry, required super.child});
  final WorkspaceLayoutGeometry geometry;
  static WorkspaceLayoutGeometry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceLayoutGeometryScope>()?.geometry;
  @override
  bool updateShouldNotify(WorkspaceLayoutGeometryScope oldWidget) => geometry != oldWidget.geometry;
}
