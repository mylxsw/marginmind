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

/// Where a summary is drawn: a bracket spanning the covered subtrees, beyond
/// everything they contain, and its label beyond the bracket. On the [left]
/// side of a balanced map both open to the left.
@immutable
class SummaryPlacement {
  const SummaryPlacement(this.bracket, this.label, {this.left = false});

  final LayoutRect bracket;
  final LayoutRect label;
  final bool left;
}

@immutable
class TreeLayoutResult {
  const TreeLayoutResult({
    required this.rects,
    required this.edges,
    required this.width,
    required this.height,
    this.summaries = const {},
    this.leftSide = const {},
  });

  final Map<String, LayoutRect> rects;
  final List<LayoutEdge> edges;

  /// Summaries whose range is shown (not folded away), by id.
  final Map<String, SummaryPlacement> summaries;

  /// Nodes growing to the left of the root (balanced layout only): their
  /// connectors leave the parent's left edge and enter the child's right.
  final Set<String> leftSide;

  /// Total canvas size including padding.
  final double width;
  final double height;
}

/// Lays a tree out left-to-right: each level sits [levelGap] to the right
/// of its parent, siblings stack with [siblingGap], and every parent is
/// vertically centered on the block of its children.
///
/// With [balanced], the root's branches are split in two: the first ones
/// grow to the right and the rest to the left, mirrored, so that both
/// sides are about as tall. A summary of the root's branches keeps its
/// range on one side.
///
/// Every subtree owns a horizontal band no other subtree on its side enters,
/// so a summary placed beyond its range's subtrees, inside their bands,
/// never overlaps another node; it only widens the canvas.
class TreeLayout {
  const TreeLayout({
    this.levelGap = 56,
    this.siblingGap = 14,
    this.padding = 48,
    this.summaryGap = 16,
    this.bracketWidth = 12,
    this.labelGap = 8,
    this.balanced = false,
  });

  final double levelGap;
  final double siblingGap;
  final double padding;

  /// Space between a range's outer edge and its bracket, the bracket's
  /// width, and the space between the bracket and the label.
  final double summaryGap;
  final double bracketWidth;
  final double labelGap;

  /// Whether the root's branches are split between its right and left.
  final bool balanced;

  TreeLayoutResult layout(LayoutNode root, {List<LayoutSummary> summaries = const []}) {
    final heights = <String, double>{};
    double measure(LayoutNode n) {
      final block = _childrenBlock(n, measure);
      final h = block > n.height ? block : n.height;
      heights[n.id] = h;
      return h;
    }

    measure(root);
    final split = balanced ? _split(root, heights, summaries) : root.children.length;
    final right = root.children.sublist(0, split), left = root.children.sublist(split);
    double block(List<LayoutNode> nodes) =>
        nodes.isEmpty ? 0 : nodes.fold<double>(0, (s, c) => s + heights[c.id]!) + siblingGap * (nodes.length - 1);
    final total = [root.height, block(right), block(left)].reduce((a, b) => a > b ? a : b);

    final rects = <String, LayoutRect>{};
    final bands = <String, (double, double)>{};
    final edges = <LayoutEdge>[];
    final leftSide = <String>{};

    // [x] is the edge facing the parent: the left edge when growing right
    // ([dir] 1), the right edge when growing left (-1).
    void place(LayoutNode n, double x, double y, int dir) {
      final subtree = heights[n.id]!;
      bands[n.id] = (y, y + subtree);
      final rect = LayoutRect(dir > 0 ? x : x - n.width, y + (subtree - n.height) / 2, n.width, n.height);
      rects[n.id] = rect;
      if (dir < 0) leftSide.add(n.id);
      if (n.children.isEmpty) return;
      var cy = y + (subtree - block(n.children)) / 2;
      final cx = dir > 0 ? rect.right + levelGap : rect.left - levelGap;
      for (final c in n.children) {
        edges.add(LayoutEdge(n.id, c.id));
        place(c, cx, cy, dir);
        cy += heights[c.id]! + siblingGap;
      }
    }

    rects[root.id] = LayoutRect(0, (total - root.height) / 2, root.width, root.height);
    bands[root.id] = (0, total);
    for (final (side, dir, x) in [(right, 1, root.width + levelGap), (left, -1, -levelGap)]) {
      var cy = (total - block(side)) / 2;
      for (final c in side) {
        place(c, x, cy, dir);
        cy += heights[c.id]! + siblingGap;
      }
    }
    edges.insertAll(0, [for (final c in root.children) LayoutEdge(root.id, c.id)]);

    final placements = <String, SummaryPlacement>{};
    if (summaries.isNotEmpty) {
      _placeSummaries(root, right, 1, rects, bands, summaries, placements);
      _placeSummaries(root, left, -1, rects, bands, summaries, placements);
    }

    var minLeft = 0.0, maxRight = 0.0;
    void extend(LayoutRect r) {
      if (r.left < minLeft) minLeft = r.left;
      if (r.right > maxRight) maxRight = r.right;
    }

    rects.values.forEach(extend);
    for (final p in placements.values) {
      extend(p.bracket);
      extend(p.label);
    }
    final dx = padding - minLeft, dy = padding;
    LayoutRect shift(LayoutRect r) => LayoutRect(r.left + dx, r.top + dy, r.width, r.height);
    return TreeLayoutResult(
      rects: {for (final e in rects.entries) e.key: shift(e.value)},
      edges: edges,
      width: maxRight - minLeft + padding * 2,
      height: total + padding * 2,
      summaries: {
        for (final e in placements.entries)
          e.key: SummaryPlacement(shift(e.value.bracket), shift(e.value.label), left: e.value.left),
      },
      leftSide: leftSide,
    );
  }

  /// How many of the root's branches go right: the split whose sides are
  /// closest in height (the right side takes the extra one on a tie), never
  /// inside a summary's range. With no such split, all go right.
  int _split(LayoutNode root, Map<String, double> heights, List<LayoutSummary> summaries) {
    final kids = root.children;
    if (kids.length < 2) return kids.length;
    final ranges = <(int, int)>[];
    for (final s in summaries) {
      if (s.parentId != root.id) continue;
      final a = kids.indexWhere((c) => c.id == s.fromId), b = kids.indexWhere((c) => c.id == s.toId);
      if (a >= 0 && b >= 0) ranges.add((a < b ? a : b, a < b ? b : a));
    }
    final prefix = <double>[0];
    for (final c in kids) {
      prefix.add(prefix.last + heights[c.id]!);
    }
    var best = kids.length;
    var bestDiff = double.infinity;
    for (var k = 1; k < kids.length; k++) {
      if (ranges.any((r) => r.$1 < k && r.$2 >= k)) continue;
      final right = prefix[k] + siblingGap * (k - 1);
      final left = prefix.last - prefix[k] + siblingGap * (kids.length - k - 1);
      final diff = (right - left).abs();
      if (diff <= bestDiff) {
        best = k;
        bestDiff = diff;
      }
    }
    return best;
  }

  /// Places the summaries of [n]'s children among [kids] (all of them below
  /// the root) bottom-up, and returns the outer edge of [n]'s subtree
  /// including them: the right edge when growing right ([dir] 1), the left
  /// edge when growing left. Narrow ranges go first; a wider range that
  /// contains or overlaps one is placed beyond its label.
  double _placeSummaries(
    LayoutNode n,
    List<LayoutNode> kids,
    int dir,
    Map<String, LayoutRect> rects,
    Map<String, (double, double)> bands,
    List<LayoutSummary> summaries,
    Map<String, SummaryPlacement> out,
  ) {
    double outer(double a, double b) => dir > 0 ? (a > b ? a : b) : (a < b ? a : b);
    final rect = rects[n.id]!;
    var edge = dir > 0 ? rect.right : rect.left;
    final extents = [for (final c in kids) _placeSummaries(c, c.children, dir, rects, bands, summaries, out)];
    for (final e in extents) {
      edge = outer(edge, e);
    }
    final ranges = <(int, int, LayoutSummary)>[];
    for (final s in summaries) {
      if (s.parentId != n.id) continue;
      final a = kids.indexWhere((c) => c.id == s.fromId);
      final b = kids.indexWhere((c) => c.id == s.toId);
      if (a < 0 || b < 0) continue;
      ranges.add((a < b ? a : b, a < b ? b : a, s));
    }
    ranges.sort((x, y) => (x.$2 - x.$1).compareTo(y.$2 - y.$1));
    final placed = <(int, int, double)>[];
    for (final (lo, hi, s) in ranges) {
      var x = extents[lo];
      for (var i = lo + 1; i <= hi; i++) {
        x = outer(x, extents[i]);
      }
      for (final (plo, phi, pedge) in placed) {
        if (plo <= hi && lo <= phi) x = outer(x, pedge);
      }
      final top = bands[kids[lo].id]!.$1, bottom = bands[kids[hi].id]!.$2;
      final bracket = dir > 0
          ? LayoutRect(x + summaryGap, top, bracketWidth, bottom - top)
          : LayoutRect(x - summaryGap - bracketWidth, top, bracketWidth, bottom - top);
      final labelLeft = dir > 0 ? bracket.right + labelGap : bracket.left - labelGap - s.width;
      final label = LayoutRect(labelLeft, (top + bottom - s.height) / 2, s.width, s.height);
      out[s.id] = SummaryPlacement(bracket, label, left: dir < 0);
      final labelEdge = dir > 0 ? label.right : label.left;
      placed.add((lo, hi, labelEdge));
      edge = outer(edge, labelEdge);
    }
    return edge;
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
