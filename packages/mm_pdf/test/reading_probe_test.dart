import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import '../example/reading_probe.dart';
import 'support/pdf_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installTestPdfBackend);
  testWidgets('layoutPages shrink scales the full page: it does not crop', (tester) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer.file(
          'probe.pdf',
          controller: controller,
          params: PdfViewerParams(
            layoutPages: (pages, params) => PdfPageLayout(
              pageLayouts: [for (var i = 0; i < pages.length; i++) Rect.fromLTWH(0, i * 420, 300, 400)],
              documentSize: const Size(300, 1260),
            ),
          ),
        ),
      ),
    );
    await ready(tester, () => controller.isReady);
    // Original 600 x 800 page is still fully represented by 300 x 400.
    final bounds = controller.layout.pageLayouts.first;
    final origin = const PdfPoint(0, 800).toOffset(page: controller.document.pages.first, scaledPageSize: bounds.size);
    final end = const PdfPoint(600, 0).toOffset(page: controller.document.pages.first, scaledPageSize: bounds.size);
    expect(origin, Offset.zero);
    expect(end, const Offset(300, 400));
    await close(tester);
  });
  testWidgets('cropped raster, selection and ink share original points; margin remains editable', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final doc = await PdfDocument.openFile('probe.pdf');
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingProbe(path: 'probe.pdf', document: doc, text: await doc.pages.first.loadText()),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('crop-surface'));
    // Backend text occupies x=30..190,y=680..700; crop=(24,36,...), scale=.65.
    final start = tester.getTopLeft(surface) + const Offset(2, 39);
    await tester.dragFrom(start, const Offset(120, 18), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    ProbeMarks painter() =>
        tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<ProbeMarks>().single;
    expect(painter().selected, isNotEmpty);
    final selected = List<PageRect>.of(painter().selected);
    await tester.tap(find.text('Zoom'));
    await tester.pumpAndSettle();
    expect(painter().selected, selected);
    expect(painter().geometry.scale, 1);
    await tester.tap(find.text('Select'));
    await tester.dragFrom(
      tester.getTopLeft(surface) + const Offset(50, 70),
      const Offset(90, 20),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(painter().ink.length, greaterThan(1));
    final ink = List<Offset>.of(painter().ink);
    await tester.tap(find.text('Uncrop'));
    await tester.pumpAndSettle();
    expect(painter().ink, ink);
    expect(painter().selected, selected);
    await tester.enterText(find.byKey(const ValueKey('margin-card')), 'editable beside PDF');
    expect(find.text('editable beside PDF'), findsOneWidget);
    await close(tester);
    await doc.dispose();
  });
  testWidgets('two actual PdfViews synchronize at 25 percent without an echo loop', (tester) async {
    final doc = await PdfDocument.openFile('probe.pdf');
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingProbe(path: 'probe.pdf', document: doc),
      ),
    );
    await tester.tap(find.text('Two PdfViews'));
    await tester.pumpAndSettle();
    final views = tester.widgetList<MMPdfView>(find.byType(MMPdfView)).toList();
    expect(views.length, 2);
    await ready(tester, () => views.every((v) => v.controller.isReady));
    final left = views[0].controller, right = views[1].controller;
    for (final (source, target, y) in [(left, right, 500.0), (right, left, 300.0)]) {
      final future = source.jumpToReadingPosition(PdfReadingPosition(page: 2, y: y));
      await tester.pumpAndSettle();
      await future;
      expect(target.readingPosition!.page, 2);
      expect(target.readingPosition!.y, closeTo(source.readingPosition!.y, .5));
      expect(source.canGoBack, false);
    }
    final before = right.readingPosition!.toJson();
    await tester.pump(const Duration(seconds: 1));
    expect(right.readingPosition!.toJson(), before);
    await close(tester);
    expect(left.readingPosition, isNull);
    expect(left.pageHeights, isEmpty);
    await left.jumpToReadingPosition(PdfReadingPosition(page: 1, y: 0));
    await doc.dispose();
  });
}

Future<void> ready(WidgetTester tester, bool Function() isReady) async {
  for (var i = 0; i < 60 && !isReady(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(isReady(), true);
  await tester.pumpAndSettle();
}

Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 300));
}
