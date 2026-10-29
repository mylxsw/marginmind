import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  late StudySetEditor editor;
  late StudySetContent content;
  late Card a, b, c;
  setUp(() {
    var nextId = 0;
    editor = StudySetEditor(newId: () => 'edit-${++nextId}', now: () => DateTime(2026));
    final (one, first) = editor.addNote(StudySetContent.empty, text: 'A');
    final (two, second) = editor.addNote(one, text: 'B');
    final (three, third) = editor.addNote(two, text: 'C');
    content = three;
    a = first;
    b = second;
    c = third;
  });

  List<String> children(StudySetContent value, String? parent) =>
      value.childrenOf(parent).map((node) => node.cardId).toList();

  test('merge uses map preorder and flattens existing segments once', () {
    final (withChild, child) = editor.addNote(content, text: 'child', parentId: a.id);
    final (withLeaf, leaf) = editor.addNote(withChild, text: 'leaf', parentId: child.id);
    final (before, sibling) = editor.addNote(withLeaf, text: 'sibling', parentId: b.id);
    final result = editor.mergeCards(before, [b.id, child.id, a.id, child.id]);
    expect(result.succeeded, isTrue);
    expect(result.value!.id, a.id);
    expect(result.value!.title, 'A\nchild\nB');
    expect(result.value!.segments.map((s) => s.text), ['A', 'child', 'B']);
    expect(children(result.content, null), [a.id, c.id]);
    expect(children(result.content, a.id), [leaf.id, sibling.id]);
    expect(result.content.card(child.id), isNull);
    expect(result.content.card(b.id), isNull);
    expect(before.card(child.id), isNotNull, reason: 'source snapshot is immutable');

    final again = editor.mergeCards(result.content, [c.id, a.id]);
    expect(again.value!.segments.map((s) => s.text), ['A', 'child', 'B', 'C']);
  });

  test('mixed excerpt merge takes the first nonempty title in map order', () {
    final before = content.copyWith(
      cards: [
        a.copyWith(
          title: '',
          kind: CardKind.excerpt,
          annotationId: 'source',
          segments: const [CardSegment(text: 'excerpt', annotationId: 'source')],
        ),
        b,
        c,
      ],
    );
    final result = editor.mergeCards(before, [b.id, a.id]);
    expect(result.value!.id, a.id);
    expect(result.value!.title, 'B');
  });

  test('merge rewires relations, removes self links and unordered duplicates', () {
    final (one, _) = editor.addRelation(content, a.id, b.id);
    final (two, keep) = editor.addRelation(one, a.id, c.id);
    final (three, _) = editor.addRelation(two, c.id, b.id);
    final result = editor.mergeCards(three, [b.id, a.id]);
    expect(result.removedRelationCount, 2);
    expect(result.content.relations, hasLength(1));
    final relation = result.content.relations.single;
    expect(relation.id, keep!.id);
    expect({relation.fromId, relation.toId}, {a.id, c.id});
  });

  test('merge preserves keeper scheduling and historical review logs', () {
    final reviewed = editor.rate(editor.rate(content, a.id, Rating.good), b.id, Rating.hard);
    final result = editor.mergeCards(reviewed, [b.id, a.id]);
    expect(result.content.reviewOf(a.id), same(reviewed.reviewOf(a.id)));
    expect(result.content.memoryOf(a.id), same(reviewed.memoryOf(a.id)));
    expect(result.content.reviewOf(b.id), same(reviewed.reviewOf(b.id)));
    expect(result.content.memoryOf(b.id), same(reviewed.memoryOf(b.id)));
    expect(result.content.reviewQueue(DateTime(2030)).map((card) => card.id), isNot(contains(b.id)));
    expect(result.content.reviewLogs, reviewed.reviewLogs);
    final undo = StudySetEditor.restore(reviewed, result.content);
    expect(children(undo, null), [a.id, b.id, c.id]);
    expect(undo.card(a.id)!.segments, isEmpty);
    expect(undo.reviewLogs, reviewed.reviewLogs);
  });

  test('split inserts adjacent cards and retains children and relations on first', () {
    final (withChild, child) = editor.addTopic(content, title: 'child', parentId: a.id);
    final (linked, relation) = editor.addRelation(withChild, a.id, c.id);
    final merged = editor.mergeCards(linked, [b.id, a.id]).content;
    final reviewed = editor.rate(merged, a.id, Rating.good);
    final result = editor.splitCard(reviewed, a.id);
    expect(result.succeeded, isTrue);
    expect(result.value, hasLength(2));
    expect(result.value!.first.id, a.id);
    final second = result.value!.last;
    expect(children(result.content, null), [a.id, second.id, c.id]);
    expect(result.content.node(child.id)!.parentId, a.id);
    expect(result.content.relations.single.id, relation!.id);
    expect(result.content.relations.single.fromId, a.id);
    expect(result.content.reviewOf(a.id), same(reviewed.reviewOf(a.id)));
    expect(result.content.reviewOf(second.id), isNull);
    expect(result.content.memoryOf(second.id), isNull);
  });

  test('invalid merge and split return reasons without changing input', () {
    for (final selection in <List<String>>[
      [],
      [a.id],
      [a.id, a.id],
      [a.id, 'missing'],
    ]) {
      final result = editor.mergeCards(content, selection);
      expect(result.succeeded, isFalse);
      expect(result.reason, isNotNull);
      expect(result.reason, editor.mergeReason(content, selection));
      expect(result.content, same(content));
      expect(result.value, isNull);
    }
    for (final id in [a.id, 'missing']) {
      final result = editor.splitCard(content, id);
      expect(result.succeeded, isFalse);
      expect(result.reason, isNotNull);
      expect(result.content, same(content));
    }
  });

  test('summary spans siblings and rejects overlapping ranges', () {
    final (before, child) = editor.addTopic(content, title: 'child', parentId: a.id);
    for (final selection in <List<String>>[
      [],
      [a.id, child.id],
      ['missing'],
    ]) {
      final result = editor.createSummary(before, selection);
      expect(result.succeeded, isFalse);
      expect(result.reason, editor.summaryReason(before, selection));
      expect(result.content, same(before));
    }
    final result = editor.createSummary(before, [b.id, a.id], label: 'Summary');
    expect(result.succeeded, isTrue);
    expect(result.content.summaryRange(result.value!), [a.id, b.id]);
    expect(editor.summaryReason(result.content, [b.id, c.id]), isNotNull);
    expect(editor.summaryReason(result.content, [a.id, b.id]), isNotNull);
    expect(editor.summaryReason(result.content, [a.id, b.id], excludingSummaryId: result.value!.id), isNull);
    final adjusted = editor.adjustSummaryRange(result.content, result.value!.id, [b.id, c.id]);
    expect(adjusted.succeeded, isTrue);
    expect(adjusted.content.summaryRange(adjusted.value!), [b.id, c.id]);
    expect(adjusted.value!.cardId, result.value!.cardId);
    final spanning = editor.createSummary(before, [c.id, a.id]);
    expect(spanning.content.summaryRange(spanning.value!), [a.id, b.id, c.id]);
  });

  test('disabled reasons distinguish center, image, summary and other-map cards', () {
    expect(editor.mergeReason(content, [a.id, 'root']), MapEditReason.centerTopic);
    final (withImage, image) = editor.createImage(content, imageFileName: 'image.png');
    expect(editor.mergeReason(withImage, [a.id, image.id]), MapEditReason.imageCard);
    final made = editor.createSummary(content, [a.id]);
    expect(editor.mergeReason(made.content, [a.id, made.value!.cardId!]), MapEditReason.summaryTopic);
    expect(editor.summaryReason(made.content, [made.value!.cardId!]), MapEditReason.summaryTopic);
    final (withMap, other) = editor.addMap(content, title: 'other');
    final otherEditor = StudySetEditor(mapId: other.id, newId: () => 'other-only', now: () => DateTime(2026));
    final (before, otherCard) = otherEditor.addTopic(withMap, title: 'other');
    expect(editor.mergeReason(before, [a.id, otherCard.id]), MapEditReason.missingCard);
    expect(editor.adjustSummaryRange(made.content, 'missing', [a.id]).reason, MapEditReason.missingSummary);
  });

  test('summary root is a card outside nodes and accepts ordinary child nodes', () {
    final made = editor.createSummary(content, [a.id, b.id], label: 'Summary');
    final summary = made.value!;
    expect(summary.cardId, isNotNull);
    expect(made.content.card(summary.cardId!)!.title, 'Summary');
    expect(made.content.node(summary.cardId!), isNull);
    final (withChild, child) = editor.addTopic(made.content, title: 'explanation', parentId: summary.cardId);
    expect(withChild.node(child.id)!.parentId, summary.cardId);
    expect(children(withChild, null), [a.id, b.id, c.id]);
    final removed = editor.removeSummary(withChild, summary.id);
    expect(removed.summaries, isEmpty);
    expect(removed.card(summary.cardId!), isNull);
    expect(removed.card(child.id), isNull);
    expect(children(removed, null), [a.id, b.id, c.id]);
  });

  test('merge shrinks affected summary and drops ranges with no survivors', () {
    final made = editor.createSummary(content, [b.id, c.id], label: 'range');
    final merged = editor.mergeCards(made.content, [a.id, b.id]);
    expect(merged.content.summaries, hasLength(1));
    expect(merged.content.summaryRange(merged.content.summaries.single), [c.id]);
    final dropped = editor.mergeCards(merged.content, [a.id, c.id]);
    expect(dropped.content.summaries, isEmpty);
    expect(dropped.removedSummaryCount, 1);
    expect(dropped.content.card(made.value!.cardId!), isNull);
  });

  test('relations deduplicate opposite endpoints and support style and reversal', () {
    final (linked, relation) = editor.addRelation(content, a.id, b.id);
    expect(editor.addRelation(linked, b.id, a.id), (linked, relation));
    final styled = editor.updateRelation(
      linked,
      relation!.id,
      arrow: RelationArrow.both,
      solid: true,
      control1: const RelationControlPoint(10, 20),
      control2: const RelationControlPoint(-4, 8),
    );
    expect(styled.relations.single.arrow, RelationArrow.both);
    expect(styled.relations.single.solid, isTrue);
    final reversed = editor.reverseRelation(styled, relation.id).relations.single;
    expect(reversed.fromId, b.id);
    expect(reversed.toId, a.id);
    expect(reversed.control1, const RelationControlPoint(-4, 8));
    expect(reversed.control2, const RelationControlPoint(10, 20));
    final reset = editor.updateRelation(styled, relation.id, resetControl1: true, resetControl2: true);
    expect(reset.relations.single.control1, isNull);
    expect(reset.relations.single.control2, isNull);
    expect(editor.updateRelation(linked, 'missing', solid: true), same(linked));
  });

  test('map appearance updates only the scoped map', () {
    final (before, other) = editor.addMap(content, title: 'other');
    final next = editor.setMapPalette(editor.setMapStructure(before, MapStructure.tree), MapPalette.ink);
    expect(next.map(MindMap.defaultId)!.structure, MapStructure.tree);
    expect(next.map(MindMap.defaultId)!.palette, MapPalette.ink);
    expect(next.map(other.id), same(other));
    expect(next.cards, same(before.cards));
    expect(next.nodes, same(before.nodes));
  });

  test('merge retains other map placements and archives consumed shared cards', () {
    final (withMap, other) = editor.addMap(content, title: 'other');
    var nextId = 100;
    final otherEditor = StudySetEditor(mapId: other.id, newId: () => 'other-${++nextId}', now: () => DateTime(2026));
    final placed = otherEditor.placeCard(otherEditor.placeCard(withMap, b.id), c.id);
    final (linked, relation) = otherEditor.addRelation(placed, b.id, c.id);
    final result = editor.mergeCards(linked, [a.id, b.id]);
    expect(result.content.node(b.id), isNull);
    expect(result.content.node(b.id, mapId: other.id), same(linked.node(b.id, mapId: other.id)));
    expect(result.content.node(c.id, mapId: other.id), same(linked.node(c.id, mapId: other.id)));
    expect(result.content.card(b.id)!.title, 'B');
    expect(result.content.card(b.id)!.suspended, isTrue);
    expect(result.content.relations.single, same(relation));
    expect(result.content.reviewQueue(DateTime(2030), mapId: other.id).map((card) => card.id), isNot(contains(b.id)));
  });

  test('splitting a shared merged card preserves its segments in the other map', () {
    final merged = editor.mergeCards(content, [a.id, b.id]).content;
    final (withMap, other) = editor.addMap(merged, title: 'other');
    final otherEditor = StudySetEditor(mapId: other.id, newId: () => 'other', now: () => DateTime(2026));
    final before = otherEditor.placeCard(withMap, a.id);
    final after = editor.splitCard(before, a.id).content;
    final texts = [
      for (final node in after.childrenOf(null, mapId: other.id))
        for (final segment in after.segmentsOf(after.card(node.cardId)!)) segment.text,
    ];
    expect(texts, ['A', 'B']);
  });

  test('moving the sole covered card into its own summary cannot delete it', () {
    final made = editor.createSummary(content, [a.id], label: 'summary');
    final after = editor.moveMany(made.content, [a.id], made.value!.cardId);
    expect(after.card(a.id), isNotNull);
    expect(after.node(a.id), isNotNull);
    expect(after, same(made.content));
    expect(editor.move(made.content, a.id, made.value!.cardId), same(made.content));
  });

  test('moving a parent into its nested summary descendants rejects a cycle', () {
    final (withChild, child) = editor.addTopic(content, title: 'child', parentId: a.id);
    final made = editor.createSummary(withChild, [child.id], label: 'nested summary');
    final (before, explanation) = editor.addTopic(made.content, title: 'explanation', parentId: made.value!.cardId);
    expect(editor.moveMany(before, [a.id], explanation.id), same(before));
    expect(editor.move(before, a.id, explanation.id), same(before));
  });
}
