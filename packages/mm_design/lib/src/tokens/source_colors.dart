import 'package:flutter/widgets.dart';

/// Dots that tell the source documents of a mind map apart (GUL-600): the
/// dot before a generated topic's page chip and the legend of a map merged
/// from several documents. Documents take the colors in the order the map
/// lists them, cycling after the last one.
abstract final class MMSourceColors {
  /// Blue, orange, green, pink, teal, gray (system colors).
  static const List<Color> light = [
    Color(0xFF007AFF),
    Color(0xFFFF9500),
    Color(0xFF34C759),
    Color(0xFFFF2D55),
    Color(0xFF30B0C7),
    Color(0xFF8E8E93),
  ];

  static const List<Color> dark = [
    Color(0xFF0A84FF),
    Color(0xFFFF9F0A),
    Color(0xFF30D158),
    Color(0xFFFF375F),
    Color(0xFF40C8E0),
    Color(0xFF8E8E93),
  ];

  /// The dot of the document at [index] among a map's sources.
  static Color of(Brightness brightness, int index) {
    final colors = brightness == Brightness.dark ? dark : light;
    return colors[index % colors.length];
  }
}
