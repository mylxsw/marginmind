import 'package:flutter/rendering.dart';

/// A dashed rounded outline: automatic context chips and the map's preview
/// of what a proposal touches.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({required this.color, required this.radius, this.width = 1, this.dash = 3, this.gap = 2});

  final Color color;
  final double radius, width, dash, gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.width != width || old.dash != dash || old.gap != gap;
}
