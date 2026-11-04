import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

/// Low-frequency explanations stay out of the main task, using the same
/// controls as the surrounding sheet rather than a Material list tile.
class SyncDetails extends StatefulWidget {
  const SyncDetails({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  State<SyncDetails> createState() => _SyncDetailsState();
}

class _SyncDetailsState extends State<SyncDetails> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        expanded: _expanded,
        child: MMButton(
          label: widget.title,
          icon: _expanded ? MMIcons.chevronDown : MMIcons.chevronRight,
          variant: MMButtonVariant.plain,
          onPressed: () => setState(() => _expanded = !_expanded),
        ),
      ),
      if (_expanded) ...widget.children,
    ],
  );
}
