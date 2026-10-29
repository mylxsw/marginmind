import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('margin attachment respects target topic, preserves excerpt source, and validates parent', () {
    var id = 0;
    final date = DateTime.utc(2026);
    final editor = StudySetEditor(newId: () => 'id${++id}', now: () => date);
    final (withDoc, doc) = editor.addDocument(StudySetContent.empty, title: 'PDF', fileName: 'a.pdf', pageCount: 2);
    final (seed, topic) = editor.addTopic(withDoc, title: 'Topic');
    final note = MarginNote(
      id: 'n',
      documentId: doc.id,
      page: 1,
      anchor: AnnotationAnchor(
        pages: [
          const AnnotationPage(page: 1, rects: [PageRect(10, 100, 200, 80)]),
        ],
        quote: 'Original quote',
      ),
      text: 'Comment',
      colorIndex: 2,
      createdAt: date,
      updatedAt: date,
    );
    final saved = editor.upsertMarginNote(seed, note);
    expect(() => editor.attachMarginNote(saved, note.id, parentId: 'missing'), throwsArgumentError);
    var attached = editor.attachMarginNote(saved, note.id, parentId: topic.id);
    final linked = attached.marginNotes.single;
    expect(attached.node(linked.nodeId!)!.parentId, topic.id);
    expect(attached.card(linked.nodeId!)!.body, 'Original quote');
    attached = editor.upsertMarginNote(attached, linked.copyWith(text: 'Edited'));
    expect(attached.card(linked.nodeId!)!.title, 'Edited');
    expect(attached.card(linked.nodeId!)!.body, 'Original quote');
    attached = editor.upsertMarginNote(attached, attached.marginNotes.single.copyWith(colorIndex: 4));
    final annotationId = attached.card(linked.nodeId!)!.annotationId!;
    expect(attached.annotation(annotationId)!.colorIndex, 4);
    attached = editor.recolor(attached, annotationId, 3);
    expect(attached.marginNotes.single.colorIndex, 3);
    expect(attached.annotation(annotationId)!.colorIndex, 3);
    final deleted = editor.removeMarginNote(attached, note.id);
    expect(deleted.card(linked.nodeId!)!.title, 'Edited');
    expect(deleted.annotations.single.quote, 'Original quote');
  });
}
