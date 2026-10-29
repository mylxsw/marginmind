import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';

/// Shared by PDF underlines and their toolbar previews. Geometry is in view
/// points, keeping fine lines legible at every document zoom.
class MMPdfAnnotationLinePainter extends CustomPainter {
  const MMPdfAnnotationLinePainter({required this.color, required this.style, this.width = 1.5, this.centered = false});

  final Color color;
  final AnnotationLineStyle style;
  final double width;
  final bool centered;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    final amplitude = math.min(1.4, size.height / 4);
    final y = centered
        ? size.height / 2
        : size.height - width / 2 - (style == AnnotationLineStyle.wavy ? amplitude : 0);
    switch (style) {
      case AnnotationLineStyle.solid:
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      case AnnotationLineStyle.dashed:
        for (var x = 0.0; x < size.width; x += 6) {
          canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, size.width), y), paint);
        }
      case AnnotationLineStyle.dotted:
        paint.style = PaintingStyle.fill;
        for (var x = width / 2; x <= size.width - width / 2; x += 4) {
          canvas.drawCircle(Offset(x, y), width / 2, paint);
        }
      case AnnotationLineStyle.wavy:
        final path = Path()..moveTo(0, y);
        for (var x = 0.5; x <= size.width; x += 0.5) {
          path.lineTo(x, y + math.sin(x * math.pi / 4) * amplitude);
        }
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(MMPdfAnnotationLinePainter old) =>
      old.color != color || old.style != style || old.width != width || old.centered != centered;
}
