import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/src/pdf_pixel_grid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fractional page positions have integer physical origins and extents', () {
    for (final dpr in [1.0, 2.0, 3.0]) {
      for (final offset in [0.0, 0.125, 0.5, 0.875]) {
        final page = ui.Rect.fromLTWH(43 + offset, -12 + offset, 492.37, 696.81);
        final snapped = pdfDeviceRect(page, dpr);
        expect(snapped.left * dpr, (snapped.left * dpr).roundToDouble());
        expect(snapped.top * dpr, (snapped.top * dpr).roundToDouble());
        expect(snapped.width * dpr, closeTo((page.width * dpr).toInt(), 1e-9));
        expect(snapped.height * dpr, closeTo((page.height * dpr).toInt(), 1e-9));
        expect((snapped.topLeft - page.topLeft).distance, lessThanOrEqualTo(0.71 / dpr));
      }
    }
  });

  test('2x bilinear painting preserves a one-device-pixel stroke', () async {
    final source = ui.PictureRecorder();
    final sourceCanvas = ui.Canvas(source);
    sourceCanvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    sourceCanvas.drawRect(const ui.Rect.fromLTWH(0, 8, 16, 1), ui.Paint()..color = const ui.Color(0xff000000));
    final picture = source.endRecording();
    final bitmap = await picture.toImage(16, 16);
    picture.dispose();
    addTearDown(bitmap.dispose);

    Future<List<int>> paint(bool snap) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
      canvas.scale(2);
      const page = ui.Rect.fromLTWH(3.25, 3.25, 8, 8);
      canvas.save();
      if (snap) alignPdfPage(canvas, page, page, 2);
      canvas.drawImageRect(
        bitmap,
        const ui.Rect.fromLTWH(0, 0, 16, 16),
        page,
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 32);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final column = [for (var y = 0; y < 32; y++) bytes[(y * 32 + 12) * 4]];
      image.dispose();
      picture.dispose();
      return column;
    }

    final blurred = await paint(false);
    expect(blurred.where((v) => v > 0 && v < 255).length, 2);
    final aligned = await paint(true);
    expect(aligned.where((v) => v == 0).length, 1);
    expect(aligned.where((v) => v > 0 && v < 255), isEmpty);
  });

  test('subpixel-sized pages do not introduce a singular canvas transform', () {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final before = canvas.getTransform();
    alignPdfPage(canvas, const ui.Rect.fromLTWH(0, 0, 1, 1), const ui.Rect.fromLTWH(0, 0, 0.1, 0.1), 1);
    expect(canvas.getTransform(), before);
    recorder.endRecording().dispose();
  });
}
