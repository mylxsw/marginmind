import 'package:mm_core/mm_core.dart';
import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'l10n.dart';

typedef DroppedFile = ({String path, String name});

/// Accepts supported documents dragged in from the desktop. While a drag hovers, the area gets
/// an accent outline and a glass label saying what dropping will do.
class PdfDropTarget extends StatefulWidget {
  const PdfDropTarget({super.key, required this.label, required this.onDrop, this.onImageDrop, required this.child});

  /// What happens on drop, e.g. "Import into this study set".
  final String label;
  final ValueChanged<List<DroppedFile>> onDrop;
  final ValueChanged<List<DroppedFile>>? onImageDrop;
  final Widget child;

  @override
  State<PdfDropTarget> createState() => _PdfDropTargetState();
}

class _PdfDropTargetState extends State<PdfDropTarget> {
  bool _hovering = false;

  void _done(List<MMDocumentFile> files) {
    final documents = [
      for (final f in files)
        if (DocumentFormat.fromFileName(f.name) != DocumentFormat.unknown) f,
    ];
    final images = [
      for (final f in files)
        if (RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(f.name)) f,
    ];
    final unsupported = [
      for (final f in files)
        if (!documents.contains(f) && (widget.onImageDrop == null || !images.contains(f))) f,
    ];
    if (documents.isNotEmpty) widget.onDrop(documents);
    if (images.isNotEmpty) widget.onImageDrop?.call(images);
    if (unsupported.isNotEmpty) {
      MMHud.show(context, context.l10n.unsupportedFile(unsupported.first.name), icon: MMIcons.close);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!MMPlatformCapabilities.current.desktopDrop) return widget.child;
    final c = context.mmColors;
    return MMFileDropTarget(
      onHover: (hovering) => setState(() => _hovering = hovering),
      onDrop: _done,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  foregroundPainter: widget.onImageDrop == null ? null : _DropBorder(c.accent),
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: c.accentTint,
                      borderRadius: BorderRadius.circular(MMRadii.card),
                      border: widget.onImageDrop == null ? Border.all(color: c.accent, width: MMSpacing.xxs) : null,
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
            ),
        ],
      ),
    );
  }
}

class _DropBorder extends CustomPainter {
  _DropBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius((Offset.zero & size).deflate(MMSpacing.s), const Radius.circular(MMRadii.card)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = MMSpacing.xxs;
    for (final metric in path.computeMetrics()) {
      for (double start = 0; start < metric.length; start += MMSpacing.s + MMSpacing.xs) {
        canvas.drawPath(metric.extractPath(start, start + MMSpacing.s), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DropBorder oldDelegate) => oldDelegate.color != color;
}
