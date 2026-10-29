import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  late StudySetEditor editor;
  var n = 0;
  setUp(() {
    n = 0;
    editor = StudySetEditor(newId: () => 'id${++n}', now: () => DateTime.utc(2026, 10, 26, 9, n));
  });

  (StudySetContent, Document) book() =>
      editor.addDocument(StudySetContent.empty, title: 'Book', fileName: 'documents/a.pdf', pageCount: 10);

  test('toggling adds a bookmark and a second toggle removes it', () {
    final (c, doc) = book();
    final marked = editor.toggleBookmark(c, doc.id, 3);
    expect(marked.bookmarkAt(doc.id, 3), isNotNull);
    expect(marked.bookmarkAt(doc.id, 3)!.title, isEmpty);
    expect(editor.toggleBookmark(marked, doc.id, 3).bookmarks, isEmpty);
  });

  test('pages outside the document and unknown documents are ignored', () {
    final (c, doc) = book();
    expect(editor.toggleBookmark(c, doc.id, 0), same(c));
    expect(editor.toggleBookmark(c, doc.id, 11), same(c));
    expect(editor.toggleBookmark(c, 'missing', 1), same(c));
  });

  test('bookmarks of a document come in page order', () {
    final (c, doc) = book();
    var next = editor.toggleBookmark(c, doc.id, 8);
    next = editor.toggleBookmark(next, doc.id, 2);
    next = editor.toggleBookmark(next, doc.id, 5);
    expect([for (final b in next.bookmarksOn(doc.id)) b.page], [2, 5, 8]);
    expect(next.bookmarksOn('other'), isEmpty);
  });

  test('rename trims, an empty title makes the bookmark unnamed again, delete removes it', () {
    final (c, doc) = book();
    final marked = editor.toggleBookmark(c, doc.id, 4);
    final id = marked.bookmarks.single.id;
    final named = editor.renameBookmark(marked, id, '  Intro ');
    expect(named.bookmarks.single.title, 'Intro');
    expect(editor.renameBookmark(named, id, '  ').bookmarks.single.title, isEmpty);
    expect(editor.removeBookmark(named, id).bookmarks, isEmpty);
  });

  test('removing a document removes its bookmarks only', () {
    final (c, doc) = book();
    final (c2, other) = editor.addDocument(c, title: 'B', fileName: 'documents/b.pdf', pageCount: 5);
    var marked = editor.toggleBookmark(c2, doc.id, 1);
    marked = editor.toggleBookmark(marked, other.id, 2);
    final removed = editor.removeDocument(marked, doc.id);
    expect([for (final b in removed.bookmarks) b.documentId], [other.id]);
  });

  test('bookmarks survive a JSON round trip and old content reads as none', () {
    final (c, doc) = book();
    var marked = editor.toggleBookmark(c, doc.id, 6);
    marked = editor.renameBookmark(marked, marked.bookmarks.single.id, '第六页');
    final back = StudySetContent.fromJson(marked.toJson());
    expect(back.bookmarks.single.title, '第六页');
    expect(back.bookmarks.single.page, 6);
    expect(back.toJson(), marked.toJson());
    final legacy = marked.toJson()..remove('bookmarks');
    expect(StudySetContent.fromJson(legacy).bookmarks, isEmpty);
  });

  test('undo keeps the bookmark list of the snapshot', () {
    final (c, doc) = book();
    final marked = editor.toggleBookmark(c, doc.id, 2);
    final restored = StudySetEditor.restore(c, marked);
    expect(restored.bookmarks, isEmpty);
  });
  test('custom ordering survives save, edit, add, undo and document isolation', () {
    final (c, doc) = book();
    var next = editor.addBookmark(c, doc.id, 8, title: 'Eight');
    next = editor.addBookmark(next, doc.id, 2, title: 'Two');
    next = editor.addBookmark(next, doc.id, 5);
    final original = next;
    final ids = next.bookmarksOn(doc.id).reversed.map((b) => b.id).toList();
    next = editor.orderBookmarks(next, doc.id, ids);
    expect(next.bookmarksOn(doc.id).map((b) => b.page), [8, 5, 2]);
    next = editor.editBookmark(next, ids.first, 'Edited', 9);
    expect(next.bookmarksOn(doc.id).map((b) => b.page), [9, 5, 2]);
    next = editor.addBookmark(next, doc.id, 1);
    expect(next.bookmarksOn(doc.id).map((b) => b.page), [9, 5, 2, 1]);
    expect(StudySetContent.fromJson(next.toJson()).bookmarksOn(doc.id).map((b) => b.page), [9, 5, 2, 1]);
    expect(StudySetEditor.restore(original, next).bookmarksOn(doc.id).map((b) => b.page), [2, 5, 8]);
    final (both, other) = editor.addDocument(next, title: 'Other', fileName: 'b.pdf', pageCount: 10);
    final withOther = editor.addBookmark(both, other.id, 3);
    final ordered = editor.orderBookmarks(
      withOther,
      doc.id,
      next.bookmarksOn(doc.id).reversed.map((b) => b.id).toList(),
    );
    expect(ordered.bookmarksOn(other.id).single.toJson(), withOther.bookmarksOn(other.id).single.toJson());
  });

  test('add is idempotent and editing cannot duplicate a page or accept invalid order', () {
    final (c, doc) = book();
    var next = editor.addBookmark(c, doc.id, 3);
    next = editor.addBookmark(next, doc.id, 5);
    expect(editor.addBookmark(next, doc.id, 3), same(next));
    final id = next.bookmarks.first.id;
    expect(editor.editBookmark(next, id, 'Invalid', 5), same(next));
    expect(editor.editBookmark(next, id, 'Invalid', 11), same(next));
    expect(editor.orderBookmarks(next, doc.id, [id, id]), same(next));
    expect(editor.orderBookmarks(next, doc.id, ['missing', id]), same(next));
    expect(editor.orderBookmarks(next, doc.id, [id]), same(next));
  });
}
