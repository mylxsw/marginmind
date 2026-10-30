import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_pdf/src/ink.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

void main() {
  setUp(() {
    installTestPdfBackend();
    TestPdfText.pages = {};
  });
  tearDown(() => TestPdfText.pages = {});

  Future<PdfViewerController> mount(
    WidgetTester t, {
    MMPdfInk? ink,
    ValueChanged<MMPdfInkDraft>? drawn,
    ValueChanged<MMPdfSelection>? selected,
    void Function(int, Offset)? unavailable,
  }) async {
    final controller = MMPdfViewController();
    await t.pumpWidget(
      MaterialApp(
        home: MMPdfView(
          filePath: 'pencil.pdf',
          controller: controller,
          useTouchSelectionHandles: true,
          ink: ink,
          inkColors: const [Colors.red],
          onInkDrawn: drawn,
          onSelectionCommitted: selected,
          onTextUnavailable: unavailable,
        ),
      ),
    );
    for (var i = 0; i < 60 && !controller.isReady; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump();
    }
    expect(controller.isReady, isTrue);
    return t.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
  }

  Future<void> settle(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  testWidgets('Pencil preserves dots and rapid strokes below drag slop, including the final sample', (t) async {
    final drafts = <MMPdfInkDraft>[];
    await mount(
      t,
      ink: const MMPdfInk(tool: MMPdfInkTool.freehand, colorIndex: 0, width: 2),
      drawn: drafts.add,
    );
    final dot = await t.startGesture(const Offset(300, 250), kind: PointerDeviceKind.stylus);
    await t.pump();
    final live = t
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<InkLivePainter>()
        .single;
    expect(live.strokes().single.$2.points, hasLength(1), reason: 'ink is visible before any movement');
    await dot.up();
    expect(drafts, hasLength(1));
    expect(drafts.single.points, hasLength(1));
    for (var i = 0; i < 20; i++) {
      final p = await t.startGesture(Offset(300 + i * 3, 280), kind: PointerDeviceKind.stylus);
      await p.moveBy(const Offset(2, 1));
      await p.up();
    }
    expect(drafts, hasLength(21));
    expect(drafts.skip(1).every((s) => s.points.length >= 2), isTrue);
    await close(t);
  });

  testWidgets('a palm cannot scroll during a Pencil stroke; fresh finger gestures still scroll', (t) async {
    final drafts = <MMPdfInkDraft>[];
    final pdf = await mount(
      t,
      ink: const MMPdfInk(tool: MMPdfInkTool.freehand, colorIndex: 0, width: 2),
      drawn: drafts.add,
    );
    final before = pdf.value.clone();
    final palm = await t.startGesture(const Offset(420, 400), kind: PointerDeviceKind.touch, pointer: 11);
    final pen = await t.startGesture(const Offset(300, 250), kind: PointerDeviceKind.stylus, pointer: 10);
    await palm.moveBy(const Offset(0, -100));
    await t.pump();
    expect(pdf.value, before);
    await palm.up();
    await pen.cancel();
    expect(drafts, isEmpty);
    final finger = await t.startGesture(const Offset(420, 400), kind: PointerDeviceKind.touch, pointer: 12);
    await finger.moveBy(const Offset(0, -100));
    await t.pump();
    await finger.moveBy(const Offset(0, -50));
    await finger.up();
    await t.pump();
    expect(pdf.value, isNot(before));
    await close(t);
  });

  for (final kind in [PointerDeviceKind.stylus, PointerDeviceKind.mouse]) {
    testWidgets('${kind.name} selects partial Chinese text without drag slop or whole-line expansion', (t) async {
      const text = '文字选择需要精准测试';
      TestPdfText.pages = {
        1: PdfPageRawText(text, List.generate(text.length, (i) => PdfRect(30 + i * 14, 700, 44 + i * 14, 680))),
      };
      final selections = <MMPdfSelection>[];
      final pdf = await mount(t, selected: selections.add);
      Offset at(double x) =>
          pdf.documentToLocal(pdf.calcRectForRectInsidePage(pageNumber: 1, rect: PdfRect(x, 690, x, 690)).topLeft);
      final pen = await t.startGesture(at(36), kind: kind);
      await pen.moveBy(const Offset(.1, 0));
      await settle(t);
      expect(await pdf.textSelectionDelegate.getSelectedText(), '文');
      await pen.moveTo(at(50));
      await settle(t);
      expect(await pdf.textSelectionDelegate.getSelectedText(), '文字');
      await pen.up();
      await t.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 20 && selections.isEmpty; i++) {
        await settle(t);
      }
      expect(selections.single.text, '文字');
      final handle = find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == 'pdf-selection-end');
      expect(handle, findsOneWidget);
      final grab = await t.startGesture(t.getCenter(handle), kind: kind);
      await grab.moveBy(const Offset(60, 0));
      await grab.up();
      await t.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 20 && selections.length < 2; i++) {
        await settle(t);
      }
      expect(selections.last.text.length, greaterThan(2), reason: 'Pencil can still drag the selection handle');
      final blank = await t.startGesture(const Offset(600, 450), kind: kind);
      await blank.up();
      await t.pump(const Duration(milliseconds: 350));
      await settle(t);
      expect(pdf.textSelectionDelegate.hasSelectedText, isFalse);
      await close(t);
    });
  }

  testWidgets('tablet long press starts at a character instead of the Chinese PDF fragment', (t) async {
    const text = '文字选择需要精准测试';
    TestPdfText.pages = {
      1: PdfPageRawText(text, List.generate(text.length, (i) => PdfRect(30 + i * 14, 700, 44 + i * 14, 680))),
    };
    final pdf = await mount(t);
    final point = pdf.documentToLocal(
      pdf.calcRectForRectInsidePage(pageNumber: 1, rect: const PdfRect(64, 690, 64, 690)).topLeft,
    );
    final finger = await t.startGesture(point, kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 650));
    await settle(t);
    expect(await pdf.textSelectionDelegate.getSelectedText(), '选');
    await finger.up();
    await close(t);
  });
  testWidgets('Pencil selection on a scanned page retains the OCR fallback', (t) async {
    TestPdfText.pages = {1: PdfPageRawText('', const [])};
    final pages = <int>[];
    await mount(t, unavailable: (page, _) => pages.add(page));
    final pen = await t.startGesture(const Offset(300, 250), kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(80, 0));
    await pen.up();
    for (var i = 0; i < 20 && pages.isEmpty; i++) {
      await settle(t);
    }
    expect(pages, [1]);
    await close(t);
  });
}
