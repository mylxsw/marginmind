import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

TranslationPage page(String text, {int number = 1, double shift = 0}) {
  var x = 40.0, y = 700.0;
  final boxes = <PageRect>[];
  for (final c in text.split('')) {
    if (c == '\n') {
      boxes.add(PageRect(x, y, x, y));
      x = 40;
      y -= 24;
    } else {
      boxes.add(PageRect(x, y + shift, x + 8, y - 16 + shift));
      x += 8;
    }
  }
  return TranslationPage(number, text, boxes);
}

void main() {
  test('headings keep their role while body and page footer remain distinct', () {
    final raw = page('Title\n\nBody.\n\n1');
    final boxes = raw.boxes.toList();
    boxes[boxes.length - 1] = const PageRect(290, 50, 298, 34);
    final result = splitTranslationParagraphs('doc', [TranslationPage(1, raw.text, boxes)]);
    expect(result.map((p) => p.text), ['Title', 'Body.']);
    expect(result.first.heading, true);
    expect(result.last.heading, false);
  });
  test('PDFium zero-space boxes and differing glyph heights do not split words', () {
    const text = 'Learning and Memory.';
    final p = TranslationPage(1, text, [
      for (var i = 0; i < text.length; i++)
        text[i] == ' ' ? const PageRect(0, 0, 0, 0) : PageRect(40 + i * 8, i.isEven ? 700 : 696, 48 + i * 8, 684),
    ]);
    expect(splitTranslationParagraphs('doc', [p]).single.text, text);
  });
  test('wraps lines, separates paragraphs, headings and pages; stable digest', () {
    final pages = [page('Heading\n\nOne line\ncontinues here.\n\nRepeated.\n\nRepeated.'), page('中文段落。', number: 2)];
    final paragraphs = splitTranslationParagraphs('doc', pages);
    expect(paragraphs.map((p) => p.text), ['Heading', 'One line continues here.', 'Repeated.', 'Repeated.', '中文段落。']);
    expect(paragraphs[1].rects.length, 2);
    expect(paragraphs[1].bounds, const PageRect(40, 652, 160, 612));
    expect(paragraphs.last.page, 2);
    expect(paragraphs.map((p) => p.index), [0, 1, 2, 3, 4]);
    expect(paragraphs[2].fingerprint, isNot(paragraphs[3].fingerprint));
    expect(splitTranslationParagraphs('doc', pages).map((p) => p.fingerprint), paragraphs.map((p) => p.fingerprint));
    expect(() => paragraphs.first.rects.clear(), throwsUnsupportedError);
  });
  test('content, document and OCR geometry invalidate fingerprints; empty scans skipped', () {
    final original = splitTranslationParagraphs('doc', [page('Hello')]).single;
    expect(splitTranslationParagraphs('other', [page('Hello')]).single.fingerprint, isNot(original.fingerprint));
    expect(splitTranslationParagraphs('doc', [page('Hallo')]).single.fingerprint, isNot(original.fingerprint));
    expect(
      splitTranslationParagraphs('doc', [page('Hello', shift: 1)]).single.fingerprint,
      isNot(original.fingerprint),
    );
    expect(splitTranslationParagraphs('doc', [TranslationPage(1, '', []), TranslationPage(2, 'scan', [])]), isEmpty);
    expect(splitTranslationParagraphs('doc', [page('  Hello  ')]).single.text, 'Hello');
  });
  test('visual line breaks without newline and indentation split', () {
    final p = TranslationPage(1, 'FirstSecondThird', [
      for (var i = 0; i < 5; i++) PageRect(40 + i * 8, 700, 48 + i * 8, 684),
      for (var i = 0; i < 6; i++) PageRect(40 + i * 8, 676, 48 + i * 8, 660),
      for (var i = 0; i < 5; i++) PageRect(90 + i * 8, 640, 98 + i * 8, 624),
    ]);
    expect(splitTranslationParagraphs('doc', [p]).map((p) => p.text), ['First Second', 'Third']);
  });
}
