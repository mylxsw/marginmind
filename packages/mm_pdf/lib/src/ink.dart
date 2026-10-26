import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mm_core/mm_core.dart' show InkPoint, InkStroke, InkTool, PageRect;

/// What a drag does while the pen is out.
enum MMPdfInkTool { freehand, ellipse, arrow, eraser }

/// The pen the reader holds; null on [MMPdfView] means "not drawing".
@immutable
class MMPdfInk {
  const MMPdfInk({required this.tool, required this.colorIndex, required this.width});

  final MMPdfInkTool tool;

  /// Index into [MMPdfView.inkColors].
  final int colorIndex;

  /// Stroke width in PDF points.
  final double width;

  @override
  bool operator ==(Object other) =>
      other is MMPdfInk && other.tool == tool && other.colorIndex == colorIndex && other.width == width;

  @override
  int get hashCode => Object.hash(tool, colorIndex, width);
}

/// A finished stroke in page coordinates, ready to become an [InkStroke].
/// A pen stroke carries simplified [points]; an arrow its two end points; a
/// regularized circle only its [ellipse] bounds.
@immutable
class MMPdfInkDraft {
  const MMPdfInkDraft({
    required this.page,
    required this.tool,
    required this.colorIndex,
    required this.width,
    this.points = const [],
    this.ellipse,
  });

  final int page;
  final InkTool tool;
  final int colorIndex;
  final double width;
  final List<InkPoint> points;
  final PageRect? ellipse;

  InkStroke toStroke({required String id, required String documentId}) => InkStroke(
    id: id,
    documentId: documentId,
    page: page,
    tool: tool,
    colorIndex: colorIndex,
    width: width,
    points: points,
    ellipse: ellipse,
  );
}

/// Upper bound for one stored stroke, well below [InkStroke.maxPoints].
const inkMaxPoints = 1000;

/// Douglas–Peucker in page points. The tolerance doubles until the stroke
/// fits [maxPoints]; the first and last points always survive.
List<InkPoint> simplifyInk(List<InkPoint> points, {double tolerance = 0.3, int maxPoints = inkMaxPoints}) {
  if (points.length <= 2) return List.of(points);
  var epsilon = tolerance;
  while (true) {
    final keep = List<bool>.filled(points.length, false);
    keep[0] = keep[points.length - 1] = true;
    final stack = <(int, int)>[(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (first, last) = stack.removeLast();
      var index = -1;
      var max = epsilon;
      for (var i = first + 1; i < last; i++) {
        final d = _segmentDistance(points[i], points[first], points[last]);
        if (d > max) {
          max = d;
          index = i;
        }
      }
      if (index < 0) continue;
      keep[index] = true;
      stack
        ..add((first, index))
        ..add((index, last));
    }
    final result = [
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
    if (result.length <= maxPoints) return result;
    epsilon *= 2;
  }
}

/// The circle the user meant: the stroke's bounds, grown by [padding] so the
/// ellipse surrounds what was circled. Never degenerate.
PageRect inkEllipseBounds(List<InkPoint> points, {double padding = 2}) {
  var left = double.infinity, right = -double.infinity, bottom = double.infinity, top = -double.infinity;
  for (final p in points) {
    left = math.min(left, p.x);
    right = math.max(right, p.x);
    bottom = math.min(bottom, p.y);
    top = math.max(top, p.y);
  }
  return PageRect(left - padding, top + padding, right + padding, bottom - padding);
}

/// Whether [point] (page coordinates) touches [stroke] within [radius]
/// points of its outline.
bool inkStrokeHit(InkStroke stroke, InkPoint point, double radius) {
  final reach = radius + stroke.width / 2;
  final ellipse = stroke.ellipse;
  if (ellipse != null) return _polylineDistance(_ellipseOutline(ellipse), point) <= reach;
  return _polylineDistance(stroke.points, point) <= reach;
}

List<InkPoint> _ellipseOutline(PageRect r, [int segments = 72]) {
  final cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
  final rx = (r.right - r.left) / 2, ry = (r.top - r.bottom) / 2;
  return [
    for (var i = 0; i <= segments; i++)
      InkPoint(cx + rx * math.cos(2 * math.pi * i / segments), cy + ry * math.sin(2 * math.pi * i / segments)),
  ];
}

double _polylineDistance(List<InkPoint> line, InkPoint p) {
  if (line.isEmpty) return double.infinity;
  if (line.length == 1) return _distance(line.first, p);
  var best = double.infinity;
  for (var i = 1; i < line.length; i++) {
    best = math.min(best, _segmentDistance(p, line[i - 1], line[i]));
  }
  return best;
}

double _distance(InkPoint a, InkPoint b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

double _segmentDistance(InkPoint p, InkPoint a, InkPoint b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final length = dx * dx + dy * dy;
  if (length == 0) return _distance(p, a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / length).clamp(0.0, 1.0);
  return _distance(p, InkPoint(a.x + t * dx, a.y + t * dy));
}

/// Paints one stroke whose geometry has already been mapped to canvas
/// coordinates. [width] is in canvas pixels.
void paintInk(
  Canvas canvas, {
  required InkTool tool,
  required List<Offset> points,
  Rect? ellipse,
  required Color color,
  required double width,
}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (ellipse != null) {
    canvas.drawOval(ellipse, paint);
    return;
  }
  if (points.isEmpty) return;
  if (points.length == 1) {
    canvas.drawCircle(points.first, width / 2, paint..style = PaintingStyle.fill);
    return;
  }
  if (tool == InkTool.arrow) {
    final a = points.first, b = points.last;
    final direction = b - a;
    final length = direction.distance;
    if (length == 0) return;
    final unit = direction / length;
    // The head grows with the stroke but never exceeds half the shaft.
    final head = math.min(width * 3 + 4, length / 2);
    final base = b - unit * head;
    final normal = Offset(-unit.dy, unit.dx) * head * 0.55;
    canvas.drawLine(a, base, paint);
    canvas.drawPath(
      Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo(base.dx + normal.dx, base.dy + normal.dy)
        ..lineTo(base.dx - normal.dx, base.dy - normal.dy)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    return;
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(path, paint);
}

/// Maps page points to canvas offsets, and the page's points to pixels.
typedef InkMapping = ({Offset Function(InkPoint) point, double scale});

/// Paints [stroke] through [mapping]. Ellipse bounds map corner to corner,
/// which stays axis-aligned for every page rotation.
void paintInkStroke(Canvas canvas, InkStroke stroke, Color color, InkMapping mapping) {
  final e = stroke.ellipse;
  paintInk(
    canvas,
    tool: stroke.tool,
    points: [for (final p in stroke.points) mapping.point(p)],
    ellipse: e == null
        ? null
        : Rect.fromPoints(mapping.point(InkPoint(e.left, e.top)), mapping.point(InkPoint(e.right, e.bottom))),
    color: color,
    width: stroke.width * mapping.scale,
  );
}

/// One page's strokes. Repaints only when this page's list, the palette or
/// [hidden] (strokes being erased) change.
class InkPagePainter extends CustomPainter {
  InkPagePainter({required this.strokes, required this.colors, required this.map, required this.hidden})
    : super(repaint: hidden);

  final List<InkStroke> strokes;
  final List<Color> colors;

  /// Page-to-canvas mapping for a canvas of the given size.
  final InkMapping Function(Size size) map;
  final ValueNotifier<Set<String>> hidden;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final mapping = map(size);
    final skip = hidden.value;
    for (final s in strokes) {
      if (skip.contains(s.id)) continue;
      paintInkStroke(canvas, s, colors[s.colorIndex.clamp(0, colors.length - 1)], mapping);
    }
  }

  @override
  bool shouldRepaint(InkPagePainter old) =>
      !identical(old.strokes, strokes) || !_sameColors(old.colors, colors) || old.hidden != hidden;
}

bool _sameColors(List<Color> a, List<Color> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The stroke under the pen and the just-finished one awaiting the parent's
/// save, in viewport coordinates.
class InkLivePainter extends CustomPainter {
  InkLivePainter({required this.strokes, required this.colors, required this.map, super.repaint});

  /// Page number and stroke, read at paint time.
  final List<(int, InkStroke)> Function() strokes;
  final List<Color> colors;
  final InkMapping? Function(int page) map;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    for (final (page, s) in strokes()) {
      final mapping = map(page);
      if (mapping == null) continue;
      paintInkStroke(canvas, s, colors[s.colorIndex.clamp(0, colors.length - 1)], mapping);
    }
  }

  @override
  bool shouldRepaint(InkLivePainter old) => true;
}

/// Rasterizes what [painter] draws on a canvas of [size]; for tests.
@visibleForTesting
Future<ui.Image> debugRenderInk(CustomPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  return recorder.endRecording().toImage(size.width.ceil(), size.height.ceil());
}
