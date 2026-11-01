import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The three approved palettes of the circular assistant mark.
enum MMAssistantPalette { iris, jade, apricot }

/// Full-colour assistant mark, with two capsule eyes tilted by eight degrees.
/// The circle fills the icon box; the design source's export padding is omitted.
class MMAssistantIcon extends StatelessWidget {
  const MMAssistantIcon({super.key, this.palette = MMAssistantPalette.iris, this.size});

  final MMAssistantPalette palette;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return ExcludeSemantics(
      child: Opacity(
        opacity: theme.opacity ?? 1,
        child: SizedBox.square(
          dimension: size ?? theme.size ?? 24,
          child: CustomPaint(painter: _AssistantPainter(palette)),
        ),
      ),
    );
  }
}

class _AssistantPainter extends CustomPainter {
  const _AssistantPainter(this.palette);

  final MMAssistantPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final (start, end, eyes) = switch (palette) {
      MMAssistantPalette.iris => (const Color(0xFF6254DB), const Color(0xFF3278C8), const Color(0xFFFFFFFF)),
      MMAssistantPalette.jade => (const Color(0xFF087E84), const Color(0xFF168B7B), const Color(0xFFFFFFFF)),
      MMAssistantPalette.apricot => (const Color(0xFFF9AE62), const Color(0xFFF28B52), const Color(0xFF643321)),
    };
    // Keep the approved SVG's geometry and gradient, cropped to its circle.
    canvas.scale(size.width / 184, size.height / 184);
    canvas.translate(-36, -36);
    final fill = Paint()
      ..shader = LinearGradient(
        colors: [start, end],
        begin: const Alignment(-.625, -.6875),
        end: const Alignment(.671875, .609375),
      ).createShader(const Rect.fromLTWH(0, 0, 256, 256));
    canvas.drawCircle(const Offset(128, 128), 92, fill);
    final eyePaint = Paint()..color = eyes;
    for (final x in [100.0, 156.0]) {
      canvas.save();
      canvas.translate(x, 124);
      canvas.rotate(8 * math.pi / 180);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-10, -26, 20, 52), const Radius.circular(10)),
        eyePaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AssistantPainter oldDelegate) => oldDelegate.palette != palette;
}
