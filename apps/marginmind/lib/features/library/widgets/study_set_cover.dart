import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

/// Generated cover: the set's color as a tint with one paper sheet per
/// document (up to three), fanned out. No PDF thumbnails — they make the
/// library noisy.
class StudySetCover extends StatelessWidget {
  const StudySetCover({
    super.key,
    required this.color,
    required this.documentCount,
    this.height = 150,
    this.compact = false,
  });

  final MMAnnotationColor color;
  final int documentCount;
  final double height;

  /// Small square variant used in "Continue Learning".
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final brightness = context.mmColors.brightness;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color.coverTint(brightness),
        borderRadius: BorderRadius.circular(compact ? 10 : MMRadii.cover),
        border: Border.all(color: color.color.withValues(alpha: 0.35), width: 0.5),
      ),
      child: CustomPaint(
        painter: _PagesPainter(count: documentCount, compact: compact),
      ),
    );
  }
}

class _PagesPainter extends CustomPainter {
  _PagesPainter({required this.count, required this.compact});

  final int count;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final pages = count.clamp(1, 3);
    final faded = count == 0;
    final w = compact ? 30.0 : 82.0;
    final h = compact ? 40.0 : 106.0;
    // (rotation in degrees, x offset) for 1, 2 and 3 sheets.
    const layouts = {
      1: [(0.0, 0.0)],
      2: [(-7.0, -14.0), (5.0, 14.0)],
      3: [(-7.0, -22.0), (5.0, 18.0), (0.0, 0.0)],
    };
    for (final (deg, dx) in layouts[compact ? 1 : pages]!) {
      canvas.save();
      canvas.translate(size.width / 2 + (compact ? 0 : dx), size.height / 2);
      canvas.rotate(deg * 3.1415926 / 180);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: faded ? 0.5 : 1));
      final line = Paint()
        ..color = Colors.black.withValues(alpha: 0.09)
        ..strokeWidth = 1;
      final pad = compact ? 5.0 : 12.0;
      final step = compact ? 5.0 : 8.0;
      for (var y = -h / 2 + (compact ? 7 : 16); y < h / 2 - pad; y += step) {
        canvas.drawLine(Offset(-w / 2 + pad, y), Offset(w / 2 - pad, y), line);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PagesPainter old) => old.count != count || old.compact != compact;
}
