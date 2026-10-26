import 'dart:math' as math;
import 'dart:ui';

/// One plan for PDFium's truncated bitmap size and the painted device rectangle.
class PdfPreviewPlan {
  const PdfPreviewPlan(this.scale, this.deviceSize);
  final double scale;
  // Null above the preview budget, where pdfrx paints partial-resolution tiles.
  final Size? deviceSize;
}

PdfPreviewPlan pdfPreviewPlan(Size page, double zoom, double dpr, {int samples = 2}) {
  assert(samples == 1 || samples == 2);
  final limit = 4000 / math.max(page.width, page.height);
  final requested = zoom * dpr * samples;
  if (requested > limit) return PdfPreviewPlan(limit, null);

  if (samples == 1) {
    // Do not round the scale down: pdfrx would then overlay a higher-resolution
    // partial tile. Only the destination is matched to the truncated bitmap.
    return PdfPreviewPlan(
      requested,
      Size((page.width * requested).floorToDouble(), (page.height * requested).floorToDouble()),
    );
  }

  // pdfrx exposes one scalar, and PDFium truncates each bitmap dimension.
  // Find intersecting scale intervals whose integer dimensions are multiples
  // of samples. Usually this removes at most one device pixel from each edge.
  for (var width = (page.width * zoom * dpr).floor(); width > 0; width--) {
    final lower = width * samples / page.width;
    final upper = math.min((width * samples + 1) / page.width, requested + 1e-10);
    final height = (page.height * lower / samples).ceil();
    final start = math.max(lower, height * samples / page.height);
    final end = math.min(upper, (height * samples + 1) / page.height);
    if (start >= end) continue;
    final scale = (start + end) / 2;
    return PdfPreviewPlan(scale, Size(width.toDouble(), height.toDouble()));
  }
  return PdfPreviewPlan(requested, null);
}

/// Global coordinates include ancestor transforms hidden by repaint boundaries.
Rect pdfDeviceRect(Rect globalRect, double dpr, {Size? deviceSize}) => Rect.fromLTWH(
  (globalRect.left * dpr).roundToDouble() / dpr,
  (globalRect.top * dpr).roundToDouble() / dpr,
  (deviceSize?.width ?? (globalRect.width * dpr).floorToDouble()) / dpr,
  (deviceSize?.height ?? (globalRect.height * dpr).floorToDouble()) / dpr,
);

/// Apply only during a page paint; PDF coordinates and navigation stay stable.
void alignPdfPage(Canvas canvas, Rect page, Rect globalRect, double dpr, {Size? deviceSize}) {
  final snapped = pdfDeviceRect(globalRect, dpr, deviceSize: deviceSize);
  if (snapped.isEmpty) return;
  final sx = snapped.width / globalRect.width;
  final sy = snapped.height / globalRect.height;
  canvas.translate(
    page.left * (1 - sx) + (snapped.left - globalRect.left) * page.width / globalRect.width,
    page.top * (1 - sy) + (snapped.top - globalRect.top) * page.height / globalRect.height,
  );
  canvas.scale(sx, sy);
}
