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
    this.primary = true,
    required this.leading,
    required this.ownsActions,
    required this.ownsLeading,
  });
  final List<MMToolbarItem> actions;
  final Widget? leading;
  final bool ownsActions, ownsLeading;
  final bool primary;
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
    required this.label,
    this.menuIcon,
  });
  final List<MMToolbarItem> items;
  final List<PopupMenuEntry<VoidCallback>> menuEntries;
  final String label;
  final Widget? menuIcon;

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceToolbarScope.maybeOf(context);
    final geometry = WorkspaceLayoutGeometryScope.maybeOf(context);
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
    final toolbar = ColoredBox(
      color: phone ? context.mmColors.surface : context.mmColors.windowBackground,
      child: MMToolbar.content(
        semanticLabel: label,
        height: phone ? MMSizes.thumbDock : MMSizes.paneHeaderHeight,
        child: Padding(
          padding: EdgeInsets.only(
            left:
                (phone
                    ? 6
                    : context.mmTablet
                    ? 16
                    : 12) +
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
                  items: [...items, if (ownsActions && scope != null) ...scope.actions],
                  menuLabel: label,
                  spacing: phone ? MMSpacing.xs : MMSpacing.s,
                  menuIcon: menuIcon,
                  menuKey: ValueKey(menuIcon == null ? 'map-more' : 'reader-more'),
                  trailingIds: {
                    if (menuIcon != null) 'documents',
                    if (ownsActions && scope != null) ...scope.actions.map((item) => item.id),
                    ':menu',
                  },
                  groups: phone
                      ? const []
                      : [
                          if (menuIcon != null) {'select', 'highlight', 'underline', 'ink', 'area', 'sync'},
                          {'layout-reader', 'layout-split', 'layout-map'},
                          {'organize-note', 'assistant'},
                        ],
                  menuEntries: menuEntries,
                ),
              ),
            ],
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
