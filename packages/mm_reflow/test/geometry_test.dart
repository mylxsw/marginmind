import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_reflow/mm_reflow.dart';

import 'engine_test.dart' show paint;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = EpubParser();

  test('indexed link anchors match the source contract across split graphemes', () {
    final c = parser.parseHtml(
      'links',
      '<p><a href="#a">e</a>́ <a href="#b">👩</a>‍👩‍👧‍👦 <a href="#c">🇦</a>🇧 '
          '<a href="#d">plain</a></p>',
    );
    final l = ChapterLayout.layout(c, const LayoutSpec(width: 400));
    var offset = 0, index = 0;
    for (final run in c.blocks.single.runs) {
      if (run.link != null) {
        expect(l.links[index++].anchor.toJson(), c.anchor(offset, offset + run.text.length).toJson());
      }
      offset += run.text.length;
    }
    expect(l.links.map((link) => link.anchor.quote), ['é', '👩‍👩‍👧‍👦', '🇦🇧', 'plain']);
    l.dispose();
  });

  test('continuous horizontal scroll keeps painted ink inside page insets', () async {
    final c = parser.parseHtml('code', '<pre>${'MMMM ' * 20}</pre>');
    final l = ChapterLayout.layout(c, const LayoutSpec(width: 100, padding: EdgeInsets.all(10)));
    final recorder = ui.PictureRecorder();
    l.paint(Canvas(recorder), horizontalOffsets: {c.blocks.single.id: 20});
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, l.height.ceil());
    final bytes = (await image.toByteData())!;
    var insideInk = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final alpha = bytes.getUint8((y * image.width + x) * 4 + 3);
        if (x < 10 || x >= 90) {
          expect(alpha, 0);
        } else {
          insideInk += alpha;
        }
      }
    }
    expect(insideInk, greaterThan(0));
    image.dispose();
    picture.dispose();
    l.dispose();
  });

  test('local horizontal scroll changes only its block and agrees with hit boxes', () {
    final c = parser.parseHtml('c', '<p>unchanged</p><pre>${'abcdef ' * 50}</pre>');
    final l = ChapterLayout.layout(c, const LayoutSpec(width: 180));
    final code = l.pieces.last;
    final anchor = c.anchor(code.textStart + 30, code.textStart + 35);
    final original = l.boxes(anchor).single.rect;
    final offsets = {code.block.id: original.left - 10};
    final shifted = l.boxes(anchor, horizontalOffsets: offsets).single;
    expect(shifted.rect.left, closeTo(10, .01));
    expect(l.hitTest(shifted.center, horizontalOffsets: offsets).start, inInclusiveRange(anchor.start, anchor.end));
    final normal = c.anchor(0, 4);
    expect(l.boxes(normal, horizontalOffsets: offsets).single.rect, l.boxes(normal).single.rect);
    expect(l.boxes(anchor, horizontalOffsets: {code.block.id: original.right + 10}), isEmpty);
    final recorder = ui.PictureRecorder();
    l.paint(Canvas(recorder), horizontalOffsets: offsets, highlight: anchor);
    recorder.endRecording().dispose();
    expect(l.restore(ViewportBookmark(c.anchor(0, 0), 0, revision: 'another')), isNull);
    l.dispose();
  });

  test('percentage max-width uses containing width and fixed boxes honor trailing edges', () {
    final flow = parser.parseHtml('flow', '<p style="width:80%;max-width:50%">${'text ' * 20}</p>');
    final layout = ChapterLayout.layout(flow, const LayoutSpec(width: 300));
    expect(layout.pieces.single.viewport!.width, 150);
    layout.dispose();
    final fixed = parser.parseHtml(
      'fixed',
      '<meta name="viewport" content="width=600,height=800">'
          '<p style="position:absolute;right:40px;bottom:100px;width:200px">fixed</p>',
    );
    final page = ChapterLayout.layout(fixed, const LayoutSpec(width: 300, pageHeight: 400));
    expect(page.pieces.single.rect.left, 180);
    expect(page.pieces.single.rect.bottom, 350);
    page.dispose();
  });

  test('fixed viewport scales text and images uniformly with matching hit geometry', () {
    final c = parser.parseHtml(
      'fixed',
      '<meta name="viewport" content="width=600,height=800">'
          '<p style="position:absolute;left:40px;top:100px;width:400px;font-size:20px">fixed text</p>'
          '<img src="pic" style="position:absolute;left:50px;top:300px;width:200px;height:100px">',
    );
    final l = ChapterLayout.layout(c, const LayoutSpec(width: 300, pageHeight: 400));
    expect(l.pages, hasLength(1));
    expect(l.height, 400);
    final text = l.pieces.first;
    expect(text.rect.topLeft, const Offset(20, 50));
    expect(text.scale, .5);
    expect(l.pieces.last.rect, const Rect.fromLTWH(25, 150, 100, 50));
    final boxes = l.boxes(c.anchor(0, 5));
    expect(l.hitTest(boxes.first.center).start, inInclusiveRange(0, 5));
    expect(l.reveal(c.anchor(0, 0))!.rect.top, 50);
    paint(l, page: 0);
    l.dispose();
  });
  test('CJK, bidi, NBSP, combining marks and ZWJ hit only grapheme boundaries', () {
    final c = parser.parseHtml(
      'c',
      '<p>中文，标点。 é 👩‍👩‍👧‍👦 😀 abc\u00a0def العربية EnglishLongWordWithoutBreaks</p>',
    );
    final original = c.anchor(0, c.canonicalText.length).toJson();
    for (final size in [16.0, 22.0]) {
      final l = ChapterLayout.layout(
        c,
        LayoutSpec(width: 180, pageHeight: 80, fontSize: size, direction: TextDirection.rtl),
      );
      for (var y = 0.0; y < l.height; y += 5) {
        for (var x = 0.0; x < 180; x += 5) {
          final hit = l.hitTest(Offset(x, y));
          expect(hit.start, hit.end);
          expect(c.anchor(hit.start, hit.start).quote, isEmpty);
        }
      }
      expect(
        l.boxes(c.anchor(0, c.canonicalText.length)).length,
        greaterThan(l.pieces.first.painter!.computeLineMetrics().length),
      );
      expect(c.anchor(0, c.canonicalText.length).toJson(), original);
      l.dispose();
    }
  });

  test('page and chapter geometry round trip with insets and scrolling', () {
    final c = parser.parseHtml('c', '<p>${'中文 mixed source ' * 100}</p>');
    final l = ChapterLayout.layout(
      c,
      const LayoutSpec(width: 200, pageHeight: 100, padding: EdgeInsets.all(10)),
      generation: 8,
    );
    final a = c.anchor(40, 50);
    final page = l.pageForOffset(a.start);
    final boxes = l.boxes(a, page: page);
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      expect(box.generation, 8);
      expect(box.page, page);
      expect(box.rect.left, greaterThanOrEqualTo(10));
      expect(box.rect.bottom, lessThanOrEqualTo(90));
      final hit = l.hitTest(box.center, page: page);
      expect(hit.start, inInclusiveRange(a.start, a.end));
    }
    final source = l.reveal(c.anchor(a.start, a.start))!.rect.topLeft;
    expect(l.toChapter(l.toPage(source, page), page), source);
    expect(
      l.toChapter(l.toPage(source, page, localScroll: const Offset(4, 8)), page, localScroll: const Offset(4, 8)),
      source,
    );
    expect(l.reveal(a, page: page)!.rect.top, greaterThanOrEqualTo(10));
    expect(l.restore(l.capture(source.dy)), closeTo(source.dy, 1));
    paint(l);
    for (var i = 0; i < l.pages.length; i++) {
      paint(l, page: i);
    }
    l.dispose();
  });

  test('ruby decoration never enters source anchors and links target footnotes', () {
    final c = parser.parseHtml(
      'c',
      '<p>A<ruby>汉<rt>han</rt></ruby>B<a href="#note" epub:type="noteref">1</a><a href="https://example.org">web</a></p>'
          '<aside epub:type="footnote" id="note">Footnote</aside>',
    );
    final l = ChapterLayout.layout(c, const LayoutSpec(width: 500));
    expect(c.canonicalText, isNot(contains('han')));
    expect(l.pieces.first.painter!.plainText, contains('汉(han)B'));
    final b = c.canonicalText.indexOf('B');
    final box = l.boxes(c.anchor(b, b + 1)).single;
    expect(l.hitTest(box.center).start, inInclusiveRange(b, b + 1));
    final base = l.boxes(c.anchor(1, 2)).single;
    expect(base.rect.right, lessThan(box.rect.left));
    expect(l.links.length, 2);
    expect(l.links.first.footnote, isTrue);
    expect(l.target(l.links.first.target)!.start, c.elementOffsets['note']);
    expect(l.target('c#note')!.start, c.elementOffsets['note']);
    expect(l.target('other#note'), isNull);
    expect(l.target('https://example.org#note'), isNull);
    expect(l.target('#missing'), isNull);
    expect(l.target('plain'), isNull);
    paint(l);
    l.dispose();
  });

  test('nested lists, CSS boxes and unknown container metadata fallback', () {
    final c = parser.parseHtml(
      'c',
      '<section><ol start="3"><li>one<ul><li>nested</li></ul></li><li>two</li></ol></section>'
          '<p style="padding: 2px 3px 4px 5px; margin-left: 6px; width: 80%; max-width: 120px; text-indent: 1em; text-align:center">indented text</p>'
          '<pre>${'unwrapped ' * 20}</pre><hr>',
    );
    final section = c.structure.first;
    final fallback = ChapterLayout.layout(c, const LayoutSpec(width: 300));
    final styled = ChapterLayout.layout(
      c,
      const LayoutSpec(width: 300),
      resources: LayoutResources(
        containerStyles: {
          section.path: {'padding': '10px 20px', 'margin': '3px 4px 5px 6px'},
        },
      ),
    );
    expect(styled.pieces.first.rect.left - fallback.pieces.first.rect.left, 26);
    expect(styled.pieces.first.rect.top - fallback.pieces.first.rect.top, 13);
    final nested = styled.pieces.firstWhere((p) => p.block.text == 'nested' && !p.decorative);
    expect(nested.rect.left, greaterThan(styled.pieces.first.rect.left));
    expect(
      styled.pieces.where((p) => p.decorative && p.painter != null).map((p) => p.painter!.plainText),
      containsAll(['3.', '4.', '•']),
    );
    final code = styled.pieces.firstWhere((p) => p.block.kind == BlockKind.code);
    expect(code.contentWidth, greaterThan(code.viewport!.width));
    expect(code.painter!.computeLineMetrics().length, 1);
    final paragraph = styled.pieces.firstWhere((p) => p.block.text == 'indented text');
    expect(paragraph.rect.width, lessThanOrEqualTo(120));
    final anchor = c.anchor(paragraph.textStart, paragraph.textEnd);
    expect(styled.boxes(anchor), isNotEmpty);
    paint(styled, page: styled.pages.length - 1, scroll: const Offset(200, 0));
    paint(fallback);
    styled.dispose();
    fallback.dispose();
  });

  test('rowspan groups stay together, colspan occupies columns and headers repeat', () {
    final c = parser.parseHtml(
      'c',
      '<table><tr><th>head1</th><th>head2</th></tr>'
          '<tr><td rowspan="2">tall</td><td>r1</td></tr><tr><td>r2</td></tr>'
          '<tr><td colspan="2">wide</td></tr><tr><td>end1</td><td>end2</td></tr></table>',
    );
    final l = ChapterLayout.layout(
      c,
      const LayoutSpec(width: 200, pageHeight: 80),
      resources: LayoutResources(headerRows: {c.blocks.first.id: 1}),
    );
    final r1 = l.pieces.firstWhere((p) => p.painter!.plainText == 'r1');
    final r2 = l.pieces.firstWhere((p) => p.painter!.plainText == 'r2');
    expect(r1.rect.left, r2.rect.left);
    expect(l.pageForOffset(r1.textStart), l.pageForOffset(r2.textStart));
    expect(l.pages.any((p) => p.header.isNotEmpty), isTrue);
    final wide = l.pieces.firstWhere((p) => p.painter!.plainText == 'wide');
    expect(wide.viewport!.width, greaterThan(r1.viewport!.width));
    for (final p in l.pieces) {
      final boxes = l.boxes(c.anchor(p.textStart, p.textEnd));
      expect(boxes, isNotEmpty);
      expect(l.hitTest(boxes.first.center).start, inInclusiveRange(p.textStart, p.textEnd));
    }
    for (var page = 0; page < l.pages.length; page++) {
      paint(l, page: page);
    }
    final withoutHeaders = ChapterLayout.layout(c, const LayoutSpec(width: 200, pageHeight: 80));
    expect(withoutHeaders.pages.every((p) => p.header.isEmpty), isTrue);
    l.dispose();
    withoutHeaders.dispose();
  });

  test('oversized row is locally scrollable and remains a single shaped group', () {
    final c = parser.parseHtml('c', '<table><tr><td>${'long ' * 100}</td></tr></table><p>next</p>');
    final l = ChapterLayout.layout(c, const LayoutSpec(width: 120, pageHeight: 60));
    expect(l.pages.first.scrollExtent, greaterThan(60));
    expect(l.pages.length, 2);
    final anchor = c.anchor(c.blocks.first.end - 5, c.blocks.first.end);
    expect(l.boxes(anchor, page: 0), isEmpty);
    final scroll = Offset(0, l.pages.first.scrollExtent);
    final boxes = l.boxes(anchor, page: 0, localScroll: scroll);
    expect(boxes, isNotEmpty);
    expect(
      l.hitTest(boxes.first.center, page: 0, localScroll: scroll).start,
      inInclusiveRange(anchor.start, anchor.end),
    );
    paint(l, page: 0, scroll: scroll);
    l.dispose();
  });

  test('break before/after and avoid use unchanged shaped paragraphs', () {
    final c = parser.parseHtml(
      'c',
      '<p>first</p><p style="break-before:page;break-after:page">second</p>'
          '<p style="break-inside:avoid">${'third ' * 20}</p>',
    );
    final l = ChapterLayout.layout(c, const LayoutSpec(width: 200, pageHeight: 160));
    expect(l.pageForOffset(c.blocks[0].start), 0);
    expect(l.pageForOffset(c.blocks[1].start), 1);
    expect(l.pageForOffset(c.blocks[2].start), 2);
    expect(l.pieces.length, 3);
    l.dispose();
    final trailing = ChapterLayout.layout(
      parser.parseHtml('tail', '<p style="break-after:page">last</p>'),
      const LayoutSpec(width: 200),
    );
    expect(trailing.pages.length, 1);
    trailing.dispose();
  });

  test('intrinsic image dimensions and absent/invalid facts preserve bounded geometry', () {
    final c = parser.parseHtml('c', '<img src="large"><p>A<img src="inline">B</p>');
    final l = ChapterLayout.layout(
      c,
      const LayoutSpec(width: 200, pageHeight: 100),
      resources: LayoutResources(intrinsicSizes: {'large': const Size(100000, 50000), 'inline': const Size(100, 25)}),
    );
    expect(l.pieces.first.rect.size, const Size(200, 100));
    expect(l.pieces[1].artwork.single.rect.width, 100);
    final fallback = ChapterLayout.layout(
      c,
      const LayoutSpec(width: 200, pageHeight: 100),
      resources: LayoutResources(intrinsicSizes: {'large': const Size(-1, double.infinity)}),
    );
    expect(fallback.pieces.first.rect.width, lessThanOrEqualTo(200));
    expect(fallback.pieces.first.rect.height, lessThanOrEqualTo(100));
    paint(l);
    paint(fallback);
    l.dispose();
    fallback.dispose();
  });
}
