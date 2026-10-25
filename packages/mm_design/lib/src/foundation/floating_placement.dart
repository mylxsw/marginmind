import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart' show immutable;

import '../tokens/metrics.dart';

/// Which side of the anchor a floating control ended up on.
enum MMFloatingSide { above, below }

/// Result of [placeFloatingToolbar]: top-left corner of the toolbar, in the
/// same coordinates as the anchor and viewport.
@immutable
class MMFloatingPlacement {
  const MMFloatingPlacement(this.offset, this.side);

  final Offset offset;
  final MMFloatingSide side;

  @override
  bool operator ==(Object other) => other is MMFloatingPlacement && other.offset == offset && other.side == side;

  @override
  int get hashCode => Object.hash(offset, side);

  @override
  String toString() => 'MMFloatingPlacement($offset, ${side.name})';
}

/// Places a toolbar of [size] next to [anchor] (e.g. a text selection)
/// inside [viewport].
///
/// Prefers [gap] above the anchor, falls back to below it, and when neither
/// side has room takes the roomier one and overlaps the anchor rather than
/// leave the viewport. Horizontally the toolbar is centered on the anchor and
/// pushed inwards so it keeps [margin] from the viewport edges. The result is
/// always fully inside the viewport unless the toolbar is larger than it.
MMFloatingPlacement placeFloatingToolbar({
  required Rect anchor,
  required Size size,
  required Rect viewport,
  double gap = MMSpacing.s,
  double margin = MMSpacing.s,
}) {
  final bounds = viewport.deflate(margin);

  double clampAxis(double value, double min, double max) => max < min ? min : value.clamp(min, max);

  final x = clampAxis(anchor.center.dx - size.width / 2, bounds.left, bounds.right - size.width);

  final aboveTop = anchor.top - gap - size.height;
  final belowTop = anchor.bottom + gap;
  final MMFloatingSide side;
  final double y;
  if (aboveTop >= bounds.top) {
    side = MMFloatingSide.above;
    y = aboveTop;
  } else if (belowTop + size.height <= bounds.bottom) {
    side = MMFloatingSide.below;
    y = belowTop;
  } else {
    final roomAbove = anchor.top - bounds.top;
    final roomBelow = bounds.bottom - anchor.bottom;
    side = roomAbove >= roomBelow ? MMFloatingSide.above : MMFloatingSide.below;
    y = side == MMFloatingSide.above ? aboveTop : belowTop;
  }
  return MMFloatingPlacement(Offset(x, clampAxis(y, bounds.top, bounds.bottom - size.height)), side);
}
