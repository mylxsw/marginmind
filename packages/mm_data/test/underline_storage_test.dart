import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  test('underline styles survive disk reopen and copying a linked excerpt', () async {
    final root = await Directory.systemTemp.createTemp('underline_storage_');
    addTearDown(() => root.delete(recursive: true));
    var store = FileLibraryStore(root);
    var n = 0;
    final editor = StudySetEditor(newId: () => 'id${n++}', now: () => DateTime.utc(2026, 10, 29));
    final set = await store.create(const NewStudySet(title: 'Underlines', colorIndex: 0));
    await store.update(set.id, (content) {
      var (c, doc) = editor.addDocument(content, title: 'Source', fileName: 'a.pdf', pageCount: 2);
      for (final style in AnnotationLineStyle.values) {
        final (next, mark) = editor.underline(
          c,
          documentId: doc.id,
          pages: [
            AnnotationPage(page: 1, rects: [PageRect(10, 100 + style.index * 20, 100, 80 + style.index * 20)]),
          ],
          quote: 'Quote ${style.name}',
          colorIndex: 0x0112A4B8,
          lineStyle: style,
        );
        c = editor.attachCard(next, mark.id).$1;
      }
      return c;
    });
    final saved = await store.load(set.id);
    await store.dispose();
    store = FileLibraryStore(root);
    final reopened = await store.load(set.id);
    expect(reopened.toJson(), saved.toJson());
    final payload = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(reopened, [reopened.cards.last.id])))!;
    final pasted = editor.paste(reopened, payload).$1;
    expect(pasted.annotations.last.kind, AnnotationKind.underline);
    expect(pasted.annotations.last.lineStyle, AnnotationLineStyle.wavy);
    expect(pasted.annotations.last.colorIndex, 0x0112A4B8);
    expect(pasted.annotations.length, reopened.annotations.length + 1);
    await store.dispose();
  });
}
