import 'package:mm_design/mm_design.dart';

/// What a workspace window of [windowWidth] shows: the sidebar, the source /
/// map split and the right panel ([panelWidth] 0 when [panelOpen] is false).
///
/// The right panel is 400 wide while the sidebar (if [sidebarVisible]) and
/// the panes of [layout] still fit beside it. A narrower window collapses the
/// sidebar first and gives the panel 360; whatever is left follows
/// [MMSplitView.effectiveMode], so a split that still does not fit shows the
/// source alone. With [preservePanes], the assistant instead shares the
/// available width between the chosen panes, leaving visibility to the user.
/// Nothing here changes the user's saved choices.
({bool sidebarVisible, MMSplitMode mode, double panelWidth}) resolveWorkspaceLayout({
  required double windowWidth,
  required bool sidebarVisible,
  required MMSplitMode layout,
  required bool panelOpen,
  bool preservePanes = false,
  double minReader = MMSizes.readerMinWidth,
  double minMap = MMSizes.mapMinWidth,
}) {
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
  return fit(false, MMSizes.rightPanelNarrowWidth);
}
