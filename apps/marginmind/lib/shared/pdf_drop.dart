import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import 'l10n.dart';

typedef DroppedFile = ({String path, String name});

/// Accepts PDFs dragged in from Finder. While a drag hovers, the area gets
/// an accent outline and a glass label saying what dropping will do.
class PdfDropTarget extends StatefulWidget {
  const PdfDropTarget({super.key, required this.label, required this.onDrop, required this.child});

  /// What happens on drop, e.g. "Import into this study set".
  final String label;
  final ValueChanged<List<DroppedFile>> onDrop;
  final Widget child;

  @override
  State<PdfDropTarget> createState() => _PdfDropTargetState();
}

class _PdfDropTargetState extends State<PdfDropTarget> {
  bool _hovering = false;

  void _done(DropDoneDetails details) {
    setState(() => _hovering = false);
    final pdfs = [
      for (final f in details.files)
        if (f.path.toLowerCase().endsWith('.pdf')) (path: f.path, name: f.name),
    ];
    if (pdfs.isEmpty) {
      MMHud.show(context, context.l10n.dropOnlyPdf, icon: MMIcons.close);
      return;
    }
    widget.onDrop(pdfs);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: _done,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.accentTint,
                    borderRadius: BorderRadius.circular(MMRadii.card),
                    border: Border.all(color: c.accent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: MMGlass(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.fromLTRB(14, 9, 16, 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(MMIcons.import, size: 15, color: c.label),
                        const SizedBox(width: 8),
                        Text(widget.label, style: context.mmText.headline),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
