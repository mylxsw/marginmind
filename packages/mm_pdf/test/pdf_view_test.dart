import 'package:flutter/gestures.dart';
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
  testWidgets('area tool reports a page rectangle, clamps to the page and keeps scrolling', (tester) async {
    final controller = MMPdfViewController();
    final areas = <MMPdfArea>[];
    var viewportChanges = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'area-test.pdf',
          controller: controller,
          areaSelecting: true,
          highlights: const [
            MMPdfHighlight(
              id: 'figure',
              page: 1,
              rects: [PageRect(100, 500, 300, 300)],
              color: Color(0x80FFCC00),
              underline: Color(0xFFFFCC00),
              framed: true,
            ),
          ],
          onAreaSelected: areas.add,
          onViewportChanged: () => viewportChanges++,
        ),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).params.textSelectionParams!.enabled, isFalse);
    final frame = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border is Border && (d.border! as Border).top.width == 2);
    expect(frame, isNotEmpty);

    final view = tester.getTopLeft(find.byType(MMPdfView));
    Offset at(double x, double y) =>
        view + pdf.documentToLocal(pdf.calcRectForRectInsidePage(pageNumber: 1, rect: PdfRect(x, y, x, y)).topLeft);
    final gesture = await tester.startGesture(at(100, 600), kind: PointerDeviceKind.mouse);
    await gesture.moveTo(at(150, 550));
    await tester.pump();
    // The rectangle is drawn while dragging.
    bool marquee(Widget w) =>
        w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border?.top.width == 1.5;
    expect(find.byWidgetPredicate(marquee), findsOneWidget);
    await gesture.moveTo(at(300, 400));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.byWidgetPredicate(marquee), findsNothing);
    expect(areas, hasLength(1));
    final area = areas.single;
    expect(area.page, 1);
    expect(area.rect.left, closeTo(100, 1));
    expect(area.rect.top, closeTo(600, 1));
    expect(area.rect.right, closeTo(300, 1));
    expect(area.rect.bottom, closeTo(400, 1));
    expect(area.viewportRect.width, greaterThan(6));

    // Dragging past the page edge stops at the edge.
    await tester.dragFrom(at(450, 450), const Offset(2000, -2000), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(areas, hasLength(2));
    expect(areas.last.rect.left, closeTo(450, 1));
    expect(areas.last.rect.right, closeTo(600, 1));
    expect(areas.last.rect.top, closeTo(800, 1));
    expect(areas.last.rect.bottom, closeTo(450, 1));

    // A click is not an area.
    await tester.tapAt(at(50, 50));
    await tester.pump(const Duration(milliseconds: 400));
    expect(areas, hasLength(2));

    final before = viewportChanges;
    await tester.sendEventToBinding(PointerScrollEvent(position: at(200, 400), scrollDelta: const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(viewportChanges, greaterThan(before));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('captures an area as PNG at the requested scale', (tester) async {
    final controller = MMPdfViewController();
    expect(await controller.captureArea(1, const PageRect(0, 10, 10, 0)), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'capture.pdf', controller: controller),
      ),
    );
    await _waitReady(tester, controller);
    TestPdfRender.produceImages = true;
    addTearDown(() => TestPdfRender.produceImages = false);
    TestPdfRender.renders.clear();
    final png = await tester.runAsync(() => controller.captureArea(1, const PageRect(100, 700, 200, 650), scale: 2));
    expect(png, isNotNull);
    expect(png!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(TestPdfRender.renders.single, {'x': 200, 'y': 200, 'width': 200, 'height': 100, 'fullWidth': 1200.0});
    TestPdfRender.renders.clear();
    await tester.runAsync(() => controller.captureArea(1, const PageRect(0, 800, 600, 0), maxPixels: 300));
    expect(TestPdfRender.renders.single['width'], 225);
    expect(TestPdfRender.renders.single['height'], 300);
    expect(await tester.runAsync(() => controller.captureArea(9, const PageRect(0, 10, 10, 0))), isNull);
    expect(await tester.runAsync(() => controller.captureArea(1, const PageRect(5, 5, 5, 5))), isNull);
    TestPdfRender.produceImages = false;
    expect(await tester.runAsync(() => controller.captureArea(1, const PageRect(0, 10, 10, 0))), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
}

Future<void> _waitReady(WidgetTester tester, MMPdfViewController controller) async {
  for (var i = 0; i < 100 && !controller.isReady; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(controller.isReady, isTrue);
}
