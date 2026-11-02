import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

/// Shared compact navigation for PDF and reflow reader sidebars.
class ReaderSidebarTabBar extends StatelessWidget {
  const ReaderSidebarTabBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MMCompactToolbarScope(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: LayoutBuilder(
        builder: (context, bounds) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: bounds.maxWidth),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: children),
          ),
        ),
      ),
    ),
  );
}
