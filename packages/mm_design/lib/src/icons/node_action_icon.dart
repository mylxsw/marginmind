import 'package:flutter/widgets.dart';

/// Node operations share a 24-point grid with the system outline icons.
enum MMNodeAction { child, sibling, merge, summary, relation }

class MMNodeActionIcon extends StatelessWidget {
  const MMNodeActionIcon(this.action, {super.key, required this.color, this.size = 18});
  final MMNodeAction action;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _NodeActionPainter(action, color)),
  );
}

class _NodeActionPainter extends CustomPainter {
  const _NodeActionPainter(this.action, this.color);
  final MMNodeAction action;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void box(double x, double y, double w, double h) =>
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(1.3)), pen);
    final path = Path();
    switch (action) {
      case MMNodeAction.child:
        box(2, 2.5, 9, 7);
        box(13, 14, 9, 8);
        path
          ..moveTo(6.5, 9.5)
          ..lineTo(6.5, 18)
          ..lineTo(13, 18)
          ..moveTo(15.5, 18)
          ..lineTo(19.5, 18)
          ..moveTo(17.5, 16)
          ..lineTo(17.5, 20);
      case MMNodeAction.sibling:
        box(10, 2.5, 12, 7);
        box(10, 15, 12, 7);
        path
          ..moveTo(3, 6)
          ..lineTo(10, 6)
          ..moveTo(3, 6)
          ..lineTo(3, 18.5)
          ..lineTo(10, 18.5)
          ..moveTo(14, 18.5)
          ..lineTo(18, 18.5)
          ..moveTo(16, 16.5)
          ..lineTo(16, 20.5);
      case MMNodeAction.merge:
        box(1, 3, 6, 5);
        box(1, 16, 6, 5);
        box(17, 9, 6, 6);
        path
          ..moveTo(7, 5.5)
          ..lineTo(11, 5.5)
          ..lineTo(16.5, 12)
          ..moveTo(7, 18.5)
          ..lineTo(11, 18.5)
          ..lineTo(16.5, 12);
      case MMNodeAction.summary:
        box(1, 3, 7, 5);
        box(1, 16, 7, 5);
        box(17, 9, 6, 6);
        path
          ..moveTo(11, 3)
          ..cubicTo(13, 3, 13, 3, 13, 6)
          ..lineTo(13, 9)
          ..cubicTo(13, 12, 14, 12, 16, 12)
          ..cubicTo(14, 12, 13, 12, 13, 15)
          ..lineTo(13, 18)
          ..cubicTo(13, 21, 13, 21, 11, 21);
      case MMNodeAction.relation:
        box(1, 2.5, 7, 5);
        box(16, 16.5, 7, 5);
        path
          ..moveTo(8, 5)
          ..cubicTo(23, 3, 1, 21, 16, 19)
          ..moveTo(13.5, 16.5)
          ..lineTo(16, 19)
          ..lineTo(13.5, 21.5);
    }
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_NodeActionPainter old) => old.action != action || old.color != color;
}
