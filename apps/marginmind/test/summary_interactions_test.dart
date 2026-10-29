import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:mm_core/mm_core.dart';

import 'mind_map_cache_test.dart' show update;

void main() {
  late StudySetContent content;
  late StudySetEditor editor;
  setUp(() {
    var seq = 0;
    editor = StudySetEditor(newId: () => 'id${seq++}', now: () => DateTime(2026));
    content = StudySetContent(
      cards: [
        for (final id in ['a', 'b', 'c', 'd']) Card(id: id, kind: CardKind.topic, title: id, createdAt: DateTime(2026)),
      ],
      nodes: [
        for (var i = 0; i < 4; i++) MapNode(cardId: ['a', 'b', 'c', 'd'][i], order: i.toDouble()),
      ],
    );
  });

  test('range snapping excludes the opposite side, overlap and crossing', () {
    final result = editor.createSummary(content, ['a', 'b'], label: 'Summary');
    content = result.content;
    final summary = result.value!;
    final rects = {
      for (var i = 0; i < 4; i++) ['a', 'b', 'c', 'd'][i]: Rect.fromLTWH(100, i * 100, 50, 30),
    };
    expect(summaryRangeAt(content, summary, rects, {'d'}, const Offset(200, 320), start: false), ('a', 'c'));
    expect(
      summaryRangeAt(content, summary, rects, {}, const Offset(200, 320), start: true),
      isNull,
      reason: 'cannot cross the other end',
    );
    content = editor.createSummary(content, ['c'], label: 'Other').content;
    expect(
      summaryRangeAt(content, summary, rects, {'d'}, const Offset(200, 220), start: false),
      isNull,
      reason: 'cannot overlap',
    );
  });

  for (final structure in MapStructure.values) {
    test('$structure lays out summary topics and descendants and updates after editing', () {
      content = editor.setMapStructure(content, structure);
      final result = editor.createSummary(content, ['a', 'c'], label: 'Summary');
      final summary = result.value!;
      final (next, child) = editor.addTopic(result.content, parentId: summary.cardId, title: 'Detail');
      final cache = MindMapRenderCache();
      final layout = update(cache, next);
      expect(layout.rects[summary.cardId], isNotNull);
      expect(layout.rects[child.id], isNotNull);
      final branches = mapBranches(layout, rootNodeId, summarySources: {summary.cardId!: summary.fromId});
      expect(branches[child.id], branches[summary.fromId], reason: 'summary details inherit their source branch');
      expect(layout.edges.any((e) => e.parentId == summary.cardId && e.childId == child.id), isTrue);
      final changed = update(cache, editor.rename(next, child.id, 'A much wider detail topic'));
      expect(changed.rects[child.id]!.width, greaterThan(layout.rects[child.id]!.width));
      final folded = update(cache, editor.setCollapsed(next, 'a', collapsed: true));
      expect(folded.rects[summary.cardId], isNotNull);
    });
  }

  test('saved control points follow endpoint centers across layouts', () {
    const relation = MapRelation(
      id: 'r',
      fromId: 'a',
      toId: 'b',
      control1: RelationControlPoint(80, -40),
      control2: RelationControlPoint(-50, 30),
    );
    const a = Rect.fromLTWH(100, 100, 50, 30), b = Rect.fromLTWH(400, 200, 50, 30);
    final first = mapRelationCurve(relation, a, b, [], left: false);
    final moved = mapRelationCurve(relation, a.shift(const Offset(60, 70)), b, [], left: false);
    expect(moved.$2 - first.$2, const Offset(60, 70));
    expect(moved.$3, first.$3);
    expect(relation.control1!.dx, 80);
  });
}
