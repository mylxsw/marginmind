import 'dart:ui';

/// Quantize the page extent and origin to the device grid. The caller supplies global coordinates because a repaint
/// boundary's canvas does not include all ancestor transforms.
Rect pdfDeviceRect(Rect globalRect, double dpr) => Rect.fromLTWH(
  (globalRect.left * dpr).roundToDouble() / dpr,
  (globalRect.top * dpr).roundToDouble() / dpr,
  (globalRect.width * dpr).floorToDouble() / dpr,
  (globalRect.height * dpr).floorToDouble() / dpr,
);

/// Apply only during a page paint; PDF coordinates and navigation stay stable.
void alignPdfPage(Canvas canvas, Rect page, Rect globalRect, double dpr) {
  final snapped = pdfDeviceRect(globalRect, dpr);
  if (snapped.isEmpty) return;
  final sx = snapped.width / globalRect.width;
  final sy = snapped.height / globalRect.height;
  canvas.translate(
    page.left * (1 - sx) + (snapped.left - globalRect.left) * page.width / globalRect.width,
    page.top * (1 - sy) + (snapped.top - globalRect.top) * page.height / globalRect.height,
  );
  canvas.scale(sx, sy);
}
