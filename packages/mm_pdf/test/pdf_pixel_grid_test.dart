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

  test('every source row survives the actual preview downscale at both DPRs', () async {
    Future<bool> survives(int width, int height, ui.Size target, int row) async {
      final source = ui.PictureRecorder();
      final sc = ui.Canvas(source)..drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
      sc.drawRect(
        ui.Rect.fromLTWH(0, row.toDouble(), width.toDouble(), 1),
        ui.Paint()..color = const ui.Color(0xff000000),
      );
      final sp = source.endRecording();
      final bitmap = await sp.toImage(width, height);
      final output = ui.PictureRecorder();
      final canvas = ui.Canvas(output)..drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
      canvas.drawImageRect(
        bitmap,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Offset.zero & target,
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      final picture = output.endRecording();
      final image = await picture.toImage(target.width.toInt(), target.height.toInt());
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      final visible = [
        for (var y = 0; y < target.height; y++) bytes[(y * target.width.toInt() + target.width ~/ 2) * 4],
      ].any((v) => v < 200);
      image.dispose();
      picture.dispose();
      bitmap.dispose();
      sp.dispose();
      return visible;
    }

    // Negative control: the rejected 3:1 policy demonstrably loses rows.
    expect(await survives(24, 24, const ui.Size(8, 8), 0), isFalse);
    for (final dpr in [1.0, 2.0]) {
      for (final samples in [1, 2]) {
        final plan = pdfPreviewPlan(const ui.Size(19.37, 27.81), .83, dpr, samples: samples);
        final width = (19.37 * plan.scale).toInt();
        final height = (27.81 * plan.scale).toInt();
        expect(width, plan.deviceSize!.width * samples);
        expect(height, plan.deviceSize!.height * samples);
        for (var row = 0; row < height; row++) {
          expect(
            await survives(width, height, plan.deviceSize!, row),
            isTrue,
            reason: 'DPR=$dpr samples=$samples source row=$row/$height',
          );
        }
      }
    }
  });

  test('fractional page sizes keep both bitmap dimensions at an exact integer ratio', () {
    for (final page in [const ui.Size(595.28, 841.89), const ui.Size(612, 792), const ui.Size(800, 600)]) {
      for (final dpr in [1.0, 2.0]) {
        for (final zoom in [.31, .8273, 1.26]) {
          for (final samples in [1, 2]) {
            final plan = pdfPreviewPlan(page, zoom, dpr, samples: samples);
            if (plan.deviceSize == null) {
              expect(plan.scale * page.longestSide, closeTo(4000, 1e-8));
              continue;
            }
            expect((page.width * plan.scale).toInt(), plan.deviceSize!.width * samples);
            expect((page.height * plan.scale).toInt(), plan.deviceSize!.height * samples);
            expect((plan.deviceSize!.width - page.width * zoom * dpr).abs(), lessThan(3));
            expect((plan.deviceSize!.height - page.height * zoom * dpr).abs(), lessThan(3));
          }
        }
      }
    }
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
