import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'reading_probe_test.dart' show ready, close;
import 'support/pdf_backend.dart';

void main() {
  setUp(installTestPdfBackend);
  testWidgets('removing an expanded margin restores ordinary page painting', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    Future<void> mount(MMPdfMargin? margin) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(filePath: 'margin-removal.pdf', controller: controller, margin: margin),
        ),
      );
      await ready(tester, () => controller.isReady);
      await tester.pumpAndSettle();
    }

    await mount(MMPdfMargin(requested: true, extent: (_, _, _, _) => 0, builder: (_, _) => []));
    expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!.documentSize.width, 832);
    await mount(null);
    expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!.documentSize.width, 632);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
  testWidgets(
    'column adds outer width and overflow while source page keeps full size; collapsing preserves reading line',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MMPdfViewController();
      addTearDown(controller.dispose);
      MMPdfMarginViewport? viewport;
      final measured = <int>{};
      Future<void> mount({
        bool requested = true,
        bool collapsed = false,
        DocumentCrop? crop,
        double width = 1000,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: width,
                child: MMPdfView(
                  filePath: 'margin-layout.pdf',
                  controller: controller,
                  crop: crop,
                  margin: MMPdfMargin(
                    requested: requested,
                    forceCollapsed: collapsed,
                    extent: (page, size, insets, zoom) {
                      measured.add(page);
                      expect(size, const Size(600, 800));
                      return 150;
                    },
                    builder: (_, v) {
                      viewport = v;
                      return [];
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await ready(tester, () => controller.isReady);
        await tester.pumpAndSettle();
      }

      await mount();
      final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
      expect(pdf.layout.pageLayouts.first.size, const Size(600, 800));
      expect(pdf.documentSize.width, 832);
      expect(pdf.layout.pageLayouts[1].top - pdf.layout.pageLayouts.first.bottom, 166);
      expect(viewport!.expanded, true);
      expect(measured, {1, 2}, reason: 'offscreen card layout waits until its page approaches the viewport');
      expect(viewport!.pages.length, lessThanOrEqualTo(3));
      final initial = controller.readingPosition!;
      final firstReveal = controller.ensureVisible(1, const PageRect(20, 700, 100, 680));
      await tester.pumpAndSettle();
      await firstReveal;
      expect(controller.readingPosition!.y, closeTo(initial.y, 1));
      await controller.ensureVisible(0, const PageRect(20, 700, 100, 680));
      final reveal = controller.ensureVisible(3, const PageRect(20, 700, 100, 680));
      await tester.pumpAndSettle();
      await reveal;
      expect(controller.readingPosition!.page, greaterThan(1));
      expect(measured, contains(3));
      final before = controller.readingPosition!;
      await mount(requested: false);
      expect(pdf.documentSize.width, 632);
      expect(viewport!.expanded, false);
      expect(controller.readingPosition!.y, closeTo(before.y, 1));
      await mount(collapsed: true);
      expect(viewport!.expanded, false);
      await mount(width: 640);
      expect(viewport!.expanded, false);
      await mount(crop: DocumentCrop(all: CropInsets(left: 60, right: 60, top: 30, bottom: 30)), width: 640);
      expect(viewport!.expanded, true);
      expect(pdf.layout.pageLayouts.first.size, const Size(480, 740));
      expect(pdf.documentSize.width, 712);
      expect(controller.pageSize(1), const Size(600, 800));
      await close(tester);
    },
  );
  testWidgets('rapid navigation and zoom finish while lazy heights preserve the original reading line', (tester) async {
    installTestPdfBackend(pageCount: 20);
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = MMPdfViewController();
    addTearDown(controller.dispose);
    final measured = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'margin-rapid.pdf',
          controller: controller,
          margin: MMPdfMargin(
            requested: true,
            extent: (page, _, _, _) {
              measured.add(page);
              return 150;
            },
            builder: (_, _) => [],
          ),
        ),
      ),
    );
    await ready(tester, () => controller.isReady);
    expect(measured, {1, 2});
    final moves = Future.wait([controller.goToPage(1), controller.goToPage(15)]);
    await tester.pumpAndSettle();
    await moves;
    expect(controller.currentPage, 15);
    expect(measured, containsAll([14, 15, 16]));
    expect(measured.intersection({for (var n = 3; n < 13; n++) n}), isEmpty);
    final before = controller.readingPosition!;
    final zooms = Future.wait([controller.zoomIn(), controller.zoomOut()]);
    await tester.pumpAndSettle();
    await zooms;
    expect(controller.readingPosition!.page, before.page);
    expect(controller.readingPosition!.y, closeTo(before.y, 1));
    for (final move in [controller.actualSize, controller.fitWidth, controller.fitPage]) {
      final moving = move();
      await tester.pumpAndSettle();
      await moving;
      expect(controller.currentPage, 15);
    }
    final interruptedZoom = controller.zoomIn();
    final direct = controller.jumpToReadingPosition(PdfReadingPosition(page: 10, y: 500));
    await tester.pumpAndSettle();
    await Future.wait([interruptedZoom, direct]);
    expect(controller.readingPosition!.page, 10);
    expect(controller.readingPosition!.y, closeTo(500, 1));
    final scrubbing = controller.scrubToPage(1);
    await tester.pumpAndSettle();
    await scrubbing;
    expect(controller.currentPage, 1);
    await close(tester);
  });
}
