import 'dart:ui';

/// Picks the nearest marked line, with exact hits taking priority over nearby
/// marks. Supply newest marks first to resolve overlaps consistently. Geometry
/// and tolerance use the same coordinates; callers scale screen-space tolerance
/// when the reading surface is zoomed.
String? hitAnnotation(Offset point, Iterable<(String, Rect)> lines, {double tolerance = 0}) {
  String? nearest;
  var distance = double.infinity;
  for (final (id, rect) in lines) {
    if (rect.isEmpty) continue;
    if (rect.contains(point)) return id;
    final dx = point.dx - point.dx.clamp(rect.left, rect.right);
    final dy = point.dy - point.dy.clamp(rect.top, rect.bottom);
    final squared = dx * dx + dy * dy;
    if (squared <= tolerance * tolerance && squared < distance) {
      nearest = id;
      distance = squared;
    }
  }
  return nearest;
}
