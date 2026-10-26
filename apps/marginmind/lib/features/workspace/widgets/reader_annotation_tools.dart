import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

class ReaderAnnotationTools extends StatelessWidget {
  const ReaderAnnotationTools({super.key, required this.state, required this.controller});

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
        AnnotationTool.ink => AppShortcuts.tip(label, AppShortcuts.toggleInkTool),
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
        tool(MMIcons.pen, l.toolPen, AnnotationTool.ink),
        const MMToolbarDivider(),
        MMColorMenuButton(
          selected: state.color,
          labelOf: l.colorName,
          tooltip: l.annotationColor,
          onChanged: controller.setColor,
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
