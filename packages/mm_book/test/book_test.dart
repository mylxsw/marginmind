import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

Uint8List epub({String href = 'c.xhtml', String? extra, bool empty = false}) {
  final archive = Archive();
  void add(String name, String text) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
  }

  add('META-INF/container.xml', '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>');
  add(
    'OPS/book.opf',
    '<package><metadata><title>Book</title></metadata><manifest><item id="c" href="$href"/></manifest><spine>${empty ? '' : '<itemref idref="c"/>'}</spine></package>',
  );
  add('OPS/c.xhtml', '<h1>Title</h1><p>你好 <strong>world</strong> 👩‍💻.</p>');
  if (extra != null) add(extra, 'bad');
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  const parser = EpubParser();
  test('EPUB spine, relative resources and UTF16 offsets', () {
    final book = parser.parse(epub());
    expect(book.title, 'Book');
    final chapter = book.chapters.single;
    expect(chapter.id, 'OPS/c.xhtml');
    expect(chapter.canonicalText, 'Title\n你好 world 👩‍💻.');
    final b = chapter.blocks.last;
    expect(chapter.canonicalText.substring(b.start, b.end), b.text);
    expect(b.runs.any((r) => r.strong && r.text == 'world'), isTrue);
    final start = chapter.canonicalText.indexOf('👩');
    final anchor = chapter.anchor(start + 1, start + 2);
    expect(anchor.quote, '👩‍💻');
    expect(chapter.resolves(anchor), isTrue);
    expect(anchor.toJson()['start'], start);
    expect(chapter.resolves(TextAnchor('other', 0, 1, 'T')), isFalse);
    expect(chapter.resolves(TextAnchor(chapter.id, -1, 1, 'T')), isFalse);
    expect(chapter.resolves(TextAnchor(chapter.id, 0, 1000, 'T')), isFalse);
    expect(() => chapter.anchor(9, 1), throwsRangeError);
    expect(() => chapter.blocks.clear(), throwsUnsupportedError);
  });
  test('supported blocks, inline whitespace, code, table and images', () {
    final diagnostics = <String>[];
    final c = parser.parseHtml(
      'OPS/chapter.xhtml',
      '''
      plain<section><h2>Heading</h2><p>A <em> B</em> <code>x</code><a href="#x">link</a><br>end<img src="img.png"></p>
      <ul><li>one</li><li>two</li></ul><blockquote>quote</blockquote><pre> a\n  b</pre>
      <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
      <svg><image href="image.png"/></svg><img src="https://bad/x"><script>bad</script><p hidden>hidden</p></section>''',
      diagnostics,
    );
    expect(c.blocks.map((b) => b.kind).toSet(), containsAll(BlockKind.values));
    expect(c.canonicalText, contains('A B xlink\nend'));
    expect(c.canonicalText, contains(' a\n  b'));
    expect(c.canonicalText, contains('A\tB\n1\t2'));
    expect(c.canonicalText, isNot(contains('bad')));
    expect(c.canonicalText, isNot(contains('hidden')));
    expect(c.blocks.where((b) => b.resource != null).map((b) => b.resource), ['OPS/img.png', 'OPS/image.png']);
    expect(diagnostics, hasLength(1));
    for (final b in c.blocks) {
      expect(c.canonicalText.substring(b.start, b.end), b.text);
    }
    expect(c.blocks.first.kind, BlockKind.paragraph);
  });
  test('reject missing, dangerous and oversized archives', () {
    expect(() => parser.parse(epub(href: 'missing.xhtml')), throwsFormatException);
    expect(() => parser.parse(epub(href: '../../outside')), throwsFormatException);
    expect(() => parser.parse(epub(extra: '../escape')), throwsFormatException);
    expect(() => parser.parse(epub(extra: '/absolute')), throwsFormatException);
    expect(() => parser.parse(epub(empty: true)), throwsFormatException);
    expect(() => const EpubParser(maxBytes: 1).parse(epub()), throwsFormatException);
    expect(() => const EpubParser(maxEntries: 1).parse(epub()), throwsFormatException);
    expect(() => parser.parse(Uint8List(10)), throwsA(anything));
  });
  test('empty and grapheme boundary cases', () {
    final c = parser.parseHtml('main', '<p>é😀</p>');
    expect(c.anchor(1, 3).quote, 'é😀');
    expect(c.anchor(0, 0).quote, '');
    expect(parser.parseHtml('main', '').blocks, isEmpty);
    expect(c.resolves(const TextAnchor('main', 0, 1, 'wrong')), isFalse);
  });
  test('table image fallback remains explicit and diagnosed', () {
    final diagnostics = <String>[];
    final chapter = parser.parseHtml(
      'book/ch.xhtml',
      '<table><tr><td>cell<img src="pic.png"></td></tr></table>',
      diagnostics,
    );
    expect(chapter.blocks.map((b) => b.kind), [BlockKind.table, BlockKind.image]);
    expect(chapter.blocks.last.resource, 'book/pic.png');
    expect(diagnostics.single, contains('Table images placed after table'));
    expect(chapter.canonicalText, 'cell\n\uFFFC');
    expect(() => parser.parse(epub(extra: '%2e%2e/escape')), throwsFormatException);
  });
}
