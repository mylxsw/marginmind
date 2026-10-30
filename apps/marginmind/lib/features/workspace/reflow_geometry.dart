import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_reflow/mm_reflow.dart';

/// Nondecorative leaf geometry, including the cells of a table.
LayoutPiece? inkPieceAt(ChapterLayout layout, Offset point) {
  LayoutPiece? nearest;
  var distance = double.infinity;
  for (final piece in layout.pieces) {
    if (piece.decorative || piece.rect.isEmpty || piece.textStart == piece.textEnd) continue;
    final dx = math.max(math.max(piece.rect.left - point.dx, point.dx - piece.rect.right), 0.0);
    final dy = math.max(math.max(piece.rect.top - point.dy, point.dy - piece.rect.bottom), 0.0);
    final d = dx * dx + dy * dy;
    if (d < distance) {
      distance = d;
      nearest = piece;
    }
  }
  return nearest;
}

/// Each consecutive leaf segment is persisted in the same editing transaction.
List<InkStroke> paragraphInk(
  ChapterLayout layout,
  List<Offset> points, {
  required String documentId,
  required String Function() newId,
  required InkTool tool,
  required int colorIndex,
  required double width,
}) {
  final groups = <(LayoutPiece, List<Offset>)>[];
  // Subdivide sparse pointer events so crossing a short paragraph cannot skip it.
  final samples = <Offset>[];
  for (var i = 0; i < points.length; i++) {
    final from = i == 0 ? points[i] : points[i - 1], to = points[i];
    final count = math.max(1, ((to - from).distance / math.max(1, layout.spec.fontSize / 2)).ceil());
    for (var n = 1; n <= count && samples.length < InkStroke.maxPoints; n++) {
      samples.add(Offset.lerp(from, to, n / count)!);
    }
    if (samples.length == InkStroke.maxPoints) break;
  }
  for (final point in samples) {
    final piece = inkPieceAt(layout, point);
    if (piece == null) continue;
    if (groups.isEmpty || groups.last.$1 != piece) groups.add((piece, []));
    groups.last.$2.add(point - piece.rect.topLeft);
  }
  return [
    for (final (piece, local) in groups)
      InkStroke(
        id: newId(),
        documentId: documentId,
        textAnchor: ParagraphInkAnchor(
          anchor: layout.chapter.anchor(piece.textStart, piece.textEnd, revision: layout.revision),
          blockId: piece.block.id,
          capturedWidth: piece.rect.width,
          originX: 0,
          originY: 0,
        ),
        tool: tool,
        colorIndex: colorIndex,
        width: width,
        points: tool == InkTool.ellipse
            ? const []
            : [
                for (final point in tool == InkTool.arrow ? [local.first, local.last] : local.take(InkStroke.maxPoints))
                  InkPoint(point.dx, point.dy),
              ],
        // PageRect's top/bottom convention is retained even for local ink.
        ellipse: tool != InkTool.ellipse
            ? null
            : PageRect(
                local.map((p) => p.dx).reduce(math.min) - width,
                local.map((p) => p.dy).reduce(math.max) + width,
                local.map((p) => p.dx).reduce(math.max) + width,
                local.map((p) => p.dy).reduce(math.min) - width,
              ),
      ),
  ];
}

({Offset origin, double scale})? paragraphInkTransform(ChapterLayout layout, ParagraphInkAnchor anchor) {
  if (layout.isDisposed || anchor.anchor.revision != layout.revision || !layout.chapter.resolves(anchor.anchor)) {
    return null;
  }
  final piece = layout.pieces
      .where(
        (p) =>
            !p.decorative &&
            p.block.id == anchor.blockId &&
            p.textStart == anchor.anchor.start &&
            p.textEnd == anchor.anchor.end,
      )
      .firstOrNull;
  if (piece == null || piece.rect.isEmpty) return null;
  final scale = piece.rect.width / anchor.capturedWidth;
  return (origin: piece.rect.topLeft + Offset(anchor.originX, anchor.originY) * scale, scale: scale);
}

List<TextAnchor> captureAnchors(ChapterLayout layout, Rect region, {int? page}) => [
  for (final piece in layout.pieces)
    if (!piece.decorative && piece.textStart < piece.textEnd)
      if ((page == null
              ? piece.rect
              : Rect.fromPoints(layout.toPage(piece.rect.topLeft, page), layout.toPage(piece.rect.bottomRight, page)))
          .overlaps(region))
        layout.chapter.anchor(piece.textStart, piece.textEnd, revision: layout.revision),
];

/// Overflowing cards remain markers; they never extend below the reader.
List<({double top, bool card})> packReflowNotes(List<({double y, double height})> notes, double height, double gap) {
  var bottom = 0.0;
  return [
    for (final note in notes)
      (() {
        final top = math.max(note.y, bottom);
        final fits = top + note.height <= height;
        if (fits) bottom = top + note.height + gap;
        return (top: fits ? top : note.y.clamp(0.0, math.max(0.0, height - gap)).toDouble(), card: fits);
      })(),
  ];
}
