import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import 'reading_probe_test.dart' show ready, close;
import 'support/pdf_backend.dart';

void main() {
  setUp(installTestPdfBackend);
  testWidgets(
    'column adds outer width and overflow while source page keeps full size; collapsing preserves reading line',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MMPdfViewController();
      addTearDown(controller.dispose);
      MMPdfMarginViewport? viewport;
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
                    extent: (_, size, insets, zoom) {
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
      expect(viewport!.pages.length, lessThanOrEqualTo(3));
      final initial = controller.readingPosition!;
      await controller.ensureVisible(1, const PageRect(20, 700, 100, 680));
      expect(controller.readingPosition!.y, closeTo(initial.y, 1));
      await controller.ensureVisible(0, const PageRect(20, 700, 100, 680));
      final reveal = controller.ensureVisible(3, const PageRect(20, 700, 100, 680));
      await tester.pumpAndSettle();
      await reveal;
      expect(controller.readingPosition!.page, greaterThan(1));
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
}
