import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

const _mark = MMPdfHighlight(id: 'mark', page: 1, rects: [PageRect(30, 700, 90, 680)], color: Colors.yellow);

void main() {
  setUp(installTestPdfBackend);
  tearDown(() => TestPdfLinks.pages = {});
  Future<({MMPdfViewController controller, PdfViewerController pdf})> open(
    WidgetTester tester,
    List<String> taps, {
    bool touch = false,
    bool marker = false,
  }) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'immediate-annotations.pdf',
          controller: controller,
          useTouchSelectionHandles: touch,
          highlights: [
            _mark,
            const MMPdfHighlight(id: 'other', page: 1, rects: [PageRect(300, 700, 400, 680)], color: Colors.blue),
            if (marker)
              const MMPdfHighlight(
                id: 'note:marker',
                page: 1,
                rects: [PageRect(30, 600, 90, 580)],
                color: Colors.transparent,
                marker: Colors.blue,
              ),
          ],
          onHighlightTap: (id, _) => taps.add(id),
        ),
      ),
    );
    for (var n = 0; n < 100 && !controller.isReady; n++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.isReady, isTrue);
    await tester.pumpAndSettle();
    return (controller: controller, pdf: tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!);
  }

  Offset at(WidgetTester tester, PdfViewerController pdf, PdfRect rect) {
    final bounds = pdf.calcRectForRectInsidePage(pageNumber: 1, rect: rect);
    return tester.getTopLeft(find.byType(MMPdfView)) + pdf.documentToLocal(bounds.center);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 700));
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('$kind separate rapid annotation clicks each dispatch once immediately', (tester) async {
      final taps = <String>[];
      final app = await open(tester, taps, touch: kind == PointerDeviceKind.touch);
      await tester.tapAt(at(tester, app.pdf, const PdfRect(30, 700, 90, 680)), kind: kind);
      expect(taps, ['mark']);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at(tester, app.pdf, const PdfRect(300, 700, 400, 680)), kind: kind);
      expect(taps, ['mark', 'other']);
      await tester.pump(const Duration(milliseconds: 700));
      expect(taps, ['mark', 'other']);
      await close(tester);
    });
    testWidgets('$kind double click, long press and scrolling do not repeat the first action', (tester) async {
      final taps = <String>[];
      final app = await open(tester, taps, touch: kind == PointerDeviceKind.touch);
      final point = at(tester, app.pdf, const PdfRect(30, 700, 90, 680));
      await tester.tapAt(point, kind: kind);
      expect(taps, ['mark']);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point, kind: kind);
      await tester.pump(const Duration(milliseconds: 700));
      expect(taps, ['mark']);
      taps.clear();
      final hold = await tester.startGesture(point, kind: kind);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await hold.up();
      expect(taps, ['mark']);
      await tester.pump(const Duration(milliseconds: 700));
      expect(taps, ['mark']);
      taps.clear();
      await tester.tapAt(point, kind: kind);
      expect(taps, ['mark']);
      app.pdf.value = app.pdf.value.clone()..translateByDouble(0, -100, 0, 1);
      await tester.pump(const Duration(milliseconds: 700));
      expect(taps, ['mark'], reason: 'a queued native tap must not reopen the annotation after scrolling');
      await close(tester);
    });
  }
  testWidgets('a drag across marked text remains a selection and a pinch on a marker remains a zoom', (tester) async {
    final taps = <String>[];
    final app = await open(tester, taps, touch: true, marker: true);
    final point = at(tester, app.pdf, const PdfRect(30, 700, 90, 680));
    await tester.dragFrom(point, const Offset(120, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(taps, isEmpty);
    expect(app.pdf.textSelectionDelegate.hasSelectedText, isTrue);
    await app.controller.clearSelection();
    await tester.pump(const Duration(milliseconds: 700));
    final marker = tester.getCenter(find.byKey(const ValueKey('pdf-marker-note:marker')));
    final zoom = app.controller.zoom;
    final a = await tester.startGesture(marker, pointer: 41);
    final b = await tester.startGesture(marker - const Offset(100, 0), pointer: 42);
    await a.moveBy(const Offset(30, 0));
    await b.moveBy(const Offset(-30, 0));
    await tester.pump();
    await a.moveBy(const Offset(30, 0));
    await b.moveBy(const Offset(-30, 0));
    await tester.pump();
    await b.up();
    await a.up();
    await tester.pumpAndSettle();
    expect(app.controller.zoom, greaterThan(zoom));
    expect(taps, isEmpty);
    await close(tester);
  });
  testWidgets('a precise PDF link beside an annotation is not stolen by nearby-hit tolerance', (tester) async {
    TestPdfLinks.pages = {
      1: [
        const PdfLink([PdfRect(91, 700, 105, 680)], dest: PdfDest(2, PdfDestCommand.fit, null)),
      ],
    };
    final taps = <String>[];
    final app = await open(tester, taps);
    final near = at(tester, app.pdf, const PdfRect(91, 700, 93, 680));
    await tester.tapAt(near, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(taps, isEmpty);
    // Link navigation is owned by the host; this view must leave its exact
    // metadata target alone instead of opening the adjacent annotation.
    expect(app.controller.currentPage, 1);
    await close(tester);
  });
}
