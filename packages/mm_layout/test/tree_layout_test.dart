import 'package:mm_layout/mm_layout.dart';
import 'package:test/test.dart';

void main() {
  const layout = TreeLayout(levelGap: 50, siblingGap: 10, padding: 20);

  test('single node sits at the padding', () {
    final r = layout.layout(const LayoutNode(id: 'r', width: 100, height: 40));
    expect(r.rects['r']!.left, 20);
    expect(r.rects['r']!.top, 20);
    expect(r.width, 140);
    expect(r.height, 80);
    expect(r.edges, isEmpty);
  });

  test('children stack to the right and the parent is centered on them', () {
    final r = layout.layout(
      const LayoutNode(
        id: 'r',
        width: 100,
        height: 40,
        children: [
          LayoutNode(id: 'a', width: 80, height: 30),
          LayoutNode(id: 'b', width: 120, height: 50),
        ],
      ),
    );
    final root = r.rects['r']!, a = r.rects['a']!, b = r.rects['b']!;
    expect(a.left, 20 + 100 + 50);
    expect(b.left, a.left);
    expect(b.top, a.bottom + 10);
    final blockCenter = (a.top + b.bottom) / 2;
    expect(root.centerY, closeTo(blockCenter, 1e-9));
    expect(r.edges.map((e) => e.childId), ['a', 'b']);
    expect(r.width, b.right + 20);
  });

  test('a tall leaf grows its subtree without overlapping siblings', () {
    final r = layout.layout(
      const LayoutNode(
        id: 'r',
        width: 10,
        height: 10,
        children: [
          LayoutNode(
            id: 'a',
            width: 10,
            height: 10,
            children: [LayoutNode(id: 'a1', width: 10, height: 100)],
          ),
          LayoutNode(id: 'b', width: 10, height: 10),
        ],
      ),
    );
    expect(r.rects['b']!.top, greaterThanOrEqualTo(r.rects['a1']!.bottom + 10));
    expect(r.rects['a']!.centerY, closeTo(r.rects['a1']!.centerY, 1e-9));
  });

  test('handles wide trees deterministically', () {
    final kids = [for (var i = 0; i < 50; i++) LayoutNode(id: 'k$i', width: 40, height: 20)];
    final r = layout.layout(LayoutNode(id: 'r', width: 40, height: 20, children: kids));
    for (var i = 1; i < 50; i++) {
      expect(r.rects['k$i']!.top, r.rects['k${i - 1}']!.bottom + 10);
    }
  });
}
