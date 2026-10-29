import 'dart:convert';
import 'dart:io';

import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('container cascade persists box, position, background and alignment in JSON', () {
    final diagnostics = <String>[];
    final chapter = const EpubParser().parseHtml(
      'main',
      '<style>section {padding:1em;color:red;text-align:center} '
          '.box {padding:2em !important;background-color:#abc} '
          '#box {padding:3em} section article {margin-left:5%;max-width:20em}</style>'
          '<section id="box" class="box" style="padding:4em;position:absolute;top:10px;left:2px;'
          'width:200px;height:300px;border:1px solid black;box-sizing:border-box">'
          '<article><p>你好 😀</p></article></section>',
      diagnostics,
    );
    final section = chapter.structure.single;
    expect(section.blockId, isNull);
    expect(section.style, {
      'padding': '2em',
      'color': 'red',
      'text-align': 'center',
      'background-color': '#abc',
      'position': 'absolute',
      'top': '10px',
      'left': '2px',
      'width': '200px',
      'height': '300px',
      'border': '1px solid black',
      'box-sizing': 'border-box',
    });
    final article = section.children.single;
    expect(article.style, {'color': 'red', 'text-align': 'center', 'margin-left': '5%', 'max-width': '20em'});
    expect(article.children.single.style, {'color': 'red', 'text-align': 'center'});
    expect(section.toJson()['style'], section.style);
    expect(chapter.blocks.single.style, article.children.single.style);
    expect(chapter.canonicalText, '你好 😀');
    expect(chapter.sourceMap.single['end'], chapter.canonicalText.length);
    expect(diagnostics, isEmpty);
    expect(() => section.style['padding'] = '0', throwsUnsupportedError);
    final style = {'margin': '1px'};
    final node = BookNode('0', 'div', null, [], style: style);
    style.clear();
    expect(node.style['margin'], '1px');
    expect(BookNode('0', 'div', null, []).style, isEmpty);
  });

  test('linked stylesheets compute container styles through the EPUB entry point', () {
    final book = const EpubParser().parse(
      richEpub(
        chapter: '<link rel="stylesheet" href="a.css"><section id="title"><p id="body">Text</p></section>',
        extra: {'OPS/a.css': utf8.encode('section {background:ivory;padding:12px;text-align:right}')},
      ),
    );
    expect(book.chapters.single.structure.single.style, {
      'background': 'ivory',
      'padding': '12px',
      'text-align': 'right',
    });
    expect(book.diagnostics, isEmpty);
  });

  test('thead td and th outside thead retain header identity, spans and offsets', () {
    final chapter = const EpubParser().parseHtml(
      'main',
      '<table><thead><tr><td colspan="2">A</td><th>B</th></tr></thead>'
          '<tbody><tr><th rowspan="2">C</th><td>D</td></tr><tr><td>E</td></tr></tbody>'
          '<tfoot><tr><td>F</td></tr></tfoot></table>',
    );
    final block = chapter.blocks.single;
    expect(block.rows.map((r) => r.map((c) => c.header).toList()).toList(), [
      [true, true],
      [true, false],
      [false],
      [false],
    ]);
    expect(block.rows.first.first.colSpan, 2);
    expect(block.rows[1].first.rowSpan, 2);
    expect(chapter.canonicalText, 'A\tB\nC\tD\nE\nF');
    for (final entry in chapter.sourceMap) {
      expect(
        chapter.canonicalText.substring(entry['start'] as int, entry['end'] as int),
        isIn(['A', 'B', 'C', 'D', 'E', 'F']),
      );
    }
    final book = Book('', [chapter], {}, []);
    final json = (book.toJson()['spine'] as List).single['blocks'][0]['rows'] as List;
    expect(json.first[0]['header'], isTrue);
    expect(json[1][1]['header'], isFalse);
    expect(BookCell([]).header, isFalse);
  });

  test('Markdown tables preserve headers through the shared HTML adapter', () async {
    final book = await const MarkdownBookParser().parse(utf8.encode('|A|B|\n|-|-|\n|1|2|'));
    final rows = book.chapters.single.blocks.single.rows;
    expect(rows.first.every((c) => c.header), isTrue);
    expect(rows.last.any((c) => c.header), isFalse);
  });

  test('hidden table sections, rows and cells never become readable headers', () {
    final chapter = const EpubParser().parseHtml(
      'main',
      '<table><thead hidden><tr><th>hidden head</th></tr></thead><tbody>'
          '<tr style="display:none"><th>hidden row</th></tr>'
          '<tr><th hidden>hidden cell</th><td>visible</td></tr></tbody></table>',
    );
    expect(chapter.canonicalText, 'visible');
    expect(chapter.blocks.single.rows.single.single.header, isFalse);
    expect(chapter.sourceMap.single['start'], 0);
  });

  test('background URL declarations remain blocked without affecting text', () {
    final diagnostics = <String>[];
    final chapter = const EpubParser().parseHtml(
      'main',
      '<section style="background:URL(https://host/img);background-color:ivory"><p>Text</p></section>',
      diagnostics,
    );
    expect(chapter.structure.single.style, {'background-color': 'ivory'});
    expect(diagnostics, ['Unsupported CSS declaration: background']);
    expect(chapter.canonicalText, 'Text');
  });

  test('version 1 JSON fixture matches the parser contract and revision', () {
    final book = const EpubParser().parse(contractEpub());
    expect(book.toJson(), jsonDecode(File('test/fixtures/book-v1.json').readAsStringSync()));
    expect(book.diagnostics, isEmpty);
    expect(book.resourceManifest['OPS/a.png']!.width, 1);
  });
}
