import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_core/mm_core.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installTestPdfBackend);

  testWidgets('commits viewport bounds, cancels stale selection and reports scrolling', (tester) async {
    final controller = MMPdfViewController();
    MMPdfSelection? committed;
    var viewportChanges = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'selection-test.pdf',
          controller: controller,
          onSelectionCommitted: (s) => committed = s,
          onViewportChanged: () => viewportChanges++,
        ),
      ),
    );
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.isReady, isTrue);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final pdf = viewer.controller!;
    final page = pdf.document.pages.first;
    final text = (await tester.runAsync(page.loadStructuredText))!;
    await tester.runAsync(
      () => pdf.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(text, 0), PdfTextSelectionPoint(text, 8)),
      ),
    );
    final listener = tester
        .widgetList<Listener>(find.descendant(of: find.byType(MMPdfView), matching: find.byType(Listener)))
        .firstWhere((w) => w.onPointerUp != null);
    listener.onPointerUp!(const PointerUpEvent());
    await tester.pump(const Duration(milliseconds: 130));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(committed, isNotNull);
    expect(committed!.viewportRect!.width, greaterThan(0));
    final firstRect = pdf.calcRectForRectInsidePage(pageNumber: 1, rect: text.charRects.first);
    expect(committed!.viewportRect!.contains(pdf.documentToLocal(firstRect.center)), isTrue);
    committed = null;
    listener.onPointerUp!(const PointerUpEvent());
    pdf.value = pdf.value.clone()..translateByDouble(0, -20, 0, 1);
    await tester.pump(const Duration(milliseconds: 130));
    expect(committed, isNull);
    listener.onPointerUp!(const PointerUpEvent());
    await controller.clearSelection();
    await tester.pump(const Duration(milliseconds: 130));
    expect(committed, isNull);
    final before = viewportChanges;
    final navigation = controller.goToPage(2);
    await tester.pumpAndSettle();
    await navigation;
    expect(viewportChanges, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.isReady, isFalse);
  });
  for (final reverse in [false, true]) {
    testWidgets('commits three pages in reading order, reverse=$reverse', (tester) async {
      final controller = MMPdfViewController();
      MMPdfSelection? committed;
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'cross-page.pdf',
            controller: controller,
            onSelectionCommitted: (s) => committed = s,
          ),
        ),
      );
      for (var i = 0; i < 100 && !controller.isReady; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(controller.isReady, isTrue);
      final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
      final first = (await tester.runAsync(pdf.document.pages.first.loadStructuredText))!;
      final last = (await tester.runAsync(pdf.document.pages.last.loadStructuredText))!;
      final a = PdfTextSelectionPoint(first, 9);
      final b = PdfTextSelectionPoint(last, 7);
      await tester.runAsync(
        () => pdf.textSelectionDelegate.setTextSelectionPointRange(
          PdfTextSelectionRange.fromPoints(reverse ? b : a, reverse ? a : b),
        ),
      );
      final listener = tester
          .widgetList<Listener>(find.descendant(of: find.byType(MMPdfView), matching: find.byType(Listener)))
          .firstWhere((w) => w.onPointerUp != null);
      listener.onPointerUp!(const PointerUpEvent());
      await tester.pump(const Duration(milliseconds: 130));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(committed, isNotNull);
      expect(committed!.pages.map((p) => p.page), [1, 2, 3]);
      expect(committed!.pages.every((p) => p.rects.isNotEmpty), isTrue);
      expect(committed!.text, 'passage\nSelected passage\nSelected');
      expect(committed!.page, 1);
      expect(committed!.rects, committed!.pages.first.rects);
      final viewport = Offset.zero & tester.getSize(find.byType(MMPdfView));
      expect(viewport.contains(committed!.viewportRect!.center), isTrue);
      var navigation = controller.goToPage(3);
      await tester.pumpAndSettle();
      await navigation;
      navigation = controller.reveal(committed!.page, committed!.rects);
      await tester.pumpAndSettle();
      await navigation;
      final target = pdf.calcRectForRectInsidePage(pageNumber: 1, rect: first.charRects[9]);
      expect(viewport.contains(pdf.documentToLocal(target.center)), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });
  }
  testWidgets('highlight tap reports union bounds after zoom and scroll', (tester) async {
    final controller = MMPdfViewController();
    String? tapped;
    Rect? anchor;
    const rects = [PageRect(30, 700, 90, 680), PageRect(30, 670, 110, 650)];
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'highlight-test.pdf',
          controller: controller,
          highlights: const [
            MMPdfHighlight(id: 'highlight', page: 1, rects: rects, color: Colors.yellow),
            MMPdfHighlight(id: 'highlight', page: 2, rects: rects, color: Colors.yellow),
          ],
          onHighlightTap: (id, bounds) {
            tapped = id;
            anchor = bounds;
          },
        ),
      ),
    );
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.isReady, isTrue);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    for (final pageNumber in [1, 2]) {
      final navigation = controller.goToPage(pageNumber);
      await tester.pumpAndSettle();
      await navigation;
      for (final zoomed in [false, true]) {
        if (zoomed) {
          pdf.value = pdf.value.clone()
            ..scaleByDouble(1.2, 1.2, 1, 1)
            ..translateByDouble(0, -20, 0, 1);
          await tester.pumpAndSettle();
        }
        final bounds = rects
            .map(
              (r) => pdf.calcRectForRectInsidePage(
                pageNumber: pageNumber,
                rect: PdfRect(r.left, r.top, r.right, r.bottom),
              ),
            )
            .reduce((a, b) => a.expandToInclude(b));
        final first = pdf.calcRectForRectInsidePage(pageNumber: pageNumber, rect: const PdfRect(30, 700, 90, 680));
        final view = tester.getTopLeft(find.byType(MMPdfView));
        await tester.tapAt(view + pdf.documentToLocal(first.center));
        await tester.pumpAndSettle(const Duration(milliseconds: 350));
        expect(tapped, 'highlight');
        expect(anchor, Rect.fromPoints(pdf.documentToLocal(bounds.topLeft), pdf.documentToLocal(bounds.bottomRight)));
        tapped = null;
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
