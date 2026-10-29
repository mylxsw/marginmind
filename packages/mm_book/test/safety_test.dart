import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

import 'fixtures.dart';
import 'parsers_test.dart' show error;

void main() {
  test('font-face resources resolve from stylesheet location and block remote URLs', () {
    final diagnostics = <String>[];
    final chapter = EpubParser().parseHtml(
      'OPS/ch.xhtml',
      '<style data-mm-source="OPS/styles/book.css">@font-face {font-family:"Book";src:url(../fonts/book.otf);font-weight:700}@font-face {font-family:Remote;src:url(https://host/f.woff)}</style><p>Text</p>',
      diagnostics,
    );
    expect(chapter.fonts.single.family, 'Book');
    expect(chapter.fonts.single.resource, 'OPS/fonts/book.otf');
    expect(chapter.fonts.single.weight, '700');
    expect(diagnostics.single, startsWith('Blocked font URL:'));
    expect((Book('A', [chapter], {}, []).toJson()['spine'] as List).single['fonts'], hasLength(1));
  });
  test('MOBI links use source bytes before UTF16 normalization', () {
    final book = MobiParser().parse(mobi('<p>😀</p><p>End</p><a filepos="11">Go</a>'));
    expect(book.chapters.single.canonicalText, '😀\nEnd\nGo');
    expect(book.chapters.single.elementOffsets['pos-11'], 3);
    final kf8 = MobiParser().parse(palm(kf8Records(links: true)));
    final chapter = kf8.chapters.single;
    expect(chapter.blocks.single.runs.last.link, 'part-0.xhtml#pos-15');
    expect(chapter.elementOffsets['pos-15'], 0);
  });
  test('inline text across source nodes and CSS runs stays in one block', () {
    final chapter = EpubParser().parseHtml(
      'main',
      '<div>Hello <strong>world</strong>!<p>Next</p>Tail <em>end</em></div>',
    );
    expect(chapter.canonicalText, 'Hello world!\nNext\nTail end');
    expect(chapter.blocks.length, 3);
    expect(chapter.blocks.first.runs[1].strong, isTrue);
    expect(
      EpubParser()
          .parseHtml('main', '<p><ruby>漢<script>SECRET</script><rt>kan<script>PRIVATE</script></rt></ruby></p>')
          .canonicalText,
      '漢',
    );
    for (final block in chapter.blocks) {
      expect(chapter.canonicalText.substring(block.start, block.end), block.text);
    }
    final svg = Uint8List.fromList(utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'));
    final manifest =
        Book('SVG', [], {
              'flow-1': svg,
              'fake.svg': Uint8List.fromList([1, 2, 3]),
            }, []).toJson()['resources']
            as List;
    expect(manifest.where((r) => r['path'] == 'flow-1').single['mime'], 'image/svg+xml');
    expect(manifest.where((r) => r['path'] == 'fake.svg').single['mime'], 'application/octet-stream');
  });
  test('unified parser dispatch, copied immutable resources and cancellation', () async {
    final parser = BookParser();
    for (final ext in ['mobi', 'azw', 'azw3', 'azw4']) {
      expect((await parser.parse(SourceBytes('a.$ext', mobi('<p>A</p>')))).chapters.single.canonicalText, 'A');
    }
    expect((await parser.parse(SourceBytes('a.epub', richEpub()))).title, 'Sample');
    for (final ext in ['md', 'markdown']) {
      final result = await parser.parse(SourceBytes('a.$ext', Uint8List.fromList(utf8.encode('# Hi'))));
      expect(result.title, 'Hi');
    }
    for (final ext in ['kfx', 'xyz']) {
      await expectLater(parser.parse(SourceBytes('a.$ext', Uint8List(0))), throwsA(error(BookErrorKind.unsupported)));
    }
    await expectLater(
      parser.parse(SourceBytes('a.epub', richEpub()), cancellation: BookCancellationToken()..cancel()),
      throwsA(error(BookErrorKind.cancelled)),
    );
    final data = Uint8List.fromList([1]);
    final book = Book(
      'A',
      [],
      {'r': data},
      [],
      metadata: {
        'creator': ['A'],
      },
    );
    final revision = book.revision;
    data[0] = 2;
    expect(book.resources['r']![0], 1);
    expect(book.revision, revision);
    expect(() => book.resources['r']![0] = 4, throwsUnsupportedError);
    expect(() => book.metadata['creator']!.add('B'), throwsUnsupportedError);
  });
  test('remote placeholder, heading IDs, nested structure and source maps persist', () async {
    final book = await MarkdownBookParser().parse(
      Uint8List.fromList(utf8.encode('# Hi\n\n# Hi\n\n![alt](https://host/p.png)\n\n> quote')),
    );
    final chapter = book.chapters.single;
    expect(chapter.elementOffsets.keys, containsAll(['hi', 'hi-1']));
    expect(
      chapter.blocks.expand((b) => b.runs).where((r) => r.remoteUrl != null).single.remoteUrl,
      'https://host/p.png',
    );
    final json = book.toJson();
    expect((json['spine'] as List).single['structure'], isNotEmpty);
    expect(chapter.sourceMap.last['end'], chapter.canonicalText.length);
    expect(chapter.structure.last.tag, 'blockquote');
    final emptyAnchor = EpubParser().parseHtml('main', '<p>A</p><a id="end"></a>');
    expect(emptyAnchor.elementOffsets['end'], 1);
  });
  test('linked stylesheet cascade and archive CRC, aliases and path traversal rejection', () {
    final book = EpubParser().parse(
      richEpub(
        chapter: '<html><head><link rel="stylesheet" href="styles.css"/></head><body><p>Text</p></body></html>',
        extra: {'OPS/styles.css': utf8.encode('p {font-style:italic}')},
      ),
    );
    expect(book.chapters.single.blocks.single.runs.single.emphasis, isTrue);
    for (final path in ['%2fabsolute', '%2e%2e%2fescape', 'a\\b', '//host/file', 'https://host/a']) {
      expect(
        () => EpubParser().parse(richEpub(manifest: '<item id="c" href="$path"/>')),
        throwsA(isA<BookParseException>()),
      );
    }
    final source = richEpub();
    final corrupt = Uint8List.fromList(source);
    // Corrupt a stored central directory CRC (directory and local agree on size).
    for (var i = 0; i < corrupt.length - 46; i++) {
      if (corrupt[i] == 80 && corrupt[i + 1] == 75 && corrupt[i + 2] == 1 && corrupt[i + 3] == 2) {
        corrupt[i + 16] ^= 1;
        break;
      }
    }
    expect(() => EpubParser().parse(corrupt), throwsA(error(BookErrorKind.damaged)));
  });
  test('MOBI trailers and FONT decompress within declared bounds', () {
    final plain = utf8.encode('<p>Text</p>');
    final trailerHeader = mobiHeader(plain.length, flags: 3);
    expect(
      MobiParser()
          .parse(
            palm([
              trailerHeader,
              Uint8List.fromList([...plain, 0, 0x81]),
            ]),
          )
          .chapters
          .single
          .canonicalText,
      'Text',
    );
    expect(
      () => MobiParser().parse(
        palm([
          trailerHeader,
          Uint8List.fromList([...plain, 0x8f]),
        ]),
      ),
      throwsA(error(BookErrorKind.damaged)),
    );
    final fontData = Uint8List.fromList([0, 1, 0, 0, ...List.generate(2048, (i) => i % 256)]);
    for (final compressed in [true, false]) {
      var payload = compressed ? ZLibEncoder().encodeBytes(fontData) : Uint8List.fromList(fontData);
      final font = Uint8List(28 + payload.length);
      for (var i = 0; i < payload.length && i < 1040; i++) {
        payload[i] ^= [5, 9, 13, 17][i % 4];
      }
      magic(font, 0, 'FONT');
      u32(font, 4, fontData.length);
      u32(font, 8, compressed ? 3 : 2);
      u32(font, 12, 28);
      u32(font, 16, 4);
      u32(font, 20, 24);
      font.setRange(24, 28, [5, 9, 13, 17]);
      font.setRange(28, font.length, payload);
      expect(MobiParser().parse(mobi('<p>Text</p>', tail: [font])).resources['resource-1'], fontData);
    }
  });
  test('HUFF recursive phrase and cycle detection', () {
    final huff = huffRecords('<p>Text</p>');
    // Two dictionary slots: slot zero recursively decodes byte one to literal slot one.
    final c = Uint8List(25 + utf8.encode('<p>Text</p>').length);
    magic(c, 0, 'CDIC');
    u32(c, 4, 16);
    u32(c, 8, 2);
    u32(c, 12, 1);
    u16(c, 16, 4);
    u16(c, 18, 7);
    u16(c, 20, 1);
    c[22] = 1;
    u16(c, 23, 0x8000 | utf8.encode('<p>Text</p>').length);
    c.setRange(25, c.length, utf8.encode('<p>Text</p>'));
    // For code byte 1, a ceiling of 2 maps it to index one.
    u32(huff[0], 24 + 4, (2 << 8) | 0x88);
    final header = mobiHeader(utf8.encode('<p>Text</p>').length, compression: 0x4448, huffCount: 2, firstResource: 4);
    expect(
      MobiParser()
          .parse(
            palm([
              header,
              Uint8List.fromList([0]),
              huff[0],
              c,
            ]),
          )
          .chapters
          .single
          .canonicalText,
      'Text',
    );
    c[22] = 0;
    expect(
      () => MobiParser().parse(
        palm([
          header,
          Uint8List.fromList([0]),
          huff[0],
          c,
        ]),
      ),
      throwsA(error(BookErrorKind.damaged)),
    );
  });
  test('deterministic binary mutation corpus never leaks untyped parse errors', () {
    final random = Random(574);
    final seeds = [
      richEpub(),
      mobi('<p>Hello 😀</p>'),
      palm(kf8Records()),
      palm([
        mobiHeader(1, compression: 0x4448, huffCount: 2),
        Uint8List.fromList([0]),
        ...huffRecords('x'),
      ]),
    ];
    for (var n = 0; n < 240; n++) {
      final seed = seeds[n % seeds.length], b = Uint8List.fromList(seed);
      for (var j = 0; j < 3; j++) {
        b[random.nextInt(b.length)] = random.nextInt(256);
      }
      try {
        final book = n % seeds.length == 0 ? EpubParser().parse(b) : MobiParser().parse(b);
        for (final chapter in book.chapters) {
          for (final block in chapter.blocks) {
            expect(chapter.canonicalText.substring(block.start, block.end), block.text);
          }
        }
      } on BookParseException {
        /* expected, all other exceptions fail the test */
      }
    }
  });
}
