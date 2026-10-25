import 'package:mm_layout/mm_layout.dart';
import 'package:test/test.dart';

void main() {
  test('500 nodes: full layout and one resized node p95 below 16 ms', () {
    LayoutNode tree(int iteration) => LayoutNode(
      id: 'root',
      width: 120,
      height: 42,
      children: [
        for (var branch = 0; branch < 10; branch++)
          LayoutNode(
            id: 'b$branch',
            width: 160,
            height: 34,
            children: [
              for (var leaf = 0; leaf < (branch == 9 ? 48 : 49); leaf++)
                LayoutNode(
                  id: '$branch-$leaf',
                  width: 240,
                  height: branch == 0 && leaf == 0 ? 90.0 + iteration % 80 : 90,
                ),
            ],
          ),
      ],
    );
    const layout = TreeLayout(levelGap: 56, siblingGap: 14, padding: 72);
    final samples = <int>[];
    for (var i = 0; i < 220; i++) {
      final input = tree(i);
      final timer = Stopwatch()..start();
      final result = layout.layout(input);
      timer.stop();
      expect(result.rects, hasLength(500));
      expect(result.edges, hasLength(499));
      if (i >= 20) samples.add(timer.elapsedMicroseconds);
    }
    samples.sort();
    print('500-node full layout/reflow: median=${samples[99]}us p95=${samples[189]}us (limit 16000us)');
    expect(samples[189], lessThan(16000));
  });
}
