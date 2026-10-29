import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SVG picture preserves intrinsic size, scales and releases', () async {
    MMBookImage.clearSvgCache();
    final bytes = Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10" fill="red"/></svg>',
      ),
    );
    for (var i = 0; i < 2; i++) {
      final image = await MMBookImage.decode(bytes, svgImage: true);
      expect(image.size, const ui.Size(20, 10));
      final recorder = ui.PictureRecorder();
      image.paint(ui.Canvas(recorder), const ui.Rect.fromLTWH(0, 0, 40, 20));
      final picture = recorder.endRecording();
      final raster = await picture.toImage(40, 20);
      final pixel = (await raster.toByteData())!;
      expect(pixel.getUint8(0), 255);
      expect(pixel.getUint8(1), 0);
      expect(pixel.getUint8(3), 255);
      final png = await raster.toByteData(format: ui.ImageByteFormat.png);
      final decoded = await MMBookImage.decode(png!.buffer.asUint8List(), svgImage: false);
      final r = ui.PictureRecorder();
      decoded.paint(ui.Canvas(r), const ui.Rect.fromLTWH(0, 0, 40, 20));
      r.endRecording().dispose();
      decoded.dispose();
      raster.dispose();
      picture.dispose();
      image.dispose();
    }
    MMBookImage.clearSvgCache();
    await expectLater(MMBookImage.decode(Uint8List(4), svgImage: false), throwsA(anything));
    await expectLater(
      MMBookImage.decode(Uint8List.fromList(utf8.encode('not svg')), svgImage: true),
      throwsA(anything),
    );
  });
}
