import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:mm_core/mm_core.dart';

/// Where a dragged node lands relative to the node under the pointer.
enum MapDropZone { before, child, after }

/// One place a drag can land. The preview and the drop are both read from
/// the same value, so the node always lands where the preview showed.
@immutable
class MapDrop {
  const MapDrop({required this.targetId, required this.zone, required this.parentId, required this.index});

  /// Node under the pointer ([rootId] for the root).
  final String targetId;
  final MapDropZone zone;

  /// New parent (null = root) and index among the siblings left once the
  /// moving nodes are taken out (null = last), as `StudySetEditor.moveMany`
  /// expects.
  final String? parentId;
  final int? index;

  @override
  bool operator ==(Object other) =>
      other is MapDrop &&
      other.targetId == targetId &&
      other.zone == zone &&
      other.parentId == parentId &&
      other.index == index;

  @override
  int get hashCode => Object.hash(targetId, zone, parentId, index);

  @override
  String toString() => 'MapDrop($targetId, $zone, parent: $parentId, index: $index)';

  /// Finds the drop under [point] (scene coordinates). [rects] are the
  /// nodes as drawn; [rootId] is the key of the root among them. A node
  /// also owns half of the [gap] above and below it, so there is no dead
  /// space between siblings. Its top and bottom quarter insert before /
  /// after it; the middle (and the whole root) makes it the parent.
  /// Returns null over empty space and over the moving nodes or their
  /// descendants.
  static MapDrop? resolve({
    required Offset point,
    required Map<String, Rect> rects,
    required StudySetContent content,
    required Set<String> moving,
    required String rootId,
    double gap = 0,
  }) {
    String? hit;
    var best = double.infinity;
    for (final e in rects.entries) {
      final r = e.value;
      if (point.dx < r.left || point.dx > r.right) continue;
      if (point.dy < r.top - gap / 2 || point.dy > r.bottom + gap / 2) continue;
      final distance = (point.dy - r.center.dy).abs();
      if (distance < best) {
        best = distance;
        hit = e.key;
      }
    }
    if (hit == null || !_accepts(hit, content, moving, rootId)) return null;
    if (hit == rootId) return MapDrop(targetId: hit, zone: MapDropZone.child, parentId: null, index: null);
    final r = rects[hit]!;
    final y = (point.dy - r.top) / r.height;
    final zone = y < 0.25
        ? MapDropZone.before
        : y > 0.75
        ? MapDropZone.after
        : MapDropZone.child;
    if (zone == MapDropZone.child) return MapDrop(targetId: hit, zone: zone, parentId: hit, index: null);
    final parent = content.node(hit)?.parentId;
    final siblings = [
      for (final n in content.childrenOf(parent))
        if (!moving.contains(n.cardId)) n.cardId,
    ];
    final i = siblings.indexOf(hit);
    return MapDrop(targetId: hit, zone: zone, parentId: parent, index: zone == MapDropZone.before ? i : i + 1);
  }

  /// A node can't be dropped onto itself or its own descendants.
  static bool _accepts(String target, StudySetContent content, Set<String> moving, String rootId) {
    if (moving.contains(target)) return false;
    if (target == rootId) return true;
    String? id = target;
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      if (moving.contains(id)) return false;
      id = content.node(id)?.parentId;
    }
    return true;
  }

  /// Where the preview is drawn: the target itself for [MapDropZone.child]
  /// (a ring), otherwise a line of [thickness] centered in the [gap] above
  /// or below it, so "after A" and "before B" show the same line.
  Rect previewRect(Map<String, Rect> rects, {required double gap, required double thickness}) {
    final r = rects[targetId]!;
    return switch (zone) {
      MapDropZone.child => r,
      MapDropZone.before => Rect.fromLTWH(r.left, r.top - gap / 2 - thickness / 2, r.width, thickness),
      MapDropZone.after => Rect.fromLTWH(r.left, r.bottom + gap / 2 - thickness / 2, r.width, thickness),
    };
  }
}

/// Speed (logical pixels per second, signed) at which the canvas pans while
/// a drag is held near its edges. Inside [edge] of a side the speed grows
/// linearly to [maxSpeed]; at or beyond the side it is [maxSpeed]. Panning
/// toward a side reveals content on that side, so a positive value moves
/// the content right / down.
@visibleForTesting
Offset autoScrollVelocity(Offset pointer, Size viewport, {required double edge, required double maxSpeed}) {
  double axis(double v, double extent) {
    if (extent <= edge * 2) return 0;
    if (v < edge) return maxSpeed * ((edge - v) / edge).clamp(0.0, 1.0);
    if (v > extent - edge) return -maxSpeed * ((v - (extent - edge)) / edge).clamp(0.0, 1.0);
    return 0;
  }

  return Offset(axis(pointer.dx, viewport.width), axis(pointer.dy, viewport.height));
}

/// Applies one auto-scroll [step] to the translation [current], but never
/// pans the [content] (on screen, in viewport coordinates) further than
/// [margin] inside the viewport: scrolling stops once the far side of the
/// map is visible. A translation already past that limit is left alone.
@visibleForTesting
Offset clampAutoScroll(Offset current, Offset step, Rect content, Size viewport, {required double margin}) {
  double axis(double t, double d, double start, double end, double extent) {
    if (d > 0) return math.min(t + d, math.max(t, t + margin - start));
    if (d < 0) return math.max(t + d, math.min(t, t + extent - margin - end));
    return t;
  }

  return Offset(
    axis(current.dx, step.dx, content.left, content.right, viewport.width),
    axis(current.dy, step.dy, content.top, content.bottom, viewport.height),
  );
}
