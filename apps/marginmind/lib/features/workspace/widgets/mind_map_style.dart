import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

/// A cubic Bézier segment: start, two control points, end.
typedef MapCubic = (Offset, Offset, Offset, Offset);

/// The layout arrangement for a map's stored structure.
LayoutStructure layoutStructureOf(MapStructure structure) => switch (structure) {
  MapStructure.mind => LayoutStructure.mind,
  MapStructure.logic => LayoutStructure.logic,
  MapStructure.brace => LayoutStructure.brace,
  MapStructure.tree => LayoutStructure.tree,
};

/// The design tokens of a map's stored palette.
MMMapPalette mapPaletteOf(MapPalette palette) => MMMapPalette.byName(palette.name);

/// One drawn parent-child connector: contiguous segments, and the node whose
/// branch gives its color (null for the neutral line color).
class MapConnector {
  const MapConnector(this.colorId, this.segments);

  final String? colorId;
  final List<MapCubic> segments;

  Path get path {
    final path = Path()..moveTo(segments.first.$1.dx, segments.first.$1.dy);
    for (final s in segments) {
      path.cubicTo(s.$2.dx, s.$2.dy, s.$3.dx, s.$3.dy, s.$4.dx, s.$4.dy);
    }
    return path;
  }
}

/// Which of the root's branches each node belongs to: the index of its
/// first-level ancestor among the root's children, in drawing order.
Map<String, int> mapBranches(TreeLayoutResult layout, String rootId, {Map<String, String> summarySources = const {}}) {
  final children = <String, List<String>>{};
  for (final e in layout.edges) {
    children.putIfAbsent(e.parentId, () => []).add(e.childId);
  }
  final branches = <String, int>{};
  void mark(String id, int branch) {
    if (branches.containsKey(id)) return;
    branches[id] = branch;
    for (final c in children[id] ?? const <String>[]) {
      mark(c, branch);
    }
  }

  final first = children[rootId] ?? const <String>[];
  for (var i = 0; i < first.length; i++) {
    mark(first[i], i);
  }
  // Summary topics are positioned beside their range rather than attached
  // by a tree edge. Their descendants still belong to that range's branch.
  final pending = Map.of(summarySources);
  while (pending.isNotEmpty) {
    final ready = pending.keys.where((id) => branches.containsKey(pending[id])).toList();
    if (ready.isEmpty) break;
    for (final id in ready) {
      mark(id, branches[pending.remove(id)]!);
    }
  }
  return branches;
}

/// The connectors of [layout] in its structure, between nodes drawn at
/// [at]: curves (mind), elbows (logic), one brace per parent (brace) or a
/// trunk down the parent's left side with a branch to each child (tree).
List<MapConnector> mapConnectors(TreeLayoutResult layout, Rect Function(String id) at, {required String rootId}) {
  final out = <MapConnector>[];
  switch (layout.structure) {
    case LayoutStructure.mind:
      for (final e in layout.edges) {
        out.add(MapConnector(e.childId, [_curve(at(e.parentId), at(e.childId), layout.leftSide.contains(e.childId))]));
      }
    case LayoutStructure.logic:
      for (final e in layout.edges) {
        out.add(MapConnector(e.childId, _elbow(at(e.parentId), at(e.childId), layout.leftSide.contains(e.childId))));
      }
    case LayoutStructure.tree:
      for (final e in layout.edges) {
        out.add(MapConnector(e.childId, _trunk(at(e.parentId), at(e.childId))));
      }
    case LayoutStructure.brace:
      final children = <String, List<String>>{};
      for (final e in layout.edges) {
        children.putIfAbsent(e.parentId, () => []).add(e.childId);
      }
      for (final e in children.entries) {
        // Below the root a brace belongs to one branch; the root's spans all.
        final colorId = e.key == rootId ? null : e.key;
        final parent = at(e.key);
        final kids = [for (final id in e.value) at(id)];
        final left = layout.leftSide.contains(e.value.first);
        if (kids.length == 1) {
          out.add(MapConnector(e.value.first, [_curve(parent, kids.single, left)]));
          continue;
        }
        final (brace, tip) = _brace(parent, kids, left);
        out
          ..add(MapConnector(colorId, brace))
          ..add(MapConnector(colorId, [_line(Offset(left ? parent.left : parent.right, parent.center.dy), tip)]));
      }
  }
  return out;
}

/// From the parent's outer side to the child's inner side, level at both ends.
MapCubic _curve(Rect a, Rect b, bool left) {
  final start = Offset(left ? a.left : a.right, a.center.dy);
  final end = Offset(left ? b.right : b.left, b.center.dy);
  final midX = (start.dx + end.dx) / 2;
  return (start, Offset(midX, start.dy), Offset(midX, end.dy), end);
}

MapCubic _line(Offset a, Offset b) => (a, Offset.lerp(a, b, 1 / 3)!, Offset.lerp(a, b, 2 / 3)!, b);

/// A quadratic segment (start, control, end) as a cubic.
MapCubic _quad(Offset a, Offset c, Offset b) => (a, a + (c - a) * (2 / 3), b + (c - b) * (2 / 3), b);

/// How far in from a node's left edge its children's trunk runs in a tree.
const mapTreeTrunkInset = 16.0;

/// Corner radius of elbows and tree branches.
const _corner = 6.0;

/// Out of the parent, along a shared vertical a short way out, and level into
/// the child, with rounded corners.
List<MapCubic> _elbow(Rect a, Rect b, bool left) {
  final dir = left ? -1.0 : 1.0;
  final x0 = left ? a.left : a.right, y0 = a.center.dy;
  final x1 = left ? b.right : b.left, y1 = b.center.dy;
  final mx = x0 + dir * math.min(18.0, (x1 - x0).abs() / 2);
  final dy = y1 - y0;
  if (dy.abs() < 1) return [_line(Offset(x0, y0), Offset(x1, y1))];
  final s = dy.sign, r = math.min(_corner, dy.abs() / 2);
  return [
    _line(Offset(x0, y0), Offset(mx - r * dir, y0)),
    _quad(Offset(mx - r * dir, y0), Offset(mx, y0), Offset(mx, y0 + r * s)),
    _line(Offset(mx, y0 + r * s), Offset(mx, y1 - r * s)),
    _quad(Offset(mx, y1 - r * s), Offset(mx, y1), Offset(mx + r * dir, y1)),
    _line(Offset(mx + r * dir, y1), Offset(x1, y1)),
  ];
}

/// Down from the parent's bottom near its left edge, then right into the
/// child at its middle.
List<MapCubic> _trunk(Rect a, Rect b) {
  final x = a.left + math.min(mapTreeTrunkInset, a.width / 2), y0 = a.bottom, y1 = b.center.dy;
  final r = math.min(_corner, math.min(y1 - y0, b.left - x));
  if (r <= 0) return [_line(Offset(x, y0), Offset(b.left, y1))];
  return [
    _line(Offset(x, y0), Offset(x, y1 - r)),
    _quad(Offset(x, y1 - r), Offset(x, y1), Offset(x + r, y1)),
    _line(Offset(x + r, y1), Offset(b.left, y1)),
  ];
}

/// A curly brace just before [kids] from the first one's middle to the last
/// one's, its point toward the parent; and where the point is.
(List<MapCubic>, Offset) _brace(Rect parent, List<Rect> kids, bool left) {
  const width = 8.0, gap = 6.0;
  final dir = left ? -1.0 : 1.0;
  final x = left ? kids.map((k) => k.right).reduce(math.max) + gap : kids.map((k) => k.left).reduce(math.min) - gap;
  final top = kids.map((k) => k.center.dy).reduce(math.min);
  final bottom = kids.map((k) => k.center.dy).reduce(math.max);
  final k = math.min(width, (bottom - top) / 4);
  final tipY = parent.center.dy.clamp(top + k, bottom - k).toDouble();
  final mid = x - width * dir, tip = Offset(x - 2 * width * dir, tipY);
  return (
    [
      _quad(Offset(x, top), Offset(mid, top), Offset(mid, top + k)),
      _line(Offset(mid, top + k), Offset(mid, tipY - k)),
      _quad(Offset(mid, tipY - k), Offset(mid, tipY), tip),
      _quad(tip, Offset(mid, tipY), Offset(mid, tipY + k)),
      _line(Offset(mid, tipY + k), Offset(mid, bottom - k)),
      _quad(Offset(mid, bottom - k), Offset(mid, bottom), Offset(x, bottom)),
    ],
    tip,
  );
}
