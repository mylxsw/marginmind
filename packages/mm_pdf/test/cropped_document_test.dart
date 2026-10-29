import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/src/cropped_document.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installTestPdfBackend);
  test('source tiles crop original pixels; text and destinations translate without changing the file', () async {
    final original = await PdfDocument.openFile('crop-proxy.pdf');
    final crop = CropInsets(left: 24, top: 36, right: 60, bottom: 80);
    final doc = CroppedDocument(original, DocumentCrop(all: crop));
    final page = doc.pages.first as CroppedPage;
    expect(page.width, 516);
    expect(page.height, 684);
    expect(original.pages.first.width, 600);
    expect(original.pages.first.height, 800);
    final text = await page.loadStructuredText();
    final source = await original.pages.first.loadStructuredText();
    expect(text.fullText, source.fullText);
    expect(text.charRects.first.left, source.charRects.first.left - 24);
    expect(text.charRects.first.top, source.charRects.first.top - 80);
    expect(page.toOriginal(page.fromOriginal(source.charRects.first)), source.charRects.first);
    final t = page.transform(scale: 2, origin: const Offset(10, 20));
    expect(t.toViewport(const Offset(24, 764)), const Offset(10, 20));
    TestPdfRender.produceImages = true;
    addTearDown(() {
      TestPdfRender.produceImages = false;
      TestPdfRender.renders.clear();
    });
    final image = await page.render(x: 10, y: 12, width: 100, height: 120, fullWidth: 1032, fullHeight: 1368);
    expect(image!.width, 100);
    expect(TestPdfRender.renders.last['x'], 58);
    expect(TestPdfRender.renders.last['y'], 84);
    image.dispose();
    final full = await page.render();
    expect(full!.width, 516);
    expect(full.height, 684);
    full.dispose();
    for (final (command, params, expected) in [
      (PdfDestCommand.xyz, <double?>[100, 500, null], <double?>[76, 420, null]),
      (PdfDestCommand.fitH, <double?>[500], <double?>[420]),
      (PdfDestCommand.fitBH, <double?>[null], <double?>[null]),
      (PdfDestCommand.fitV, <double?>[100], <double?>[76]),
      (PdfDestCommand.fitBV, <double?>[100], <double?>[76]),
      (PdfDestCommand.fitR, <double?>[100, 200, 300, 400], <double?>[76, 120, 276, 320]),
      (PdfDestCommand.fit, <double?>[], <double?>[]),
    ]) {
      expect(doc.destination(PdfDest(2, command, params))!.params, expected);
    }
    expect(doc.destination(null), isNull);
    expect(doc.destination(const PdfDest(99, PdfDestCommand.fit, null))!.pageNumber, 99);
    expect(page.rotation, PdfPageRotation.none);
    expect(page.isLoaded, isTrue);
    expect(page.pageNumber, 1);
    expect(page.createCancellationToken().isCanceled, isFalse);
    TestPdfLinks.pages = {
      1: [
        const PdfLink([PdfRect(100, 700, 200, 680)], dest: PdfDest(2, PdfDestCommand.xyz, [100, 500])),
      ],
    };
    final link = (await page.loadLinks()).single;
    expect(link.rects.single, const PdfRect(76, 620, 176, 600));
    expect(link.dest!.params, [76, 420]);
    TestPdfLinks.pages = {};
    expect(await page.loadLinks(), isEmpty);
    expect(doc.isEncrypted, false);
    expect(doc.permissions, isNull);
    expect(doc.isIdenticalDocumentHandle(doc), true);
    expect(doc.isIdenticalDocumentHandle(original), false);
    expect(() => doc.pages = [], throwsUnsupportedError);
    expect(() => doc.assemble(), throwsUnsupportedError);
    expect(() => doc.encodePdf(), throwsUnsupportedError);
    expect(() => doc.reloadPages(), throwsUnsupportedError);
    await doc.loadPagesProgressively<void>();
    TestPdfOutline.nodes = [
      const PdfOutlineNode(title: 'chapter', dest: PdfDest(1, PdfDestCommand.xyz, [100, 500]), children: []),
    ];
    expect((await doc.loadOutline()).first.dest!.params, [76, 420]);
    TestPdfOutline.nodes = [];
    await doc.dispose();
  });
  test('invalid source crop rejected before rendering', () async {
    final original = await PdfDocument.openFile('invalid-crop.pdf');
    expect(() => CroppedDocument(original, DocumentCrop(all: CropInsets(left: 600))), throwsArgumentError);
    await original.dispose();
  });
}
