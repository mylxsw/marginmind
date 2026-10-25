import 'package:meta/meta.dart';

/// Input: a node with its measured size and children in display order.
@immutable
class LayoutNode {
  const LayoutNode({required this.id, required this.width, required this.height, this.children = const []});

  final String id;
  final double width;
  final double height;
  final List<LayoutNode> children;
}

@immutable
class LayoutRect {
  const LayoutRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerY => top + height / 2;

  @override
  String toString() => 'LayoutRect($left, $top, $width, $height)';
}

/// A connector from a parent's right edge to a child's left edge.
@immutable
class LayoutEdge {
  const LayoutEdge(this.parentId, this.childId);

  final String parentId;
  final String childId;
}

@immutable
class TreeLayoutResult {
  const TreeLayoutResult({required this.rects, required this.edges, required this.width, required this.height});

  final Map<String, LayoutRect> rects;
  final List<LayoutEdge> edges;

  /// Total canvas size including padding.
  final double width;
  final double height;
}

/// Lays a tree out left-to-right: each level sits [levelGap] to the right
/// of its parent, siblings stack with [siblingGap], and every parent is
/// vertically centered on the block of its children.
class TreeLayout {
  const TreeLayout({this.levelGap = 56, this.siblingGap = 14, this.padding = 48});

  final double levelGap;
  final double siblingGap;
  final double padding;

  TreeLayoutResult layout(LayoutNode root) {
    final heights = <String, double>{};
    double measure(LayoutNode n) {
      final block = _childrenBlock(n, measure);
      final h = block > n.height ? block : n.height;
      heights[n.id] = h;
      return h;
    }

    measure(root);
    final rects = <String, LayoutRect>{};
    final edges = <LayoutEdge>[];
    var maxRight = 0.0;

    void place(LayoutNode n, double x, double y) {
      final subtree = heights[n.id]!;
      final rect = LayoutRect(x, y + (subtree - n.height) / 2, n.width, n.height);
      rects[n.id] = rect;
      if (rect.right > maxRight) maxRight = rect.right;
      if (n.children.isEmpty) return;
      final block = n.children.fold<double>(0, (s, c) => s + heights[c.id]!) + siblingGap * (n.children.length - 1);
      var cy = y + (subtree - block) / 2;
      for (final c in n.children) {
        edges.add(LayoutEdge(n.id, c.id));
        place(c, x + n.width + levelGap, cy);
        cy += heights[c.id]! + siblingGap;
      }
    }

    place(root, padding, padding);
    return TreeLayoutResult(
      rects: rects,
      edges: edges,
      width: maxRight + padding,
      height: heights[root.id]! + padding * 2,
    );
  }

  double _childrenBlock(LayoutNode n, double Function(LayoutNode) measure) {
    if (n.children.isEmpty) return 0;
    var sum = 0.0;
    for (final c in n.children) {
      sum += measure(c);
    }
    return sum + siblingGap * (n.children.length - 1);
  }
}
