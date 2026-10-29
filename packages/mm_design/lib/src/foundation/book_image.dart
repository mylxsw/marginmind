import 'dart:typed_data';
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

  static Future<MMBookImage> decode(Uint8List bytes, {required bool svgImage}) async {
    if (svgImage) {
      final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
      return MMBookImage._vector(info.picture, info.size);
    }
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1024, allowUpscaling: false);
    try {
      return MMBookImage.raster((await codec.getNextFrame()).image);
    } finally {
      codec.dispose();
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
