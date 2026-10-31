import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import 'workspace_toolbar.dart';

/// Reader command presentation, independent of PDF and reflow sessions.
class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({
    super.key,
    required this.items,
    required this.menuEntries,
    required this.label,
    required this.overflowLabel,
  });
  final List<MMToolbarItem> items;
  final List<PopupMenuEntry<VoidCallback>> menuEntries;
  final String label;
  final String overflowLabel;
  @override
  Widget build(BuildContext context) => WorkspaceToolbar(
    items: items,
    menuEntries: menuEntries,
    label: label,
    overflowLabel: overflowLabel,
    menuIcon: Icon(MMIcons.more, semanticLabel: label),
  );
}
