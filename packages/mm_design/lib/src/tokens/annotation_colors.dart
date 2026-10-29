import 'package:flutter/widgets.dart';

/// Presets retain stored IDs 0–5. Custom colors use a tagged 24-bit RGB ID
/// (0x01000000 | RGB), so marks, clipboard copies and notes retain exact color
/// without a process-local palette or changing existing document IDs.
@immutable
final class MMAnnotationColor {
  const MMAnnotationColor._(this.index, this.color, this.name);

  static const yellow = MMAnnotationColor._(0, Color(0xFFFFCC00), 'yellow');
  static const green = MMAnnotationColor._(1, Color(0xFF34C759), 'green');
  static const blue = MMAnnotationColor._(2, Color(0xFF007AFF), 'blue');
  static const pink = MMAnnotationColor._(3, Color(0xFFFF2D55), 'pink');
  static const orange = MMAnnotationColor._(4, Color(0xFFFF9500), 'orange');
  static const purple = MMAnnotationColor._(5, Color(0xFFAF52DE), 'purple');
  static const values = [yellow, green, blue, pink, orange, purple];

  final int index;
  final Color color;
  final String name;
  bool get isCustom => index >= 0x01000000;
  String get hex => '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  factory MMAnnotationColor.fromColor(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    for (final preset in values) {
      if ((preset.color.toARGB32() & 0x00FFFFFF) == rgb) return preset;
    }
    return MMAnnotationColor._(
      0x01000000 | rgb,
      Color(0xFF000000 | rgb),
      '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}',
    );
  }

  static MMAnnotationColor fromIndex(int index) => index >= 0x01000000 && index <= 0x01FFFFFF
      ? MMAnnotationColor.fromColor(Color(0xFF000000 | (index & 0x00FFFFFF)))
      : values[index.clamp(0, values.length - 1)];

  static MMAnnotationColor? tryParse(String? value) {
    for (final preset in values) {
      if (preset.name == value) return preset;
    }
    if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return null;
    return MMAnnotationColor.fromColor(Color(0xFF000000 | int.parse(value.substring(1), radix: 16)));
  }

  @override
  bool operator ==(Object other) => other is MMAnnotationColor && index == other.index;
  @override
  int get hashCode => index.hashCode;
  @override
  String toString() => 'MMAnnotationColor.$name';

  /// Background of highlighted source text.
  Color get highlight => color.withValues(alpha: 0.32);

  /// 2px underline that marks "excerpted into a card".
  Color get underline => color.withValues(alpha: 0.9);

  /// Excerpt block inside a card.
  Color get cardTint => color.withValues(alpha: 0.14);

  /// Library cover tint.
  Color coverTint(Brightness brightness) => color.withValues(alpha: brightness == Brightness.dark ? 0.24 : 0.18);
}
