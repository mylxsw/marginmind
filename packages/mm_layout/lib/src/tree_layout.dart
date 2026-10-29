import 'package:meta/meta.dart';

/// The connector style and arrangement used for all nodes, including summaries.
enum LayoutStructure { mind, logic, brace, tree }

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

/// A parent-child connector. Use the result's structure, rectangles and
/// leftSide to draw curves (mind), elbows (logic), grouped braces (brace),
/// or a vertical trunk from the parent's bottom to child centers (tree).
@immutable
class LayoutEdge {
  const LayoutEdge(this.parentId, this.childId);

  final String parentId;
  final String childId;
}

/// Input: a summary of the children of [parentId] from [fromId] to [toId]
/// (either order), with a measured label or a topic [node] subtree.
@immutable
class LayoutSummary {
  const LayoutSummary({
    required this.id,
    required this.parentId,
    required this.fromId,
    required this.toId,
    this.width = 0,
    this.height = 0,
    this.node,
  });

  /// Optional summary topic, including its descendants. Its measured size
  /// takes precedence over the legacy label width and height. IDs must be
  /// unique across the main tree and all summary trees.
  final LayoutNode? node;

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

  /// Topic rectangle when LayoutSummary.node is supplied; otherwise the
  /// legacy label rectangle. Summary descendants are in TreeLayoutResult.rects.
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
    this.structure = LayoutStructure.mind,
  });

  final LayoutStructure structure;

  /// Includes summary topic nodes and their descendants, keyed by node ID.
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

/// Pure Dart layout for mind maps, right-growing logic/brace maps and
/// indented, top-down trees. [balanced] controls the mind map's root split;
/// other structures always grow right. The legacy default remains unbalanced.
/// Summary subtrees reserve vertical space within their covered sibling range.
class TreeLayout {
  const TreeLayout({
    this.levelGap = 56,
    this.siblingGap = 14,
    this.padding = 48,
    this.summaryGap = 16,
    this.bracketWidth = 12,
    this.labelGap = 8,
    this.balanced = false,
    this.structure = LayoutStructure.mind,
    this.braceGap = 24,
  });

  final LayoutStructure structure;

  /// Additional horizontal clearance for the parent-child brace.
  final double braceGap;

  /// Parent-child horizontal gap, or left-edge indent for tree structure.
  final double levelGap;
  final double siblingGap;
  final double padding;

  /// Space between a range's outer edge and its bracket, the bracket's
  /// width, and the space between the bracket and the label.
  final double summaryGap;
  final double bracketWidth;
  final double labelGap;

  /// Whether mind structure splits root branches between right and left.
  /// Ignored by logic, brace and tree structures.
  final bool balanced;

  TreeLayoutResult layout(LayoutNode root, {List<LayoutSummary> summaries = const []}) {
    final heights = <String, double>{};
    // Space a summary subtree needs beyond its covered range, split evenly
    // before the range's first sibling and after its last one. The range
    // itself keeps its normal sibling gaps and the bracket hugs its content.
    final padBefore = <String, double>{}, padAfter = <String, double>{};
    double padded(LayoutNode c) => (padBefore[c.id] ?? 0) + heights[c.id]! + (padAfter[c.id] ?? 0);
    final byParent = <String, List<LayoutSummary>>{};
    for (final s in summaries) {
      byParent.putIfAbsent(s.parentId, () => []).add(s);
    }
    final vertical = structure == LayoutStructure.tree;
    final gap = levelGap + (structure == LayoutStructure.brace ? braceGap : 0);
    double block(List<LayoutNode> nodes) =>
        nodes.isEmpty ? 0 : nodes.fold<double>(0, (s, c) => s + padded(c)) + siblingGap * (nodes.length - 1);
    double measure(LayoutNode n) {
      for (final c in n.children) {
        measure(c);
      }
      // Narrow ranges first, matching bracket placement.
      final ranges = <(int, int, LayoutSummary)>[];
      for (final s in byParent[n.id] ?? <LayoutSummary>[]) {
        final a = n.children.indexWhere((c) => c.id == s.fromId);
        final b = n.children.indexWhere((c) => c.id == s.toId);
        if (a >= 0 && b >= 0) ranges.add((a < b ? a : b, a < b ? b : a, s));
      }
      ranges.sort((a, b) => (a.$2 - a.$1).compareTo(b.$2 - b.$1));
      for (final (lo, hi, s) in ranges) {
        // Label-only summaries retain their original node positions.
        if (s.node == null) continue;
        final needed = measure(s.node!);
        final range = n.children.sublist(lo, hi + 1);
        final available = block(range) - (padBefore[range.first.id] ?? 0) - (padAfter[range.last.id] ?? 0);
        // The topic is centred on the range; in a tree its subtree then grows
        // downward from there, so nearly all the extra space goes below.
        final above = vertical ? s.node!.height / 2 : needed / 2;
        final below = needed - above;
        final before = above - available / 2, after = below - available / 2;
        if (before > 0) padBefore[range.first.id] = before;
        if (after > 0) padAfter[range.last.id] = after;
      }
      final childrenHeight = block(n.children);
      final h = vertical
          ? n.height + (n.children.isEmpty ? 0 : siblingGap + childrenHeight)
          : (childrenHeight > n.height ? childrenHeight : n.height);
      heights[n.id] = h;
      return h;
    }

    measure(root);
    final split = balanced && structure == LayoutStructure.mind
        ? _split(root, {for (final c in root.children) c.id: padded(c)}, summaries)
        : root.children.length;
    final right = root.children.sublist(0, split), left = root.children.sublist(split);
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
      final rect = LayoutRect(
        dir > 0 ? x : x - n.width,
        vertical ? y : y + (subtree - n.height) / 2,
        n.width,
        n.height,
      );
      rects[n.id] = rect;
      if (dir < 0) leftSide.add(n.id);
      if (n.children.isEmpty) return;
      var cy = vertical ? rect.bottom + siblingGap : y + (subtree - block(n.children)) / 2;
      final cx = vertical ? rect.left + levelGap : (dir > 0 ? rect.right + gap : rect.left - gap);
      for (final c in n.children) {
        edges.add(LayoutEdge(n.id, c.id));
        cy += padBefore[c.id] ?? 0;
        place(c, cx, cy, dir);
        cy += heights[c.id]! + (padAfter[c.id] ?? 0) + siblingGap;
      }
    }

    if (vertical) {
      place(root, 0, 0, 1);
    } else {
      rects[root.id] = LayoutRect(0, (total - root.height) / 2, root.width, root.height);
      bands[root.id] = (0, total);
      for (final (side, dir, x) in [(right, 1, root.width + gap), (left, -1, -gap)]) {
        var cy = (total - block(side)) / 2;
        for (final c in side) {
          cy += padBefore[c.id] ?? 0;
          place(c, x, cy, dir);
          cy += heights[c.id]! + (padAfter[c.id] ?? 0) + siblingGap;
        }
      }
      edges.insertAll(0, [for (final c in root.children) LayoutEdge(root.id, c.id)]);
    }

    final placements = <String, SummaryPlacement>{};
    if (summaries.isNotEmpty) {
      _placeSummaries(root, right, 1, rects, bands, byParent, placements, heights, place);
      _placeSummaries(root, left, -1, rects, bands, byParent, placements, heights, place);
    }

    var minLeft = 0.0, maxRight = 0.0, maxBottom = vertical ? heights[root.id]! : total, minTop = 0.0;
    void extend(LayoutRect r) {
      if (r.top < minTop) minTop = r.top;
      if (r.bottom > maxBottom) maxBottom = r.bottom;
      if (r.left < minLeft) minLeft = r.left;
      if (r.right > maxRight) maxRight = r.right;
    }

    rects.values.forEach(extend);
    for (final p in placements.values) {
      extend(p.bracket);
      extend(p.label);
    }
    final dx = padding - minLeft, dy = padding - minTop;
    LayoutRect shift(LayoutRect r) => LayoutRect(r.left + dx, r.top + dy, r.width, r.height);
    return TreeLayoutResult(
      structure: structure,
      rects: {for (final e in rects.entries) e.key: shift(e.value)},
      edges: edges,
      width: maxRight - minLeft + padding * 2,
      height: maxBottom - minTop + padding * 2,
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
    Map<String, List<LayoutSummary>> byParent,
    Map<String, SummaryPlacement> out,
    Map<String, double> heights,
    void Function(LayoutNode, double, double, int) place,
  ) {
    double outer(double a, double b) => dir > 0 ? (a > b ? a : b) : (a < b ? a : b);
    final rect = rects[n.id]!;
    var edge = dir > 0 ? rect.right : rect.left;
    final extents = [
      for (final c in kids) _placeSummaries(c, c.children, dir, rects, bands, byParent, out, heights, place),
    ];
    for (final e in extents) {
      edge = outer(edge, e);
    }
    final ranges = <(int, int, LayoutSummary)>[];
    for (final s in byParent[n.id] ?? <LayoutSummary>[]) {
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
      final node = s.node;
      final width = node?.width ?? s.width, height = node?.height ?? s.height;
      final labelLeft = dir > 0 ? bracket.right + labelGap : bracket.left - labelGap - width;
      var label = LayoutRect(labelLeft, (top + bottom - height) / 2, width, height);
      double? subtreeEdge;
      if (node != null) {
        final topY = structure == LayoutStructure.tree
            ? (top + bottom - node.height) / 2
            : (top + bottom - heights[node.id]!) / 2;
        place(node, dir > 0 ? labelLeft : labelLeft + width, topY, dir);
        label = rects[node.id]!;
        subtreeEdge = _placeSummaries(node, node.children, dir, rects, bands, byParent, out, heights, place);
      }
      out[s.id] = SummaryPlacement(bracket, label, left: dir < 0);
      final labelEdge = subtreeEdge ?? (dir > 0 ? label.right : label.left);
      placed.add((lo, hi, labelEdge));
      edge = outer(edge, labelEdge);
    }
    return edge;
  }
}
