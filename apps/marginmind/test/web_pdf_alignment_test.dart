import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:marginmind/features/workspace/web_document.dart';

TranslationPage page(int number, String text) =>
    TranslationPage(number, text, [for (var i = 0; i < text.length; i++) PageRect(i.toDouble(), 20, i + 1, 10)]);

void main() {
  test('PDF relocation uses the same line joining as selection and maps back to original boxes', () {
    const text = 'before target\r\nphrase after';
    final result = alignPdfQuote('target phrase', [page(1, text)])!;
    expect(result.single.rects.first.left, text.indexOf('target'));
    expect(result.single.rects.last.right, text.indexOf(' after'));
    expect(alignPdfQuote('跨行的中文 reflow text', [page(1, '跨行的\r\n中文 \r\nre-\nflow text')]), isNotNull);
    expect(alignPdfQuote('cooperate', [page(1, 'co\u00ad\noperate')]), isNotNull);
    expect(alignPdfQuote('target phrase', [page(1, 'target\nphrase'), page(2, 'target phrase')]), isNull);
    expect(alignPdfQuote('alpha beta', [page(1, 'alpha\r\n'), page(2, 'beta')])!.map((p) => p.page), [1, 2]);
  });
}
