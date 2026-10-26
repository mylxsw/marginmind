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
    final a = page(1, header: 'Chapter 1');
    final b = page(2, header: 'Chapter 2');
    expect(buildExcerptText([a, b], [ExcerptTextSpan(1, 0, a.text.length)]).text, contains('Chapter 1'));
    final c = page(2, header: 'Chapter 1', top: 799);
    expect(buildExcerptText([a, c], [ExcerptTextSpan(1, 0, a.text.length)]).text, contains('Chapter 1'));
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
