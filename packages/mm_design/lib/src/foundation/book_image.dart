import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

/// Caller-owned decoded book artwork. No third-party types cross this boundary.
class MMBookImage {
  MMBookImage.raster(ui.Image image)
    : _image = image,
      _picture = null,
      size = ui.Size(image.width.toDouble(), image.height.toDouble());
  MMBookImage._vector(this._picture, this.size) : _image = null;
  final ui.Image? _image;
  final ui.Picture? _picture;
  final ui.Size size;

  /// Raster pixels retained by this handle; vector pictures allocate no raster.
  int get decodedPixels => _image == null ? 0 : _image.width * _image.height;

  /// Bounds raster allocation by both dimensions and total pixels, including
  /// unusually tall images. Vector pictures do not allocate a raster here.
  static Future<MMBookImage> decode(Uint8List bytes, {required bool svgImage, int maxPixels = 4 * 1024 * 1024}) async {
    if (maxPixels < 1) throw ArgumentError.value(maxPixels, 'maxPixels');
    if (svgImage) {
      final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
      return MMBookImage._vector(info.picture, info.size);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final ratio = math.min(
          1.0,
          math.min(1024 / descriptor.width, math.sqrt(maxPixels / (descriptor.width * descriptor.height))),
        );
        final targetWidth = math.max(1, math.min(maxPixels, (descriptor.width * ratio).floor()));
        final targetHeight = math.max(1, math.min((descriptor.height * ratio).floor(), maxPixels ~/ targetWidth));
        final codec = await descriptor.instantiateCodec(targetWidth: targetWidth, targetHeight: targetHeight);
        try {
          return MMBookImage.raster((await codec.getNextFrame()).image);
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  /// Clears compiled SVG bytes for a reproducible cold benchmark. Pictures are
  /// never retained here; normal loading uses the library's bounded byte cache.
  static void clearSvgCache() => svg.cache.clear();

  void paint(ui.Canvas canvas, ui.Rect rect) {
    if (_image != null) {
      canvas.drawImageRect(_image, ui.Offset.zero & size, rect, ui.Paint());
    } else {
      canvas.save();
      canvas.translate(rect.left, rect.top);
      canvas.scale(rect.width / size.width, rect.height / size.height);
      canvas.drawPicture(_picture!);
      canvas.restore();
    }
  }

  void dispose() {
    _image?.dispose();
    _picture?.dispose();
  }
}
