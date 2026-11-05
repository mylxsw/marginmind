import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

BookChapter _chapter() => BookChapter(
  'c1',
  [
    BookBlock(id: 'h', kind: BlockKind.heading, start: 0, level: 2, runs: const [InlineRun('Title & more')]),
    BookBlock(
      id: 'p',
      kind: BlockKind.paragraph,
      start: 13,
      style: const {'text-align': 'center', 'background': 'url(http://x/y.png)'},
      runs: const [
        InlineRun('Plain '),
        InlineRun('bold', strong: true),
        InlineRun(' tail', link: 'https://e.com/?a=1&b=2'),
      ],
    ),
    BookBlock(id: 'l1', kind: BlockKind.list, start: 29, runs: const [InlineRun('one')]),
    BookBlock(id: 'l2', kind: BlockKind.list, start: 33, runs: const [InlineRun('two')]),
    BookBlock(
      id: 'i',
      kind: BlockKind.image,
      start: 37,
      resource: 'pic.png',
      runs: const [InlineRun('￼', resource: 'pic.png')],
    ),
    BookBlock(id: 'r', kind: BlockKind.rule, start: 39, runs: const []),
  ],
  elementOffsets: const {'target': 13},
);

TextAnchor _anchor(BookChapter c, int start, int end) => c.anchor(start, end, revision: 'v1');

Map<String, ArchiveFile> _files(Uint8List bytes) => {for (final f in ZipDecoder().decodeBytes(bytes).files) f.name: f};

void main() {
  final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);

  group('BookEpubWriter', () {
    Uint8List write({
      List<BookExportMark> marks = const [],
      List<BookExportNote> notes = const [],
      List<BookTocEntry>? toc,
    }) => BookEpubWriter(
      title: 'A <Book>',
      identifier: 'urn:test',
      chapters: [_chapter()],
      toc: toc ?? [BookTocEntry('t', 'Start', 'c1', 13)],
      resources: {'pic.png': (bytes: png, mime: 'image/png')},
      marks: marks,
      notes: notes,
      modified: DateTime.utc(2026),
    ).write();

    test('follows the OCF container rules', () {
      final out = write();
      final files = ZipDecoder().decodeBytes(out).files;
      expect(files.first.name, 'mimetype');
      expect(utf8.decode(files.first.content), 'application/epub+zip');
      // The name begins at a fixed offset and the entry is stored, not deflated.
      expect(ascii.decode(out.sublist(30, 38)), 'mimetype');
      expect(out[8], 0);
      expect(_files(out).keys, containsAll(['META-INF/container.xml', 'OEBPS/content.opf', 'OEBPS/nav.xhtml']));
    });

    test('its output parses back with the same text and table of contents', () {
      final book = EpubParser().parse(write());
      expect(book.chapters.single.canonicalText, contains('Title & more'));
      expect(book.chapters.single.canonicalText, contains('Plain bold tail'));
      expect(book.toc.single.title, 'Start');
      expect(book.title, 'A <Book>');
    });

    test('a mark spanning runs keeps inline formatting and every piece of text', () {
      final c = _chapter();
      final out = _files(write(marks: [BookExportMark(_anchor(c, 15, 24), rgb: 0xFFCC00)]));
      final xhtml = utf8.decode(out['OEBPS/chapter0.xhtml']!.content);
      expect(xhtml, contains('<mark style="background-color: #ffcc0066; color: inherit">ain </mark>'));
      expect(xhtml, contains('<strong><mark style="background-color: #ffcc0066; color: inherit">bold</mark></strong>'));
      expect(xhtml, contains('Pl<mark'));
      XmlProbe.parse(xhtml);
    });

    test('underlines and notes use readable markup and pop-up footnotes', () {
      final c = _chapter();
      final xhtml = utf8.decode(
        _files(
          write(
            marks: [BookExportMark(_anchor(c, 13, 18), rgb: 0x007AFF, underline: true)],
            notes: [BookExportNote(_anchor(c, 13, 18), 'first\nline <b>')],
          ),
        )['OEBPS/chapter0.xhtml']!.content,
      );
      expect(xhtml, contains('text-decoration: underline; text-decoration-color: #007aff'));
      expect(xhtml, contains('epub:type="noteref" href="#mm-note-1"'));
      expect(xhtml, contains('<aside epub:type="footnote" id="mm-note-1"><p>first<br/>line &lt;b&gt;</p></aside>'));
      XmlProbe.parse(xhtml);
    });

    test('groups list items, ships referenced images and drops unsafe style', () {
      final out = _files(write());
      final xhtml = utf8.decode(out['OEBPS/chapter0.xhtml']!.content);
      expect(RegExp('<ul>').allMatches(xhtml), hasLength(1));
      expect(xhtml, contains('src="images/0.png"'));
      expect(out['OEBPS/images/0.png'], isNotNull);
      expect(xhtml, isNot(contains('url(')));
      expect(xhtml, contains('text-align: center'));
      expect(xhtml, contains('href="https://e.com/?a=1&amp;b=2"'));
    });

    test('a missing resource leaves no broken image', () {
      final bytes = BookEpubWriter(
        title: 't',
        identifier: 'i',
        chapters: [_chapter()],
        toc: const [],
        resources: const {},
      ).write();
      final out = _files(bytes);
      expect(utf8.decode(out['OEBPS/chapter0.xhtml']!.content), isNot(contains('<img')));
      expect(utf8.decode(out['OEBPS/nav.xhtml']!.content), contains('chapter0.xhtml'));
    });

    test('internal links resolve to their block; foreign schemes are dropped', () {
      final writer = BookEpubWriter(
        title: 't',
        identifier: 'i',
        chapters: [_chapter()],
        toc: const [],
        resources: const {},
      );
      expect(writer.linkTarget('other.xhtml#target'), 'chapter0.xhtml#b13');
      expect(writer.linkTarget('javascript:alert(1)'), isNull);
      expect(writer.linkTarget('other.xhtml#unknown'), isNull);
    });
  });

  group('BookMarkdownAnnotator', () {
    const source = '# Heading\n\nSome **bold words** here and bold words again.\n\n- item one\n- item two\n';
    TextAnchor at(String quote, int start) => TextAnchor('c', start, start + quote.length, quote, revision: 'v');

    test('wraps a quote across inline syntax without altering the source', () {
      final out = BookMarkdownAnnotator(
        source,
        canonicalLength: 60,
      ).write(marks: [BookExportMark(at('bold words', 12), rgb: 0)]);
      expect(out, contains('Some **<mark>bold words</mark>** here'));
      expect(out.replaceAll('<mark>', '').replaceAll('</mark>', ''), source);
    });

    test('prefers the occurrence nearest the stored position', () {
      final out = BookMarkdownAnnotator(
        source,
        canonicalLength: 60,
      ).write(marks: [BookExportMark(at('bold words', 31), rgb: 0)]);
      expect(out, contains('here and <mark>bold words</mark> again'));
    });

    test('matches text that spans emphasis markers', () {
      final out = BookMarkdownAnnotator(
        'a **b** c\n',
        canonicalLength: 5,
      ).write(marks: [BookExportMark(at('a b c', 0), rgb: 0, underline: true)]);
      expect(out, '<u>a **b** c</u>\n');
    });

    test('notes become footnotes, after any closing mark', () {
      final quote = at('item one', 40);
      final out = BookMarkdownAnnotator(
        source,
        canonicalLength: 60,
      ).write(marks: [BookExportMark(quote, rgb: 0)], notes: [BookExportNote(quote, 'why\nthis')]);
      expect(out, contains('- <mark>item one</mark>[^1]\n'));
      expect(out, contains('[^1]: why\n    this\n'));
    });

    test('a note whose quote is gone is kept at the end with its quote', () {
      final out = BookMarkdownAnnotator(
        source,
        canonicalLength: 60,
      ).write(notes: [BookExportNote(at('not in source', 1), 'note')], unplacedHeading: 'Notes');
      expect(out, contains('## Notes\n\n> not in source[^1]'));
      expect(out, contains('[^1]: note'));
    });

    test('an unlocatable mark and an overlapping mark change nothing', () {
      final out = BookMarkdownAnnotator(source, canonicalLength: 60).write(
        marks: [
          BookExportMark(at('not in source', 1), rgb: 0),
          BookExportMark(at('item one', 40), rgb: 0),
          BookExportMark(at('item', 40), rgb: 0, underline: true),
        ],
      );
      expect(out, isNot(contains('<u>')));
      expect('<mark>'.allMatches(out), hasLength(1));
    });
  });
}

/// Exported chapters must be well-formed XML, or readers reject the whole book.
abstract final class XmlProbe {
  static void parse(String xhtml) {
    final tags = RegExp(r'<(/?)([a-zA-Z0-9:]+)[^<>]*?(/?)>');
    final stack = <String>[];
    for (final match in tags.allMatches(xhtml.substring(xhtml.indexOf('<html')))) {
      if (match.group(3) == '/') continue;
      if (match.group(1) == '/') {
        expect(stack.removeLast(), match.group(2));
      } else {
        stack.add(match.group(2)!);
      }
    }
    expect(stack, isEmpty);
  }
}
