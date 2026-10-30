import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('text underline restyles same source independently of quote context', () {
    var id = 0;
    final editor = StudySetEditor(newId: () => '${++id}', now: () => DateTime(2026));
    const target = TextAnchor('chapter', 0, 4, 'text', revision: 'v1', suffix: ' after');
    final (content, first) = editor.underline(
      StudySetContent.empty,
      documentId: 'book',
      textAnchors: [target],
      quote: 'text',
      colorIndex: 0,
      lineStyle: AnnotationLineStyle.solid,
    );
    final (updated, second) = editor.underline(
      content,
      documentId: 'book',
      textAnchors: [const TextAnchor('chapter', 0, 4, 'text', revision: 'v1')],
      quote: 'text',
      colorIndex: 1,
      lineStyle: AnnotationLineStyle.wavy,
    );
    expect(updated.annotations.length, 1);
    expect(second.id, first.id);
    expect(second.colorIndex, 1);
    expect(second.lineStyle, AnnotationLineStyle.wavy);
    final (stable, unchanged) = editor.underline(
      updated,
      documentId: 'book',
      textAnchors: [target],
      quote: 'text',
      colorIndex: 1,
      lineStyle: AnnotationLineStyle.wavy,
    );
    expect(stable, same(updated));
    expect(unchanged.id, first.id);
    for (final anchors in [
      [target],
      [const TextAnchor('chapter', 0, 4, 'text')],
    ]) {
      expect(
        () => editor.underline(
          updated,
          documentId: 'book',
          textAnchors: anchors,
          pages: [],
          quote: 'text',
          colorIndex: 1,
          lineStyle: AnnotationLineStyle.wavy,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => editor.underline(
        updated,
        documentId: 'book',
        textAnchors: [const TextAnchor('chapter', -1, 3, 'text', revision: 'v1')],
        quote: 'text',
        colorIndex: 1,
        lineStyle: AnnotationLineStyle.wavy,
      ),
      throwsArgumentError,
    );
    final (newRevision, _) = editor.underline(
      updated,
      documentId: 'book',
      textAnchors: [const TextAnchor('chapter', 0, 4, 'text', revision: 'v2')],
      quote: 'text',
      colorIndex: 1,
      lineStyle: AnnotationLineStyle.wavy,
    );
    expect(newRevision.annotations.length, 2);
  });
}
