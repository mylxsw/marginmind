import 'package:flutter/widgets.dart';

import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';

/// A three-line preview; its accessible name comes from the enclosing segment.
class MMReaderLineSpacing extends StatelessWidget {
  const MMReaderLineSpacing({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: MMSizes.dropdownIcon,
    child: CustomPaint(painter: _LineSpacingPainter(index, context.mmColors.label)),
  );
}

class _LineSpacingPainter extends CustomPainter {
  const _LineSpacingPainter(this.index, this.color);
  final int index;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.height * (index.clamp(0, 2) + 2) / 8;
    final paint = Paint()
      ..color = color
      ..strokeWidth = MMSizes.readerProgressTrack;
    for (var line = -1; line <= 1; line++) {
      final y = size.height / 2 + line * gap;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_LineSpacingPainter old) => old.index != index || old.color != color;
}
