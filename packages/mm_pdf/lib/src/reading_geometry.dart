import 'dart:math' as math;
import 'dart:ui';

import 'package:mm_core/mm_core.dart';

/// All crop rendering and hit testing share this original-PDF transform.
class PageViewportTransform {
  PageViewportTransform({required this.pageSize, required this.crop, this.scale = 1, this.origin = Offset.zero}) {
    crop.validateSize(pageSize.width, pageSize.height);
    if (!scale.isFinite || scale <= 0) throw ArgumentError('Invalid scale');
  }
  final Size pageSize;
  final CropInsets crop;
  final double scale;
  final Offset origin;
  Size get visibleSize =>
      Size((pageSize.width - crop.left - crop.right) * scale, (pageSize.height - crop.top - crop.bottom) * scale);
  Offset toViewport(Offset pdf) => origin + Offset(pdf.dx - crop.left, pageSize.height - pdf.dy - crop.top) * scale;
  Offset toPdf(Offset viewport) {
    final local = (viewport - origin) / scale;
    return Offset(local.dx + crop.left, pageSize.height - crop.top - local.dy);
  }

  Rect rect(PageRect value) =>
      Rect.fromPoints(toViewport(Offset(value.left, value.top)), toViewport(Offset(value.right, value.bottom)));
}

/// Monotone, invertible mapping in page fractions, independent of crop/zoom.
class ReadingAlignment {
  ReadingAlignment({
    required List<double> leftHeights,
    required List<double> rightHeights,
    List<AlignPoint> points = const [],
  }) : leftHeights = List.unmodifiable(leftHeights),
       rightHeights = List.unmodifiable(rightHeights) {
    for (final heights in [leftHeights, rightHeights]) {
      if (heights.isEmpty || heights.any((h) => !h.isFinite || h <= 0)) throw ArgumentError('Invalid page heights');
    }
    final anchors = [for (final p in points) (scalar(p.left, leftHeights), scalar(p.right, rightHeights))]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    _points = [
      (0, 0),
      ...anchors.where((p) => p != (0.0, 0.0) && p != (leftHeights.length.toDouble(), rightHeights.length.toDouble())),
      (leftHeights.length.toDouble(), rightHeights.length.toDouble()),
    ];
    for (var i = 1; i < _points.length; i++) {
      if (_points[i].$1 <= _points[i - 1].$1 || _points[i].$2 <= _points[i - 1].$2) {
        throw ArgumentError('Crossed or duplicate alignment');
      }
    }
  }
  final List<double> leftHeights, rightHeights;
  late final List<(double, double)> _points;
  static double scalar(PdfReadingPosition p, List<double> heights) {
    if (p.page > heights.length || p.y > heights[p.page - 1]) throw ArgumentError('Position outside page');
    return p.page - 1 + (heights[p.page - 1] - p.y) / heights[p.page - 1];
  }

  static PdfReadingPosition position(double value, List<double> heights) {
    final s = value.clamp(0.0, heights.length.toDouble());
    final index = math.min(s.floor(), heights.length - 1);
    return PdfReadingPosition(page: index + 1, y: heights[index] * (1 - (s - index)));
  }

  PdfReadingPosition map(PdfReadingPosition source, {bool reverse = false}) {
    final s = scalar(source, reverse ? rightHeights : leftHeights);
    final points = reverse ? [for (final p in _points) (p.$2, p.$1)] : _points;
    var i = 1;
    while (i < points.length - 1 && s > points[i].$1) {
      i++;
    }
    final a = points[i - 1], b = points[i];
    return position(a.$2 + (s - a.$1) * (b.$2 - a.$2) / (b.$1 - a.$1), reverse ? leftHeights : rightHeights);
  }
}

/// Own one per pair. Programmatic callbacks are ignored until the driven
/// jump completes. A fresh user gesture takes ownership even during a jump.
class ReadingSync {
  int _generation = 0;
  int? _driven;
  bool enabled = true;
  bool _disposed = false;
  int drives = 0;
  void userInput(int side) {
    if (_driven == side) {
      _generation++;
      _driven = null;
    }
  }

  Future<void> drive(int source, Future<void> Function() jump) async {
    if (_disposed || !enabled || _driven == source) return;
    final generation = ++_generation;
    _driven = 1 - source;
    drives++;
    try {
      await jump();
    } finally {
      if (generation == _generation) _driven = null;
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _driven = null;
  }
}
