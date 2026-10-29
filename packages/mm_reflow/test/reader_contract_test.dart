import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_reflow/mm_reflow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = EpubParser();

  test('reader themes invalidate cached painters and paint ink, highlight and both placeholders', () async {
    final c = parser.parseHtml(
      'theme',
      '<p>M&nbsp;X<img src="inline" width="12" height="12"></p>'
          '<img src="block" width="20" height="20">',
    );
    final engine = ReflowEngine(maxChapters: MMReaderStyle.values.length);
    final layouts = <ChapterLayout>[];
    for (final style in MMReaderStyle.values) {
      final layout = await engine.layout(c, LayoutSpec(width: 120, readerStyle: style), 1, revision: 'r');
      layouts.add(layout);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawPaint(Paint()..color = style.paperColor);
      layout.paint(canvas, highlight: c.anchor(1, 2));
      final picture = recorder.endRecording();
      final image = await picture.toImage(120, layout.height.ceil());
      final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      void expectPixel(Offset point, Color expected) {
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final argb = expected.toARGB32();
        for (var channel = 0; channel < 3; channel++) {
          expect(pixels.getUint8(offset + channel), closeTo((argb >> (16 - channel * 8)) & 255, 1));
        }
        expect(pixels.getUint8(offset + 3), 255);
      }

      expectPixel(layout.boxes(c.anchor(0, 1)).single.center, style.inkColor);
      expectPixel(layout.boxes(c.anchor(1, 2)).single.center, Color.alphaBlend(style.marginNoteLine, style.paperColor));
      final inline = layout.pieces.first.artwork.single.rect.shift(layout.pieces.first.rect.topLeft);
      final placeholder = Color.alphaBlend(style.marginGuide, style.paperColor);
      expectPixel(inline.center, placeholder);
      expectPixel(layout.pieces.last.rect.center, placeholder);
      image.dispose();
      picture.dispose();
    }
    expect(layouts.map((l) => l.pieces.first.painter).toSet().length, MMReaderStyle.values.length);
    final whiteAgain = await engine.layout(c, const LayoutSpec(width: 120), 1, revision: 'r');
    expect(identical(whiteAgain.pieces.first.painter, layouts.first.pieces.first.painter), isTrue);
    whiteAgain.dispose();
    for (final layout in layouts) {
      layout.dispose();
    }
    engine.dispose();
  });

  for (final table in [false, true]) {
    test('controller geometry preserves page and local scrolling for ${table ? 'tables' : 'code'}', () async {
      final c = parser.parseHtml(
        'scroll',
        '<p>before</p>${table ? '<table><tr>${'<td>${'long cell ' * 20}</td>' * 6}</tr></table>' : '<pre>${'wide text ' * 30}</pre>'}',
      );
      final controller = ReflowController();
      final layout = (await controller.layout(
        c,
        const LayoutSpec(width: 180, pageHeight: 80, padding: EdgeInsets.all(10)),
        revision: 'r',
      ))!;
      final piece = layout.pieces.last;
      final start = table ? piece.textEnd - 5 : piece.textStart + 30;
      final anchor = c.anchor(start, start + 3);
      final original = layout.boxes(anchor).first.rect;
      final offsets = {piece.block.id: original.left - 35};
      expect(offsets.values.single, greaterThan(0));
      final page = layout.pageForOffset(start);
      final scroll = Offset(3, (original.top - layout.pages[page].top - 20).clamp(0.0, double.infinity));
      final boxes = controller.boxes(anchor, page: page, localScroll: scroll, horizontalOffsets: offsets);
      expect(boxes, isNotEmpty);
      expect(boxes.first.rect.left, closeTo(32, .01));
      expect(
        boxes.map((b) => b.rect),
        layout.boxes(anchor, page: page, localScroll: scroll, horizontalOffsets: offsets).map((b) => b.rect),
      );
      final hit = controller.hitTest(
        boxes.first.center,
        generation: controller.generation,
        page: page,
        localScroll: scroll,
        horizontalOffsets: offsets,
      )!;
      expect(hit.start, inInclusiveRange(anchor.start, anchor.end));
      final position = c.anchor(start, start);
      final caret = controller.reveal(position, page: page, localScroll: scroll, horizontalOffsets: offsets)!;
      final expectedCaret = layout
          .reveal(position)!
          .rect
          .shift(Offset(-offsets.values.single, 0))
          .shift(layout.toPage(Offset.zero, page, localScroll: scroll));
      expect(caret.rect, expectedCaret);
      expect(caret.page, page);
      expect(caret.generation, controller.generation);
      final generation = controller.generation;
      controller.engine.invalidate();
      expect(
        controller.hitTest(
          boxes.first.center,
          generation: generation,
          page: page,
          localScroll: scroll,
          horizontalOffsets: offsets,
        ),
        isNull,
      );
      expect(controller.boxes(anchor, page: page, localScroll: scroll, horizontalOffsets: offsets), isEmpty);
      expect(controller.reveal(position, page: page, localScroll: scroll, horizontalOffsets: offsets), isNull);
      controller.dispose();
    });
  }
}
