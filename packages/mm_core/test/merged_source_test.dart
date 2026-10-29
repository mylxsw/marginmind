import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('cross-document merge, split, source removal and review retain all text', () {
    var seq = 0;
    final e = StudySetEditor(newId: () => 's${seq++}', now: () => DateTime.utc(2026));
    var c = StudySetContent.empty;
    final ids = <String>[];
    final sources = <String>[];
    final documents = <String>[];
    for (var i = 0; i < 2; i++) {
      final (withDoc, doc) = e.addDocument(c, title: 'Book $i', fileName: '$i.pdf', pageCount: 1);
      final (next, card) = e.createExcerpt(
        withDoc,
        documentId: doc.id,
        page: 1,
        rects: const [PageRect(0, 10, 10, 0)],
        quote: 'quote $i',
        colorIndex: i,
      );
      c = e.rename(next, card.id, 'Question $i');
      ids.add(card.id);
      sources.add(card.annotationId!);
      documents.add(doc.id);
    }
    final result = e.mergeCards(c, ids.reversed);
    expect(result.value!.segments, hasLength(2));
    expect(result.value!.title, 'Question 0');
    expect(result.content.segmentsForAnnotation(sources.last).single.segmentIndex, 1);
    expect(buildReviewFace(result.value!, result.content).back.quote, 'quote 0\nquote 1');
    final split = e.splitCard(result.content, result.value!.id);
    expect(split.value, hasLength(2));
    expect(split.value!.map((c) => c.annotationId), sources);
    expect(StudySetEditor.restore(result.content, split.content).toJson(), result.content.toJson());

    final removed = e.removeDocument(result.content, documents.first);
    final kept = removed.card(ids.first)!;
    expect(kept.annotationId, sources.last);
    expect(kept.segments.first.text, 'quote 0');
    expect(kept.segments.first.annotationId, isNull);
    expect(removed.cardForAnnotation(sources.last)!.id, kept.id);
    expect(buildReviewFace(kept, removed).back.quote, 'quote 0\nquote 1');
  });
}
