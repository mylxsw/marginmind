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

/// Input: a summary of the children of [parentId] from [fromId] to [toId]
/// (either order), with its measured label size.
@immutable
class LayoutSummary {
  const LayoutSummary({
    required this.id,
    required this.parentId,
    required this.fromId,
    required this.toId,
    required this.width,
    required this.height,
  });

  final String id;
  final String parentId;
  final String fromId;
  final String toId;
  final double width;
  final double height;
}

/// Where a summary is drawn: a bracket spanning the covered subtrees, right
/// of everything they contain, and its label beyond the bracket.
@immutable
class SummaryPlacement {
  const SummaryPlacement(this.bracket, this.label);

  final LayoutRect bracket;
  final LayoutRect label;
}

@immutable
class TreeLayoutResult {
  const TreeLayoutResult({
    required this.rects,
    required this.edges,
    required this.width,
    required this.height,
    this.summaries = const {},
  });

  final Map<String, LayoutRect> rects;
  final List<LayoutEdge> edges;

  /// Summaries whose range is shown (not folded away), by id.
  final Map<String, SummaryPlacement> summaries;

  /// Total canvas size including padding.
  final double width;
  final double height;
}

/// Lays a tree out left-to-right: each level sits [levelGap] to the right
/// of its parent, siblings stack with [siblingGap], and every parent is
/// vertically centered on the block of its children.
///
/// Every subtree owns a horizontal band no other subtree enters, so a
/// summary placed right of its range's subtrees, inside their bands, never
/// overlaps another node; it only widens the canvas.
class TreeLayout {
  const TreeLayout({
    this.levelGap = 56,
    this.siblingGap = 14,
    this.padding = 48,
    this.summaryGap = 16,
    this.bracketWidth = 12,
    this.labelGap = 8,
  });

  final double levelGap;
  final double siblingGap;
  final double padding;

  /// Space between a range's right edge and its bracket, the bracket's
  /// width, and the space between the bracket and the label.
  final double summaryGap;
  final double bracketWidth;
  final double labelGap;

  TreeLayoutResult layout(LayoutNode root, {List<LayoutSummary> summaries = const []}) {
    final heights = <String, double>{};
    double measure(LayoutNode n) {
      final block = _childrenBlock(n, measure);
      final h = block > n.height ? block : n.height;
      heights[n.id] = h;
      return h;
    }

    measure(root);
    final rects = <String, LayoutRect>{};
    final bands = <String, (double, double)>{};
    final edges = <LayoutEdge>[];
    var maxRight = 0.0;

    void place(LayoutNode n, double x, double y) {
      final subtree = heights[n.id]!;
      bands[n.id] = (y, y + subtree);
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
    final placements = <String, SummaryPlacement>{};
    if (summaries.isNotEmpty) {
      final right = _placeSummaries(root, rects, bands, summaries, placements);
      if (right > maxRight) maxRight = right;
    }
    return TreeLayoutResult(
      rects: rects,
      edges: edges,
      width: maxRight + padding,
      height: heights[root.id]! + padding * 2,
      summaries: placements,
    );
  }

  /// Places summaries bottom-up and returns the right edge of [n]'s subtree
  /// including them. Narrow ranges go first; a wider range that contains or
  /// overlaps one is placed beyond its label.
  double _placeSummaries(
    LayoutNode n,
    Map<String, LayoutRect> rects,
    Map<String, (double, double)> bands,
    List<LayoutSummary> summaries,
    Map<String, SummaryPlacement> out,
  ) {
    var right = rects[n.id]!.right;
    final extents = [for (final c in n.children) _placeSummaries(c, rects, bands, summaries, out)];
    for (final e in extents) {
      if (e > right) right = e;
    }
    final ranges = <(int, int, LayoutSummary)>[];
    for (final s in summaries) {
      if (s.parentId != n.id) continue;
      final a = n.children.indexWhere((c) => c.id == s.fromId);
      final b = n.children.indexWhere((c) => c.id == s.toId);
      if (a < 0 || b < 0) continue;
      ranges.add((a < b ? a : b, a < b ? b : a, s));
    }
    ranges.sort((x, y) => (x.$2 - x.$1).compareTo(y.$2 - y.$1));
    final placed = <(int, int, double)>[];
    for (final (lo, hi, s) in ranges) {
      var x = 0.0;
      for (var i = lo; i <= hi; i++) {
        if (extents[i] > x) x = extents[i];
      }
      for (final (plo, phi, pright) in placed) {
        if (plo <= hi && lo <= phi && pright > x) x = pright;
      }
      final top = bands[n.children[lo].id]!.$1, bottom = bands[n.children[hi].id]!.$2;
      final bracket = LayoutRect(x + summaryGap, top, bracketWidth, bottom - top);
      final label = LayoutRect(bracket.right + labelGap, (top + bottom - s.height) / 2, s.width, s.height);
      out[s.id] = SummaryPlacement(bracket, label);
      placed.add((lo, hi, label.right));
      if (label.right > right) right = label.right;
    }
    return right;
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
