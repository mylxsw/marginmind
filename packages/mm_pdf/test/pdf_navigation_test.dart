import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';

void main() {
  const c1s1 = MMPdfOutlineItem(title: '1.1', page: 3);
  const c1s2 = MMPdfOutlineItem(title: '1.2', page: 6);
  const c1 = MMPdfOutlineItem(title: 'One', page: 2, children: [c1s1, c1s2]);
  const c2 = MMPdfOutlineItem(title: 'Two', page: 10);
  const broken = MMPdfOutlineItem(title: 'No destination', page: 0);
  const roots = [c1, broken, c2];

  group('outline', () {
    test('flattens in reading order, parents first', () {
      expect(flattenOutline(roots).map((i) => i.title), ['One', '1.1', '1.2', 'No destination', 'Two']);
    });

    test('the active section is the latest one that started', () {
      expect(activeOutlineItem(roots, 1), isNull);
      expect(activeOutlineItem(roots, 2), same(c1));
      expect(activeOutlineItem(roots, 4), same(c1s1));
      expect(activeOutlineItem(roots, 9), same(c1s2));
      expect(activeOutlineItem(roots, 10), same(c2));
      expect(activeOutlineItem(roots, 500), same(c2));
      expect(activeOutlineItem(const [], 5), isNull);
    });

    test('items on the same page: the deeper later one wins', () {
      const child = MMPdfOutlineItem(title: 'child', page: 5);
      const parent = MMPdfOutlineItem(title: 'parent', page: 5, children: [child]);
      expect(activeOutlineItem(const [parent], 5), same(child));
    });

    test('path to an item lists its ancestors', () {
      expect(outlinePathTo(roots, c1s2), [c1, c1s2]);
      expect(outlinePathTo(roots, c2), [c2]);
      expect(outlinePathTo(roots, const MMPdfOutlineItem(title: 'x', page: 1)), isEmpty);
    });

    test('items without a destination cannot be opened', () {
      expect(broken.isNavigable, isFalse);
      expect(c1.isNavigable, isTrue);
    });
  });

  group('page history', () {
    test('goes back through recorded pages, newest first', () {
      final history = PageHistory();
      expect(history.canGoBack, isFalse);
      expect(history.back(), isNull);
      history
        ..record(1)
        ..record(5)
        ..record(5);
      expect(history.canGoBack, isTrue);
      expect(history.back(), 5);
      expect(history.back(), 1);
      expect(history.canGoBack, isFalse);
    });

    test('keeps only the most recent entries', () {
      final history = PageHistory(limit: 3);
      for (var i = 1; i <= 5; i++) {
        history.record(i);
      }
      expect([history.back(), history.back(), history.back(), history.back()], [5, 4, 3, null]);
    });

    test('clear forgets everything', () {
      final history = PageHistory()..record(2);
      history.clear();
      expect(history.canGoBack, isFalse);
    });
  });
}
