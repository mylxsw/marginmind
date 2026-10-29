import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';
import 'reading_probe_test.dart' show ready, close;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installTestPdfBackend);
  testWidgets('screen-distance scrolling stays exact across crop, zoom and clamped reversal', (tester) async {
    for (final cropped in [false, true]) {
      final controller = MMPdfViewController();
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'screen-distance.pdf',
            controller: controller,
            crop: cropped ? DocumentCrop(all: CropInsets(left: 24, top: 36, right: 60, bottom: 80)) : null,
          ),
        ),
      );
      await ready(tester, () => controller.isReady);
      for (final factor in [.5, 1.0, 2.0]) {
        final zoom = controller.setWidthZoom(factor);
        await tester.pumpAndSettle();
        await zoom;
        await controller.jumpToReadingPosition(PdfReadingPosition(page: 2, y: 400));
        await tester.pumpAndSettle();
        final before = controller.scrollPosition!;
        await controller.scrollByScreenDistance(80);
        await tester.pumpAndSettle();
        expect(controller.scrollPosition!.offset - before.offset, closeTo(80, .001));
        expect(controller.scrollPosition!.sameGeometry(before), true);
        await controller.scrollByScreenDistance(1000000);
        await tester.pumpAndSettle();
        final end = controller.scrollPosition!.offset;
        for (var i = 0; i < 10; i++) {
          await controller.scrollByScreenDistance(80);
        }
        await tester.pumpAndSettle();
        expect(controller.scrollPosition!.offset, end);
        await controller.scrollByScreenDistance(-60);
        await tester.pumpAndSettle();
        expect(controller.scrollPosition!.offset - end, closeTo(-60, .001));
        await controller.scrollByScreenDistance(-1000000);
        await tester.pumpAndSettle();
        final start = controller.scrollPosition!.offset;
        for (var i = 0; i < 10; i++) {
          await controller.scrollByScreenDistance(-80);
        }
        expect(controller.scrollPosition!.offset, start);
        await controller.scrollByScreenDistance(60);
        await tester.pumpAndSettle();
        expect(controller.scrollPosition!.offset - start, closeTo(60, .001));
      }
      await close(tester);
      controller.dispose();
    }
  });

  testWidgets('toggle crop clips the source, preserves original reading line, and caps fit at 140%', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    final crop = DocumentCrop(all: CropInsets(left: 24, top: 36, right: 60, bottom: 80));
    Future<void> mount(DocumentCrop? value, {bool editing = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'crop-toggle.pdf',
            controller: controller,
            crop: value,
            cropEditorBuilder: editing ? (_, _, _) => [] : null,
          ),
        ),
      );
      final expected = editing || value == null ? 600.0 : 516.0;
      await ready(tester, () {
        final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
        return pdf.isReady && pdf.document.pages.first.width == expected;
      });
    }

    await mount(null);
    final firstPosition = controller.readingPosition!;
    await mount(crop);
    expect(controller.readingPosition!.page, firstPosition.page);
    expect(
      controller.readingPosition!.y,
      closeTo(firstPosition.y, 1),
      reason: 'the first page needs top boundary space',
    );
    await mount(null);
    final jump = controller.jumpToReadingPosition(PdfReadingPosition(page: 2, y: 420));
    await tester.pumpAndSettle();
    await jump;
    final position = controller.readingPosition!;
    await mount(crop);
    expect(controller.pageSize(1), const Size(600, 800));
    expect(controller.pageHeights, [800, 800, 800]);
    expect(controller.readingPosition!.page, position.page);
    expect(controller.readingPosition!.y, closeTo(position.y, 1));
    final width = controller.fitWidth();
    await tester.pumpAndSettle();
    await width;
    expect(controller.zoom, lessThanOrEqualTo(1.4));
    final previousZoom = controller.zoom;
    await mount(crop, editing: true);
    controller.restoreZoomAfterCrop(previousZoom);
    controller.restorePositionAfterCrop(position);
    await mount(crop);
    expect(controller.zoom, closeTo(previousZoom, .001));
    expect(controller.readingPosition!.page, 2);
    expect(controller.readingPosition!.y, closeTo(420, 1));
    await mount(null);
    expect(controller.readingPosition!.y, closeTo(420, 1));
    await close(tester);
  });
  testWidgets('reading targets clamp to reachable edges after zoom and crop without creeping', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    for (final crop in [null, DocumentCrop(all: CropInsets(left: 24, top: 36, right: 60, bottom: 80))]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(filePath: 'sync-edges.pdf', controller: controller, crop: crop),
        ),
      );
      await ready(tester, () => controller.isReady);
      await tester.pumpAndSettle();
      for (final factor in [.5, 1.0, 2.0]) {
        final zoom = controller.setWidthZoom(factor);
        await tester.pumpAndSettle();
        await zoom;
        for (final requested in [PdfReadingPosition(page: 1, y: 800), PdfReadingPosition(page: 3, y: 0)]) {
          final expected = controller.clampedReadingPosition(requested)!;
          final move = controller.jumpToReadingPosition(requested);
          await tester.pumpAndSettle();
          await move;
          expect(controller.readingPosition!.page, expected.page);
          expect(controller.readingPosition!.y, closeTo(expected.y, .001));
          final before = controller.readingPosition!.toJson();
          for (var i = 0; i < 5; i++) {
            final repeated = controller.jumpToReadingPosition(requested);
            await tester.pump(const Duration(milliseconds: 50));
            await repeated;
          }
          controller.stopScroll();
          await tester.pumpAndSettle();
          expect(controller.readingPosition!.toJson(), before);
        }
      }
    }
    await close(tester);
  });

  testWidgets('cropped real selection, search, highlights, area and ink keep original coordinates', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    final crop = DocumentCrop(all: CropInsets(left: 24, top: 36, right: 60, bottom: 80));
    MMPdfSelection? committed;
    MMPdfArea? area;
    MMPdfInkDraft? ink;
    Rect? highlight;
    Future<void> mount({bool selectingArea = false, bool pen = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'crop-tools.pdf',
            controller: controller,
            crop: crop,
            areaSelecting: selectingArea,
            onAreaSelected: (v) => area = v,
            ink: pen ? const MMPdfInk(tool: MMPdfInkTool.freehand, colorIndex: 0, width: 2) : null,
            onInkDrawn: (v) => ink = v,
            inkColors: const [Colors.red],
            highlights: const [
              MMPdfHighlight(id: 'h', page: 1, rects: [PageRect(30, 700, 190, 680)], color: Colors.yellow),
            ],
            onHighlightTap: (_, r) => highlight = r,
            onSelectionCommitted: (v) => committed = v,
          ),
        ),
      );
      await ready(tester, () => controller.isReady);
    }

    await mount();
    PdfViewerController pdf() => tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    Offset at(double x, double y) =>
        pdf().documentToLocal(pdf().layout.pageLayouts.first.topLeft + Offset(x - 24, 800 - y - 36));
    await tester.tapAt(at(80, 690));
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    expect(highlight, isNotNull);
    final text = (await tester.runAsync(pdf().document.pages.first.loadStructuredText))!;
    await tester.runAsync(
      () => pdf().textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(text, 0), PdfTextSelectionPoint(text, 8)),
      ),
    );
    final listener = tester
        .widgetList<Listener>(find.descendant(of: find.byType(MMPdfView), matching: find.byType(Listener)))
        .firstWhere((w) => w.onPointerUp != null);
    listener.onPointerUp!(const PointerUpEvent());
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(committed, isNotNull);
    expect(committed!.rects.first.left, 30);
    expect(committed!.rects.first.top, 700);
    controller.search('Selected');
    for (var n = 0; n < 20 && controller.matchCount < 3; n++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.matchCount, 3);
    controller.clearSearch();
    await controller.clearSelection();
    await mount(selectingArea: true);
    await tester.dragFrom(at(250, 580), at(350, 480) - at(250, 580), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(area, isNotNull);
    expect(area!.rect.left, closeTo(250, 1));
    expect(area!.rect.top, closeTo(580, 1));
    await mount(pen: true);
    await tester.dragFrom(at(250, 580), at(350, 480) - at(250, 580), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(ink, isNotNull);
    expect(ink!.points.first.x, closeTo(250, 2));
    expect(ink!.points.first.y, closeTo(580, 2));
    await close(tester);
  });
  testWidgets('automatic frame reuses bitmap cache and includes latest user marks', (tester) async {
    TestPdfRender.produceImages = true;
    addTearDown(() {
      TestPdfRender.produceImages = false;
      TestPdfRender.renders.clear();
    });
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'crop-auto.pdf', controller: controller),
      ),
    );
    await ready(tester, () => controller.isReady);
    final crop = (await tester.runAsync(() => controller.automaticCrop()))!;
    expect(crop.all.left, 16);
    final before = TestPdfRender.renders.length;
    final expanded = (await tester.runAsync(
      () => controller.automaticCrop(
        anchors: [
          AnnotationPage(page: 2, rects: const [PageRect(4, 720, 20, 700)]),
        ],
      ),
    ))!;
    expect(expanded.all.left, 0);
    expect(TestPdfRender.renders.length, before);
    await close(tester);
  });
  testWidgets('scanned pages use a cached pixel bounding box without a text layer', (tester) async {
    TestPdfRender.produceImages = true;
    TestPdfRender.scanImage = true;
    TestPdfText.pages = {for (var n = 1; n <= 3; n++) n: PdfPageRawText('', [])};
    addTearDown(() {
      TestPdfRender.produceImages = false;
      TestPdfRender.scanImage = false;
      TestPdfText.pages = {};
    });
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'crop-scan.pdf', controller: controller),
      ),
    );
    await ready(tester, () => controller.isReady);
    final crop = (await tester.runAsync(() => controller.automaticCrop()))!;
    expect(crop.all.left, closeTo(106, 2));
    expect(crop.all.right, closeTo(106, 2));
    expect(crop.all.top, closeTo(106, 2));
    expect(crop.all.bottom, closeTo(106, 2));
    expect(await controller.pageText(1), isNull);
    await close(tester);
  });
  testWidgets('touch long press retains native selection and handles after cropping', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    final selections = <MMPdfSelection>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'crop-touch.pdf',
          controller: controller,
          crop: DocumentCrop(all: CropInsets(left: 24, top: 36, right: 60, bottom: 80)),
          onSelectionCommitted: selections.add,
        ),
      ),
    );
    await ready(tester, () => controller.isReady);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final point =
        tester.getTopLeft(find.byType(MMPdfView)) +
        pdf.documentToLocal(
          pdf.calcRectForRectInsidePage(pageNumber: 1, rect: const PdfRect(36, 610, 36, 610)).topLeft,
        );
    final finger = await tester.startGesture(point, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 650));
    await finger.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(pdf.textSelectionDelegate.hasSelectedText, true);
    for (var n = 0; n < 30 && selections.isEmpty; n++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(selections.single.rects.first.top, 700);
    expect(selections.single.rects.first.left, 30);
    expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).params.textSelectionParams!.enabled, true);
    await close(tester);
  });
}
