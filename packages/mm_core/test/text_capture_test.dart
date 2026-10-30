import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('capture parameters survive annotation serialization and recoloring', () {
    final capture = TextCapture(
      width: 80,
      height: 90,
      fontSize: 18,
      lineHeight: 1.6,
      viewportWidth: 640,
      pixelRatio: 2,
    );
    final anchor = TextAnchor('main', 0, 4, 'text', revision: 'v1');
    final annotation = Annotation(
      id: 'a',
      documentId: 'd',
      textAnchors: [anchor],
      quote: '',
      colorIndex: 0,
      createdAt: DateTime(2026),
      capture: capture,
      needsReview: true,
    );
    final restored = Annotation.fromJson(annotation.toJson()).copyWith(colorIndex: 2);
    expect(restored.capture!.toJson(), capture.toJson());
    expect(restored.needsReview, isTrue);
    expect(restored.copyWith(needsReview: false).needsReview, isFalse);
    expect(restored.copyWith(needsReview: false).capture!.toJson(), capture.toJson());
    expect(restored.textAnchors.single.toJson(), anchor.toJson());
    expect(restored.quote, isEmpty);
    expect(
      () => TextCapture(width: double.nan, height: 1, fontSize: 1, lineHeight: 1, viewportWidth: 1, pixelRatio: 1),
      throwsArgumentError,
    );
    expect(
      () => Annotation(
        id: 'a',
        documentId: 'd',
        page: 1,
        rects: [PageRect(1, 20, 20, 1)],
        quote: '',
        colorIndex: 0,
        createdAt: DateTime(2026),
        capture: capture,
        needsReview: true,
      ),
      throwsArgumentError,
    );
  });
  test('PDF alignment positions optionally retain a precise region', () {
    expect(ReadingPosition.fromJson(PdfPosition(2, y: 300).toJson()).toJson(), {'type': 'pdf', 'page': 2, 'y': 300});
    expect(ReadingPosition.fromJson({'type': 'pdf', 'page': 2}).toJson(), {'type': 'pdf', 'page': 2});
    expect(() => PdfPosition(1, y: double.infinity), throwsArgumentError);
    expect(() => PdfPosition(1, y: -1), throwsArgumentError);
  });
  test('source pair validation rejects duplicate, stale and wrong-kind positions', () {
    final now = DateTime(2026);
    var id = 0;
    final editor = StudySetEditor(newId: () => 'id${id++}', now: () => now);
    final text = Document(
      id: 't',
      title: 'Text',
      format: DocumentFormat.markdown,
      layout: DocumentLayout.reflow,
      pageCount: 0,
      fileName: 'books/t/v1/manifest.json',
      contentManifest: 'books/t/v1/manifest.json',
      revision: 'v1',
      importedAt: now,
    );
    final pdf = Document(id: 'p', title: 'PDF', fileName: 'a.pdf', pageCount: 3, importedAt: now);
    final content = StudySetContent.empty.copyWith(documents: [text, pdf]);
    final point = SourceAlignPoint(
      left: TextReadingPosition(revision: 'v1', chapterId: 'main', offset: 0),
      right: PdfPosition(2, y: 100),
    );
    ComparePair pair(List<SourceAlignPoint> points) =>
        ComparePair(id: 'pair', leftDocumentId: 't', right: PdfCompareTarget('p'), sourceAlignPoints: points);
    expect(
      editor.upsertComparePair(content, pair([point])).comparePairs.single.sourceAlignPoints.single.toJson(),
      point.toJson(),
    );
    expect(() => editor.upsertComparePair(content, pair([point, point])), throwsArgumentError);
    expect(
      () => editor.upsertComparePair(content, pair([SourceAlignPoint(left: PdfPosition(1), right: PdfPosition(1))])),
      throwsArgumentError,
    );
    expect(
      () => editor.upsertComparePair(content, pair([SourceAlignPoint(left: point.left, right: PdfPosition(4))])),
      throwsArgumentError,
    );
    expect(
      () => editor.upsertComparePair(
        content,
        pair([
          SourceAlignPoint(
            left: TextReadingPosition(revision: 'v0', chapterId: 'main', offset: 0),
            right: point.right,
          ),
        ]),
      ),
      throwsArgumentError,
    );

    final capture = TextCapture(
      width: 30,
      height: 40,
      fontSize: 18,
      lineHeight: 1.6,
      viewportWidth: 600,
      pixelRatio: 2,
    );
    final annotation = Annotation(
      id: 'a',
      documentId: text.id,
      textAnchors: [TextAnchor('main', 0, 4, 'text', revision: 'v1')],
      quote: '',
      colorIndex: 0,
      createdAt: now,
      capture: capture,
      needsReview: true,
    );
    final (withCard, card) = editor.createImage(
      content.copyWith(annotations: [annotation]),
      imageFileName: 'images/a.png',
      annotationId: 'a',
    );
    final entries = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(withCard, [card.id])))!;
    expect(entries.single.annotation!.capture!.toJson(), capture.toJson());
    expect(entries.single.annotation!.needsReview, isTrue);
    final pasted = editor.paste(withCard, entries).$1;
    expect(pasted.annotations.last.capture!.toJson(), capture.toJson());
    expect(pasted.annotations.last.needsReview, isTrue);
  });
}
