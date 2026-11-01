import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../workspace_layout.dart';
import '../workspace_chrome_controller.dart';

/// Global commands are scoped to their owning pane. Both the header and body
/// receive the split's exact constraints, including sidebar animation frames.
class WorkspaceToolbarScope extends InheritedWidget {
  const WorkspaceToolbarScope({
    super.key,
    required super.child,
    required this.actions,
    this.menuEntries = const [],
    this.primary = true,
    this.useGeometry = true,
    required this.leading,
    required this.ownsActions,
    required this.ownsLeading,
  });
  final List<MMToolbarItem> actions;
  final List<PopupMenuEntry<VoidCallback>> menuEntries;
  final Widget? leading;
  final bool ownsActions, ownsLeading;
  final bool primary;
  final bool useGeometry;
  static WorkspaceToolbarScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceToolbarScope>();
  @override
  bool updateShouldNotify(WorkspaceToolbarScope oldWidget) => true;
}

class WorkspaceToolbar extends StatelessWidget {
  const WorkspaceToolbar({
    super.key,
    required this.items,
    required this.menuEntries,
    this.trailingItems = const [],
    this.trailingMenuEntries = const [],
    required this.label,
    this.menuIcon,
    this.overflowLabel,
    this.leadingPadding,
  });
  final List<MMToolbarItem> items;
  final List<MMToolbarItem> trailingItems;
  final List<PopupMenuEntry<VoidCallback>> menuEntries;
  final List<PopupMenuEntry<VoidCallback>> trailingMenuEntries;
  final String label;
  final Widget? menuIcon;
  final String? overflowLabel;
  final double? leadingPadding;

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceToolbarScope.maybeOf(context);
    final geometry = scope?.useGeometry == false ? null : WorkspaceLayoutGeometryScope.maybeOf(context);
    final ownsLeading = geometry == null
        ? scope?.ownsLeading == true
        : scope?.primary == true || geometry.split.effectiveMode == MMSplitMode.secondary;
    final ownsActions = geometry == null
        ? scope?.ownsActions == true
        : scope?.primary == true
        ? geometry.split.axis == Axis.vertical || geometry.split.effectiveMode == MMSplitMode.primary
        : geometry.split.axis == Axis.horizontal || geometry.split.effectiveMode == MMSplitMode.secondary;
    final leading = ownsLeading ? scope?.leading : null;
    final inset = ownsLeading ? MMWindowChrome.maybeOf(context)?.toolbarLeadingInset ?? 0 : 0.0;
    final phone = MMInput.of(context).phone;
    final portraitTablet = context.mmTablet && MediaQuery.orientationOf(context) == Orientation.portrait;
    final readerCompanions = portraitTablet && menuIcon != null
        ? items.where((item) => item.id == 'compare' || item.id == 'documents').toList()
        : <MMToolbarItem>[];
    final actions = ownsActions && scope != null ? scope.actions : <MMToolbarItem>[];
    final toolbarItems = [
      ...items.where((item) => !readerCompanions.contains(item)),
      ...actions.where((item) => item.id != 'assistant'),
      ...readerCompanions,
      ...actions.where((item) => item.id == 'assistant'),
      ...trailingItems,
    ];
    final toolbar = MMCompactToolbarScope(
      child: ColoredBox(
        color: phone ? context.mmColors.surface : context.mmColors.windowBackground,
        child: MMToolbar.content(
          semanticLabel: label,
          height: phone
              ? MMSizes.thumbDock
              : context.mmTouchPlatform
              ? MMSizes.tabletPaneHeaderHeight
              : MMSizes.desktopPaneHeaderHeight,
          child: Padding(
            padding: EdgeInsets.only(
              left:
                  (leadingPadding ??
                      (phone
                          ? 6
                          : context.mmTablet
                          ? 16
                          : 6)) +
                  inset,
              right: phone
                  ? 6
                  : context.mmTablet
                  ? 16
                  : 12,
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: MMSpacing.s)],
                Expanded(
                  child: MMAdaptiveToolbar(
                    items: toolbarItems,
                    menuLabel: label,
                    overflowLabel: overflowLabel,
                    spacing: phone
                        ? MMSpacing.xs
                        : context.mmTablet
                        ? MMSpacing.m
                        : MMToolbarSpacing.group,
                    menuIcon: menuIcon,
                    cascadingMenu: menuIcon != null,
                    menuKey: ValueKey(menuIcon == null ? 'map-more' : 'reader-more'),
                    trailingIds: {
                      ...trailingItems.map((item) => item.id),
                      if (menuIcon != null && !portraitTablet) ...{'compare', 'documents'},
                      if (readerCompanions.isNotEmpty && actions.isEmpty) ...{'compare', 'documents'},
                      if (ownsActions && scope != null) ...scope.actions.map((item) => item.id),
                      ':menu',
                    },
                    groups: phone
                        ? const []
                        : [
                            if (menuIcon != null) {'select', 'highlight', 'underline', 'ink', 'area', 'sync'},
                            if (context.mmTablet) ...[
                              {'map-view', 'map-style'},
                              if (!portraitTablet) {'compare', 'documents'},
                            ],
                            {'layout-reader', 'layout-split', 'layout-map'},
                            if (portraitTablet) {'compare', 'documents'},
                          ],
                    menuEntries: [
                      ...menuEntries,
                      if (ownsActions && scope != null && scope.menuEntries.isNotEmpty) ...[
                        if (menuEntries.isNotEmpty) const PopupMenuDivider(),
                        ...scope.menuEntries,
                      ],
                      ...trailingMenuEntries,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return WorkspaceChromeBar(
      bottom: phone,
      child: phone
          ? MMThumbDockScope(
              child: Container(
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: context.mmColors.border, width: MMSizes.hairline),
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(28), child: toolbar),
              ),
            )
          : toolbar,
    );
  }
}
