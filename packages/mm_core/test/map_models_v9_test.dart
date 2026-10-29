import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  final epoch = DateTime.utc(1970);
  Card card(String id, {CardKind kind = CardKind.topic}) => Card(id: id, kind: kind, createdAt: epoch);

  test('map and relation styles roundtrip and independent handle clearing', () {
    final map = MindMap.main.copyWith(structure: MapStructure.brace, palette: MapPalette.ink);
    final loadedMap = MindMap.fromJson(map.toJson());
    expect(loadedMap.structure, MapStructure.brace);
    expect(loadedMap.palette, MapPalette.ink);
    final relation = MapRelation(
      id: 'r',
      fromId: 'a',
      toId: 'b',
      arrow: RelationArrow.both,
      solid: true,
      control1: const RelationControlPoint(.2, .3),
      control2: const RelationControlPoint(.7, .8),
    );
    final loaded = MapRelation.fromJson(relation.toJson());
    expect(loaded.toJson(), relation.toJson());
    final reset = loaded.copyWith(clearControl1: true, fromId: 'c', label: 'why');
    expect(reset.control1, isNull);
    expect(reset.control2, relation.control2);
    expect(reset.fromId, 'c');
    expect(reset.toId, 'b');
    expect(reset.copyWith(clearControl2: true).control2, isNull);
    final legacy = MapRelation.fromJson({'id': 'r', 'fromId': 'a', 'toId': 'b'});
    expect(legacy.arrow, RelationArrow.end);
    expect(legacy.solid, isFalse);
    expect(MindMap.fromJson({'id': 'm', 'title': ''}).structure, MapStructure.mind);
    expect(MindMap.fromJson({'id': 'm', 'title': ''}).palette, MapPalette.system);
  });

  test('segments retain legacy content and identify every annotation occurrence', () {
    final annotation = Annotation(
      id: 'a',
      documentId: 'd',
      page: 1,
      rects: const [],
      quote: 'source',
      colorIndex: 0,
      createdAt: epoch,
    );
    final legacy = Card(
      id: 'c',
      kind: CardKind.excerpt,
      title: 'title',
      body: 'body',
      annotationId: 'a',
      createdAt: epoch,
    );
    final merged = legacy.copyWith(
      annotationId: null,
      segments: const [
        CardSegment(text: 'first', annotationId: 'a'),
        CardSegment(text: 'separator'),
        CardSegment(text: 'second', annotationId: 'a'),
      ],
    );
    final content = StudySetContent(
      annotations: [annotation],
      cards: [
        legacy,
        merged.copyWith(kind: CardKind.note),
      ],
    );
    expect(content.segmentsOf(legacy).map((s) => s.text), ['source', 'body']);
    expect(content.segmentsForAnnotation('a').map((m) => m.segmentIndex), [0, 0, 2]);
    expect(content.cardForAnnotation('a'), same(legacy));
    expect(content.cardForAnnotation('missing'), isNull);
    expect(merged.annotationId, isNull);
    expect(Card.fromJson(merged.toJson()).toJson(), merged.toJson());
    expect(const CardSegment(text: 'x', annotationId: 'a').copyWith(annotationId: null).annotationId, isNull);
    final placed = content.copyWith(
      cards: [merged],
      nodes: const [MapNode(cardId: 'c', order: 0)],
    );
    expect(placed.reviewableCards.single.id, 'c');
    expect(placed.search('second').map((c) => c.id), ['c']);
    expect(placed.search('separator').map((c) => c.id), ['c']);
    expect(content.segmentsOf(legacy.copyWith(body: '')).length, 1);
    expect(content.segmentsOf(card('empty')).single.text, '');
    expect(content.segmentsOf(card('empty-note', kind: CardKind.note)).single.text, '');
    final image = Card(
      id: 'image',
      kind: CardKind.image,
      annotationId: 'a',
      imageFileName: 'image.png',
      createdAt: epoch,
    );
    final imageContent = content.copyWith(cards: [image]);
    expect(imageContent.cardForAnnotation('a'), same(image));
    expect(imageContent.segmentsForAnnotation('a').single.segmentIndex, 0);
    expect(imageContent.segmentsOf(image).single.text, 'source');
    // Annotation lookup remains compatible even for a missing legacy source.
    expect(imageContent.copyWith(annotations: []).cardForAnnotation('a'), same(image));
  });

  test('legacy summaries normalize deterministically without colliding or duplicating', () {
    final raw = StudySetContent(
      cards: [card('a'), card('b'), card('summary-topic:s')],
      nodes: const [
        MapNode(cardId: 'a', order: 0),
        MapNode(cardId: 'b', order: 1),
      ],
      summaries: const [MapSummary(id: 's', fromId: 'a', toId: 'b', label: 'Meaning')],
    ).toJson();
    final content = StudySetContent.fromJson(raw);
    final id = content.summaries.single.cardId!;
    expect(id, 'summary-topic:s:1');
    expect(content.card(id)!.title, 'Meaning');
    expect(content.card(id)!.createdAt, epoch);
    expect(content.node(id), isNull);
    expect(content.isPlaced(id), isTrue);
    expect(content.isPlaced(id, mapId: 'other'), isFalse);
    expect(content.containsCard(id), isTrue);
    expect(StudySetContent.fromJson(content.toJson()).toJson(), content.toJson());
    final withChild = content.copyWith(
      cards: [...content.cards, card('child')],
      nodes: [
        ...content.nodes,
        MapNode(cardId: 'child', parentId: id, order: 0),
      ],
      relations: [MapRelation(id: 'r', fromId: id, toId: 'a')],
    );
    expect(withChild.branch(id), {id, 'child'});
    expect(withChild.relationsOf('main').single.id, 'r');
    expect(withChild.branch('missing'), isEmpty);
    final broken = withChild.copyWith(nodes: [withChild.nodes.last]);
    expect(broken.isPlaced(id), isFalse);
    expect(broken.relationsOf('main'), isEmpty);
  });
}
