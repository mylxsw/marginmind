import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

void main() {
  var seq = 0;
  final now = DateTime.utc(2026, 10, 26);
  StudySetEditor editor([String mapId = MindMap.defaultId]) =>
      StudySetEditor(newId: () => 'id-${seq++}', now: () => now, mapId: mapId);
  const rect = PageRect(40, 600, 300, 420);

  (StudySetContent, Document, Card) area() {
    final e = editor();
    final (withDoc, doc) = e.addDocument(StudySetContent.empty, title: 'Book', fileName: 'book.pdf', pageCount: 9);
    final (withTopic, topic) = e.addTopic(withDoc, title: 'Figures');
    final (c, card) = e.createAreaExcerpt(
      withTopic,
      documentId: doc.id,
      page: 3,
      rect: rect,
      imageFileName: 'images/a.png',
      colorIndex: 2,
      parentId: topic.id,
    );
    return (c, doc, card);
  }

  test('area excerpt frames one page region and places an image card', () {
    final (c, doc, card) = area();
    expect(card.kind, CardKind.image);
    expect(card.imageFileName, 'images/a.png');
    final a = c.annotation(card.annotationId!)!;
    expect(a.documentId, doc.id);
    expect(a.page, 3);
    expect(a.rects, [rect]);
    expect(a.quote, isEmpty);
    expect(a.colorIndex, 2);
    expect(c.cardForAnnotation(a.id)!.id, card.id);
    expect(c.node(card.id)!.parentId, c.cards.firstWhere((c) => c.kind == CardKind.topic).id);
    expect(c.reviewableCards.map((c) => c.id), contains(card.id));
    final loaded = StudySetContent.fromJson(c.toJson());
    expect(loaded.card(card.id)!.imageFileName, 'images/a.png');
    expect(loaded.annotation(a.id)!.rects, [rect]);
  });

  test('removing an image card drops its area; other maps keep both', () {
    final (c, _, card) = area();
    final e = editor();
    final removed = e.removeFromMap(c, card.id);
    expect(removed.card(card.id), isNull);
    expect(removed.annotations, isEmpty);
    expect(e.removeMany(c, [card.id]).annotations, isEmpty);
    // Excerpt highlights still survive removal as plain highlights.
    final (withExcerpt, excerpt) = e.createExcerpt(
      c,
      documentId: c.documents.single.id,
      page: 1,
      rects: const [PageRect(1, 2, 3, 1)],
      quote: 'kept',
      colorIndex: 0,
    );
    expect(e.removeFromMap(withExcerpt, excerpt.id).annotation(excerpt.annotationId!), isNotNull);

    final (withMap, map) = e.addMap(c, title: 'Second');
    final placed = editor(map.id).placeCard(withMap, card.id);
    final fromMain = e.removeFromMap(placed, card.id);
    expect(fromMain.card(card.id), isNotNull);
    expect(fromMain.annotation(card.annotationId!), isNotNull);
    expect(e.deleteAnnotation(placed, card.annotationId!).card(card.id), isNull);
  });

  test('paste keeps images in the same package, after cut, and when imported', () {
    final (c, _, card) = area();
    final e = editor();
    final entries = MapClipboard.decode(
      MapClipboard.encode(MapClipboard.copy(c, [card.id], resolveImage: (name) => '/library/set/$name')),
    )!;
    expect(entries.single.imagePath, '/library/set/images/a.png');
    expect(MapClipboard.copy(c, [card.id]).single.imagePath, isNull);

    final copied = e.paste(c, entries).$1;
    expect(copied.cards.last.kind, CardKind.image);
    expect(copied.annotations.length, 2);

    // Cut removed the card and its area; the document proves the file is here.
    final cut = e.removeFromMap(c, card.id);
    final restored = e.paste(cut, entries).$1;
    expect(restored.cards.last.kind, CardKind.image);
    expect(restored.cards.last.imageFileName, 'images/a.png');
    expect(restored.annotation(restored.cards.last.annotationId!)!.rects, [rect]);

    final foreign = e.paste(StudySetContent.empty, entries).$1;
    expect(foreign.cards.single.kind, CardKind.note);
    final imported = e.paste(StudySetContent.empty, entries, images: {'images/a.png': 'images/b.png'}).$1;
    expect(imported.cards.single.kind, CardKind.image);
    expect(imported.cards.single.imageFileName, 'images/b.png');
    expect(imported.cards.single.annotationId, isNull);
    expect(imported.annotations, isEmpty);
    expect(imported.reviewableCards.single.id, imported.cards.single.id);
  });

  test('text clipboard and exports keep untitled images and their source', () {
    final (c, _, card) = area();
    final topic = c.cards.firstWhere((c) => c.kind == CardKind.topic);
    final (withChild, _) = editor().addTopic(c, title: 'Under the figure', parentId: card.id);
    final text = MapClipboard.toText(MapClipboard.copy(withChild, [topic.id]));
    expect(text, 'Figures\n\t![](images/a.png)\n\t\tUnder the figure');
    expect(MapClipboard.fromText(text).map((e) => e.depth), [0, 1, 2]);
    final exporter = MapExporter(c, rootTitle: 'Root', source: (doc, page) => '${doc.title} p$page');
    expect(exporter.markdown(), contains('![](images/a.png) *(Book p3)*'));
    expect(exporter.opml(), contains('<outline text="images/a.png" _note="Book p3"/>'));
    final titled = editor().rename(c, card.id, 'Chart');
    expect(MapExporter(titled, rootTitle: 'Root').opml(), contains('text="Chart"'));
    final unanchored = editor().createImage(StudySetContent.empty, imageFileName: 'images/x.png', annotationId: 'none');
    expect(MapExporter(unanchored.$1, rootTitle: 'Root').opml(), contains('<outline text="images/x.png"/>'));
  });

  test('in-memory repository stores image bytes by content', () async {
    final repo = InMemoryStudySetContentRepository();
    final a = await repo.importImageBytes('set', [1, 2, 3]);
    final b = await repo.importImageBytes('set', [1, 2, 3]);
    expect(a, b);
    expect(a, startsWith('images/'));
    expect(repo.images[a], [1, 2, 3]);
    expect(await repo.importImageBytes('set', [4]), isNot(a));
  });
}
