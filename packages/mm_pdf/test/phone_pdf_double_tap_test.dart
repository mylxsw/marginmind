import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

void main() {
  setUp(() => installTestPdfBackend(pageCount: 10));

  testWidgets('phone scrollProfile toggles zoom between fitWidth and 1.5x on double tap', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = MMPdfViewController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MMPdfView(
            filePath: 'double-tap-test.pdf',
            controller: controller,
            scrollProfile: MMPdfScrollProfile.phone,
          ),
        ),
      ),
    );

    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.isReady, isTrue);
    await tester.pumpAndSettle();

    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final initialZoom = pdf.currentZoom;

    // First double tap: zooms in to 1.5x widthZoom
    await tester.tap(find.byType(MMPdfView));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(MMPdfView));
    await tester.pumpAndSettle();

    expect(pdf.currentZoom, greaterThan(initialZoom));
    expect(pdf.currentZoom, closeTo(initialZoom * 1.5, 0.05));

    // Second double tap: returns to fitWidth
    await tester.tap(find.byType(MMPdfView));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(MMPdfView));
    await tester.pumpAndSettle();

    expect(pdf.currentZoom, closeTo(initialZoom, 0.05));
    controller.dispose();
  });

  testWidgets('non-phone scrollProfile does not alter zoom on double tap', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = MMPdfViewController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MMPdfView(filePath: 'desktop-tap-test.pdf', controller: controller, scrollProfile: null),
        ),
      ),
    );

    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.isReady, isTrue);
    await tester.pumpAndSettle();

    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final initialZoom = pdf.currentZoom;

    await tester.tap(find.byType(MMPdfView));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(MMPdfView));
    await tester.pumpAndSettle();

    expect(pdf.currentZoom, closeTo(initialZoom, 0.001));
    controller.dispose();
  });
}
