import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mm_core/mm_core.dart';

import 'reading_geometry.dart';

const marginColumnWidth = 200.0;

bool marginFits(double viewportWidth, double pageWidth) =>
    viewportWidth.isFinite && pageWidth > 0 && viewportWidth / (pageWidth + marginColumnWidth + 32) >= .78;

/// Page coordinates remain unchanged; only the outer document gains space.
class MMPdfMargin {
  const MMPdfMargin({
    required this.requested,
    this.revision,
    this.forceCollapsed = false,
    this.backgroundColor = const Color(0xFFFFFFFF),
    required this.extent,
    required this.builder,
  });
  final bool requested, forceCollapsed;
  final Object? revision;

  /// Paper color for the combined source page and expanded margin surface.
  final Color backgroundColor;

  /// Extra height in PDF points. Cache estimates independently of visible widgets.
  final double Function(int page, Size originalSize, CropInsets crop, double zoom) extent;
  final List<Widget> Function(BuildContext context, MMPdfMarginViewport viewport) builder;
}

class MMPdfMarginPage {
  const MMPdfMarginPage({required this.page, required this.rect, required this.transform, required this.extent});
  final int page;
  final Rect rect;
  final PageViewportTransform transform;
  final double extent;
}

class MMPdfMarginViewport {
  const MMPdfMarginViewport({required this.pages, required this.zoom, required this.expanded, required this.size});

  /// Visible pages and their immediate neighbours only.
  final List<MMPdfMarginPage> pages;
  final double zoom;
  final bool expanded;
  final Size size;
}

class MarginPlacement {
  const MarginPlacement(this.note, this.anchorY, this.top, this.height);
  final MarginNote note;
  final double anchorY, top, height;
}

double marginAnchorY(MarginNote note, PageViewportTransform transform) =>
    transform.toViewport(Offset(0, note.lineY ?? note.anchor!.pages.first.rects.first.top)).dy;

/// Stable order, then one linear downward pass. Heights and spacing are screen points.
List<MarginPlacement> layoutMarginNotes(
  Iterable<MarginNote> notes, {
  required PageViewportTransform transform,
  required double Function(MarginNote) height,
}) {
  final sorted = notes.toList()
    ..sort((a, b) {
      final y = marginAnchorY(a, transform).compareTo(marginAnchorY(b, transform));
      if (y != 0) return y;
      final time = a.createdAt.compareTo(b.createdAt);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
  var bottom = transform.origin.dy - 4 * transform.scale;
  return [
    for (final note in sorted)
      (() {
        final y = marginAnchorY(note, transform);
        final top = math.max(
          math.max(transform.origin.dy + 4 * transform.scale, y - 3 * transform.scale),
          bottom + 8 * transform.scale,
        );
        final h = height(note);
        bottom = top + h;
        return MarginPlacement(note, y, top, h);
      })(),
  ];
}

/// Adjacent anchors merge into one clickable marker, retaining every note.
List<List<MarginNote>> groupMarginMarkers(Iterable<MarginNote> notes, PageViewportTransform transform) {
  final sorted = notes.toList()..sort((a, b) => marginAnchorY(a, transform).compareTo(marginAnchorY(b, transform)));
  final groups = <List<MarginNote>>[];
  for (final note in sorted) {
    if (groups.isEmpty || marginAnchorY(note, transform) - marginAnchorY(groups.last.first, transform) >= 22) {
      groups.add([note]);
    } else {
      groups.last.add(note);
    }
  }
  return groups;
}
