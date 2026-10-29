import 'package:mm_layout/mm_layout.dart';
import 'package:test/test.dart';

LayoutNode node(String id, {double height = 30, List<LayoutNode> children = const []}) =>
    LayoutNode(id: id, width: 80, height: height, children: children);

void contained(TreeLayoutResult result) {
  for (final rect in [
    ...result.rects.values,
    for (final summary in result.summaries.values) ...[summary.bracket, summary.label],
  ]) {
    expect(rect.left, greaterThanOrEqualTo(20));
    expect(rect.top, greaterThanOrEqualTo(20));
    expect(rect.right, lessThanOrEqualTo(result.width - 20));
    expect(rect.bottom, lessThanOrEqualTo(result.height - 20));
  }
}

void main() {
  final root = node(
    'root',
    children: [
      node('a', children: [node('a1'), node('a2')]),
      node('b'),
      node('c'),
      node('d'),
    ],
  );

  test('default mind keeps the legacy right-growing layout and balanced opt-in', () {
    final legacy = const TreeLayout(padding: 20).layout(root);
    expect(legacy.structure, LayoutStructure.mind);
    expect(legacy.leftSide, isEmpty);
    final balanced = const TreeLayout(balanced: true, padding: 20).layout(root);
    expect(balanced.leftSide, isNotEmpty);
    for (final id in balanced.leftSide) {
      expect(balanced.rects[id]!.right, lessThan(balanced.rects['root']!.left));
    }
    contained(balanced);
  });

  for (final structure in [LayoutStructure.logic, LayoutStructure.brace]) {
    test('$structure grows right despite balanced, with connector clearance', () {
      final result = TreeLayout(structure: structure, balanced: true, padding: 20).layout(root);
      expect(result.structure, structure);
      expect(result.leftSide, isEmpty);
      for (final edge in result.edges) {
        final parent = result.rects[edge.parentId]!, child = result.rects[edge.childId]!;
        expect(child.left - parent.right, structure == LayoutStructure.brace ? 80 : 56);
      }
      expect(result.rects['b']!.top, greaterThan(result.rects['a2']!.bottom));
      contained(result);
    });
  }

  test('tree walks depth first below parents with one indent per level', () {
    final result = const TreeLayout(structure: LayoutStructure.tree, balanced: true, padding: 20).layout(root);
    expect(result.structure, LayoutStructure.tree);
    expect(result.leftSide, isEmpty);
    expect(result.rects['root']!.top, 20);
    for (final edge in result.edges) {
      final parent = result.rects[edge.parentId]!, child = result.rects[edge.childId]!;
      expect(child.left, parent.left + 56);
      expect(child.top, greaterThanOrEqualTo(parent.bottom + 14));
    }
    expect(result.rects['a2']!.top, result.rects['a1']!.bottom + 14);
    expect(result.rects['b']!.top, result.rects['a2']!.bottom + 14);
    contained(result);
  });

  for (final structure in LayoutStructure.values) {
    test('$structure reserves a tall summary subtree before the next sibling', () {
      final result = TreeLayout(structure: structure, padding: 20).layout(
        root,
        summaries: [
          LayoutSummary(
            id: 's',
            parentId: 'root',
            fromId: 'b',
            toId: 'a',
            // Node dimensions override legacy label dimensions.
            width: 1,
            height: 1,
            node: node('topic', children: [node('detail1', height: 180), node('detail2', height: 180)]),
          ),
        ],
      );
      final placement = result.summaries['s']!;
      expect(placement.label.toString(), result.rects['topic'].toString());
      expect(placement.label.width, 80);
      expect(placement.label.left, placement.bracket.right + 8);
      expect(placement.bracket.left, greaterThan(result.rects['a1']!.right));
      expect(result.rects['c']!.top, greaterThanOrEqualTo(result.rects['detail2']!.bottom + 14));
      expect(result.edges.where((e) => e.parentId == 'topic').map((e) => e.childId), ['detail1', 'detail2']);
      expect(result.edges.any((e) => e.childId == 'topic'), isFalse, reason: 'the summary bracket connects the topic');
      if (structure == LayoutStructure.tree) {
        expect(result.rects['detail1']!.left, placement.label.left + 56);
        expect(result.rects['detail1']!.top, greaterThan(placement.label.bottom));
      }
      contained(result);
    });

    test('$structure keeps the summarized range compact around a tall topic subtree', () {
      final result = TreeLayout(structure: structure, padding: 20).layout(
        node('r', children: [node('a', height: 20), node('b', height: 20), node('c', height: 20)]),
        summaries: [
          LayoutSummary(
            id: 's',
            parentId: 'r',
            fromId: 'a',
            toId: 'b',
            node: node('topic', height: 20, children: [for (var i = 0; i < 4; i++) node('t$i', height: 20)]),
          ),
        ],
      );
      final a = result.rects['a']!, b = result.rects['b']!, c = result.rects['c']!, topic = result.rects['topic']!;
      final bracket = result.summaries['s']!.bracket;
      expect(b.top - a.bottom, 14);
      expect(bracket.top, a.top);
      expect(bracket.bottom, b.bottom);
      expect(topic.top + topic.height / 2, closeTo((a.top + b.bottom) / 2, 0.001));
      final subtreeBottom = [for (var i = 0; i < 4; i++) result.rects['t$i']!.bottom].reduce((x, y) => x > y ? x : y);
      expect(c.top, greaterThanOrEqualTo(subtreeBottom + 14));
      contained(result);
    });

    test('$structure ignores a hidden summary subtree', () {
      final result = TreeLayout(structure: structure, padding: 20).layout(
        root,
        summaries: [LayoutSummary(id: 's', parentId: 'a', fromId: 'missing', toId: 'a1', node: node('hidden'))],
      );
      expect(result.rects, isNot(contains('hidden')));
      expect(result.summaries, isEmpty);
      contained(result);
    });

    test('$structure handles a single node', () {
      final result = TreeLayout(structure: structure, padding: 20).layout(node('only'));
      expect(result.rects['only']!.top, 20);
      expect(result.rects['only']!.left, 20);
      expect(result.width, 120);
      expect(result.height, 70);
      expect(result.edges, isEmpty);
    });
  }

  test('disjoint summary trees reserve independent bands and clear nested summaries', () {
    final result = const TreeLayout(padding: 20).layout(
      root,
      summaries: [
        LayoutSummary(
          id: 'first',
          parentId: 'root',
          fromId: 'a',
          toId: 'a',
          node: node(
            'topic1',
            children: [
              node('branch', children: [node('deep', height: 250)]),
            ],
          ),
        ),
        LayoutSummary(
          id: 'second',
          parentId: 'root',
          fromId: 'b',
          toId: 'b',
          node: node('topic2', children: [node('detail', height: 350)]),
        ),
        const LayoutSummary(id: 'inner', parentId: 'a', fromId: 'a1', toId: 'a2', width: 200, height: 20),
        const LayoutSummary(id: 'outer', parentId: 'root', fromId: 'a', toId: 'b', width: 60, height: 20),
      ],
    );
    expect(result.summaries['first']!.bracket.left, result.summaries['inner']!.label.right + 16);
    expect(result.rects['topic2']!.top, greaterThan(result.rects['deep']!.bottom));
    expect(result.rects['c']!.top, greaterThan(result.rects['detail']!.bottom));
    expect(result.summaries['outer']!.bracket.left, greaterThan(result.rects['deep']!.right));
    contained(result);
  });

  test('left summary descendants mirror and outer summaries clear the entire subtree', () {
    final result = const TreeLayout(balanced: true, padding: 20).layout(
      node(
        'r',
        children: [
          node('right', height: 1000),
          node('left', children: [node('l1'), node('l2')]),
        ],
      ),
      summaries: [
        LayoutSummary(
          id: 'inner',
          parentId: 'left',
          fromId: 'l1',
          toId: 'l2',
          node: node('topic', children: [node('detail', height: 200)]),
        ),
        const LayoutSummary(id: 'outer', parentId: 'r', fromId: 'left', toId: 'left', width: 60, height: 20),
      ],
    );
    expect(result.leftSide, containsAll(['left', 'l1', 'l2', 'topic', 'detail']));
    expect(result.summaries['inner']!.left, isTrue);
    expect(result.rects['topic']!.right, result.summaries['inner']!.bracket.left - 8);
    expect(result.rects['detail']!.right, result.rects['topic']!.left - 56);
    expect(result.summaries['outer']!.bracket.right, result.rects['detail']!.left - 16);
    contained(result);
  });

  test('root summary with a subtree cannot be split across mind map sides', () {
    final result = const TreeLayout(balanced: true).layout(
      root,
      summaries: [LayoutSummary(id: 's', parentId: 'root', fromId: 'b', toId: 'c', node: node('topic'))],
    );
    expect(result.leftSide.contains('b'), result.leftSide.contains('c'));
    expect(result.leftSide.contains('topic'), result.leftSide.contains('b'));
  });
}
