import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Where a relation between [a] and [b] runs: from the border of [a] facing
/// [b] to the border of [b] facing [a], bowed to one side so it stands out
/// from the tree's connectors. Start, two control points, end.
///
/// Two nodes stacked in one column with nothing to their right (leaves) are
/// joined around their right side instead, past everything in [others]
/// (nodes, summary labels) between them, so the line and its label do not
/// run under the nodes in between.
(Offset, Offset, Offset, Offset) relationCurve(Rect a, Rect b, [Iterable<Rect> others = const []]) {
  final stacked = a.left < b.right && b.left < a.right && (a.bottom <= b.top || b.bottom <= a.top);
  bool beside(Rect n, Rect o) => o.left >= n.right && o.top < n.bottom && o.bottom > n.top;
  if (stacked && !others.any((o) => beside(a, o) || beside(b, o))) {
    final top = math.min(a.top, b.top), bottom = math.max(a.bottom, b.bottom), left = math.min(a.left, b.left);
    var right = math.max(a.right, b.right);
    for (final o in others) {
      if (o.left >= left && o.top < bottom && o.bottom > top) right = math.max(right, o.right);
    }
    final start = Offset(a.right, a.center.dy), end = Offset(b.right, b.center.dy);
    // The curve's apex sits three quarters of the way to the control points:
    // put it a full bow's three quarters past [right].
    final bow = ((end.dy - start.dy).abs() * 0.3).clamp(48.0, 120.0);
    final x = right + bow + (right - math.min(a.right, b.right)) / 3;
    return (start, Offset(x, start.dy), Offset(x, end.dy), end);
  }

  Offset border(Rect r, Offset toward) {
    final d = toward - r.center;
    if (d == Offset.zero) return r.center;
    final scale = math.min(
      d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs(),
      d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs(),
    );
    return r.center + d * math.min(scale, 1);
  }

  final start = border(a, b.center), end = border(b, a.center);
  final d = end - start;
  final length = d.distance;
  final normal = length == 0 ? Offset.zero : Offset(-d.dy, d.dx) / length * math.min(64, length * 0.25);
  return (start, start + d * 0.25 + normal, start + d * 0.75 + normal, end);
}

/// [relationCurve] for a relation whose ends both grow [left] of the root:
/// mirrored, so a line between stacked nodes goes around their outer (left)
/// side. Its control points stay on the canvas (x ≥ 0).
(Offset, Offset, Offset, Offset) relationCurveOnSide(Rect a, Rect b, Iterable<Rect> others, {required bool left}) {
  if (!left) return relationCurve(a, b, others);
  Rect flip(Rect r) => Rect.fromLTRB(-r.right, r.top, -r.left, r.bottom);
  final c = relationCurve(flip(a), flip(b), others.map(flip));
  Offset back(Offset p) => Offset(-p.dx, p.dy);
  Offset control(Offset p) => Offset(math.max(-p.dx, 0), p.dy);
  return (back(c.$1), control(c.$2), control(c.$3), back(c.$4));
}

/// Whether [c] is the curve [relationCurve] runs around the right of a
/// column (or [relationCurveOnSide] around the left). Its label then sits
/// beside the apex instead of on it.
bool relationGoesAround((Offset, Offset, Offset, Offset) c) =>
    c.$2.dx == c.$3.dx &&
    c.$2.dy == c.$1.dy &&
    c.$3.dy == c.$4.dy &&
    (c.$2.dx > math.max(c.$1.dx, c.$4.dx) || c.$2.dx < math.min(c.$1.dx, c.$4.dx));

Offset cubicPoint((Offset, Offset, Offset, Offset) c, double t) {
  final u = 1 - t;
  return c.$1 * (u * u * u) + c.$2 * (3 * u * u * t) + c.$3 * (3 * u * t * t) + c.$4 * (t * t * t);
}
