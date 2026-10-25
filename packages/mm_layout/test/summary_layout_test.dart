import 'package:mm_layout/mm_layout.dart';
import 'package:test/test.dart';

void main() {
  const layout = TreeLayout(levelGap: 50, siblingGap: 10, padding: 20, summaryGap: 16, bracketWidth: 12, labelGap: 8);

  // r ─┬─ a ── a1 (wide)
  //    ├─ b
  //    └─ c
  const tree = LayoutNode(
    id: 'r',
    width: 100,
    height: 40,
    children: [
      LayoutNode(
        id: 'a',
        width: 80,
        height: 30,
        children: [LayoutNode(id: 'a1', width: 200, height: 30)],
      ),
      LayoutNode(id: 'b', width: 80, height: 30),
      LayoutNode(id: 'c', width: 80, height: 50),
    ],
  );

  LayoutSummary summary(String id, String parent, String from, String to, {double width = 60}) =>
      LayoutSummary(id: id, parentId: parent, fromId: from, toId: to, width: width, height: 20);

  test('a summary sits right of the deepest node of its range and spans it', () {
    final plain = layout.layout(tree);
    final r = layout.layout(tree, summaries: [summary('s', 'r', 'b', 'a')]);
    expect(r.rects['a']!.top, plain.rects['a']!.top, reason: 'nodes keep their places');
    final p = r.summaries['s']!;
    final a1 = r.rects['a1']!, a = r.rects['a']!, b = r.rects['b']!;
    expect(p.bracket.left, a1.right + 16);
    expect(p.bracket.width, 12);
    expect(p.bracket.top, a.top);
    expect(p.bracket.bottom, b.bottom);
    expect(p.label.left, p.bracket.right + 8);
    expect(p.label.top + p.label.height / 2, (p.bracket.top + p.bracket.bottom) / 2);
    expect(r.width, p.label.right + 20, reason: 'the canvas grows to show the label');
    expect(r.height, plain.height);
  });

  test('a range of shallow siblings ignores deeper ones outside it', () {
    final r = layout.layout(tree, summaries: [summary('s', 'r', 'b', 'c')]);
    expect(r.summaries['s']!.bracket.left, r.rects['c']!.right + 16);
    expect(r.width, r.rects['a1']!.right + 20, reason: 'a1 is still the widest');
  });

  test('a summary of grandchildren and an outer one stack left to right', () {
    final r = layout.layout(
      tree,
      summaries: [summary('outer', 'r', 'a', 'c'), summary('inner', 'a', 'a1', 'a1', width: 40)],
    );
    final inner = r.summaries['inner']!, outer = r.summaries['outer']!;
    expect(inner.bracket.left, r.rects['a1']!.right + 16);
    expect(outer.bracket.left, inner.label.right + 16);
  });

  test('overlapping ranges of one parent do not overlap, narrow first', () {
    final r = layout.layout(tree, summaries: [summary('wide', 'r', 'b', 'c'), summary('narrow', 'r', 'c', 'c')]);
    final narrow = r.summaries['narrow']!, wide = r.summaries['wide']!;
    expect(narrow.bracket.left, r.rects['c']!.right + 16);
    expect(wide.bracket.left, narrow.label.right + 16);
    final apart = layout.layout(tree, summaries: [summary('first', 'r', 'b', 'b'), summary('second', 'r', 'c', 'c')]);
    expect(apart.summaries['first']!.bracket.left, apart.summaries['second']!.bracket.left);
  });

  test('summaries of hidden or unknown nodes are skipped', () {
    final r = layout.layout(tree, summaries: [summary('gone', 'r', 'a', 'x'), summary('folded', 'b', 'b1', 'b1')]);
    expect(r.summaries, isEmpty);
    expect(r.width, layout.layout(tree).width);
  });
}
