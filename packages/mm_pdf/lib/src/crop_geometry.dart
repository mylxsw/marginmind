import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:mm_core/mm_core.dart';

/// Conservative non-white BGRA bounds. Runs in a background isolate for scans.
Rect? cropPixelBounds(({Uint8List pixels, int width, int height}) image) {
  if (image.width <= 0 || image.height <= 0 || image.pixels.length != image.width * image.height * 4) {
    throw ArgumentError('Invalid crop bitmap');
  }
  var left = image.width, top = image.height, right = -1, bottom = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final i = (y * image.width + x) * 4;
      if (image.pixels[i + 3] > 16 &&
          (image.pixels[i] < 240 || image.pixels[i + 1] < 240 || image.pixels[i + 2] < 240)) {
        left = math.min(left, x);
        top = math.min(top, y);
        right = math.max(right, x);
        bottom = math.max(bottom, y);
      }
    }
  }
  return right < left ? null : Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}

/// One set of edge distances for the whole document. A blank or unreadable
/// page contributes zero insets, so uncertain content is never discarded.
CropInsets automaticCrop(List<({Size size, Rect? content})> pages, {double padding = 14}) {
  if (pages.isEmpty) return CropInsets();
  var left = double.infinity, top = left, right = left, bottom = left;
  for (final page in pages) {
    final r = page.content;
    if (r == null || r.isEmpty) return CropInsets();
    left = math.min(left, math.max(0, r.left - padding));
    top = math.min(top, math.max(0, r.top - padding));
    right = math.min(right, math.max(0, page.size.width - r.right - padding));
    bottom = math.min(bottom, math.max(0, page.size.height - r.bottom - padding));
  }
  return CropInsets(left: left, top: top, right: right, bottom: bottom);
}

/// Original PDF coordinates of each mark, including the pen's full footprint.
List<PageRect> cropInkBounds(InkStroke stroke) {
  final ellipse = stroke.ellipse;
  if (ellipse != null) {
    final padding = stroke.width / 2;
    return [PageRect(ellipse.left - padding, ellipse.top + padding, ellipse.right + padding, ellipse.bottom - padding)];
  }
  if (stroke.points.isEmpty) return const [];
  final padding = stroke.width * (stroke.tool == InkTool.arrow ? 5 : .5);
  return [
    PageRect(
      stroke.points.map((p) => p.x).reduce(math.min) - padding,
      stroke.points.map((p) => p.y).reduce(math.max) + padding,
      stroke.points.map((p) => p.x).reduce(math.max) + padding,
      stroke.points.map((p) => p.y).reduce(math.min) - padding,
    ),
  ];
}

DocumentCrop changeCropScope(DocumentCrop crop, CropScope scope, int page) {
  final effective = crop.forPage(page);
  return switch (scope) {
    CropScope.all => DocumentCrop(mode: CropMode.manual, all: effective),
    CropScope.oddEven => DocumentCrop(mode: CropMode.manual, scope: scope, all: effective, odd: effective),
    CropScope.page => DocumentCrop(
      mode: CropMode.manual,
      scope: scope,
      all: crop.all,
      pages: {...crop.pages, page: effective},
    ),
  };
}

DocumentCrop changeCropPage(DocumentCrop crop, int page, CropInsets insets) => switch (crop.scope) {
  CropScope.all => crop.copyWith(enabled: true, mode: CropMode.manual, all: insets),
  CropScope.oddEven =>
    page.isOdd
        ? crop.copyWith(enabled: true, mode: CropMode.manual, odd: insets)
        : crop.copyWith(enabled: true, mode: CropMode.manual, all: insets),
  CropScope.page => crop.copyWith(enabled: true, mode: CropMode.manual, pages: {...crop.pages, page: insets}),
};
