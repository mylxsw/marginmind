import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26);
  var seq = 0;
  StudySetEditor editor([String mapId = MindMap.defaultId]) =>
      StudySetEditor(newId: () => 'scope-${seq++}', now: () => now, mapId: mapId);
  Card note(String id, {List<String> tags = const [], bool suspended = false}) => Card(
    id: id,
    kind: CardKind.note,
    title: id,
    tags: tags,
    suspended: suspended,
    createdAt: now.add(Duration(seconds: id.codeUnitAt(0))),
  );

  // main map:  t (topic) ─ a ─ b(folded child of a: c)   d
  // second map: d ─ a
  final base = StudySetContent(
    maps: const [
      MindMap(id: MindMap.defaultId, title: ''),
      MindMap(id: 'second', title: 'Second'),
    ],
    cards: [
      Card(id: 't', kind: CardKind.topic, title: 'Topic', createdAt: now),
      note('a', tags: ['Memory']),
      note('b'),
      note('c', tags: ['memory', 'other']),
      note('d', tags: ['other']),
    ],
    nodes: const [
      MapNode(cardId: 't', order: 0),
      MapNode(cardId: 'a', parentId: 't', order: 0),
      MapNode(cardId: 'b', parentId: 'a', order: 0, collapsed: true),
      MapNode(cardId: 'c', parentId: 'b', order: 0),
      MapNode(cardId: 'd', order: 1),
      MapNode(mapId: 'second', cardId: 'd', order: 0),
      MapNode(mapId: 'second', cardId: 'a', parentId: 'd', order: 0),
    ],
  );
  List<String> ids(Iterable<Card> cards) => [for (final c in cards) c.id];

  test('branch covers the card and every descendant on its map, folded or not', () {
    expect(base.branch('t'), {'t', 'a', 'b', 'c'});
    expect(base.branch('b'), {'b', 'c'});
    expect(base.branch('d'), {'d'});
    expect(base.branch('d', mapId: 'second'), {'d', 'a'});
    expect(base.branch('c', mapId: 'second'), isEmpty);
    expect(base.branch('missing'), isEmpty);
  });

  test('a branch queue keeps only that subtree, on the given map', () {
    expect(ids(base.reviewQueue(now)), ['a', 'b', 'c', 'd']);
    expect(ids(base.reviewQueue(now, branchId: 't')), ['a', 'b', 'c']);
    expect(ids(base.reviewQueue(now, mapId: MindMap.defaultId, branchId: 'b')), ['b', 'c']);
    expect(ids(base.reviewQueue(now, mapId: 'second', branchId: 'd')), ['a', 'd']);
    expect(ids(base.reviewQueue(now, mapId: 'second', branchId: 'b')), isEmpty);
    expect(base.dueCount(now, branchId: 'missing'), 0);
  });

  test('a tag queue matches exactly, ignoring case, and combines with map and branch', () {
    expect(ids(base.reviewQueue(now, tag: 'MEMORY')), ['a', 'c']);
    expect(ids(base.reviewQueue(now, tag: 'mem')), isEmpty);
    expect(ids(base.reviewQueue(now, mapId: 'second', tag: 'memory')), ['a']);
    expect(ids(base.reviewQueue(now, tag: 'other', branchId: 'b')), ['c']);
    expect(base.dueCount(now, mapId: 'second', tag: 'other'), 1);
  });

  test('suspended cards leave every queue and count, and come back when resumed', () {
    final e = editor();
    var c = e.setSuspended(base, 'a', suspended: true);
    expect(ids(c.reviewQueue(now)), ['b', 'c', 'd']);
    expect(ids(c.reviewQueue(now, tag: 'memory')), ['c']);
    expect(ids(c.reviewQueue(now, mapId: 'second')), ['d']);
    expect(c.dueCount(now, branchId: 'a'), 2);
    // Due cards too, not only new ones.
    c = e.rate(e.setSuspended(c, 'a', suspended: false), 'a', Rating.again);
    final later = now.add(const Duration(days: 1));
    expect(ids(c.reviewQueue(later)).first, 'a');
    c = e.setSuspended(c, 'a', suspended: true);
    expect(ids(c.reviewQueue(later)), ['b', 'c', 'd']);
    expect(c.dueCount(later), 3);
    expect(ids(e.setSuspended(c, 'a', suspended: false).reviewQueue(later)), ['a', 'b', 'c', 'd']);
  });

  test('scopes filter before the new-card limit', () {
    final e = editor();
    var c = StudySetContent.empty;
    for (var i = 0; i < ReviewScheduler.newPerSession + 5; i++) {
      c = e.addNote(c, text: 'n$i').$1;
    }
    final last = c.cards.last;
    c = e.setTags(c, last.id, ['late']);
    expect(c.reviewQueue(now).map((x) => x.id), isNot(contains(last.id)));
    expect(ids(c.reviewQueue(now, tag: 'late')), [last.id]);
    expect(ids(c.reviewQueue(now, branchId: last.id)), [last.id]);
    final first = c.cards.first;
    c = e.setSuspended(c, first.id, suspended: true);
    expect(c.reviewQueue(now), hasLength(ReviewScheduler.newPerSession));
    expect(c.reviewQueue(now).map((x) => x.id), isNot(contains(first.id)));
  });
}
