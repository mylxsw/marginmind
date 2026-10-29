import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'support/pdf_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installTestPdfBackend);

  test('translation extraction keeps original page boxes and closes the document', () async {
    final paragraphs = await MMPdfEngine.translationParagraphs('any.pdf', 'doc');
    expect(paragraphs.map((p) => p.page), [1, 2, 3]);
    expect(paragraphs.first.documentId, 'doc');
    expect(paragraphs.first.text, 'Selected passage');
    expect(paragraphs.first.rects, isNotEmpty);
    expect(paragraphs.first.fingerprint, isNot(paragraphs.last.fingerprint));
  });

  test('pageText reads one page and gives null for bad pages', () async {
    expect(await MMPdfEngine.pageText('any.pdf', 2), 'Selected passage');
    expect(await MMPdfEngine.pageContent('any.pdf', 2), (text: 'Selected passage', height: 800.0));
    expect(await MMPdfEngine.pageText('any.pdf', 0), isNull);
    expect(await MMPdfEngine.pageText('any.pdf', 4), isNull);
  });

  testWidgets('page preview covers the excerpt area in page coordinates', (tester) async {
    const cover = Color(0xFF123456);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: MMPdfPagePreview(
              filePath: 'a.pdf',
              page: 2,
              covers: [PageRect(60, 700, 360, 600)],
              coverColor: cover,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final box = find.byWidgetPredicate((w) => w is ColoredBox && w.color == cover);
    expect(box, findsOneWidget);
    // The 600x800 page is shown at 300 wide: half scale, top edge 700 -> y 50.
    expect(tester.getSize(box), const Size(150, 50));
    final page = tester.getTopLeft(find.byType(AspectRatio).first);
    expect(tester.getTopLeft(box) - page, const Offset(30, 50));
  });

  testWidgets('page preview is empty for a page that does not exist', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MMPdfPagePreview(filePath: 'a.pdf', page: 9, coverColor: Color(0xFF000000)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(AspectRatio), findsNothing);
  });
}
