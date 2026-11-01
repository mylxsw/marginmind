import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    installTestPdfBackend(pageCount: 50);
    TestPdfRender.requestedFullSizes.clear();
  });

  testWidgets('renders at viewport DPR, resizes and reaches the final page without a scrollbar', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final data = Uint8List.fromList([1]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: MMPdfDataPreview(data: data, sourceName: 'multipage.pdf', header: const Text('Article')),
      ),
    );
    await tester.pumpAndSettle();
    expect(TestPdfRender.requestedFullSizes, contains((1200.0, 1600.0)));
    expect(find.byType(PdfPageView), findsWidgets);
    expect(tester.widgetList<PdfPageView>(find.byType(PdfPageView)).length, lessThan(50));
    expect(find.byType(RawScrollbar), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pdf-data-page-50')),
      800,
      scrollable: find.byType(Scrollable),
      maxScrolls: 60,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('pdf-data-page-50'))).overlaps(const Rect.fromLTWH(0, 0, 600, 400)),
      isTrue,
    );
    expect(find.byType(RawScrollbar), findsNothing);
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pumpAndSettle();
    expect(TestPdfRender.requestedFullSizes.map((size) => size.$1), contains(closeTo(1600, 0.01)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
