import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_drop.dart';
import 'package:mm_core/mm_core.dart';

final _now = DateTime(2026);

/// root ─ a ─ a1
///      ├ b
///      └ c
StudySetContent _content() => StudySetContent(
  cards: [for (final id in ['a', 'a1', 'b', 'c']) Card(id: id, kind: CardKind.topic, title: id, createdAt: _now)],
  nodes: const [
    MapNode(cardId: 'a', parentId: null, order: 0),
    MapNode(cardId: 'b', parentId: null, order: 1),
    MapNode(cardId: 'c', parentId: null, order: 2),
    MapNode(cardId: 'a1', parentId: 'a', order: 0),
  ],
);

const _rects = {
  'root': Rect.fromLTWH(0, 60, 80, 40),
  'a': Rect.fromLTWH(140, 0, 100, 40),
  'b': Rect.fromLTWH(140, 54, 100, 40),
  'c': Rect.fromLTWH(140, 108, 100, 40),
  'a1': Rect.fromLTWH(300, 0, 100, 40),
};

MapDrop? _at(Offset point, {Set<String> moving = const {'c'}}) => MapDrop.resolve(
  point: point,
  rects: _rects,
  content: _content(),
  moving: moving,
  rootId: 'root',
  gap: 14,
);

void main() {
  group('MapDrop.resolve', () {
    test('top, middle and bottom of a node insert before, as child and after', () {
      expect(_at(const Offset(150, 56)), const MapDrop(targetId: 'b', zone: MapDropZone.before, parentId: null, index: 1));
      expect(_at(const Offset(150, 74)), const MapDrop(targetId: 'b', zone: MapDropZone.child, parentId: 'b', index: null));
      expect(_at(const Offset(150, 92)), const MapDrop(targetId: 'b', zone: MapDropZone.after, parentId: null, index: 2));
      // Indexes skip the moving node: moving `a` puts "before b" at 0.
      expect(_at(const Offset(150, 56), moving: {'a'})!.index, 0);
      expect(_at(const Offset(310, 2), moving: {'b'}), const MapDrop(targetId: 'a1', zone: MapDropZone.before, parentId: 'a', index: 0));
    });

    test('the gap between siblings belongs to the nearer node', () {
      // a ends at 40, b starts at 54: 45 is nearer a, 50 nearer b.
      expect(_at(const Offset(150, 45))!.targetId, 'a');
      expect(_at(const Offset(150, 45))!.zone, MapDropZone.after);
      expect(_at(const Offset(150, 50))!.targetId, 'b');
      expect(_at(const Offset(150, 50))!.zone, MapDropZone.before);
      // Both mean the same slot.
      expect(_at(const Offset(150, 45))!.index, _at(const Offset(150, 50))!.index);
    });

    test('the root only takes children; empty space, moving nodes and descendants take nothing', () {
      expect(_at(const Offset(10, 62)), const MapDrop(targetId: 'root', zone: MapDropZone.child, parentId: null, index: null));
      expect(_at(const Offset(110, 70)), isNull);
      expect(_at(const Offset(150, 300)), isNull);
      expect(_at(const Offset(150, 120)), isNull);
      expect(_at(const Offset(310, 20), moving: {'a'}), isNull);
      expect(_at(const Offset(310, 20), moving: {'b', 'a'}), isNull);
    });

    test('equality and description', () {
      const drop = MapDrop(targetId: 'b', zone: MapDropZone.after, parentId: null, index: 2);
      expect(drop.hashCode, const MapDrop(targetId: 'b', zone: MapDropZone.after, parentId: null, index: 2).hashCode);
      expect(drop == const MapDrop(targetId: 'b', zone: MapDropZone.after, parentId: null, index: 1), isFalse);
      expect(drop.toString(), contains('after'));
    });
  });

  test('previewRect: ring on the parent, lines centered in the sibling gap', () {
    const after = MapDrop(targetId: 'a', zone: MapDropZone.after, parentId: null, index: 1);
    const before = MapDrop(targetId: 'b', zone: MapDropZone.before, parentId: null, index: 1);
    const child = MapDrop(targetId: 'b', zone: MapDropZone.child, parentId: 'b', index: null);
    final line = after.previewRect(_rects, gap: 14, thickness: 3);
    expect(line, const Rect.fromLTWH(140, 45.5, 100, 3));
    // "After a" and "before b" are the same slot and the same line.
    expect(before.previewRect(_rects, gap: 14, thickness: 3).center.dy, line.center.dy);
    expect(child.previewRect(_rects, gap: 14, thickness: 3), _rects['b']);
  });

  group('auto-scroll', () {
    const viewport = Size(400, 300);
    Offset v(Offset p) => autoScrollVelocity(p, viewport, edge: 40, maxSpeed: 800);

    test('speed grows toward each side and is full beyond it', () {
      expect(v(const Offset(200, 150)), Offset.zero);
      expect(v(const Offset(20, 150)), const Offset(400, 0));
      expect(v(const Offset(380, 150)), const Offset(-400, 0));
      expect(v(const Offset(200, 0)), const Offset(0, 800));
      expect(v(const Offset(200, 900)), const Offset(0, -800));
      expect(v(const Offset(-50, -50)), const Offset(800, 800));
      expect(autoScrollVelocity(const Offset(10, 10), const Size(60, 60), edge: 40, maxSpeed: 800), Offset.zero);
    });

    test('stops once the far side of the map is inside the margin', () {
      Offset clamp(Offset t, Offset step, Rect content) => clampAutoScroll(t, step, content, viewport, margin: 40);
      // Content 0..1000 wide on screen at translation 0: room to reveal the right.
      expect(clamp(Offset.zero, const Offset(-30, 0), const Rect.fromLTWH(0, 0, 1000, 200)), const Offset(-30, 0));
      // Right side at 370: only 10 more before it reaches 400 - 40.
      expect(
        clamp(const Offset(-630, 0), const Offset(-30, 0), const Rect.fromLTWH(-630, 0, 1000, 200)),
        const Offset(-640, 0),
      );
      // Already past the limit: left alone rather than pulled back.
      expect(clamp(const Offset(-700, 0), const Offset(-30, 0), const Rect.fromLTWH(-700, 0, 1000, 200)), const Offset(-700, 0));
      // Left side at 20: room for 20 more toward the left, nothing upward.
      expect(clamp(const Offset(20, 50), const Offset(30, 30), const Rect.fromLTWH(20, 50, 1000, 200)), const Offset(40, 50));
      expect(clamp(const Offset(5, 5), Offset.zero, const Rect.fromLTWH(5, 5, 10, 10)), const Offset(5, 5));
      expect(clamp(Offset.zero, const Offset(0, -30), const Rect.fromLTWH(0, 0, 100, 1000)), const Offset(0, -30));
    });
  });
}
