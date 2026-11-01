import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_pdf/src/pdf_pixel_grid.dart';
import 'package:mm_core/mm_core.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';
import 'excerpt_text_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installTestPdfBackend);

  testWidgets('right-clicking the document does not show a context menu', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: MMPdfView(filePath: 'document.pdf', controller: controller)));
    await _waitReady(tester, controller);
    await tester.tapAt(tester.getCenter(find.byType(PdfViewer)), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsNothing);
    expect(find.byKey(const Key('contextMenu')), findsNothing);
  });

  testWidgets('scrolled highlights, underlines and margin notes stay inside the viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    const surround = Color(0xFF303030);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: surround,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 120),
            child: MMPdfView(
              filePath: 'clipped-overlays.pdf',
              controller: controller,
              // Margin anchors use viewport coordinates outside pdfrx's own
              // page clip, as the reader's comments do when collapsed.
              margin: MMPdfMargin(
                requested: false,
                extent: (_, _, _, _) => 0,
                builder: (context, viewport) => [
                  for (final page in viewport.pages.where((p) => p.page == 1)) ...[
                    Positioned.fromRect(
                      rect: page.transform.rect(const PageRect(30, 760, 430, 740)),
                      child: CustomPaint(
                        painter: MMPdfAnnotationLinePainter(color: Colors.yellow, style: AnnotationLineStyle.dashed),
                      ),
                    ),
                    Positioned(
                      left: page.rect.right - 25,
                      top: page.transform.rect(const PageRect(30, 760, 430, 740)).top,
                      child: const Icon(Icons.sticky_note_2_outlined, color: Colors.yellow, size: 18),
                    ),
                  ],
                ],
              ),
              highlights: const [
                MMPdfHighlight(id: 'fill', page: 1, rects: [PageRect(30, 700, 150, 660)], color: Colors.red),
                MMPdfHighlight(
                  id: 'line',
                  page: 1,
                  rects: [PageRect(170, 700, 290, 660)],
                  color: Colors.transparent,
                  underline: Colors.blue,
                  lineStyle: AnnotationLineStyle.dashed,
                ),
                MMPdfHighlight(
                  id: 'note',
                  page: 1,
                  rects: [PageRect(310, 700, 430, 660)],
                  color: Colors.transparent,
                  underline: Colors.yellow,
                  dashed: true,
                  marker: Colors.yellow,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _waitReady(tester, controller);
    await tester.pumpAndSettle();
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final viewport = tester.getRect(find.byType(MMPdfView));
    for (final scroll in [100.0, 140.0, 200.0]) {
      pdf.value = Matrix4.identity()..translateByDouble(0, -scroll, 0, 1);
      await tester.pumpAndSettle();
      // The page and its overlays still exist while crossing the upper edge.
      expect(find.byKey(const ValueKey('pdf-marker-note')), findsOneWidget);
      final image = (await tester.runAsync(
        () => (tester.binding.renderViews.first.debugLayer! as OffsetLayer).toImage(
          Offset.zero & tester.view.physicalSize,
          pixelRatio: 1,
        ),
      ))!;
      final pixels = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      var leaked = 0;
      for (var y = 0; y < image.height; y++) {
        if (y >= viewport.top && y < viewport.bottom) continue;
        for (var x = 0; x < image.width; x++) {
          final i = (y * image.width + x) * 4;
          if (pixels.getUint8(i) != 0x30 || pixels.getUint8(i + 1) != 0x30 || pixels.getUint8(i + 2) != 0x30) {
            leaked++;
          }
        }
      }
      image.dispose();
      expect(leaked, 0, reason: 'PDF overlays must not paint into the bars at scroll $scroll');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('drag on empty text prompts OCR; clicks, text, area and ink do not', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    addTearDown(() => TestPdfText.pages = {});
    TestPdfText.pages = {1: PdfPageRawText('', [])};
    final prompted = <int>[];
    Future<void> open({bool area = false, MMPdfInk? ink}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'scan.pdf',
            controller: controller,
            areaSelecting: area,
            ink: ink,
            onTextUnavailable: (page, _) => prompted.add(page),
          ),
        ),
      );
      await _waitReady(tester, controller);
      await tester.pumpAndSettle();
    }

    await open();
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final pdf = viewer.controller!;
    final start = pdf.documentToLocal(pdf.layout.pageLayouts.first.topLeft + const Offset(60, 100));
    await tester.tapAt(start);
    await tester.pumpAndSettle();
    expect(prompted, isEmpty);
    await tester.dragFrom(start, const Offset(100, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(prompted, [1]);
    await open(area: true);
    await tester.dragFrom(start, const Offset(100, 40), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(prompted, [1]);
    await open(ink: const MMPdfInk(tool: MMPdfInkTool.freehand, colorIndex: 0, width: 2));
    await tester.dragFrom(start, const Offset(100, 40), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(prompted, [1]);
    await open();
    final jump = controller.jumpToPage(2);
    await tester.pumpAndSettle();
    await jump;
    final textStart = pdf.documentToLocal(pdf.layout.pageLayouts[1].topLeft + const Offset(60, 100));
    await tester.dragFrom(textStart, const Offset(100, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(prompted, [1]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('mouse wheel uses full scroll distance without changing zoom', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'wheel.pdf', controller: controller),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final jump = controller.jumpToPage(2);
    await tester.pumpAndSettle();
    await jump;
    final before = pdf.value.clone();
    await tester.sendEventToBinding(
      PointerScrollEvent(position: tester.getCenter(find.byType(PdfViewer)), scrollDelta: const Offset(0, 100)),
    );
    await tester.pumpAndSettle();
    expect(pdf.value.storage[13] - before.storage[13], closeTo(-100 * before.storage[0], 1));
    expect(pdf.value.storage[0], before.storage[0]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('preview follows zoom and display DPR with a bounded allocation', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dpr in [1.0, 2.0, 3.0, 1.0]) {
      final samples = 2 * dpr;
      tester.view.devicePixelRatio = dpr;
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(filePath: 'scale.pdf', controller: controller),
        ),
      );
      for (var i = 0; i < 100 && !controller.isReady; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(controller.isReady, isTrue);
      // Finish viewport resizing before explicitly choosing a test zoom.
      await tester.pumpAndSettle();
      final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      final pdf = viewer.controller!;
      pdf.value = Matrix4.diagonal3Values(0.5, 0.5, 1);
      TestPdfRender.requestedFullSizes.clear();
      await tester.pump();
      final page = pdf.document.pages.first;
      final renderScale = viewer.params.getPageRenderingScale!;
      final context = tester.element(find.byType(PdfViewer));
      // Normal page-fit sizes should no longer use a 200-DPI bitmap.
      expect(renderScale(context, page, pdf, 200 / 72), closeTo(pdf.currentZoom * samples, 0.002));
      final plan = pdfPreviewPlan(Size(page.width, page.height), pdf.currentZoom, dpr);
      for (var i = 0; i < 20 && TestPdfRender.requestedFullSizes.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(TestPdfRender.requestedFullSizes, contains((page.width * plan.scale, page.height * plan.scale)));
      expect((page.width * plan.scale).toInt(), plan.deviceSize!.width * 2);
      expect((page.height * plan.scale).toInt(), plan.deviceSize!.height * 2);
      pdf.value = Matrix4.diagonal3Values(4, 4, 1);
      await tester.pump();
      expect(renderScale(context, page, pdf, 200 / 72), 4000 / 800);
      // Reset between display changes; the viewer remains mounted.
      pdf.value = Matrix4.diagonal3Values(pdf.minScale, pdf.minScale, 1);
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('reveal centers a multi-rect excerpt without changing zoom', (tester) async {
    final controller = MMPdfViewController();
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'reveal.pdf', controller: controller),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    const rects = [PageRect(250, 450, 330, 430), PageRect(270, 425, 350, 400)];
    for (final zoom in [1.0, 2.0]) {
      await pdf.setZoom(pdf.centerPosition, zoom, duration: Duration.zero);
      await tester.pumpAndSettle();
      final before = pdf.currentZoom;
      final action = controller.reveal(2, rects);
      await tester.pumpAndSettle();
      await action;
      expect(pdf.currentZoom, closeTo(before, .001));
      final layout = pdf.layout.pageLayouts[1];
      final target = const PdfRect(
        250,
        450,
        350,
        400,
      ).toRect(page: pdf.pages[1], scaledPageSize: layout.size).shift(layout.topLeft);
      final center = pdf.documentToLocal(target.center);
      expect((center - pdf.viewSize.center(Offset.zero)).distance, lessThan(1));
      expect(pdf.visibleRect.contains(target.topLeft), isTrue);
      expect(pdf.visibleRect.contains(target.bottomRight), isTrue);
    }
    final before = pdf.value.clone();
    await controller.reveal(0, rects);
    await controller.reveal(999, rects);
    expect(pdf.value, before);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('reveal starts at the left edge of an excerpt wider than the viewport', (tester) async {
    final controller = MMPdfViewController();
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'wide.pdf', controller: controller),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    await pdf.setZoom(pdf.centerPosition, 2, duration: Duration.zero);
    await tester.pumpAndSettle();
    const rects = [PageRect(20, 450, 580, 400)];
    final action = controller.reveal(2, rects);
    await tester.pumpAndSettle();
    await action;
    final layout = pdf.layout.pageLayouts[1];
    final target = const PdfRect(
      20,
      450,
      580,
      400,
    ).toRect(page: pdf.pages[1], scaledPageSize: layout.size).shift(layout.topLeft);
    expect(target.width * pdf.currentZoom, greaterThan(pdf.viewSize.width));
    final topLeft = pdf.documentToLocal(target.topLeft);
    expect(topLeft.dx, closeTo(0, 1), reason: 'both ends cannot show; the start does');
    expect(pdf.documentToLocal(target.center).dy, closeTo(pdf.viewSize.height / 2, 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('zoom commands fit the current page and are safe before ready', (tester) async {
    final controller = MMPdfViewController();
    await controller.zoomIn();
    await controller.zoomOut();
    await controller.actualSize();
    await controller.fitWidth();
    await controller.fitPage();
    expect(await controller.renderPreview(1), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'zoom.pdf', controller: controller),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    Future<void> complete(Future<void> action) async {
      await tester.pumpAndSettle();
      await action;
    }

    await complete(controller.actualSize());
    expect(pdf.currentZoom, closeTo(1, .001));
    await complete(controller.zoomIn());
    expect(pdf.currentZoom, greaterThan(1));
    final enlarged = pdf.currentZoom;
    await complete(controller.zoomOut());
    expect(pdf.currentZoom, lessThan(enlarged));
    await complete(controller.goToPage(2));
    await complete(controller.fitWidth());
    expect(pdf.currentZoom, closeTo(pdf.viewSize.width / 632, .001));
    await controller.scrubToPage(1);
    await tester.pumpAndSettle();
    expect(controller.currentPage, 1);
    await controller.scrubToPage(999);
    await tester.pumpAndSettle();
    expect(controller.currentPage, controller.pageCount);
    await complete(controller.goToPage(2));
    await complete(controller.fitPage());
    final rect = pdf.layout.pageLayouts[1];
    expect(pdf.documentToLocal(rect.topLeft).dy, greaterThanOrEqualTo(-1));
    expect(pdf.documentToLocal(rect.bottomRight).dy, lessThanOrEqualTo(pdf.viewSize.height + 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('resizing the reader refits page width while preserving the original 25% reading line', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    final width = ValueNotifier<double>(760);
    addTearDown(width.dispose);
    const filter = ColorFilter.mode(Colors.amber, BlendMode.modulate);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, value, _) => SizedBox(
              width: value,
              height: 550,
              child: MMPdfView(filePath: 'resize.pdf', controller: controller, pageColorFilter: filter),
            ),
          ),
        ),
      ),
    );
    await _waitReady(tester, controller);
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(viewer.params.pageImageColorFilter, filter);
    final pdf = viewer.controller!;
    await pdf.goToPage(pageNumber: 2, duration: Duration.zero);
    await tester.pumpAndSettle();
    final position = controller.readingPosition!;
    for (final size in [544.0, 760.0]) {
      width.value = size;
      // One layout frame must apply the zoom, without another input/frame.
      await tester.pump();
      expect(pdf.currentZoom, closeTo(size / 632, .001));
      expect(controller.readingPosition!.page, position.page);
      expect(controller.readingPosition!.y, closeTo(position.y, 1));
      final page = pdf.layout.pageLayouts[1];
      expect(pdf.documentToLocal(page.topLeft).dx, greaterThanOrEqualTo(0));
      expect(pdf.documentToLocal(page.bottomRight).dx, lessThanOrEqualTo(size));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('fit width has no horizontal drift from wheel or trackpad at any reader width', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    final width = ValueNotifier<double>(1400);
    addTearDown(width.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, value, _) => SizedBox(
              width: value,
              height: 700,
              child: MMPdfView(filePath: 'fit-width.pdf', controller: controller),
            ),
          ),
        ),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    await controller.scrubToPage(2);
    await tester.pumpAndSettle();
    final fit = controller.fitWidth();
    await tester.pumpAndSettle();
    await fit;
    for (final size in [1400.0, 960.0, 544.0, 1400.0]) {
      width.value = size;
      await tester.pumpAndSettle();
      final x = pdf.value.storage[12];
      final y = pdf.value.storage[13];
      final position = tester.getCenter(find.byType(PdfViewer));
      for (final delta in [const Offset(80, 30), const Offset(-160, 30)]) {
        await tester.sendEventToBinding(PointerScrollEvent(position: position, scrollDelta: delta));
        await tester.pumpAndSettle();
        expect(pdf.value.storage[12], closeTo(x, .01), reason: 'wheel at width $size');
      }
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pan.panZoomStart(position);
      await pan.panZoomUpdate(position, pan: const Offset(100, -40));
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(pdf.value.storage[12], closeTo(x, .01), reason: 'trackpad at width $size');
      expect(pdf.value.storage[13], lessThan(y), reason: 'vertical reading still scrolls');
      final page = pdf.layout.pageLayouts[1];
      expect(pdf.documentToLocal(page.topLeft).dx, greaterThanOrEqualTo(0));
      expect(pdf.documentToLocal(page.bottomRight).dx, lessThanOrEqualTo(size));
    }
    // Deliberately enlarging a page must still allow horizontal navigation.
    await pdf.setZoom(pdf.centerPosition, pdf.currentZoom * 2, duration: Duration.zero);
    await tester.pumpAndSettle();
    final x = pdf.value.storage[12];
    await tester.sendEventToBinding(
      PointerScrollEvent(position: tester.getCenter(find.byType(PdfViewer)), scrollDelta: const Offset(100, 0)),
    );
    await tester.pumpAndSettle();
    expect((pdf.value.storage[12] - x).abs(), greaterThan(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('fit width includes landscape pages in a mixed-size document', (tester) async {
    installTestPdfBackend(pageWidths: [600, 1000, 600]);
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'mixed-sizes.pdf', controller: controller),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final fit = controller.fitWidth();
    await tester.pumpAndSettle();
    await fit;
    expect(pdf.currentZoom, closeTo(pdf.viewSize.width / 1032, .001));
    for (final pageNumber in [1, 2, 3]) {
      await controller.scrubToPage(pageNumber);
      await tester.pumpAndSettle();
      final page = pdf.layout.pageLayouts[pageNumber - 1];
      expect(pdf.documentToLocal(page.topLeft).dx, greaterThanOrEqualTo(0));
      expect(pdf.documentToLocal(page.bottomRight).dx, lessThanOrEqualTo(pdf.viewSize.width));
      final x = pdf.value.storage[12];
      await tester.sendEventToBinding(
        PointerScrollEvent(position: tester.getCenter(find.byType(PdfViewer)), scrollDelta: const Offset(100, 0)),
      );
      await tester.pumpAndSettle();
      expect(pdf.value.storage[12], closeTo(x, .01));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a bottom inset lets the last page scroll clear of floating chrome', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    final width = ValueNotifier<double>(432);
    addTearDown(width.dispose);
    const inset = 90.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, value, _) => SizedBox(
              width: value,
              height: 550,
              child: MMPdfView(filePath: 'inset.pdf', controller: controller, bottomInset: inset),
            ),
          ),
        ),
      ),
    );
    await _waitReady(tester, controller);
    await tester.pumpAndSettle();
    PdfViewer viewer() => tester.widget<PdfViewer>(find.byType(PdfViewer));
    final pdf = viewer().controller!;
    // The margin is in document units: the inset at the zoom that fits the
    // document (pages and their margins) to the width.
    expect(viewer().params.boundaryMargin!.bottom, closeTo(inset / (432 / 632), .01));

    final end = controller.jumpToPage(controller.pageCount);
    await tester.pumpAndSettle();
    await end;
    for (var i = 0; i < 20; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: tester.getCenter(find.byType(PdfViewer)), scrollDelta: const Offset(0, 2000)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final bottom = pdf.documentToLocal(Offset(0, pdf.layout.documentSize.height)).dy;
    expect(bottom, closeTo(550 - inset, 1));

    // A wider view fits at a larger zoom and needs fewer document units.
    width.value = 632;
    await tester.pumpAndSettle();
    expect(viewer().params.boundaryMargin!.bottom, closeTo(inset / (632 / 632), .01));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('without a bottom inset the viewer keeps its own bounds', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'no-inset.pdf', controller: controller),
      ),
    );
    await _waitReady(tester, controller);
    expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).params.boundaryMargin, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('trackpad pinch keeps the document point under its focal position', (tester) async {
    final controller = MMPdfViewController();
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(filePath: 'pinch.pdf', controller: controller),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final move = pdf.goToPage(pageNumber: 2, duration: Duration.zero);
    await tester.pumpAndSettle();
    await move;
    await pdf.setZoom(pdf.centerPosition, 2, duration: Duration.zero);
    await tester.pumpAndSettle();
    const local = Offset(250, 250);
    final global = tester.getTopLeft(find.byType(MMPdfView)) + local;
    final before = pdf.localToDocument(local);
    await tester.sendEventToBinding(PointerPanZoomStartEvent(pointer: 7, position: global));
    await tester.sendEventToBinding(PointerPanZoomUpdateEvent(pointer: 7, position: global, scale: 1.25));
    await tester.pump();
    expect(pdf.currentZoom, closeTo(2.5, .01));
    expect((pdf.localToDocument(local) - before).distance, lessThan(1));
    await tester.sendEventToBinding(PointerPanZoomEndEvent(pointer: 7, position: global));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('preview reuses PNG and invalidates when the document changes', (tester) async {
    final controller = MMPdfViewController();
    Widget view(String file) => MaterialApp(
      home: MMPdfView(filePath: file, controller: controller),
    );
    await tester.pumpWidget(view('preview.pdf'));
    await _waitReady(tester, controller);
    expect(await tester.runAsync(() => controller.renderPreview(4)), isNull);
    expect(await tester.runAsync(() => controller.renderPreview(1)), isNull);
    TestPdfRender.produceImages = true;
    addTearDown(() => TestPdfRender.produceImages = false);
    TestPdfRender.renders.clear();
    final png = await tester.runAsync(() => controller.renderPreview(1));
    expect(png!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(TestPdfRender.renders.single['width'], 192);
    expect(TestPdfRender.renders.single['height'], 256);
    final cached = await tester.runAsync(() => controller.renderPreview(1, pixelWidth: 180));
    expect(cached, same(png));
    expect(TestPdfRender.renders, hasLength(1));
    TestPdfRender.produceImages = false;
    await tester.pumpWidget(view('different.pdf'));
    await _waitReady(tester, controller);
    expect(await tester.runAsync(() => controller.renderPreview(1)), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('sidebar thumbnails share renderPreview bytes and do not rerasterize cached pages', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MMPdfViewController();
    Widget tree(bool show) => MaterialApp(
      home: Row(
        children: [
          Expanded(
            child: MMPdfView(filePath: 'shared-preview.pdf', controller: controller),
          ),
          if (show) MMPdfThumbnail(controller: controller, page: 1, width: 160, height: 200),
        ],
      ),
    );
    await tester.pumpWidget(tree(false));
    await _waitReady(tester, controller);
    TestPdfRender.produceImages = true;
    TestPdfRender.renders.clear();
    addTearDown(() => TestPdfRender.produceImages = false);
    final bytes = await tester.runAsync(() => controller.renderPreview(1));
    expect(bytes, isNotNull);
    final count = TestPdfRender.renders.where((r) => r['width'] == 192).length;
    await tester.pumpWidget(tree(true));
    await tester.pumpAndSettle();
    final thumbnail = find.byType(MMPdfThumbnail);
    final image = tester.widget<Image>(find.descendant(of: thumbnail, matching: find.byType(Image)));
    expect((image.image as MemoryImage).bytes, same(bytes));
    expect(TestPdfRender.renders.where((r) => r['width'] == 192).length, count);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('underline styles update cached overlays and remain visible when selected and zoomed', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    for (final style in AnnotationLineStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'underlines.pdf',
            controller: controller,
            highlights: [
              MMPdfHighlight(
                id: 'u',
                page: 1,
                rects: const [PageRect(30, 700, 150, 680), PageRect(30, 660, 110, 640)],
                color: Colors.transparent,
                underline: Colors.blue,
                lineStyle: style,
                emphasized: true,
              ),
            ],
          ),
        ),
      );
      await _waitReady(tester, controller);
      await tester.pumpAndSettle();
      for (final zoomed in [false, true]) {
        if (zoomed) {
          final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
          pdf.value = pdf.value.clone()..scaleByDouble(1.1, 1.1, 1, 1);
          await tester.pumpAndSettle();
        }
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.foregroundPainter ?? w.painter)
            .whereType<MMPdfAnnotationLinePainter>()
            .toList();
        expect(painters.length, greaterThanOrEqualTo(2));
        expect(painters.every((p) => p.style == style && p.color == Colors.blue), isTrue);
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('equivalent highlights reuse overlays, changes invalidate only their page', (tester) async {
    final controller = MMPdfViewController();
    List<MMPdfHighlight> highlights({Color color = Colors.yellow, double right = 60, bool second = true}) => [
      MMPdfHighlight(id: 'a', page: 1, rects: [PageRect(10, 700, right, 680)], color: color),
      if (second) const MMPdfHighlight(id: 'b', page: 2, rects: [PageRect(10, 700, 60, 680)], color: Colors.yellow),
    ];
    Future<void> mount(List<MMPdfHighlight> data) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(filePath: 'index.pdf', controller: controller, highlights: data),
        ),
      );
      await _waitReady(tester, controller);
    }

    await mount(highlights());
    List<Widget> overlays(int page) {
      final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      return viewer.params.pageOverlaysBuilder!(
        tester.element(find.byType(PdfViewer)),
        Rect.fromLTWH(
          0,
          0,
          viewer.controller!.layout.pageLayouts[page - 1].width * viewer.controller!.currentZoom,
          viewer.controller!.layout.pageLayouts[page - 1].height * viewer.controller!.currentZoom,
        ),
        viewer.controller!.document.pages[page - 1],
      );
    }

    final a = overlays(1), b = overlays(2);
    expect(overlays(3), isEmpty);
    await mount(highlights());
    expect(overlays(1), same(a));
    expect(overlays(2), same(b));
    await mount(highlights(color: Colors.blue));
    expect(overlays(1), isNot(same(a)));
    expect(overlays(2), same(b));
    final changed = overlays(1);
    await mount(highlights(color: Colors.blue, right: 70));
    expect(overlays(1), isNot(same(changed)));
    await mount(highlights(second: false));
    expect(overlays(2), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('commits after one frame, cancels stale selection and reports scrolling', (tester) async {
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
    await tester.pump();
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
  for (final (reverse, cropped) in [(false, false), (true, false), (false, true), (true, true)]) {
    testWidgets('commits three pages in reading order, reverse=$reverse, cropped=$cropped', (tester) async {
      final controller = MMPdfViewController();
      MMPdfSelection? committed;
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'cross-page-$cropped.pdf',
            crop: cropped ? DocumentCrop(all: CropInsets(left: 24, top: 36, right: 60, bottom: 80)) : null,
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
      expect(committed!.text, 'passage Selected passage Selected');
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
  testWidgets('clean selection excludes margins on real delegate', (tester) async {
    TestPdfText.pages = {
      for (var n = 1; n <= 3; n++)
        n: (() {
          final source = fixture.page(n);
          return PdfPageRawText(source.text, [for (final r in source.rects) PdfRect(r.left, r.top, r.right, r.bottom)]);
        })(),
    };
    addTearDown(() => TestPdfText.pages = {});
    final controller = MMPdfViewController();
    MMPdfSelection? committed;
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'margin-test.pdf',
          highlights: const [
            MMPdfHighlight(id: 'existing', page: 1, rects: [PageRect(30, 500, 120, 480)], color: Colors.yellow),
            MMPdfHighlight(id: 'unselected', page: 3, rects: [PageRect(30, 500, 120, 480)], color: Colors.yellow),
          ],
          controller: controller,
          onSelectionCommitted: (s) => committed = s,
        ),
      ),
    );
    await _waitReady(tester, controller);
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    List<Widget> overlays(int number) {
      final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      return viewer.params.pageOverlaysBuilder!(
        tester.element(find.byType(PdfViewer)),
        Rect.fromLTWH(
          0,
          0,
          pdf.layout.pageLayouts[number - 1].width * pdf.currentZoom,
          pdf.layout.pageLayouts[number - 1].height * pdf.currentZoom,
        ),
        pdf.document.pages[number - 1],
      );
    }

    final cachedFirst = overlays(1), cachedThird = overlays(3);
    final a = (await tester.runAsync(pdf.document.pages.first.loadStructuredText))!;
    final b = (await tester.runAsync(pdf.document.pages[1].loadStructuredText))!;
    await tester.runAsync(
      () => pdf.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(a, a.fullText.indexOf('中文')),
          PdfTextSelectionPoint(b, b.fullText.indexOf('wrapped') + 6),
        ),
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
    expect(committed!.text, isNot(contains('2026')));
    expect(committed!.text, isNot(contains('file:')));
    expect(committed!.text, isNot(contains('\n')));
    expect(committed!.pages.map((p) => p.page), [1, 2]);
    expect(committed!.pages.every((p) => p.rects.length == 3), isTrue);
    expect(Theme.of(tester.element(find.byType(PdfViewer))).textSelectionTheme.selectionColor, Colors.transparent);
    expect(overlays(1).last, same(cachedFirst.single));
    expect(overlays(1), hasLength(4));
    expect(overlays(3), same(cachedThird));
    await controller.clearSelection();
    await tester.pump();
    expect(
      Theme.of(tester.element(find.byType(PdfViewer))).textSelectionTheme.selectionColor,
      isNot(Colors.transparent),
    );
    expect(overlays(1), same(cachedFirst));
    expect(overlays(3), same(cachedThird));
    committed = null;
    await tester.runAsync(
      () => pdf.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(PdfTextSelectionPoint(a, 0), PdfTextSelectionPoint(a, 8)),
      ),
    );
    listener.onPointerUp!(const PointerUpEvent());
    await tester.pump(const Duration(milliseconds: 130));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(committed, isNull);
    expect(pdf.textSelectionDelegate.hasSelectedText, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
  testWidgets('desktop margin marker clicks fire before the double-tap timeout; hover uses source bounds', (
    tester,
  ) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    var taps = 0;
    final hovers = <(String, Rect, bool)>[];
    const rect = PageRect(30, 700, 150, 680);
    Future<void> mount({bool touch = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'note-marker.pdf',
            controller: controller,
            useTouchSelectionHandles: touch,
            highlights: const [
              MMPdfHighlight(id: 'note:one', page: 1, rects: [rect], color: Colors.transparent, marker: Colors.blue),
            ],
            onHighlightTap: (_, _) => taps++,
            onMarkerHover: (id, bounds, hovering) => hovers.add((id, bounds, hovering)),
          ),
        ),
      );
      await _waitReady(tester, controller);
      await tester.pumpAndSettle();
    }

    await mount();
    final marker = find.byKey(const ValueKey('pdf-marker-note:one'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.down(tester.getCenter(marker));
    await mouse.up();
    await tester.pump();
    expect(taps, 1, reason: 'the button must respond in the first frame after pointer up');
    await tester.pump(const Duration(milliseconds: 350));
    expect(taps, 1, reason: 'no second dispatch through the PDF gesture recognizer');
    await mouse.moveTo(const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(marker));
    await tester.pump();
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    final bounds = pdf.calcRectForRectInsidePage(pageNumber: 1, rect: const PdfRect(30, 700, 150, 680));
    expect(hovers.last, (
      'note:one',
      Rect.fromPoints(pdf.documentToLocal(bounds.topLeft), pdf.documentToLocal(bounds.bottomRight)),
      true,
    ));
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(hovers.last.$3, isFalse);
    await mouse.removePointer();
    final beforeScroll = controller.readingPosition!;
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(marker),
        scrollDelta: const Offset(0, 40),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.readingPosition!.y,
      closeTo(beforeScroll.y - 40, .01),
      reason: 'the icon must not swallow wheel scrolling',
    );
    // Touch continues to reach the PDF recognizer through the MouseRegion.
    await mount(touch: true);
    hovers.clear();
    await tester.tap(marker);
    await tester.pump(const Duration(milliseconds: 350));
    expect(taps, 2);
    expect(hovers, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 350));
  });

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
  testWidgets('touch can tap or long-press near saved PDF marks at different zooms', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'touch-marks.pdf',
          controller: controller,
          useTouchSelectionHandles: true,
          highlights: const [
            MMPdfHighlight(id: 'older', page: 1, rects: [PageRect(30, 700, 90, 680)], color: Colors.yellow),
            MMPdfHighlight(
              id: 'newer',
              page: 1,
              rects: [PageRect(30, 670, 90, 650)],
              color: Colors.transparent,
              underline: Colors.blue,
              lineStyle: AnnotationLineStyle.solid,
            ),
          ],
          onHighlightTap: (id, _) => tapped = id,
        ),
      ),
    );
    for (var i = 0; i < 100 && !controller.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
    for (final zoom in [1.0, 1.6]) {
      if (zoom != 1) {
        pdf.value = pdf.value.clone()..scaleByDouble(zoom, zoom, 1, 1);
        await tester.pumpAndSettle();
      }
      for (final (id, rect) in [
        ('older', const PdfRect(30, 700, 90, 680)),
        ('newer', const PdfRect(30, 670, 90, 650)),
      ]) {
        final bounds = pdf.calcRectForRectInsidePage(pageNumber: 1, rect: rect);
        final near =
            tester.getTopLeft(find.byType(MMPdfView)) + pdf.documentToLocal(bounds.centerRight) + const Offset(8, 0);
        tapped = null;
        await tester.tapAt(near);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(tapped, id);
        tapped = null;
        await tester.longPressAt(near);
        await tester.pumpAndSettle();
        expect(tapped, id);
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
  testWidgets('near hits on a cross-page mark keep the toolbar on the hit page', (tester) async {
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    String? tapped;
    Rect? anchor;
    const first = PdfRect(30, 8, 90, 0);
    const second = PdfRect(30, 800, 90, 792);
    const continuation = PdfRect(30, 400, 90, 380);
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'cross-page-mark.pdf',
          controller: controller,
          useTouchSelectionHandles: true,
          highlights: const [
            MMPdfHighlight(id: 'same-mark', page: 1, rects: [PageRect(30, 8, 90, 0)], color: Colors.yellow),
            MMPdfHighlight(
              id: 'same-mark',
              page: 2,
              rects: [PageRect(30, 800, 90, 792), PageRect(30, 400, 90, 380)],
              color: Colors.yellow,
            ),
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
    final split = pdf.layout.pageLayouts.first.bottom;
    for (final zoom in [.5, .75]) {
      pdf.value = Matrix4.identity()
        ..scaleByDouble(zoom, zoom, 1, 1)
        ..setTranslationRaw(200, 220 - split * zoom, 0);
      await tester.pumpAndSettle();
      for (final page in [1, 2]) {
        final rect = pdf.calcRectForRectInsidePage(pageNumber: page, rect: page == 1 ? first : second);
        final bounds = page == 1
            ? rect
            : rect.expandToInclude(pdf.calcRectForRectInsidePage(pageNumber: 2, rect: continuation));
        final point =
            tester.getTopLeft(find.byType(MMPdfView)) + pdf.documentToLocal(rect.centerRight) + const Offset(8, 0);
        tapped = null;
        anchor = null;
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(tapped, 'same-mark');
        expect(
          anchor,
          Rect.fromPoints(pdf.documentToLocal(bounds.topLeft), pdf.documentToLocal(bounds.bottomRight)),
          reason: 'Toolbar must use page $page bounds at zoom $zoom, not another page with the same annotation id',
        );
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
    expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).params.textSelectionParams!.enabled, isTrue);
    final frame = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border is Border && (d.border! as Border).top.width == 2);
    expect(frame, isNotEmpty);

    final view = tester.getTopLeft(find.byType(MMPdfView));
    Offset at(double x, double y) =>
        view + pdf.documentToLocal(pdf.calcRectForRectInsidePage(pageNumber: 1, rect: PdfRect(x, y, x, y)).topLeft);
    final viewerBeforeDrag = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final gesture = await tester.startGesture(at(100, 600), kind: PointerDeviceKind.mouse);
    await gesture.moveTo(at(150, 550));
    await tester.pump();
    expect(tester.widget<PdfViewer>(find.byType(PdfViewer)), same(viewerBeforeDrag));
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
