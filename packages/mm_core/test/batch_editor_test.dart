import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  late StudySetEditor editor;
  late StudySetContent c;
  late String a, b, child, leaf;
  setUp(() {
    var id = 0;
    editor = StudySetEditor(newId: () => '${++id}', now: () => DateTime(2026));
    final (c1, ca) = editor.addTopic(StudySetContent.empty, title: 'A');
    final (c2, cb) = editor.addTopic(c1, title: 'B');
    final (c3, cc) = editor.addNote(c2, text: 'child', parentId: ca.id);
    final (c4, cl) = editor.addNote(c3, text: 'leaf', parentId: cc.id);
    c = c4;
    a = ca.id;
    b = cb.id;
    child = cc.id;
    leaf = cl.id;
  });
  List<String> children(StudySetContent value, String? parent) =>
      value.childrenOf(parent).map((n) => n.cardId).toList();

  test('insert siblings before and after, including root and missing node', () {
    final (next, added) = editor.insertSibling(c, a, title: ' after ');
    expect(children(next, null), [a, added!.id, b]);
    expect(added.title, 'after');
    final (before, first) = editor.insertSibling(next, a, title: 'before', before: true);
    expect(children(before, null), [first!.id, a, added.id, b]);
    final (nested, sibling) = editor.insertSibling(c, child, title: 'nested');
    expect(children(nested, a), [child, sibling!.id]);
    expect(editor.insertSibling(c, null, title: 'root').$1.cards.length, c.cards.length + 1);
    expect(editor.insertSibling(c, 'missing', title: 'bad'), (c, null));
    expect(c.cards.length, 4, reason: 'input remains immutable');
  });

  test('promote places subtree after its parent and protects root', () {
    final next = editor.promote(c, child);
    expect(children(next, null), [a, child, b]);
    expect(next.node(leaf)!.parentId, child);
    for (final id in [null, a, 'missing']) {
      expect(editor.promote(c, id), same(c));
    }
  });

  test('insert parent preserves sibling slot and subtree', () {
    final (next, parent) = editor.insertParent(c, a, title: 'wrapper');
    expect(children(next, null), [parent!.id, b]);
    expect(children(next, parent.id), [a]);
    expect(next.node(child)!.parentId, a);
    final (nested, p) = editor.insertParent(c, child, title: 'nested');
    expect(children(nested, a), [p!.id]);
    expect(children(nested, p.id), [child]);
    for (final id in [null, 'missing']) {
      expect(editor.insertParent(c, id, title: 'bad'), (c, null));
    }
  });

  test('batch remove deduplicates ancestors and preserves highlights/reviews', () {
    final (next, excerpt) = editor.createExcerpt(
      c,
      documentId: 'doc',
      page: 1,
      rects: const [],
      quote: 'q',
      colorIndex: 0,
      parentId: a,
    );
    final reviewed = editor.rate(next, excerpt.id, Rating.good);
    final removed = editor.removeMany(reviewed, [a, child, a, 'missing']);
    expect(removed.cards.map((c) => c.id), [b]);
    expect(removed.annotations, reviewed.annotations);
    expect(removed.reviews, reviewed.reviews);
    expect(editor.removeMany(c, []), same(c));
    expect(editor.removeMany(c, ['missing']), same(c));
  });

  test('cross-branch move uses map order and moves selected descendants once', () {
    final (next, other) = editor.addTopic(c, title: 'other', parentId: b);
    final moved = editor.moveMany(next, [other.id, leaf, child, child], null, index: 1);
    expect(children(moved, null), [a, child, other.id, b]);
    expect(moved.node(leaf)!.parentId, child);
    expect(children(moved, a), isEmpty);
    expect(children(moved, b), isEmpty);
    expect(next.node(child)!.parentId, a);
  });

  test('batch move rejects cycles and missing targets atomically', () {
    for (final target in [a, child, leaf, 'missing']) {
      expect(editor.moveMany(c, [b, a], target), same(c));
    }
    expect(editor.moveMany(c, [], null), same(c));
    expect(editor.moveMany(c, ['missing'], null), same(c));
  });

  test('batch move reorders siblings, clamps index and expands target', () {
    expect(children(editor.moveMany(c, [b], null, index: -2), null), [b, a]);
    expect(children(editor.moveMany(c, [a], null, index: 99), null), [b, a]);
    final folded = editor.setCollapsed(c, b, collapsed: true);
    final moved = editor.moveMany(folded, [child], b);
    expect(children(moved, b), [child]);
    expect(moved.node(b)!.collapsed, isFalse);
  });

  test('batch color affects only selected excerpt highlights', () {
    final (c1, e1) = editor.createExcerpt(
      c,
      documentId: 'doc',
      page: 1,
      rects: const [],
      quote: 'one',
      colorIndex: 0,
      parentId: a,
    );
    final (c2, e2) = editor.createExcerpt(c1, documentId: 'doc', page: 1, rects: const [], quote: 'two', colorIndex: 1);
    final next = editor.recolorMany(c2, [a, e1.id, e1.id, 'missing'], 3);
    expect(next.annotation(e1.annotationId!)!.colorIndex, 3);
    expect(next.annotation(e2.annotationId!)!.colorIndex, 1);
    expect(editor.recolorMany(next, [e1.id], 3), same(next));
    expect(editor.recolorMany(c2, [], 3), same(c2));
    expect(editor.recolorMany(c2, [a, 'missing'], 3), same(c2));
  });
}
