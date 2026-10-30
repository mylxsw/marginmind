import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  test('real file stores legacy content, notes, archived deletion and undo without migration', () async {
    final dir = await Directory.systemTemp.createTemp('study_notes_');
    addTearDown(() => dir.delete(recursive: true));
    final now = DateTime.utc(2026, 10, 30);
    final editor = StudySetEditor(newId: newId, now: () => now);
    var store = FileLibraryStore(dir);
    final set = await store.create(const NewStudySet(title: 'Notes', colorIndex: 0));
    final legacy = await store.load(set.id);
    expect(legacy.studyNotes, isEmpty);
    final before = await store.update(set.id, (c) {
      final (withDoc, doc) = editor.addDocument(c, title: 'Book', fileName: 'book.pdf', pageCount: 10);
      final (withQuote, card) = editor.createExcerpt(
        withDoc,
        documentId: doc.id,
        page: 1,
        rects: const [PageRect(0, 10, 10, 0)],
        quote: '原文不变',
        colorIndex: 0,
      );
      return editor.saveStudyNote(
        withQuote,
        StudyNote(
          id: 'note',
          title: 'Reading',
          scope: const WholeSet(),
          settings: NoteSettings(),
          createdAt: now,
          updatedAt: now,
          organizedAt: now,
          sections: [
            NoteSection(
              id: 's',
              title: 'Chapter',
              blocks: [QuoteBlock(id: 'q', annotationId: card.annotationId!)],
            ),
          ],
        ),
      );
    });
    final sourceId = before.annotations.single.id;
    final removed = await store.update(set.id, (c) => editor.deleteAnnotation(c, sourceId));
    await store.dispose();
    store = FileLibraryStore(dir);
    final reopened = await store.load(set.id);
    expect(jsonEncode(reopened.toJson()), jsonEncode(removed.toJson()));
    expect(resolveNoteSource(reopened, sourceId).annotation!.quote, '原文不变');
    expect(resolveNoteSource(reopened, sourceId).status, NoteSourceStatus.annotationDeleted);
    await store.update(set.id, (c) => StudySetEditor.restore(before, c));
    await store.dispose();
    store = FileLibraryStore(dir);
    final restored = await store.load(set.id);
    expect(resolveNoteSource(restored, sourceId).status, NoteSourceStatus.available);
    expect(restored.noteSourceArchive, isEmpty);
    await store.update(set.id, (c) => editor.deleteStudyNote(editor.deleteAnnotation(c, sourceId), 'note'));
    await store.dispose();
    store = FileLibraryStore(dir);
    expect((await store.load(set.id)).noteSourceArchive, isEmpty);
    await store.dispose();
  });
}
