import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

Matcher error(BookErrorKind kind) => isA<BookParseException>().having((e) => e.kind, 'kind', kind);
void main() {
  const epub = EpubParser();
  const mobiParser = MobiParser();
  test('EPUB 3 nav and EPUB 2 NCX resolve canonical UTF16 offsets', () {
    for (final nav in [true, false]) {
      final book = epub.parse(richEpub(nav: nav));
      expect(book.toc.single.offset, 0);
      expect(book.toc.single.children.single.offset, 6);
      expect(book.chapters.single.canonicalText, 'Title\n你好 😀');
      expect(book.metadata['creator'], ['Author']);
      expect(book.revision, hasLength(64));
      expect(book.toJson()['normalizationVersion'], 1);
      expect(book.revision, epub.parse(richEpub(nav: nav)).revision);
      expect(book.chapters.single.sourceMap, isNotEmpty);
    }
  });
  test('fixed layout viewport and absolute boxes survive in IR', () {
    final book = epub.parse(
      richEpub(
        layout: 'pre-paginated',
        chapter: '<html><head><meta name="viewport" content="width=600,height=800"/></head><body><p style="position:absolute;top:20px;left:10px">Fixed</p></body></html>',
      ),
    );
    expect(book.fixedLayout, isTrue);
    expect(book.chapters.single.viewportWidth, 600);
    expect(book.chapters.single.viewportHeight, 800);
    expect(book.chapters.single.blocks.single.style['position'], 'absolute');
  });
  test('EPUB DRM differs from both supported font obfuscations', () {
    String encryption(String algorithm) =>
        '<encryption><EncryptedData><EncryptionMethod Algorithm="$algorithm"/><CipherData><CipherReference URI="OPS/font.otf"/></CipherData></EncryptedData></encryption>';
    expect(() => epub.parse(richEpub(encryption: encryption('aes'))), throwsA(error(BookErrorKind.drm)));
    final original = Uint8List.fromList([0, 1, 0, 0, ...List.generate(1500, (i) => i % 256)]);
    for (final adobe in [true, false]) {
      final key = adobe
          ? [for (var i = 0; i < 16; i++) i * 17]
          : sha1.convert(utf8.encode('urn:uuid:00112233-4455-6677-8899-aabbccddeeff')).bytes;
      final data = Uint8List.fromList(original);
      for (var i = 0; i < (adobe ? 1024 : 1040); i++) {
        data[i] ^= key[i % key.length];
      }
      final book = epub.parse(
        richEpub(
          encryption: encryption(adobe ? 'http://ns.adobe.com/pdf/enc#RC' : 'http://www.idpf.org/2008/embedding'),
          extra: {'OPS/font.otf': data},
        ),
      );
      expect(book.resources['OPS/font.otf'], original);
      expect((book.toJson()['resources'] as List).where((r) => r['path'] == 'OPS/font.otf').single['mime'], 'font/otf');
    }
  });
  test('CSS cascade, inheritance, unsupported diagnostics, whitespace, ruby and footnotes', () {
    final diagnostics = <String>[];
    final c = epub.parseHtml(
      'main',
      '''<style>p {color:red} .a {color:blue !important} #x {color:green} section p {font-weight:bold} p:hover {color:black} .hidden {display:none}</style><section style="font-family:serif"><p id="x" class="a" style="color:yellow">A <ruby>漢<rt>kan</rt></ruby><a epub:type="noteref" href="#fn">1</a></p><p class="hidden">SECRET</p><aside id="fn" epub:type="footnote">note</aside><hr><pre> a\r\n  b</pre><p style="display:flex;float:left">visible</p></section>''',
      diagnostics,
    );
    expect(c.blocks.first.style['color'], 'blue');
    expect(c.blocks.first.style['font-family'], 'serif');
    expect(c.blocks.first.runs.every((r) => r.strong), isTrue);
    expect(c.blocks.first.runs.where((r) => r.ruby != null).single.ruby, 'kan');
    expect(c.blocks.first.runs.last.footnoteRef, '#fn');
    expect(c.canonicalText, isNot(contains('SECRET')));
    expect(c.canonicalText, contains('A 漢1\nnote\n\n a\n  b\nvisible'));
    expect(c.blocks.map((b) => b.kind), containsAll([BlockKind.rule, BlockKind.footnote]));
    expect(diagnostics, hasLength(3));
    for (final m in c.sourceMap) {
      expect((m['end'] as int) <= c.canonicalText.length, isTrue);
    }
  });
  test('table spans, nested lists and safe links', () {
    final c = epub.parseHtml(
      'main',
      '<ol start="3"><li>one<ul><li>two</li></ul></li></ol><table><tr><td rowspan="2" colspan="3">A<img src="a.png"></td></tr></table><p><a href="javascript:alert(1)">safe</a></p>',
    );
    expect(c.canonicalText, 'one\ntwo\nA\uFFFC\nsafe');
    expect(c.blocks.where((b) => b.kind == BlockKind.table).single.rows.single.single.rowSpan, 2);
    expect(c.blocks.last.runs.single.link, isNull);
  });
  test('Markdown imports relative images once and never requests remote URLs', () async {
    final seen = <String>[];
    final book = await const MarkdownBookParser().parse(
      Uint8List.fromList(
        utf8.encode(
          '# 标题\n\nHello **world**\n\n![a](img/a.png) ![b](img/a.png) ![c](https://host/a.png)\n\n|A|B|\n|-|-|\n|1|2|',
        ),
      ),
      sourcePath: 'notes/book.md',
      resolver: (p) async {
        seen.add(p);
        return Uint8List.fromList([137, 80, 78, 71]);
      },
    );
    expect(seen, ['img/a.png']);
    expect(book.resources.keys.single, matches(r'^images/[a-f0-9]{64}\.png$'));
    expect(
      book.chapters.single.blocks.expand((b) => b.runs).where((r) => r.resource != null).map((r) => r.resource).toSet(),
      book.resources.keys.toSet(),
    );
    expect(book.chapters.single.id, 'main');
    expect(book.toc.single.title, '标题');
    expect(book.diagnostics.single, startsWith('Blocked image URL:'));
    expect(book.chapters.single.canonicalText, contains('Hello world'));
    expect(book.chapters.single.blocks.where((b) => b.kind == BlockKind.table), hasLength(1));
  });
  test('Markdown missing resources, invalid utf8, traversal, limits and cancellation', () async {
    Future<Book> parse(String s, {BookCancellationToken? token}) =>
        const MarkdownBookParser().parse(Uint8List.fromList(utf8.encode(s)), cancellation: token);
    expect((await parse('![a](missing.png)')).diagnostics.single, startsWith('Missing image:'));
    expect((await parse('![a](../secret.png)')).diagnostics.single, startsWith('Missing image:'));
    await expectLater(
      const MarkdownBookParser().parse(Uint8List.fromList([255])),
      throwsA(error(BookErrorKind.damaged)),
    );
    await expectLater(
      const MarkdownBookParser(maxBytes: 1).parse(Uint8List(2)),
      throwsA(error(BookErrorKind.limitExceeded)),
    );
    await expectLater(parse('x', token: BookCancellationToken()..cancel()), throwsA(error(BookErrorKind.cancelled)));
    final token = BookCancellationToken();
    await expectLater(
      const MarkdownBookParser().parse(
        Uint8List.fromList(utf8.encode('![a](a.png)')),
        cancellation: token,
        resolver: (_) async {
          token.cancel();
          return Uint8List(1);
        },
      ),
      throwsA(error(BookErrorKind.cancelled)),
    );
  });
  test('MOBI6 metadata, UTF8, Windows1252, resources and filepos links', () {
    final book = mobiParser.parse(
      mobi(
        '<p>Hello 😀<img recindex="1"/><a filepos="0">Start</a></p>',
        tail: [
          Uint8List.fromList([137, 80, 78, 71]),
        ],
      ),
    );
    expect(book.title, 'Title');
    expect(book.metadata['creator'], ['Author']);
    expect(book.chapters.single.canonicalText, 'Hello 😀\uFFFCStart');
    expect(book.chapters.single.blocks.single.runs.last.link, 'part-0.xhtml#pos-0');
    expect(book.resources.keys, ['resource-1']);
    expect(mobiParser.parse(mobi('<p>\u0080</p>', encoding: 1252)).chapters.single.canonicalText, '€');
  });
  test('PalmDOC literal runs, space shortcuts and overlapping backreferences', () {
    final book = mobiParser.parse(mobi('AAAAAA A', compression: 2, compressed: [1, 65, 0x80, 0x0a, 0xc1]));
    expect(book.chapters.single.canonicalText, 'AAAAAA A');
    for (final data in [
      [8],
      [0x80],
      [0x80, 0],
      [0x80, 8],
    ]) {
      expect(
        () => mobiParser.parse(mobi('x', compression: 2, compressed: data)),
        throwsA(error(BookErrorKind.damaged)),
      );
    }
  });
  test('HUFF/CDIC reconstructs literal phrases', () {
    const source = '<p>HUFF 你好</p>';
    final bytes = palm([
      mobiHeader(utf8.encode(source).length, compression: 0x4448, huffCount: 2, firstResource: 4),
      Uint8List.fromList([0]),
      ...huffRecords(source),
    ]);
    expect(mobiParser.parse(bytes).chapters.single.canonicalText, 'HUFF 你好');
  });
  test('KF8 reconstructs skeleton and fragment, FDST resources and hybrid prefers KF8', () {
    for (final flows in [true, false]) {
      final book = mobiParser.parse(palm(kf8Records(flows: flows)));
      expect(book.chapters.single.canonicalText, 'Hello 😀\uFFFC');
      expect(book.resources.keys, contains('resource-1'));
      if (flows) expect(book.resources.keys, contains('flow-1'));
    }
    final old = Uint8List.fromList(utf8.encode('<p>OLD</p>'));
    final modern = kf8Records();
    final hybrid = palm([
      mobiHeader(old.length, boundary: 3),
      old,
      Uint8List.fromList(ascii.encode('BOUNDARY')),
      ...modern,
    ]);
    expect(mobiParser.parse(hybrid).chapters.single.canonicalText, 'Hello 😀\uFFFC');
    expect(() => mobiParser.parse(palm(kf8Records(badFragment: true))), throwsA(error(BookErrorKind.damaged)));
  });
  test('AZW4 extracts the indexed PDF payload', () {
    final pdf = ascii.encode('%PDF-1.7\n%%EOF');
    final raw = Uint8List(20 + pdf.length);
    magic(raw, 0, '%MOP');
    u32(raw, 4, 1);
    u32(raw, 8, 1);
    u32(raw, 12, 20);
    u32(raw, 16, pdf.length);
    raw.setRange(20, raw.length, pdf);
    final book = mobiParser.parse(palm([mobiHeader(raw.length, type: 248), raw]));
    expect(book.pdf, pdf);
    expect(book.chapters, isEmpty);
    expect(book.toJson()['pdfSha256'], hasLength(64));
  });
  test('MOBI typed failures and bounded record parsing', () {
    expect(() => mobiParser.parse(mobi('x', encryption: 1)), throwsA(error(BookErrorKind.drm)));
    expect(() => mobiParser.parse(Uint8List.fromList(ascii.encode('CONT'))), throwsA(error(BookErrorKind.unsupported)));
    expect(() => mobiParser.parse(mobi('x', compression: 3)), throwsA(error(BookErrorKind.unsupported)));
    expect(() => mobiParser.parse(mobi('x', version: 9)), throwsA(error(BookErrorKind.unsupported)));
    expect(() => mobiParser.parse(mobi('x', version: 8)), throwsA(error(BookErrorKind.unsupported)));
    expect(() => const MobiParser(maxRecords: 1).parse(mobi('x')), throwsA(error(BookErrorKind.limitExceeded)));
    expect(() => const MobiParser(maxBytes: 1).parse(mobi('x')), throwsA(error(BookErrorKind.limitExceeded)));
    final bytes = mobi('x');
    u32(bytes, 78, 0);
    expect(() => mobiParser.parse(bytes), throwsA(error(BookErrorKind.damaged)));
    for (var i = 0; i < 600; i++) {
      final b = mobi('content');
      if (i < b.length) {
        expect(() => mobiParser.parse(Uint8List.sublistView(b, 0, i)), throwsA(isA<BookParseException>()));
      }
    }
  });
}
