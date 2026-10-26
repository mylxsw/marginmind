import 'package:flutter/widgets.dart';

/// The six pen colors of the ink toolbar (system colors plus ink black).
/// Data stores the index only.
enum MMInkColor {
  red(Color(0xFFFF3B30)),
  orange(Color(0xFFFF9500)),
  yellow(Color(0xFFFFCC00)),
  green(Color(0xFF34C759)),
  blue(Color(0xFF007AFF)),
  black(Color(0xFF1D1D1F));

  const MMInkColor(this.color);

  final Color color;

  /// Strokes are drawn slightly translucent so the text below stays legible.
  Color get stroke => color.withValues(alpha: 0.9);

  static MMInkColor fromIndex(int index) => values[index.clamp(0, values.length - 1)];
}

/// The three pen widths, in PDF points: strokes scale with the page.
enum MMInkWidth {
  thin(1.5),
  medium(2.5),
  bold(4);

  const MMInkWidth(this.points);

  final double points;
}
