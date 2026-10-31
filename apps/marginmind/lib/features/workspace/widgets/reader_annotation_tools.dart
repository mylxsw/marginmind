import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'annotation_palette.dart';
import 'highlight_color_button.dart';
import 'underline_tool_button.dart';

class ReaderAnnotationTools extends StatelessWidget {
  const ReaderAnnotationTools({
    super.key,
    required this.state,
    required this.controller,
    this.compact = false,
    this.textOnly = false,
    this.child,
  });

  final Widget? child;
  final WorkspaceState state;
  final WorkspaceController controller;
  final bool compact;
  final bool textOnly;

  @override
  Widget build(BuildContext context) {
    if (child != null) return TapRegion(groupId: annotationTapGroup(controller.studySetId), child: child!);
    final l = context.l10n;
    MMToolbarButton tool(IconData icon, String label, AnnotationTool value) => MMToolbarButton(
      icon: icon,
      tooltip: switch (value) {
        AnnotationTool.highlight => AppShortcuts.tip(label, AppShortcuts.toggleAnnotationTool),
        AnnotationTool.area => AppShortcuts.tip(label, AppShortcuts.toggleAreaTool),
        AnnotationTool.ink => AppShortcuts.tip(label, AppShortcuts.toggleInkTool),
        AnnotationTool.select => label,
        AnnotationTool.underline => label,
      },
      selected: state.tool == value,
      compact: compact,
      onPressed: controller.canUseTool(value) ? () => controller.setTool(value) : null,
    );
    return TapRegion(
      groupId: annotationTapGroup(controller.studySetId),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: MMToolbarGroup(
          compact: compact,
          children: [
            tool(MMIcons.select, l.toolSelect, AnnotationTool.select),
            HighlightColorButton(
              color: state.color,
              selected: state.tool == AnnotationTool.highlight,
              compact: compact,
              enabled: controller.activeCapabilities.annotate,
              onOpen: () => controller.setTool(AnnotationTool.highlight),
              onChanged: controller.setColor,
            ),
            UnderlineToolButton(
              studySetId: controller.studySetId,
              compact: compact,
              enabled: controller.activeCapabilities.annotate,
            ),
            if (!textOnly) ...[
              tool(MMIcons.areaSelect, l.toolArea, AnnotationTool.area),
              tool(MMIcons.pen, l.toolPen, AnnotationTool.ink),
              const MMToolbarDivider(),
              MMToolbarButton(
                compact: compact,
                icon: MMIcons.syncToMap,
                tooltip: state.syncToMap ? l.syncToMapOn : l.syncToMapOff,
                selected: state.syncToMap,
                onPressed: controller.activeCapabilities.excerpt ? controller.toggleSyncToMap : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
