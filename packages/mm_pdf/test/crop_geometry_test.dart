import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

void main() {
  test('pixel bounds include dark and colored content, ignore transparent pixels', () {
    final pixels = Uint8List.fromList(List.filled(8 * 10 * 4, 255));
    for (final (x, y) in [(2, 3), (5, 7)]) {
      pixels[(y * 8 + x) * 4] = 10;
    }
    pixels[0] = 0;
    pixels[3] = 0;
    expect(cropPixelBounds((pixels: pixels, width: 8, height: 10)), const Rect.fromLTRB(2, 3, 6, 8));
    expect(cropPixelBounds((pixels: Uint8List(4), width: 1, height: 1)), isNull);
    expect(() => cropPixelBounds((pixels: pixels, width: 1, height: 1)), throwsArgumentError);
    expect(() => cropPixelBounds((pixels: Uint8List(0), width: 0, height: 0)), throwsArgumentError);
  });
  test('one document frame retains headers, footers, unequal sizes and 14pt padding', () {
    final result = automaticCrop([
      (size: const Size(600, 800), content: const Rect.fromLTRB(80, 20, 520, 770)),
      (size: const Size(500, 700), content: const Rect.fromLTRB(90, 30, 450, 650)),
    ]);
    expect(result.toJson(), CropInsets(left: 66, top: 6, right: 36, bottom: 16).toJson());
    expect(automaticCrop([]).left, 0);
    expect(automaticCrop([(size: const Size(500, 700), content: null)]).left, 0);
    expect(
      automaticCrop([(size: const Size(500, 700), content: const Rect.fromLTRB(-4, -5, 600, 800))]).toJson(),
      CropInsets().toJson(),
    );
  });
  test('ink footprint expands the automatic frame for pen, ellipse and arrow', () {
    InkStroke stroke(InkTool tool) => InkStroke(
      id: 's',
      documentId: 'd',
      page: 1,
      tool: tool,
      colorIndex: 0,
      width: 4,
      points: const [InkPoint(20, 300), InkPoint(180, 320)],
    );
    final pen = cropInkBounds(stroke(InkTool.pen)).single;
    expect(pen.left, 18);
    expect(pen.top, 322);
    expect(pen.right, 182);
    expect(pen.bottom, 298);
    expect(cropInkBounds(stroke(InkTool.arrow)).single.left, 0);
    final ellipse = InkStroke(
      id: 'e',
      documentId: 'd',
      page: 1,
      tool: InkTool.ellipse,
      colorIndex: 0,
      width: 2,
      ellipse: const PageRect(10, 400, 90, 300),
    );
    expect(cropInkBounds(ellipse).single, const PageRect(9, 401, 91, 299));
    final crop = automaticCrop([
      (size: const Size(600, 800), content: Rect.fromLTRB(pen.left, 800 - pen.top, 500, 700)),
    ]);
    expect(crop.left, 4);
  });
  test('scope changes and edits preserve page numbering and separate odd/even', () {
    final initial = DocumentCrop(all: CropInsets(left: 30, right: 40));
    var crop = changeCropScope(initial, CropScope.oddEven, 1);
    crop = changeCropPage(crop, 1, CropInsets(left: 50));
    expect(crop.forPage(1).left, 50);
    expect(crop.forPage(2).left, 30);
    crop = changeCropPage(crop, 2, CropInsets(right: 80));
    expect(crop.forPage(2).right, 80);
    crop = changeCropScope(crop, CropScope.page, 2);
    expect(crop.forPage(2).right, 80);
    expect(crop.forPage(1).left, 0);
    crop = changeCropPage(crop, 3, CropInsets(top: 10));
    expect(crop.forPage(3).top, 10);
    crop = changeCropScope(crop, CropScope.all, 3);
    expect(crop.pages, isEmpty);
    expect(crop.odd, isNull);
    expect(crop.forPage(100).top, 10);
    crop = changeCropPage(crop, 2, CropInsets(left: 5));
    expect(crop.forPage(1).left, 5);
  });
}
