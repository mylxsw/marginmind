import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_pdf/src/ink.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/pdf_backend.dart';

const _colors = [Color(0xFFFF3B30), Color(0xFF007AFF)];

InkStroke _pen(String id, List<InkPoint> points, {int page = 1, double width = 2}) =>
    InkStroke(id: id, documentId: 'd', page: page, tool: InkTool.pen, colorIndex: 0, width: width, points: points);

void main() {
  group('geometry', () {
    test('simplification drops collinear points, keeps corners and fits the cap', () {
      final line = [for (var i = 0; i <= 100; i++) InkPoint(i.toDouble(), 0)];
      expect(simplifyInk(line).map((p) => p.x), [0, 100]);
      final corner = [...line, for (var i = 1; i <= 100; i++) InkPoint(100, i.toDouble())];
      final simplified = simplifyInk(corner);
      expect(simplified, hasLength(3));
      expect(simplified[1].x, 100);
      expect(simplified[1].y, 0);
      final zigzag = [for (var i = 0; i < 5000; i++) InkPoint(i.toDouble(), i.isEven ? 0 : 10)];
      final capped = simplifyInk(zigzag, maxPoints: 200);
      expect(capped.length, lessThanOrEqualTo(200));
      expect(capped.first.x, 0);
      expect(capped.last.x, 4999);
      expect(simplifyInk(const [InkPoint(1, 1)]), hasLength(1));
    });

    test('ellipse bounds surround the stroke in page orientation', () {
      final r = inkEllipseBounds(const [InkPoint(10, 50), InkPoint(40, 20), InkPoint(25, 60)], padding: 2);
      expect(r, const PageRect(8, 62, 42, 18));
      final flat = inkEllipseBounds(const [InkPoint(0, 5), InkPoint(30, 5)], padding: 1);
      expect(flat.top, greaterThan(flat.bottom));
    });

    test('hit testing reaches the outline, not the inside', () {
      final pen = _pen('p', const [InkPoint(0, 0), InkPoint(100, 0)]);
      expect(inkStrokeHit(pen, const InkPoint(50, 3), 2), isTrue, reason: 'radius + half width');
      expect(inkStrokeHit(pen, const InkPoint(50, 4), 2), isFalse);
      expect(inkStrokeHit(pen, const InkPoint(103, 0), 2), isTrue);
      final dot = _pen('d', const [InkPoint(5, 5)]);
      expect(inkStrokeHit(dot, const InkPoint(6, 6), 1), isTrue);
      expect(inkStrokeHit(_pen('e', const []), const InkPoint(0, 0), 100), isFalse);
      final ellipse = InkStroke(
        id: 'o',
        documentId: 'd',
        page: 1,
        tool: InkTool.ellipse,
        colorIndex: 0,
        width: 2,
        ellipse: const PageRect(0, 100, 200, 0),
      );
      expect(inkStrokeHit(ellipse, const InkPoint(0, 50), 1), isTrue);
      expect(inkStrokeHit(ellipse, const InkPoint(100, 100), 1), isTrue);
      expect(inkStrokeHit(ellipse, const InkPoint(100, 50), 10), isFalse, reason: 'the middle is not ink');
    });

    test('painting draws paths, circles, arrows and single dots where mapped', () async {
      final strokes = [
        _pen('line', const [InkPoint(10, 10), InkPoint(90, 10)], width: 4),
        _pen('dot', const [InkPoint(50, 50)], width: 6),
        InkStroke(
          id: 'arrow',
          documentId: 'd',
          page: 1,
          tool: InkTool.arrow,
          colorIndex: 1,
          width: 2,
          points: const [InkPoint(10, 80), InkPoint(90, 80)],
        ),
        InkStroke(
          id: 'zero',
          documentId: 'd',
          page: 1,
          tool: InkTool.arrow,
          colorIndex: 1,
          width: 2,
          points: const [InkPoint(5, 5), InkPoint(5, 5)],
        ),
        InkStroke(
          id: 'ellipse',
          documentId: 'd',
          page: 1,
          tool: InkTool.ellipse,
          colorIndex: 1,
          width: 2,
          ellipse: const PageRect(20, 70, 80, 30),
        ),
      ];
      final hidden = ValueNotifier<Set<String>>(const {});
      addTearDown(hidden.dispose);
      // y grows downwards on the canvas.
      final painter = InkPagePainter(
        strokes: strokes,
        colors: _colors,
        hidden: hidden,
        map: (size) => (point: (p) => Offset(p.x, size.height - p.y), scale: 1),
      );
      final image = await debugRenderInk(painter, const Size(100, 100));
      final bytes = (await image.toByteData())!;
      int alpha(int x, int y) => bytes.getUint8((y * 100 + x) * 4 + 3);
      expect(alpha(50, 90), greaterThan(0), reason: 'line at page y=10');
      expect(alpha(50, 50), greaterThan(0), reason: 'dot');
      expect(alpha(88, 20), greaterThan(0), reason: 'arrow head');
      expect(alpha(20, 50), greaterThan(0), reason: 'ellipse left edge');
      expect(alpha(50, 40), 0, reason: 'inside the ellipse');
      image.dispose();

      hidden.value = {'line'};
      final without = await debugRenderInk(painter, const Size(100, 100));
      final after = (await without.toByteData())!;
      expect(after.getUint8((90 * 100 + 50) * 4 + 3), 0);
      without.dispose();
      expect(
        painter.shouldRepaint(
          InkPagePainter(strokes: strokes, colors: List.of(_colors), hidden: hidden, map: painter.map),
        ),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          InkPagePainter(strokes: List.of(strokes), colors: _colors, hidden: hidden, map: painter.map),
        ),
        isTrue,
      );
      expect(
        painter.shouldRepaint(
          InkPagePainter(strokes: strokes, colors: const [Colors.black], hidden: hidden, map: painter.map),
        ),
        isTrue,
      );
      expect(
        const MMPdfInk(tool: MMPdfInkTool.arrow, colorIndex: 1, width: 2).hashCode,
        const MMPdfInk(tool: MMPdfInkTool.arrow, colorIndex: 1, width: 2).hashCode,
      );
      final empty = InkPagePainter(strokes: strokes, colors: const [], hidden: hidden, map: painter.map);
      final blank = await debugRenderInk(empty, const Size(10, 10));
      blank.dispose();
    });
  });

  group('view', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUp(installTestPdfBackend);

    testWidgets('pen strokes keep page coordinates across zoom, scroll and reopening', (tester) async {
      var controller = MMPdfViewController();
      final drawn = <MMPdfInkDraft>[];
      final erased = <Set<String>>[];
      Future<void> mount({MMPdfInk? ink, List<InkStroke> strokes = const [], String file = 'ink.pdf'}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MMPdfView(
              filePath: file,
              controller: controller,
              inkStrokes: strokes,
              inkColors: _colors,
              ink: ink,
              onInkDrawn: drawn.add,
              onInkErased: erased.add,
            ),
          ),
        );
        if (!controller.isReady) await _waitReady(tester, controller);
      }

      const pen = MMPdfInk(tool: MMPdfInkTool.freehand, colorIndex: 1, width: 2.5);
      await mount(ink: pen);
      PdfViewerController pdf() => tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
      expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).params.textSelectionParams!.enabled, isFalse);
      Offset at(double x, double y) =>
          tester.getTopLeft(find.byType(MMPdfView)) +
          pdf().documentToLocal(pdf().calcRectForRectInsidePage(pageNumber: 1, rect: PdfRect(x, y, x, y)).topLeft);

      Future<MMPdfInkDraft> draw(List<(double, double)> path) async {
        final before = drawn.length;
        final gesture = await tester.startGesture(at(path.first.$1, path.first.$2), kind: PointerDeviceKind.mouse);
        for (final (x, y) in path.skip(1)) {
          await gesture.moveTo(at(x, y));
          await tester.pump();
        }
        await gesture.up();
        await tester.pump();
        expect(drawn, hasLength(before + 1));
        return drawn.last;
      }

      void expectNear(InkPoint p, double x, double y) {
        expect(p.x, closeTo(x, 1));
        expect(p.y, closeTo(y, 1));
      }

      final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      final first = await draw([(100, 600), (150, 560), (200, 600)]);
      expect(tester.widget<PdfViewer>(find.byType(PdfViewer)), same(viewer), reason: 'drawing does not rebuild pages');
      expect(first.page, 1);
      expect(first.tool, InkTool.pen);
      expect(first.colorIndex, 1);
      expect(first.width, 2.5);
      expectNear(first.points.first, 100, 600);
      expectNear(first.points.last, 200, 600);
      expect(first.points.any((p) => (p.x - 150).abs() < 1 && (p.y - 560).abs() < 1), isTrue);

      InkLivePainter live() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<InkLivePainter>()
          .single;
      expect(live().strokes(), hasLength(1), reason: 'shown until the parent stores it');
      // A second stroke drawn before the first is stored keeps showing.
      final second = await draw([(300, 600), (350, 560)]);
      expect(live().strokes(), hasLength(2));
      final stored = first.toStroke(id: 's1', documentId: 'doc');
      expect(stored.documentId, 'doc');
      await mount(ink: pen, strokes: [stored]);
      expect(live().strokes(), hasLength(1));
      await mount(
        ink: pen,
        strokes: [
          stored,
          second.toStroke(id: 's2', documentId: 'doc'),
        ],
      );
      expect(live().strokes(), isEmpty);
      await mount(ink: pen, strokes: [stored]);

      // Zoomed in and scrolled: the same page point produces the same data.
      pdf().value = pdf().value.clone()
        ..scaleByDouble(1.6, 1.6, 1, 1)
        ..translateByDouble(-40, -60, 0, 1);
      await tester.pumpAndSettle();
      final zoomed = await draw([(100, 600), (150, 560), (200, 600)]);
      expectNear(zoomed.points.first, 100, 600);
      expectNear(zoomed.points.last, 200, 600);
      expect(zoomed.width, 2.5, reason: 'width is in page points, not pixels');

      // ...and the eraser finds the stored stroke where it was drawn.
      await mount(
        ink: const MMPdfInk(tool: MMPdfInkTool.eraser, colorIndex: 0, width: 2.5),
        strokes: [stored],
      );
      await tester.tapAt(at(150, 560));
      await tester.pump();
      expect(erased.single, {'s1'});

      // Reopened at a different zoom: the stroke is painted at the same spot.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      controller.dispose();
      controller = MMPdfViewController();
      await mount(strokes: [stored], file: 'reopened.pdf');
      pdf().value = pdf().value.clone()..scaleByDouble(0.8, 0.8, 1, 1);
      await tester.pumpAndSettle();
      final viewerWidget = tester.widget<PdfViewer>(find.byType(PdfViewer));
      final layout = pdf().layout.pageLayouts.first;
      final size = Size(layout.width * pdf().currentZoom, layout.height * pdf().currentZoom);
      final overlays = viewerWidget.params.pageOverlaysBuilder!(
        tester.element(find.byType(PdfViewer)),
        Offset.zero & size,
        pdf().document.pages.first,
      );
      final painter = ((overlays.last as Positioned).child as IgnorePointer).child! as RepaintBoundary;
      final paint = (painter.child! as CustomPaint).painter! as InkPagePainter;
      final image = (await tester.runAsync(() => debugRenderInk(paint, size)))!;
      final bytes = (await tester.runAsync(() => image.toByteData()))!;
      final expected = PdfPoint(150, 560).toOffset(page: pdf().document.pages.first, scaledPageSize: size);
      final x = expected.dx.round(), y = expected.dy.round();
      expect(bytes.getUint8((y * image.width + x) * 4 + 3), greaterThan(0));
      expect(bytes.getUint8(((y + 40) * image.width + x) * 4 + 3), 0);
      image.dispose();
      expect(paint.map(size).scale, closeTo(size.height / 800, 1e-9));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      controller.dispose();
    });

    testWidgets('circle regularizes on release, ⇧ keeps it hand-drawn, arrows keep two ends', (tester) async {
      final controller = MMPdfViewController();
      addTearDown(controller.dispose);
      final drawn = <MMPdfInkDraft>[];
      Future<void> mount(MMPdfInk ink) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MMPdfView(
              filePath: 'shapes.pdf',
              controller: controller,
              inkColors: _colors,
              ink: ink,
              onInkDrawn: drawn.add,
            ),
          ),
        );
        if (!controller.isReady) await _waitReady(tester, controller);
      }

      await mount(const MMPdfInk(tool: MMPdfInkTool.ellipse, colorIndex: 0, width: 2));
      final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
      Offset at(double x, double y) =>
          tester.getTopLeft(find.byType(MMPdfView)) +
          pdf.documentToLocal(pdf.calcRectForRectInsidePage(pageNumber: 1, rect: PdfRect(x, y, x, y)).topLeft);
      Future<void> stroke(List<(double, double)> path) async {
        final gesture = await tester.startGesture(at(path.first.$1, path.first.$2), kind: PointerDeviceKind.mouse);
        for (final (x, y) in path.skip(1)) {
          await gesture.moveTo(at(x, y));
          await tester.pump();
        }
        await gesture.up();
        await tester.pump();
      }

      const loop = [(100.0, 500.0), (200.0, 560.0), (300.0, 500.0), (200.0, 440.0), (110.0, 505.0)];
      await stroke(loop);
      final circle = drawn.removeLast();
      expect(circle.tool, InkTool.ellipse);
      expect(circle.points, isEmpty);
      expect(circle.ellipse!.left, closeTo(98, 1));
      expect(circle.ellipse!.right, closeTo(302, 1));
      expect(circle.ellipse!.top, closeTo(562, 1));
      expect(circle.ellipse!.bottom, closeTo(438, 1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await stroke(loop);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final freehand = drawn.removeLast();
      expect(freehand.tool, InkTool.pen);
      expect(freehand.ellipse, isNull);
      expect(freehand.points.length, greaterThan(3));

      // A twitch is not a stroke.
      await stroke([(100, 500), (100.5, 500.5)]);
      expect(drawn, isEmpty);
      await tester.tapAt(at(300, 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(drawn, isEmpty);

      await mount(const MMPdfInk(tool: MMPdfInkTool.arrow, colorIndex: 1, width: 4));
      await stroke([(100, 500), (150, 520), (250, 450)]);
      final arrow = drawn.removeLast();
      expect(arrow.tool, InkTool.arrow);
      expect(arrow.points, hasLength(2));
      expect(arrow.points.first.x, closeTo(100, 1));
      expect(arrow.points.last.x, closeTo(250, 1));
      expect(arrow.points.last.y, closeTo(450, 1));

      // Dragging past the page edge stays on the starting page.
      await mount(const MMPdfInk(tool: MMPdfInkTool.freehand, colorIndex: 1, width: 4));
      final gesture = await tester.startGesture(at(500, 500), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(4000, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(drawn.single.page, 1);
      expect(drawn.single.points.last.x, closeTo(600, 1));

      // Switching tools mid-stroke drops it.
      final cancelled = await tester.startGesture(at(100, 500), kind: PointerDeviceKind.mouse);
      await cancelled.moveTo(at(200, 550));
      await tester.pump();
      await mount(const MMPdfInk(tool: MMPdfInkTool.arrow, colorIndex: 1, width: 4));
      await cancelled.up();
      await tester.pump();
      expect(drawn, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('one eraser drag removes whole strokes; they stay hidden until stored', (tester) async {
      final controller = MMPdfViewController();
      addTearDown(controller.dispose);
      final erased = <Set<String>>[];
      final strokes = [
        _pen('a', const [InkPoint(100, 600), InkPoint(100, 400)]),
        _pen('b', const [InkPoint(200, 600), InkPoint(200, 400)]),
        _pen('c', const [InkPoint(400, 600), InkPoint(400, 400)]),
        _pen('p2', const [InkPoint(100, 600), InkPoint(100, 400)], page: 2),
      ];
      Future<void> mount(List<InkStroke> data, {MMPdfInk? ink}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MMPdfView(
              filePath: 'erase.pdf',
              controller: controller,
              inkStrokes: data,
              inkColors: _colors,
              ink: ink ?? const MMPdfInk(tool: MMPdfInkTool.eraser, colorIndex: 0, width: 2),
              onInkErased: erased.add,
            ),
          ),
        );
        if (!controller.isReady) await _waitReady(tester, controller);
      }

      await mount(strokes);
      final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
      Offset at(double x, double y) =>
          tester.getTopLeft(find.byType(MMPdfView)) +
          pdf.documentToLocal(pdf.calcRectForRectInsidePage(pageNumber: 1, rect: PdfRect(x, y, x, y)).topLeft);
      InkPagePainter painterOf(int page) {
        final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
        final layout = pdf.layout.pageLayouts[page - 1];
        final overlays = viewer.params.pageOverlaysBuilder!(
          tester.element(find.byType(PdfViewer)),
          Offset.zero & layout.size,
          pdf.document.pages[page - 1],
        );
        final boundary = ((overlays.last as Positioned).child as IgnorePointer).child! as RepaintBoundary;
        return (boundary.child! as CustomPaint).painter! as InkPagePainter;
      }

      final page2 = painterOf(2);
      final gesture = await tester.startGesture(at(60, 500), kind: PointerDeviceKind.mouse);
      for (var x = 80.0; x <= 260; x += 20) {
        await gesture.moveTo(at(x, 500));
        await tester.pump();
      }
      expect(painterOf(1).hidden.value, {'a', 'b'}, reason: 'hidden while erasing');
      expect(page2.hidden.value, isEmpty, reason: 'other pages are untouched');
      await gesture.up();
      await tester.pump();
      expect(erased.single, {'a', 'b'});

      // Equivalent data keeps each page's list, so its painter does not repaint.
      final unchanged = painterOf(2).strokes;
      await mount(List.of(strokes));
      expect(painterOf(2).strokes, same(unchanged));
      expect(painterOf(1).hidden.value, {'a', 'b'}, reason: 'still waiting for the parent');

      await mount([strokes[2], strokes[3]]);
      expect(painterOf(1).hidden.value, isEmpty);
      expect(painterOf(1).strokes.map((s) => s.id), ['c']);
      expect(painterOf(2).strokes, same(unchanged));

      // Missing the strokes erases nothing.
      await tester.tapAt(at(300, 450));
      await tester.pump();
      expect(erased, hasLength(1));

      // A failed save un-hides after a while.
      await tester.tapAt(at(400, 500));
      await tester.pump();
      expect(erased.last, {'c'});
      expect(painterOf(1).hidden.value, {'c'});
      await tester.pump(const Duration(seconds: 3));
      expect(painterOf(1).hidden.value, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('without the pen, ink never takes the pointer: selection and highlight taps work', (tester) async {
      final controller = MMPdfViewController();
      addTearDown(controller.dispose);
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'through.pdf',
            controller: controller,
            inkColors: _colors,
            inkStrokes: [
              _pen('over', const [InkPoint(20, 690), InkPoint(200, 690)], width: 20),
            ],
            highlights: const [
              MMPdfHighlight(id: 'h', page: 1, rects: [PageRect(30, 700, 90, 680)], color: Colors.yellow),
            ],
            onHighlightTap: (id, _) => tapped = id,
          ),
        ),
      );
      await _waitReady(tester, controller);
      final navigation = controller.goToPage(1);
      await tester.pumpAndSettle();
      await navigation;
      expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).params.textSelectionParams!.enabled, isTrue);
      expect(
        find.byWidgetPredicate(
          (w) => w is MouseRegion && (w.cursor == SystemMouseCursors.precise || w.cursor == SystemMouseCursors.cell),
        ),
        findsNothing,
      );
      final pdf = tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
      final rect = pdf.calcRectForRectInsidePage(pageNumber: 1, rect: const PdfRect(30, 700, 90, 680));
      await tester.tapAt(tester.getTopLeft(find.byType(MMPdfView)) + pdf.documentToLocal(rect.center));
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      expect(tapped, 'h');

      // With the pen out the same click is drawing, not a highlight click.
      tapped = null;
      await tester.pumpWidget(
        MaterialApp(
          home: MMPdfView(
            filePath: 'through.pdf',
            controller: controller,
            inkColors: _colors,
            ink: const MMPdfInk(tool: MMPdfInkTool.freehand, colorIndex: 0, width: 2),
            highlights: const [
              MMPdfHighlight(id: 'h', page: 1, rects: [PageRect(30, 700, 90, 680)], color: Colors.yellow),
            ],
            onHighlightTap: (id, _) => tapped = id,
          ),
        ),
      );
      await tester.pump();
      await tester.tapAt(tester.getTopLeft(find.byType(MMPdfView)) + pdf.documentToLocal(rect.center));
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      expect(tapped, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}

Future<void> _waitReady(WidgetTester tester, MMPdfViewController controller) async {
  for (var i = 0; i < 100 && !controller.isReady; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(controller.isReady, isTrue);
}
