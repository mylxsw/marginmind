import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

void main() {
  setUp(() {
    installTestPdfBackend();
    TestPdfOutline.nodes = [
      const PdfOutlineNode(
        title: 'Chapter',
        dest: PdfDest(1, PdfDestCommand.fit, null),
        children: [PdfOutlineNode(title: 'Section', dest: PdfDest(2, PdfDestCommand.fit, null), children: [])],
      ),
    ];
  });
  tearDown(() => TestPdfOutline.nodes = []);
  test('native outline IDs match reader IDs and quote page preserves character geometry', () async {
    final outline = await MMPdfEngine.outline('/test.pdf', 'doc');
    expect(outline.items.single.id, 'pdf-0');
    expect(outline.items.single.children.single.id, 'pdf-0/0');
    expect(outline.items.single.children.single.page, 2);
    final page = await MMPdfEngine.quotePage('/test.pdf', 1);
    expect(page!.text, 'Selected passage');
    expect(page.boxes.length, page.text.length);
    expect(await MMPdfEngine.quotePage('/test.pdf', 0), isNull);
    expect(await MMPdfEngine.quotePage('/test.pdf', 4), isNull);
  });
}
