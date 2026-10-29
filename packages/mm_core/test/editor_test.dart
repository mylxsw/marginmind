import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

void main() {
  late StudySetEditor editor;
  var n = 0;
  setUp(() {
    n = 0;
    editor = StudySetEditor(newId: () => 'id${++n}', now: () => DateTime(2026, 10, 25));
  });

  const rects = [PageRect(10, 100, 200, 88)];

  StudySetContent withDoc() =>
      editor.addDocument(StudySetContent.empty, title: 'Book', fileName: 'documents/a.pdf', pageCount: 10).$1;

  test('createExcerpt adds highlight, card and node under the target', () {
    var c = withDoc();
    final (withTopic, topic) = editor.addTopic(c, title: '  遗忘的规律 ');
    expect(topic.title, '遗忘的规律');
    final (next, card) = editor.createExcerpt(
      withTopic,
      documentId: c.documents.single.id,
      page: 3,
      rects: rects,
      quote: ' 遗忘曲线 ',
      colorIndex: 2,
      parentId: topic.id,
    );
    c = next;
    expect(c.annotations.single.quote, '遗忘曲线');
    expect(card.kind, CardKind.excerpt);
    expect(c.node(card.id)!.parentId, topic.id);
    expect(c.cardForAnnotation(c.annotations.single.id)!.id, card.id);
    expect(c.excerptCount, 1);
  });

  test('excerpt target falls back to root only without a valid node in the active map', () {
    var c = withDoc();
    final (c1, topic) = editor.addTopic(c, title: 'T');
    final (c2, note) = editor.addNote(c1, text: 'N', parentId: topic.id);
    c = c2;
    expect(StudySetEditor.excerptTarget(c, null), isNull);
    expect(StudySetEditor.excerptTarget(c, topic.id), topic.id);
    expect(StudySetEditor.excerptTarget(c, note.id), note.id);
    expect(StudySetEditor.excerptTarget(c, 'missing'), isNull);
    expect(StudySetEditor.excerptTarget(c, note.id, mapId: 'other-map'), isNull);
    expect(StudySetEditor.excerptTarget(c.copyWith(nodes: []), note.id), isNull);
    expect(StudySetEditor.excerptTarget(c.copyWith(cards: []), note.id), isNull);
  });

  for (final kind in CardKind.values) {
    for (final nested in [false, true]) {
      test('excerpt target is the selected ${kind.name} node, nested=$nested', () {
        final (c, topic) = editor.addTopic(withDoc(), title: 'Parent');
        final card = Card(id: 'selected', kind: kind, createdAt: DateTime(2026));
        final content = c.copyWith(
          cards: [...c.cards, card],
          nodes: [
            ...c.nodes,
            MapNode(cardId: card.id, parentId: nested ? topic.id : null, order: 1),
          ],
        );
        expect(StudySetEditor.excerptTarget(content, card.id), card.id);
      });
    }
  }

  test('removing from the map keeps the highlight; deleting the highlight removes the card', () {
    var c = withDoc();
    final docId = c.documents.single.id;
    final (c1, card) = editor.createExcerpt(c, documentId: docId, page: 1, rects: rects, quote: 'q', colorIndex: 0);
    final (c2, child) = editor.addNote(c1, text: 'my note', parentId: card.id);

    final removed = editor.removeFromMap(c2, card.id);
    expect(removed.cards, isEmpty);
    expect(removed.node(child.id), isNull);
    expect(removed.annotations, hasLength(1));

    final (c3, again) = editor.attachCard(removed, removed.annotations.single.id);
    expect(c3.cardForAnnotation(c3.annotations.single.id)!.id, again.id);

    final deleted = editor.deleteAnnotation(c3, c3.annotations.single.id);
    expect(deleted.annotations, isEmpty);
    expect(deleted.cards, isEmpty);
  });

  test('move refuses cycles and orders siblings', () {
    var c = StudySetContent.empty;
    final (c1, a) = editor.addTopic(c, title: 'A');
    final (c2, b) = editor.addTopic(c1, title: 'B', parentId: a.id);
    c = editor.move(c2, a.id, b.id);
    expect(c.node(a.id)!.parentId, isNull, reason: 'cannot move under own child');
    c = editor.move(c, b.id, null);
    expect(c.childrenOf(null).map((n) => n.cardId), [a.id, b.id]);
  });

  test('rename, recolor and last page', () {
    var c = withDoc();
    final docId = c.documents.single.id;
    final (c1, card) = editor.createExcerpt(c, documentId: docId, page: 1, rects: rects, quote: 'q', colorIndex: 0);
    c = editor.rename(c1, card.id, ' 标题 ');
    c = editor.recolor(c, c.annotations.single.id, 4);
    c = editor.setLastPage(c, docId, 7);
    expect(c.card(card.id)!.title, '标题');
    expect(c.annotations.single.colorIndex, 4);
    expect(c.documents.single.lastPage, 7);
  });

  test('content round-trips through JSON', () {
    var c = withDoc();
    final (c1, t) = editor.addTopic(c, title: 'T');
    final (c2, _) = editor.createExcerpt(
      c1,
      documentId: c.documents.single.id,
      page: 2,
      rects: rects,
      quote: '原文',
      colorIndex: 1,
      parentId: t.id,
    );
    final json = jsonDecode(jsonEncode(c2.toJson())) as Map<String, Object?>;
    final back = StudySetContent.fromJson(json);
    expect(back.toJson(), c2.toJson());
  });

  test('in-memory repository emits updates', () async {
    final repo = InMemoryStudySetContentRepository();
    final seen = <int>[];
    final sub = repo.watch('s').listen((c) => seen.add(c.cards.length));
    await repo.update('s', (c) => editor.addTopic(c, title: 'T').$1);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [0, 1]);
    await sub.cancel();
  });
}
