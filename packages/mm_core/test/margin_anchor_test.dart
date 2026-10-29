import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  const first = AnnotationPage(page: 1, rects: [PageRect(20, 700, 200, 688), PageRect(20, 682, 220, 670)]);
  test('contiguous paragraph and area keep original PDF anchor', () {
    final result = marginAnchor([first], 'one paragraph');
    expect(result.anchor!.pages.first.rects, first.rects);
    expect(result.anchor!.quote, 'one paragraph');
    expect(result.lineY, isNull);
    expect(marginAnchor([first], '').anchor!.quote, '');
  });
  test('cross paragraph, gaps and pages degrade to original first line', () {
    expect(marginAnchor([first], 'first\n\nsecond').lineY, 700);
    expect(
      marginAnchor([
        first,
        const AnnotationPage(page: 2, rects: [PageRect(20, 700, 200, 688)]),
      ], 'both').lineY,
      700,
    );
    expect(
      marginAnchor([
        const AnnotationPage(page: 1, rects: [PageRect(20, 700, 200, 688), PageRect(20, 640, 200, 628)]),
      ], 'both').anchor,
      isNull,
    );
    expect(() => marginAnchor([], ''), throwsArgumentError);
    expect(() => marginAnchor([const AnnotationPage(page: 1, rects: [])], ''), throwsArgumentError);
  });
}
