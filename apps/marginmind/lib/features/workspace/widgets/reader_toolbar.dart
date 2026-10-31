import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import 'workspace_toolbar.dart';

/// Reader command presentation, independent of PDF and reflow sessions.
class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({super.key, required this.items, required this.appearanceEntries, required this.label});
  final List<MMToolbarItem> items;
  final List<PopupMenuEntry<VoidCallback>> appearanceEntries;
  final String label;
  @override
  Widget build(BuildContext context) => WorkspaceToolbar(
    items: items,
    menuEntries: appearanceEntries,
    label: label,
    menuIcon: Text('Aa', style: context.mmText.callout),
  );
}
