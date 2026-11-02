import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_reflow/mm_reflow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = EpubParser();

  test('mixed font metrics produce one connected underline per line', () {
    final chapter = parser.parseHtml(
      'mixed',
      '<p>${'中文<span style="font-size:0.75em"> Agent Session </span>内容 ' * 8}</p>',
    );
    for (final width in [240.0, 420.0]) {
      final layout = ChapterLayout.layout(
        chapter,
        LayoutSpec(width: width, pageHeight: 120, padding: const EdgeInsets.all(10)),
      );
      final anchor = chapter.anchor(1, chapter.canonicalText.length - 2);
      final tight = layout.boxes(anchor);
      final lines = layout.boxes(anchor, forUnderline: true);
      // Reproduces the old behavior even when the test font covers both scripts:
      // the smaller inline font has a different selection-box bottom.
      expect(tight.map((b) => b.rect.bottom).toSet().length, greaterThan(lines.length));
      expect(lines.length, layout.pieces.single.painter!.computeLineMetrics().length);
      expect(lines.first.rect.left, closeTo(tight.first.rect.left, .01));
      expect(lines.last.rect.right, closeTo(tight.last.rect.right, .01));
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].rect.top, greaterThanOrEqualTo(lines[i - 1].rect.bottom - .01));
      }
      for (var page = 0; page < layout.pages.length; page++) {
        final visible = layout.boxes(anchor, page: page, forUnderline: true);
        expect(visible, isNotEmpty);
        for (final box in visible) {
          expect(box.rect.top, greaterThanOrEqualTo(10));
          expect(box.rect.bottom, lessThanOrEqualTo(110));
          expect(box.page, page);
        }
      }
      layout.dispose();
    }
  });

  test('underlines preserve gaps for unselected bidi text and ruby decorations', () {
    for (final html in ['<p>abc אבג def</p>', '<p>A<ruby>汉<rt>han</rt></ruby>B</p>']) {
      final chapter = parser.parseHtml('gaps', html);
      final layout = ChapterLayout.layout(chapter, const LayoutSpec(width: 500));
      final anchor = chapter.anchor(0, html.contains('ruby') ? chapter.canonicalText.length : 5);
      final tight = layout.boxes(anchor);
      expect(tight, hasLength(greaterThan(1)));
      final sorted = tight.map((b) => b.rect).toList()..sort((a, b) => a.left.compareTo(b.left));
      final gap = Rect.fromLTRB(sorted.first.right, sorted.first.top, sorted.last.left, sorted.first.bottom);
      expect(gap.width, greaterThan(0));
      final lines = layout.boxes(anchor, forUnderline: true);
      expect(lines.length, greaterThan(1));
      for (final box in lines) {
        expect(box.rect.left < gap.center.dx && box.rect.right > gap.center.dx, isFalse);
      }
      layout.dispose();
    }
  });

  test('underlines never join separate table cells', () {
    final chapter = parser.parseHtml('cells', '<table><tr><td>中文 Agent</td><td>Session 内容</td></tr></table>');
    final layout = ChapterLayout.layout(chapter, const LayoutSpec(width: 500));
    final boxes = layout.boxes(chapter.anchor(0, chapter.canonicalText.length), forUnderline: true);
    expect(boxes, hasLength(2));
    expect(boxes.first.rect.right, lessThan(boxes.last.rect.left));
    layout.dispose();
  });
}
