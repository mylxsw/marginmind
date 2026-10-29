import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  test('custom highlight and linked margin note colors survive disk reopen and clipboard copy', () async {
    final root = await Directory.systemTemp.createTemp('custom_annotation_color_');
    addTearDown(() => root.delete(recursive: true));
    var store = FileLibraryStore(root);
    final date = DateTime.utc(2026, 10, 29);
    var sequence = 0;
    final editor = StudySetEditor(newId: () => 'id${sequence++}', now: () => date);
    final set = await store.create(const NewStudySet(title: 'Colors', colorIndex: 0));
    const encodedColor = 0x0112A4B8;
    await store.update(set.id, (content) {
      final (withDocument, document) = editor.addDocument(content, title: 'Source', fileName: 'a.pdf', pageCount: 2);
      final (withExcerpt, card) = editor.createExcerpt(
        withDocument,
        documentId: document.id,
        page: 1,
        rects: const [PageRect(10, 100, 100, 80)],
        quote: 'quote',
        colorIndex: encodedColor,
      );
      return editor.upsertMarginNote(
        withExcerpt,
        MarginNote(
          id: 'note',
          documentId: document.id,
          page: 1,
          anchor: AnnotationAnchor(pages: withExcerpt.annotation(card.annotationId!)!.pages, quote: 'quote'),
          text: 'Thought',
          colorIndex: encodedColor,
          nodeId: card.id,
          mapId: MindMap.defaultId,
          createdAt: date,
          updatedAt: date,
        ),
      );
    });
    final saved = await store.load(set.id);
    await store.dispose();
    store = FileLibraryStore(root);
    final reopened = await store.load(set.id);
    expect(reopened.toJson(), saved.toJson());
    expect(reopened.annotations.single.colorIndex, encodedColor);
    expect(reopened.marginNotes.single.colorIndex, encodedColor);
    final payload = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(reopened, [reopened.cards.single.id])))!;
    final pasted = editor.paste(reopened, payload);
    expect(pasted.$1.annotations.every((a) => a.colorIndex == encodedColor), isTrue);
    expect(pasted.$1.annotations, hasLength(2));
    await store.dispose();
  });
}
