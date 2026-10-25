import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

void main() {
  var seq = 0;
  final now = DateTime.utc(2026, 10, 26);
  StudySetEditor editor([String mapId = MindMap.defaultId]) =>
      StudySetEditor(newId: () => 'id-${seq++}', now: () => now, mapId: mapId);
  const pages = [
    AnnotationPage(page: 2, rects: [PageRect(1, 5, 4, 2)]),
    AnnotationPage(page: 3, rects: [PageRect(2, 6, 5, 3)]),
  ];

  test('multipage geometry survives edits, serialization and clipboard duplication', () {
    final e = editor();
    final (withDoc, doc) = e.addDocument(StudySetContent.empty, title: 'Book', fileName: 'book.pdf', pageCount: 10);
    final (content, card) = e.createExcerpt(
      withDoc,
      documentId: doc.id,
      pages: pages,
      quote: 'two pages',
      colorIndex: 1,
    );
    final changed = e.recolor(content, card.annotationId!, 3);
    final loaded = StudySetContent.fromJson(changed.toJson());
    final a = loaded.annotation(card.annotationId!)!;
    expect(a.pages.map((p) => p.page), [2, 3]);
    expect(a.pages[1].rects, pages[1].rects);
    expect(a.page, 2);
    expect(a.rects, pages[0].rects);
    expect(a.colorIndex, 3);
    expect(a.toJson().containsKey('page'), isFalse);
    final copied = MapClipboard.decode(MapClipboard.encode(MapClipboard.copy(loaded, [card.id])))!;
    final (pasted, _) = e.paste(loaded, copied);
    expect(pasted.annotations.last.pages.map((p) => p.toJson()), a.pages.map((p) => p.toJson()));
  });

  test('shared cards have independent placement, fold, order and deletion per map', () {
    final e = editor();
    var (c, topic) = e.addTopic(StudySetContent.empty, title: 'Parent');
    final (withNote, note) = e.addNote(c, text: 'Shared note', parentId: topic.id);
    final (withMap, map) = e.addMap(withNote, title: ' Second ');
    final second = editor(map.id);
    c = second.placeCard(withMap, topic.id);
    c = second.placeCard(c, note.id);
    expect(second.placeCard(c, note.id), same(c));
    expect(second.placeCard(c, 'missing'), same(c));
    expect(editor('missing').placeCard(c, note.id), same(c));
    final (withThird, third) = e.addTopic(c, title: 'Only main');
    expect(second.placeCard(withThird, third.id, parentId: 'missing'), same(withThird));
    c = second.moveMany(c, [note.id], topic.id);
    c = second.setCollapsed(c, topic.id, collapsed: true);
    expect(c.node(topic.id)!.collapsed, isFalse);
    expect(c.node(topic.id, mapId: map.id)!.collapsed, isTrue);
    c = second.promote(c, note.id);
    expect(c.node(note.id)!.parentId, topic.id);
    expect(c.node(note.id, mapId: map.id)!.parentId, isNull);
    c = second.renameMap(c, map.id, 'Renamed');
    expect(c.map(map.id)!.title, 'Renamed');
    expect(c.reviewableCards.where((c) => c.id == note.id).length, 1);
    expect(c.pathOf(note.id, mapId: map.id), isEmpty);
    expect(c.pathOf(note.id), ['Parent']);
    expect(c.search('Shared', mapId: map.id).single.id, note.id);
    expect(MapClipboard.copy(c, [note.id], mapId: map.id).single.title, 'Shared note');
    final export = MapExporter(c, rootTitle: 'Second', mapId: map.id).markdown();
    expect(export, contains('Shared note'));
    final roundtrip = StudySetContent.fromJson(c.toJson());
    expect(roundtrip.toJson(), c.toJson());
    c = second.removeMany(c, [note.id]);
    expect(c.card(note.id), isNotNull);
    expect(c.node(note.id), isNotNull);
    expect(c.node(note.id, mapId: map.id), isNull);
    c = e.removeFromMap(c, topic.id);
    expect(c.card(note.id), isNull);
    expect(c.card(topic.id), isNotNull);
    expect(c.node(topic.id, mapId: map.id), isNotNull);
    expect(e.removeMap(c, MindMap.defaultId).maps.single.id, map.id);
    c = e.removeMap(c, map.id);
    expect(c.maps, [MindMap.main]);
    expect(c.nodes, isEmpty);
  });

  test('attach, insert, paste and remove document respect multiple maps', () {
    final e = editor();
    final (base, doc) = e.addDocument(StudySetContent.empty, title: 'Book', fileName: 'book.pdf', pageCount: 10);
    var (c, card) = e.createExcerpt(base, documentId: doc.id, pages: pages, quote: 'quote', colorIndex: 0);
    final (withMap, map) = e.addMap(c, title: 'Other');
    final other = editor(map.id);
    c = other.attachCard(withMap, card.annotationId!).$1;
    expect(c.cards.length, 1);
    expect(c.nodes.length, 2);
    final (wrapped, parent) = other.insertParent(c, card.id, title: 'Wrapper');
    c = wrapped;
    expect(c.node(card.id)!.parentId, isNull);
    expect(c.node(card.id, mapId: map.id)!.parentId, parent!.id);
    final (withSibling, sibling) = other.insertSibling(c, card.id, title: 'Sibling');
    c = other.shift(withSibling, sibling!.id, -1);
    expect(c.childrenOf(parent.id, mapId: map.id).first.cardId, sibling.id);
    expect(e.move(c, card.id, 'missing'), same(c));
    c = other.paste(c, const [OutlineEntry(0, 'Pasted')], parentId: parent.id).$1;
    expect(c.childrenOf(parent.id, mapId: map.id).length, 3);
    c = e.removeDocument(c, doc.id);
    expect(c.annotations, isEmpty);
    expect(c.card(card.id), isNull);
    expect(c.nodes.where((n) => n.cardId == card.id), isEmpty);
    expect(c.card(parent.id), isNotNull);
  });

  test('image clipboard keeps available resources and reads legacy clipboard', () {
    final e = editor();
    final (base, doc) = e.addDocument(StudySetContent.empty, title: 'Book', fileName: 'book.pdf', pageCount: 10);
    final (highlighted, a) = e.highlight(base, documentId: doc.id, pages: pages, quote: 'Figure', colorIndex: 0);
    final (c, card) = e.createImage(highlighted, imageFileName: 'images/hash.png', annotationId: a.id, title: 'Figure');
    final payload = MapClipboard.encode(MapClipboard.copy(c, [card.id]));
    final entries = MapClipboard.decode(payload)!;
    final pasted = e.paste(c, entries).$1;
    expect(pasted.cards.last.kind, CardKind.image);
    expect(pasted.cards.last.imageFileName, 'images/hash.png');
    expect(pasted.annotations.last.pages.length, 2);
    final cut = e.removeFromMap(c, card.id);
    final reattached = e.paste(cut, entries).$1;
    expect(reattached.cards.single.kind, CardKind.image);
    expect(reattached.cards.single.imageFileName, 'images/hash.png');
    expect(reattached.annotations.length, 1);
    final foreign = e.paste(StudySetContent.empty, entries).$1;
    expect(foreign.cards.single.kind, CardKind.note);
    expect(foreign.cards.single.title, 'Figure');
    // The file is still in the package: the image stays, without a source.
    final noSource = e.paste(c.copyWith(documents: []), entries).$1;
    expect(noSource.cards.last.kind, CardKind.image);
    expect(noSource.cards.last.annotationId, isNull);
    final legacy = jsonDecode(payload) as Map;
    legacy['version'] = 1;
    legacy['nodes'][0]['kind'] = 'excerpt';
    final annotation = legacy['nodes'][0]['annotation'] as Map;
    annotation.remove('pages');
    annotation['page'] = 2;
    annotation['rects'] = [const PageRect(1, 5, 4, 2).toJson()];
    expect(MapClipboard.decode(jsonEncode(legacy))!.single.annotation!.page, 2);
  });

  test('image references survive rename, undo and review without duplicating cards', () async {
    final e = editor();
    final (c, card) = e.createImage(
      StudySetContent.empty,
      imageFileName: 'images/hash.png',
      annotationId: 'area',
      title: 'Figure',
    );
    final renamed = e.rename(c, card.id, 'New title');
    expect(renamed.card(card.id)!.imageFileName, 'images/hash.png');
    expect(StudySetContent.fromJson(renamed.toJson()).card(card.id)!.kind, CardKind.image);
    expect(c.reviewQueue(now).single.id, card.id);
    expect(MapExporter(c, rootTitle: 'Images').markdown(), contains('![Figure](images/hash.png)'));
    final rated = e.rate(renamed, card.id, Rating.good);
    final restored = StudySetEditor.restore(c, rated);
    expect(restored.card(card.id)!.title, 'Figure');
    expect(restored.reviews.single.toJson(), rated.reviews.single.toJson());
    final memory = InMemoryStudySetContentRepository();
    expect(await memory.importImage('set', 'image.png'), 'image.png');
  });
}
