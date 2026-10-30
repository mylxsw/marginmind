import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/selection_vocabulary_context.dart';
import 'package:mm_core/mm_core.dart';

void main() {
  TranslationParagraph pdf(String text, {int page = 1, PageRect? rect}) =>
      TranslationParagraph(documentId: 'd', page: page, index: 0, text: text, fingerprint: '', rects: [?rect]);
  test('terms strip surrounding punctuation without changing internal apostrophes', () {
    expect(selectionTerm(' “don’t” '), 'don’t');
    expect(selectionTerm('(hello world).'), 'hello world');
  });
  test('PDF geometry disambiguates repeated text on the same page', () {
    final selection = pdf('works', rect: const PageRect(0, 30, 50, 20));
    final resolved = resolveSelectionSentence([
      pdf('He works outside.', rect: const PageRect(0, 100, 80, 80)),
      pdf('Earlier. She works meticulously. Next.', rect: const PageRect(0, 40, 100, 10)),
    ], selection);
    expect(resolved.text, 'She works meticulously.');
    expect(resolved.rects, selection.rects);
    expect(resolved.page, 1);
    expect(resolveSelectionSentence([pdf('works', page: 2)], selection), same(selection));
  });
  test('reflow uses revision and exact UTF-16 offsets; CJK sentences need no space', () {
    const text = '你好。她 meticulous 地工作。下一句。';
    final offset = text.indexOf('meticulous');
    final selection = TranslationParagraph(
      documentId: 'd',
      textAnchor: TextAnchor('ch', offset, offset + 10, 'meticulous', revision: 'r'),
      index: 0,
      text: 'meticulous',
      fingerprint: '',
    );
    final paragraph = TranslationParagraph(
      documentId: 'd',
      textAnchor: const TextAnchor('ch', 0, text.length, text, revision: 'r'),
      index: 0,
      text: text,
      fingerprint: '',
    );
    final resolved = resolveSelectionSentence([paragraph], selection);
    expect(resolved.text, '她 meticulous 地工作。');
    expect(resolved.textAnchor, same(selection.textAnchor));
    final stale = TranslationParagraph(
      documentId: 'd',
      textAnchor: const TextAnchor('ch', 0, text.length, text, revision: 'old'),
      index: 0,
      text: text,
      fingerprint: '',
    );
    expect(resolveSelectionSentence([stale], selection), same(selection));
    final mismatch = TranslationParagraph(
      documentId: 'd',
      textAnchor: const TextAnchor('ch', 0, text.length, text, revision: 'r'),
      index: 0,
      text: 'bad',
      fingerprint: '',
    );
    expect(resolveSelectionSentence([mismatch], selection), same(selection));
  });
  test('no sentence delimiter retains the surrounding text', () {
    final selected = pdf('works');
    expect(resolveSelectionSentence([pdf('She works meticulously')], selected).text, 'She works meticulously');
    expect(resolveSelectionSentence([], selected), same(selected));
  });
}
