import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/src/excerpt_text.dart';

ExcerptPageText page(
  int number, {
  String header = '26/10/2026, 09:20',
  String? footer,
  double top = 785,
  List<String> body = const ['中文硬换行', '接下去 English', 'wrapped text'],
  List<double> ys = const [700, 680, 660],
}) {
  final texts = [header, ...body, footer ?? 'file:///book.html $number/301'];
  final positions = [top, ...ys, 40.0];
  return ExcerptPageText(
    page: number,
    height: 800,
    text: texts.join('\n'),
    rects: [
      for (var row = 0; row < texts.length; row++) ...[
        for (var i = 0; i < texts[row].length; i++)
          PageRect(30 + i * 8, positions[row], 38 + i * 8, positions[row] - 10),
        if (row != texts.length - 1) PageRect(0, 0, 0, 0),
      ],
    ],
  );
}

ExcerptPageText reorder(ExcerptPageText source, List<int> order) {
  final rows = RegExp(r'[^\n]+').allMatches(source.text).toList();
  return ExcerptPageText(
    page: source.page,
    height: source.height,
    text: order.map((i) => rows[i][0]!).join('\n'),
    rects: [
      for (var n = 0; n < order.length; n++) ...[
        ...source.rects.sublist(rows[order[n]].start, rows[order[n]].end),
        if (n < order.length - 1) const PageRect(0, 0, 0, 0),
      ],
    ],
  );
}

void main() {
  test('joins Chinese, English, mixed scripts, punctuation, CRLF and paragraphs', () {
    for (final entry in {
      '中文\n换行': '中文换行',
      'hello\nworld': 'hello world',
      '中文\nEnglish\n继续': '中文English继续',
      'word\n中文': 'word中文',
      '中文，\n继续。': '中文，继续。',
      'one\r\ntwo\rthree': 'one two three',
      'first line\nwrapped\n \nsecond\nparagraph': 'first line wrapped\n\nsecond paragraph',
      '  \n ': '',
      'one\n\n\nthree': 'one\n\nthree',
    }.entries) {
      expect(joinExcerptLines(entry.key), entry.value);
    }
  });
  test('keeps the space the text already has between a Latin word and Chinese', () {
    for (final entry in {
      'Ebbinghaus \n在 1885 年': 'Ebbinghaus 在 1885 年',
      'Ebbinghaus\n 在 1885 年': 'Ebbinghaus 在 1885 年',
      '发表于 \n1885 年': '发表于 1885 年',
      '发表于\n1885 年': '发表于1885 年',
      '中文 \n继续': '中文继续',
      '中文\n 继续': '中文继续',
      'Ebbinghaus\n在': 'Ebbinghaus在',
    }.entries) {
      expect(joinExcerptLines(entry.key), entry.value);
    }
  });
  test('dehyphenates broken words and discretionary hyphens; keeps explicit punctuation', () {
    expect(joinExcerptLines('inter\u0002national'), 'international');
    expect(joinExcerptLines('inter-\nnational cooper\u00ad\nation'), 'international cooperation');
    expect(joinExcerptLines('A-\nB 5-\n10 end-\nStart'), 'A- B 5- 10 end- Start');
  });
  test('merges words in a line but preserves columns, next lines and invalid geometry', () {
    final rects = excerptLineRects(const [
      PageRect(30, 700, 60, 690),
      PageRect(75, 700, 110, 690),
      PageRect(300, 700, 350, 690),
      PageRect(30, 680, 90, 670),
      PageRect(0, 0, 0, 0),
    ]);
    expect(rects, const [PageRect(30, 700, 110, 690), PageRect(300, 700, 350, 690), PageRect(30, 680, 90, 670)]);
    expect(excerptLineRects([]), isEmpty);
  });
  test('removes repeating dates, paths and changing page numbers from text AND boxes', () {
    final a = page(1), b = page(2);
    final result = buildExcerptText(
      [b, a],
      [ExcerptTextSpan(2, 0, b.text.length), ExcerptTextSpan(1, 0, a.text.length)],
    );
    expect(result.text, '中文硬换行接下去 English wrapped text中文硬换行接下去 English wrapped text');
    expect(result.pages.map((p) => p.page), [1, 2]);
    expect(
      result.pages.every((p) => p.rects.length == 3 && p.rects.every((r) => r.top <= 700 && r.bottom >= 650)),
      isTrue,
    );
  });
  test('neighbour evidence works with partial selection and header-only selection stays empty', () {
    final a = page(1), b = page(2);
    final start = a.text.indexOf('硬');
    final end = a.text.indexOf('English') + 7;
    final result = buildExcerptText([a, b], [ExcerptTextSpan(1, start, end)]);
    expect(result.text, '硬换行接下去 English');
    expect(result.pages.single.rects, hasLength(2));
    expect(buildExcerptText([a, b], [ExcerptTextSpan(1, 0, a.text.indexOf('\n'))]).text, isEmpty);
    expect(buildExcerptText([a, b], []).pages, isEmpty);
  });
  test('fallback keeps unconfirmed and body-like first/last lines', () {
    final a = page(1, footer: 'Unique footer');
    final b = page(2, header: 'Different header', footer: 'Other footer');
    final single = buildExcerptText([a], [ExcerptTextSpan(1, 0, a.text.length)]);
    expect(single.text, contains('26/10/2026'));
    expect(single.text, contains('Unique footer'));
    final different = buildExcerptText([a, b], [ExcerptTextSpan(1, 0, a.text.length)]);
    expect(different.text, contains('26/10/2026'));
    for (final top in [700.0, 735.0, 785.0]) {
      final c = page(3, top: top, body: ['body'], ys: [top - 15]);
      final d = page(4, top: top, body: ['body'], ys: [top - 15]);
      expect(buildExcerptText([c, d], [ExcerptTextSpan(3, 0, c.text.length)]).text, contains('26/10/2026'));
    }
    final short = page(1, body: [], ys: []);
    expect(buildExcerptText([short], [ExcerptTextSpan(1, 0, short.text.length)]).text, contains('26/10/2026'));
  });
  test('does not normalize digits in distinct chapter titles or mismatched margin positions', () {
    final chineseA = page(1, header: '第 1 章');
    final chineseB = page(2, header: '第 2 章');
    expect(
      buildExcerptText([chineseA, chineseB], [ExcerptTextSpan(1, 0, chineseA.text.length)]).text,
      contains('第 1 章'),
    );
    final pageA = page(1, header: '第 1 页');
    final pageB = page(2, header: '第 2 页');
    expect(buildExcerptText([pageA, pageB], [ExcerptTextSpan(1, 0, pageA.text.length)]).text, isNot(contains('第 1 页')));
    final a = page(1, header: 'Chapter 1');
    final b = page(2, header: 'Chapter 2');
    expect(buildExcerptText([a, b], [ExcerptTextSpan(1, 0, a.text.length)]).text, contains('Chapter 1'));
    final c = page(2, header: 'Chapter 1', top: 799);
    expect(buildExcerptText([a, c], [ExcerptTextSpan(1, 0, a.text.length)]).text, contains('Chapter 1'));
  });

  test('geometric extremes identify margins drawn after or between body runs', () {
    for (final order in [
      [1, 2, 3, 0, 4],
      [4, 1, 0, 2, 3],
      [1, 4, 2, 0, 3],
    ]) {
      final a = reorder(page(1), order), b = reorder(page(2), order);
      final result = buildExcerptText([a, b], [ExcerptTextSpan(1, 0, a.text.length)]);
      expect(result.text, '中文硬换行接下去 English wrapped text');
      expect(result.pages.single.rects, hasLength(3));
    }
  });
  test('edge page numbers follow PDF page differences, including offsets and gaps', () {
    for (final title in [(int n) => '$n  Book Title', (int n) => 'Book Title  $n']) {
      for (final delta in [1, 3]) {
        final a = page(4, header: title(12));
        final b = page(4 + delta, header: title(12 + delta));
        final result = buildExcerptText([b, a], [ExcerptTextSpan(4, 0, a.text.length)]);
        expect(result.text, isNot(contains('Book Title')));
        expect(result.pages.single.rects, hasLength(3));
        final wrong = page(4 + delta, header: title(12 + delta + 1));
        expect(buildExcerptText([a, wrong], [ExcerptTextSpan(4, 0, a.text.length)]).text, contains('Book Title'));
      }
    }
  });
  test('browser footer compares page numerator and preserves other URL digits and totals', () {
    for (final scheme in ['http', 'https', 'file']) {
      final a = page(5, footer: '$scheme://example.test/book2 3/12');
      final b = page(7, footer: '$scheme://example.test/book2 5/12');
      expect(buildExcerptText([a, b], [ExcerptTextSpan(5, 0, a.text.length)]).text, isNot(contains(scheme)));
      for (final footer in [
        '$scheme://example.test/book2 4/12',
        '$scheme://example.test/book2 5/13',
        '$scheme://example.test/book3 5/12',
      ]) {
        final other = page(7, footer: footer);
        expect(buildExcerptText([a, other], [ExcerptTextSpan(5, 0, a.text.length)]).text, contains(scheme));
      }
    }
  });
  test('different titles and embedded digits are not treated as page numbers', () {
    for (final headers in [
      ('12 Book One', '13 Book Two'),
      ('Book 12 Title', 'Book 13 Title'),
      ('Chapter 12', 'Chapter 13'),
      ('第12章', '第13章'),
    ]) {
      final a = page(1, header: headers.$1), b = page(2, header: headers.$2);
      expect(buildExcerptText([a, b], [ExcerptTextSpan(1, 0, a.text.length)]).text, contains(headers.$1));
    }
  });
  test('retains paragraph spacing inferred from geometric gaps', () {
    final a = page(1, ys: [700, 680, 630]);
    final result = buildExcerptText([a, page(2)], [ExcerptTextSpan(1, 0, a.text.length)]);
    expect(result.text, '中文硬换行接下去 English\n\nwrapped text');
  });
  test('empty and inconsistent text geometry cannot create malformed annotations', () {
    expect(buildExcerptText([], []).text, '');
    const a = ExcerptPageText(page: 1, height: 0, text: 'abc', rects: []);
    expect(buildExcerptText([a], [ExcerptTextSpan(1, 0, 3)]).pages, isEmpty);
  });
}
