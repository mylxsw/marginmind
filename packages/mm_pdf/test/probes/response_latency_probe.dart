// Manual probe: flutter test --no-pub test/probes/response_latency_probe.dart --reporter expanded
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdf_backend.dart';

void main() {
  setUp(installTestPdfBackend);
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    for (final id in ['highlight', 'note:attachment', 'vocabulary:entry', 'note:marker']) {
      testWidgets('measure PDF $id ${kind.name}', (tester) async {
        var calls = 0;
        final controller = MMPdfViewController();
        await tester.pumpWidget(
          MaterialApp(
            home: MMPdfView(
              filePath: 'latency.pdf',
              controller: controller,
              useTouchSelectionHandles: kind == PointerDeviceKind.touch,
              highlights: [
                MMPdfHighlight(
                  id: id,
                  page: 1,
                  rects: const [PageRect(30, 700, 150, 680)],
                  color: Colors.yellow,
                  marker: id == 'note:marker' ? Colors.blue : null,
                ),
              ],
              onHighlightTap: (_, _) => calls++,
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
        final rect = pdf.calcRectForRectInsidePage(pageNumber: 1, rect: const PdfRect(30, 700, 150, 680));
        await tester.tapAt(
          id == 'note:marker'
              ? tester.getCenter(find.byKey(ValueKey('pdf-marker-$id')))
              : tester.getTopLeft(find.byType(MMPdfView)) + pdf.documentToLocal(rect.center),
          kind: kind,
        );
        await tester.pump();
        var elapsed = 0;
        while (calls == 0 && elapsed < 400) {
          elapsed++;
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(calls, 1);
        debugPrint('LATENCY pdf-$id-${kind.name} = ${elapsed}ms');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 400));
        controller.dispose();
      });
    }
  }
}
