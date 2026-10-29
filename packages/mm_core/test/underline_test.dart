import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  var n = 0;
  late StudySetEditor editor;
  setUp(() => editor = StudySetEditor(newId: () => 'id${++n}', now: () => DateTime(2026, 10, 29)));
  const pages = [
    AnnotationPage(page: 1, rects: [PageRect(10, 100, 200, 88), PageRect(10, 80, 100, 68)]),
    AnnotationPage(page: 2, rects: [PageRect(20, 700, 210, 688)]),
  ];

  test('all styles and custom colors round-trip across lines and pages', () {
    for (final style in AnnotationLineStyle.values) {
      final (content, a) = editor.underline(
        StudySetContent.empty,
        documentId: 'pdf',
        pages: pages,
        quote: '跨行和跨页',
        colorIndex: 0x0112A4B8,
        lineStyle: style,
      );
      final restored = StudySetContent.fromJson(jsonDecode(jsonEncode(content.toJson())));
      final mark = restored.annotations.single;
      expect(mark.id, a.id);
      expect(mark.kind, AnnotationKind.underline);
      expect(mark.lineStyle, style);
      expect(mark.colorIndex, 0x0112A4B8);
      expect(mark.pages.map((p) => p.page), [1, 2]);
      expect(mark.pages.first.rects, pages.first.rects);
    }
  });

  test('legacy annotations remain highlights, including unknown future style values', () {
    final (_, a) = editor.highlight(
      StudySetContent.empty,
      documentId: 'pdf',
      pages: pages,
      quote: '原高亮',
      colorIndex: 0,
    );
    final json = a.toJson()
      ..remove('kind')
      ..remove('lineStyle');
    expect(Annotation.fromJson(json).kind, AnnotationKind.highlight);
    expect(
      Annotation.fromJson({...json, 'kind': 'future', 'lineStyle': 'future'}).lineStyle,
      AnnotationLineStyle.solid,
    );
  });

  test('same range updates one underline and keeps its card association', () {
    final (content, a) = editor.underline(
      StudySetContent.empty,
      documentId: 'pdf',
      pages: pages,
      quote: '内容',
      colorIndex: 2,
      lineStyle: AnnotationLineStyle.solid,
    );
    final (linked, card) = editor.attachCard(content, a.id);
    final (edited, changed) = editor.underline(
      linked,
      documentId: 'pdf',
      pages: pages,
      quote: '内容',
      colorIndex: 3,
      lineStyle: AnnotationLineStyle.dotted,
    );
    expect(edited.annotations, hasLength(1));
    expect(changed.id, a.id);
    expect(changed.lineStyle, AnnotationLineStyle.dotted);
    expect(edited.cardForAnnotation(changed.id)?.id, card.id);
    expect(content.annotation(a.id)?.lineStyle, AnnotationLineStyle.solid, reason: 'undo snapshot stays immutable');
  });

  test('empty text is rejected and repeating unchanged settings makes no new undo snapshot', () {
    expect(
      () => editor.underline(
        StudySetContent.empty,
        documentId: 'pdf',
        pages: pages,
        quote: ' ',
        colorIndex: 2,
        lineStyle: AnnotationLineStyle.solid,
      ),
      throwsArgumentError,
    );
    final (content, original) = editor.underline(
      StudySetContent.empty,
      documentId: 'pdf',
      pages: pages,
      quote: '文字',
      colorIndex: 2,
      lineStyle: AnnotationLineStyle.solid,
    );
    final (unchanged, repeated) = editor.underline(
      content,
      documentId: 'pdf',
      pages: pages,
      quote: '文字',
      colorIndex: 2,
      lineStyle: AnnotationLineStyle.solid,
    );
    expect(unchanged, same(content));
    expect(repeated, same(original));
  });

  test('converting a highlight preserves its identity and map link', () {
    final (content, card) = editor.createExcerpt(
      StudySetContent.empty,
      documentId: 'pdf',
      pages: pages,
      quote: '内容',
      colorIndex: 0,
    );
    final edited = editor.restyleAnnotation(
      content,
      card.annotationId!,
      colorIndex: 2,
      lineStyle: AnnotationLineStyle.wavy,
    );
    expect(edited.annotations.single.kind, AnnotationKind.underline);
    expect(edited.cardForAnnotation(card.annotationId!)?.id, card.id);
    expect(edited.annotations.single.pages.last.rects, pages.last.rects);
  });
}
