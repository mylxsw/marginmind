import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

/// Glass pen bar above the page while the pen is out: shape, color, width,
/// undo and Done.
class ReaderInkToolbar extends StatelessWidget {
  const ReaderInkToolbar({super.key, required this.state, required this.controller, required this.onUndo});

  final WorkspaceState state;
  final WorkspaceController controller;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    MMToolbarButton tool(IconData icon, String label, MMPdfInkTool value) => MMToolbarButton(
      icon: icon,
      tooltip: label,
      selected: state.inkTool == value,
      onPressed: () => controller.setInkTool(value),
    );
    final erasing = state.inkTool == MMPdfInkTool.eraser;
    return MMFloatingToolbar(
      children: [
        tool(MMIcons.inkFreehand, l.inkFreehand, MMPdfInkTool.freehand),
        tool(MMIcons.inkEllipse, l.inkEllipse, MMPdfInkTool.ellipse),
        tool(MMIcons.inkArrow, l.inkArrow, MMPdfInkTool.arrow),
        tool(MMIcons.inkEraser, l.inkEraser, MMPdfInkTool.eraser),
        const MMToolbarDivider(),
        for (final color in MMInkColor.values)
          MMFloatingToolbarSwatch(
            color: color.color,
            tooltip: l.inkColorName(color),
            selected: !erasing && state.inkColor == color,
            onPressed: () => controller.setInkColor(color),
          ),
        const MMToolbarDivider(),
        for (final width in MMInkWidth.values)
          MMFloatingToolbarStrokeWidth(
            width: width.points,
            tooltip: l.inkWidthName(width),
            selected: !erasing && state.inkWidth == width,
            onPressed: () => controller.setInkWidth(width),
          ),
        const MMToolbarDivider(),
        MMToolbarButton(
          icon: MMIcons.undo,
          tooltip: AppShortcuts.tip(l.undo, AppShortcuts.undo),
          onPressed: state.canUndo ? onUndo : null,
        ),
        MMToolbarButton(icon: null, label: l.done, tooltip: l.done, onPressed: controller.exitInk),
      ],
    );
  }
}
