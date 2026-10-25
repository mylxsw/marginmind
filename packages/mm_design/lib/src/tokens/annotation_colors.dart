import 'package:flutter/widgets.dart';

/// The six annotation colors (system colors). Data stores the index only.
enum MMAnnotationColor {
  yellow(Color(0xFFFFCC00)),
  green(Color(0xFF34C759)),
  blue(Color(0xFF007AFF)),
  pink(Color(0xFFFF2D55)),
  orange(Color(0xFFFF9500)),
  purple(Color(0xFFAF52DE));

  const MMAnnotationColor(this.color);

  final Color color;

  static MMAnnotationColor fromIndex(int index) => values[index.clamp(0, values.length - 1)];

  /// Background of highlighted source text.
  Color get highlight => color.withValues(alpha: 0.32);

  /// 2px underline that marks "excerpted into a card".
  Color get underline => color.withValues(alpha: 0.9);

  /// Excerpt block inside a card.
  Color get cardTint => color.withValues(alpha: 0.14);

  /// Library cover tint.
  Color coverTint(Brightness brightness) => color.withValues(alpha: brightness == Brightness.dark ? 0.24 : 0.18);
}
