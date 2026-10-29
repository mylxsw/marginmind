import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_reflow/mm_reflow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final parser = EpubParser();
  test('web provenance flows below the title, scales with body text and links only the domain', () {
    final html = const WebBookParser().withAttribution(
      '<h1>Article</h1><p>Body</p>',
      'Article',
      Uri.parse('https://example.com/article'),
      DateTime(2026, 10, 29),
    );
    final chapter = parser.parseHtml('main', html);
    for (final ink in MMReaderStyle.values) {
      final layout = ChapterLayout.layout(
        chapter,
        LayoutSpec(width: 500, fontSize: 20, fontFamily: 'serif', readerStyle: ink),
      );
      final source = layout.pieces[1];
      expect(source.rect.top, greaterThanOrEqualTo(layout.pieces.first.rect.bottom));
      final span = (source.painter!.text! as TextSpan).children!.first as TextSpan;
      expect(span.style!.fontSize, 15);
      expect(span.style!.fontFamily, isNull);
      expect(span.style!.inherit, isFalse);
      expect(span.style!.color, ink.inkColor.withValues(alpha: ink.inkColor.a * .6));
      expect(layout.links.single.anchor.quote, 'example.com');
      expect(layout.links.single.target, 'https://example.com/article');
      layout.dispose();
    }
  });
  test('reflow preserves exact source, selection boxes and hit tests', () {
    final c = parser.parseHtml('main', '<h1>标题</h1><p>${'中文 mixed text emoji 😀 ' * 50}</p>');
    final a = c.anchor(6, 16);
    final before = a.toJson();
    for (final size in [16.0, 22.0]) {
      final layout = ChapterLayout.layout(c, LayoutSpec(width: 320, pageHeight: 180, fontSize: size));
      expect(layout.pages.length, greaterThan(2));
      expect(layout.pages.last.bottom, layout.height);
      for (var i = 1; i < layout.pages.length; i++) {
        expect(layout.pages[i].top, layout.pages[i - 1].bottom);
      }
      final boxes = layout.boxes(a);
      expect(boxes, isNotEmpty);
      final hit = layout.hitTest(boxes.first.center).start;
      expect(hit, inInclusiveRange(a.start, a.end));
      expect(layout.pageForOffset(a.start), inInclusiveRange(0, layout.pages.length - 1));
      expect(layout.pageForOffset(c.canonicalText.length), layout.pages.length - 1);
      expect(layout.boxes(const TextAnchor('other', 0, 1, 'x')), isEmpty);
      expect(a.toJson(), before);
      final recorder = ui.PictureRecorder();
      layout.paint(Canvas(recorder), page: 0, highlight: a);
      recorder.endRecording().dispose();
      layout.dispose();
    }
  });
  test('table, image, list, quote and code share canonical coordinates', () async {
    final c = parser.parseHtml(
      'c',
      '<ul><li>list</li></ul><blockquote>quote</blockquote><pre>code</pre>'
          '<table><tr><td>first</td><td>second</td></tr><tr><td>third</td></tr></table><img src="pic.png"><img src="missing.png">',
    );
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    picture.dispose();
    final layout = ChapterLayout.layout(
      c,
      const LayoutSpec(width: 200, pageHeight: 80),
      images: {'pic.png': MMBookImage.raster(image)},
    );
    final index = c.canonicalText.indexOf('second');
    final boxes = layout.boxes(c.anchor(index, index + 6));
    expect(boxes, isNotEmpty);
    expect(layout.hitTest(boxes.first.center).start, inInclusiveRange(index, index + 6));
    final imageStart = c.blocks.last.start;
    expect(layout.boxes(c.anchor(imageStart, imageStart + 1)), hasLength(1));
    final paintRecorder = ui.PictureRecorder();
    final canvas = Canvas(paintRecorder);
    layout.paint(canvas, highlight: c.anchor(0, c.canonicalText.length));
    for (var i = 0; i < layout.pages.length; i++) {
      layout.paint(canvas, page: i);
    }
    paintRecorder.endRecording().dispose();
    layout.dispose();
    image.dispose();
  });
  test('empty, invalid geometry and oversized row', () {
    final empty = ChapterLayout.layout(parser.parseHtml('c', ''), const LayoutSpec(width: 200));
    expect(empty.hitTest(Offset.zero).start, 0);
    expect(empty.pages.length, 1);
    empty.dispose();
    expect(() => ChapterLayout.layout(parser.parseHtml('c', ''), const LayoutSpec(width: 0)), throwsArgumentError);
    final c = parser.parseHtml('c', '<table><tr><td>${'x ' * 500}</td></tr></table>');
    final layout = ChapterLayout.layout(c, const LayoutSpec(width: 100, pageHeight: 50));
    expect(layout.pages.length, 1);
    expect(layout.pages.single.scrollExtent, greaterThan(500));
    expect(layout.hitTest(const Offset(-20, -20)).start, 0);
    layout.dispose();
  });
  testWidgets('drag selects source text and repaint follows font changes', (tester) async {
    final chapter = parser.parseHtml('main', '<p>Hello world source selection</p>');
    var layout = ChapterLayout.layout(chapter, const LayoutSpec(width: 320));
    TextAnchor? selection;
    Widget view() => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: ReflowSurface(layout: layout, page: 0, highlight: selection, onSelection: (a) => selection = a),
      ),
    );
    await tester.pumpWidget(view());
    final gesture = await tester.startGesture(const Offset(5, 12));
    await gesture.moveTo(const Offset(40, 12));
    await gesture.moveTo(const Offset(130, 12));
    await gesture.up();
    expect(selection, isNotNull);
    expect(selection!.quote, isNotEmpty);
    expect(chapter.resolves(selection!), isTrue);
    final snapshot = selection!.toJson();
    final old = layout;
    layout = ChapterLayout.layout(chapter, const LayoutSpec(width: 320, fontSize: 22));
    await tester.pumpWidget(view());
    expect(selection!.toJson(), snapshot);
    expect(layout.boxes(selection!), isNotEmpty);
    old.dispose();
    await tester.pumpWidget(const SizedBox());
    layout.dispose();
  });
}
