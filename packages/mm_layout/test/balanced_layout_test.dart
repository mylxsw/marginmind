import 'package:mm_layout/mm_layout.dart';
import 'package:test/test.dart';

void main() {
  const layout = TreeLayout(levelGap: 50, siblingGap: 10, padding: 20, balanced: true);

  LayoutNode leaf(String id, {double height = 30, double width = 80, List<LayoutNode> children = const []}) =>
      LayoutNode(id: id, width: width, height: height, children: children);

  test('a single branch stays on the right', () {
    final r = layout.layout(leaf('r', width: 100, height: 40, children: [leaf('a')]));
    expect(r.rects['r']!.left, 20);
    expect(r.rects['a']!.left, 20 + 100 + 50);
    expect(r.leftSide, isEmpty);
  });

  test('branches split so both sides are about as tall, first ones on the right', () {
    final r = layout.layout(leaf('r', width: 100, height: 40, children: [for (final id in 'abcd'.split('')) leaf(id)]));
    final root = r.rects['r']!;
    expect(r.leftSide, {'c', 'd'});
    for (final id in ['a', 'b']) {
      expect(r.rects[id]!.left, root.right + 50);
    }
    for (final id in ['c', 'd']) {
      expect(r.rects[id]!.right, root.left - 50);
    }
    // Both sides are centered on the root, top to bottom in branch order.
    expect(r.rects['b']!.top, r.rects['a']!.bottom + 10);
    expect(r.rects['d']!.top, r.rects['c']!.bottom + 10);
    expect((r.rects['a']!.top + r.rects['b']!.bottom) / 2, closeTo(root.centerY, 1e-9));
    expect((r.rects['c']!.top + r.rects['d']!.bottom) / 2, closeTo(root.centerY, 1e-9));
    // The leftmost node sits at the padding; the canvas spans both sides.
    expect(r.rects['c']!.left, 20);
    expect(r.width, r.rects['a']!.right + 20);
    expect(r.height, 30 * 2 + 10 + 40);
    expect(r.edges.map((e) => (e.parentId, e.childId)), [('r', 'a'), ('r', 'b'), ('r', 'c'), ('r', 'd')]);
  });

  test('an odd branch goes right, and tall subtrees are weighed by height', () {
    final odd = layout.layout(leaf('r', children: [leaf('a'), leaf('b'), leaf('c')]));
    expect(odd.leftSide, {'c'});

    final heavy = layout.layout(leaf('r', children: [leaf('a', height: 200), leaf('b'), leaf('c'), leaf('d')]));
    expect(heavy.leftSide, {'b', 'c', 'd'});
  });

  test('left subtrees grow leftward and descendants are marked as left', () {
    final r = layout.layout(
      leaf(
        'r',
        children: [
          leaf('a'),
          leaf('b', children: [leaf('b1', width: 120), leaf('b2')]),
        ],
      ),
    );
    expect(r.leftSide, {'b', 'b1', 'b2'});
    final b = r.rects['b']!, b1 = r.rects['b1']!, b2 = r.rects['b2']!;
    expect(b1.right, b.left - 50);
    expect(b2.right, b.left - 50);
    expect(b.centerY, closeTo((b1.top + b2.bottom) / 2, 1e-9));
    expect(b1.left, 20, reason: 'the widest left node sets the padding');
    expect(r.edges.map((e) => e.childId), containsAll(['b1', 'b2']));
  });

  test('a tall right side makes the canvas tall and keeps the left centered', () {
    final r = layout.layout(
      leaf(
        'r',
        children: [
          leaf('a', children: [leaf('a1', height: 100), leaf('a2', height: 100)]),
          leaf('b'),
        ],
      ),
    );
    expect(r.height, 210 + 40);
    expect(r.rects['b']!.centerY, closeTo(r.rects['r']!.centerY, 1e-9));
  });

  group('summaries', () {
    const withSummaries = TreeLayout(
      levelGap: 50,
      siblingGap: 10,
      padding: 20,
      summaryGap: 16,
      bracketWidth: 12,
      labelGap: 8,
      balanced: true,
    );

    LayoutSummary summary(String id, String parent, String from, String to) =>
        LayoutSummary(id: id, parentId: parent, fromId: from, toId: to, width: 60, height: 20);

    test('on the left, the bracket and label open leftward past the range', () {
      final tree = leaf(
        'r',
        children: [
          leaf('a'),
          leaf('b', children: [leaf('b1', width: 150), leaf('b2')]),
        ],
      );
      final r = withSummaries.layout(tree, summaries: [summary('s', 'b', 'b2', 'b1')]);
      final p = r.summaries['s']!;
      final b1 = r.rects['b1']!, b2 = r.rects['b2']!;
      expect(p.left, isTrue);
      expect(p.bracket.right, b1.left - 16);
      expect(p.bracket.width, 12);
      expect(p.bracket.top, b1.top);
      expect(p.bracket.bottom, b2.bottom);
      expect(p.label.right, p.bracket.left - 8);
      expect(p.label.left, 20, reason: 'the label is the leftmost thing on the canvas');
    });

    test('nested left ranges are placed beyond each other', () {
      final tree = leaf(
        'r',
        children: [
          leaf('a'),
          leaf('b', children: [leaf('b1'), leaf('b2'), leaf('b3')]),
        ],
      );
      final r = withSummaries.layout(
        tree,
        summaries: [summary('wide', 'b', 'b1', 'b3'), summary('narrow', 'b', 'b1', 'b2')],
      );
      expect(r.summaries['wide']!.bracket.right, r.summaries['narrow']!.label.left - 16);
    });

    test('a right-side summary of the root stays on the right', () {
      final tree = leaf('r', children: [leaf('a'), leaf('b'), leaf('c'), leaf('d')]);
      final r = withSummaries.layout(tree, summaries: [summary('s', 'r', 'a', 'b')]);
      final p = r.summaries['s']!;
      expect(p.left, isFalse);
      expect(p.bracket.left, r.rects['a']!.right + 16);
    });

    test('the split never cuts through a summary of the root', () {
      final tree = leaf('r', children: [leaf('a'), leaf('b'), leaf('c'), leaf('d')]);
      final r = withSummaries.layout(tree, summaries: [summary('s', 'r', 'b', 'c')]);
      expect(r.leftSide, {'d'});
      expect(r.summaries['s']!.left, isFalse);

      final all = withSummaries.layout(tree, summaries: [summary('s', 'r', 'a', 'd')]);
      expect(all.leftSide, isEmpty, reason: 'no split avoids the range');
      expect(all.summaries['s']!.bracket.left, all.rects['a']!.right + 16);
    });
  });

  test('a right-growing layout is unchanged by the option', () {
    final tree = leaf('r', children: [leaf('a'), leaf('b')]);
    final plain = const TreeLayout(levelGap: 50, siblingGap: 10, padding: 20).layout(tree);
    expect(plain.leftSide, isEmpty);
    expect(plain.rects['b']!.left, plain.rects['a']!.left);
  });
}
