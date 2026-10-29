import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

const child = PdfOutlineEntry(id: 'child', title: 'Section', page: 3);
const a = PdfOutlineEntry(id: 'a', title: 'Z chapter', page: 2, children: [child]);
const b = PdfOutlineEntry(id: 'b', title: 'A chapter', page: 8);
const roots = [a, b];

void main() {
  final editor = StudySetEditor(newId: () => 'doc', now: () => DateTime.utc(2026));
  (StudySetContent, Document) book() =>
      editor.addDocument(StudySetContent.empty, title: 'Book', fileName: 'a.pdf', pageCount: 10);

  test('moves a whole subtree and rejects cycles, self drops and unknown targets', () {
    final moved = OutlineTree.move(roots, 'a', 'b', OutlineDrop.after);
    expect(moved.map((e) => e.id), ['b', 'a']);
    expect(moved.last.children.single.id, 'child');
    final nested = OutlineTree.move(roots, 'b', 'child', OutlineDrop.inside);
    expect(nested.single.children.single.children.single.id, 'b');
    expect(OutlineTree.move(roots, 'a', 'child', OutlineDrop.inside), same(roots));
    expect(OutlineTree.move(roots, 'a', 'a', OutlineDrop.before), same(roots));
    expect(OutlineTree.move(roots, 'a', 'missing', OutlineDrop.after), same(roots));
    final promoted = OutlineTree.move(nested, 'child', 'a', OutlineDrop.before);
    expect(promoted.map((e) => e.id), ['child', 'a']);
    expect(promoted.first.children.single.id, 'b');
  });

  test('add, edit destination, recursive sorting and branch deletion preserve IDs', () {
    final added = OutlineTree.insert(
      roots,
      const PdfOutlineEntry(id: 'new', title: 'New', page: 6),
      targetId: 'a',
      drop: OutlineDrop.inside,
    );
    expect(added.first.children.map((e) => e.id), ['child', 'new']);
    final edited = OutlineTree.update(added, 'child', (e) => e.copyWith(title: 'Renamed', page: 9));
    expect(edited.first.children.first.page, 9);
    expect(OutlineTree.sort(edited, ReaderEntrySort.pageAscending).first.children.map((e) => e.page), [6, 9]);
    expect(OutlineTree.sort(edited, ReaderEntrySort.pageDescending).map((e) => e.id), ['b', 'a']);
    expect(OutlineTree.sort(edited, ReaderEntrySort.title).map((e) => e.id), ['b', 'a']);
    expect(OutlineTree.remove(edited, 'a').map((e) => e.id), ['b']);
  });

  test('saved outline, including intentional empty outline, survives JSON and undo', () {
    final (c, doc) = book();
    final edited = editor.setDocumentOutline(c, doc.id, roots);
    final back = StudySetContent.fromJson(edited.toJson());
    expect(back.outlineOn(doc.id)!.items.first.children.single.id, 'child');
    expect(back.toJson(), edited.toJson());
    final empty = editor.setDocumentOutline(edited, doc.id, []);
    expect(StudySetContent.fromJson(empty.toJson()).outlineOn(doc.id)!.items, isEmpty);
    expect(StudySetEditor.restore(edited, empty).outlineOn(doc.id)!.items.length, 2);
    expect(StudySetEditor.restore(c, edited).outlineOn(doc.id), isNull);
    expect(editor.removeDocument(edited, doc.id).documentOutlines, isEmpty);
    expect(StudySetContent.fromJson({}).documentOutlines, isEmpty);
  });

  test('invalid pages and duplicate identities cannot be saved', () {
    final (c, doc) = book();
    expect(editor.setDocumentOutline(c, doc.id, [a, a]), same(c));
    expect(editor.setDocumentOutline(c, doc.id, [b.copyWith(page: 11)]), same(c));
    expect(editor.setDocumentOutline(c, doc.id, [b.copyWith(page: -1)]), same(c));
    expect(editor.setDocumentOutline(c, 'missing', roots), same(c));
    expect(editor.setDocumentOutline(c, doc.id, [b.copyWith(page: 0)]).outlineOn(doc.id), isNotNull);
  });
}
