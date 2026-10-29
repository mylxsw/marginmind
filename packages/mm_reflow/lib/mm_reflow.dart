/// Chapter geometry is disposable; canonical text and anchors are not.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_design/mm_design.dart';

class LayoutSpec {
  const LayoutSpec({required this.width, this.pageHeight = 640, this.fontSize = 16, this.lineHeight = 1.5});
  final double width, pageHeight, fontSize, lineHeight;
  void validate() {
    if (![width, pageHeight, fontSize, lineHeight].every((v) => v.isFinite && v > 0)) {
      throw ArgumentError('Layout dimensions must be finite and positive');
    }
  }
}

class LayoutPiece {
  LayoutPiece(this.block, this.painter, this.rect, this.textStart, this.textEnd, {this.image});
  final BookBlock block;
  final TextPainter? painter;
  final Rect rect;
  final int textStart, textEnd;
  final MMBookImage? image;
  final List<InlineArtwork> artwork = [];
}

class InlineArtwork {
  InlineArtwork(this.image, this.rect);
  final MMBookImage? image;
  final Rect rect;
}

class PageSlice {
  const PageSlice(this.top, this.bottom);
  final double top, bottom;
  double get height => bottom - top;
}

class ChapterLayout {
  ChapterLayout._(this.chapter, this.spec, this.pieces, this.pages, this.height);
  final BookChapter chapter;
  final LayoutSpec spec;
  final List<LayoutPiece> pieces;
  final List<PageSlice> pages;
  final double height;

  /// Callers own decoded images. The layout owns and disposes its text painters.
  factory ChapterLayout.layout(BookChapter chapter, LayoutSpec spec, {Map<String, MMBookImage> images = const {}}) {
    spec.validate();
    final pieces = <LayoutPiece>[];
    final breaks = <double>[0];
    var y = 0.0;
    final artwork = <TextPainter, List<InlineArtwork>>{};
    TextPainter textPainter(List<InlineRun> runs, double width, {double scale = 1}) {
      final dimensions = <PlaceholderDimensions>[];
      final inlineImages = <MMBookImage?>[];
      double? length(String? value) {
        final match = RegExp(r'^([0-9.]+)(px|em|ex|%)?$').firstMatch(value ?? '');
        if (match == null) return null;
        final n = double.tryParse(match[1]!);
        if (n == null || n <= 0) return null;
        return n *
            switch (match[2]) {
              'em' => spec.fontSize * scale,
              'ex' => spec.fontSize * scale * .5,
              '%' => width / 100,
              _ => 1.0,
            };
      }

      InlineSpan span(InlineRun run) {
        if (run.resource != null) {
          final image = images[run.resource];
          final natural = image?.size ?? Size(spec.fontSize, spec.fontSize);
          var w = length(run.width);
          var h = length(run.height);
          w ??= h == null ? natural.width : h * natural.width / natural.height;
          h ??= w * natural.height / natural.width;
          final ratio = math.min(1.0, math.min(width / w, spec.pageHeight / h));
          final size = Size(w * ratio, h * ratio);
          dimensions.add(PlaceholderDimensions(size: size, alignment: PlaceholderAlignment.middle));
          inlineImages.add(image);
          return const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox());
        }
        return TextSpan(
          text: run.text,
          style: TextStyle(
            fontWeight: run.strong ? FontWeight.bold : null,
            fontStyle: run.emphasis ? FontStyle.italic : null,
            fontFamily: run.code ? 'monospace' : null,
            decoration: run.link == null ? null : TextDecoration.underline,
          ),
        );
      }

      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          style: TextStyle(
            fontSize: spec.fontSize * scale,
            height: spec.lineHeight,
            color: MMReaderStyle.white.inkColor,
          ),
          children: runs.map(span).toList(),
        ),
      );
      painter.setPlaceholderDimensions(dimensions);
      painter.layout(maxWidth: width);
      final boxes = painter.inlinePlaceholderBoxes ?? [];
      artwork[painter] = [for (var i = 0; i < boxes.length; i++) InlineArtwork(inlineImages[i], boxes[i].toRect())];
      return painter;
    }

    for (final block in chapter.blocks) {
      if (block.kind == BlockKind.image) {
        final image = images[block.resource];
        final aspect = image == null ? 1.5 : image.size.width / image.size.height;
        final width = math.min(spec.width, spec.pageHeight * aspect);
        final h = width / aspect;
        pieces.add(LayoutPiece(block, null, Rect.fromLTWH(0, y, width, h), block.start, block.end, image: image));
        y += h;
        breaks.add(y);
      } else if (block.kind == BlockKind.table && block.rows.isNotEmpty) {
        final columns = block.rows.map((r) => r.length).reduce(math.max);
        final cellWidth = spec.width / columns;
        var offset = block.start;
        for (final row in block.rows) {
          final cells = <TextPainter>[];
          for (final cell in row) {
            cells.add(textPainter(cell.runs, math.max(1, cellWidth - 8)));
          }
          final rowHeight = cells.map((p) => p.height).fold(0.0, math.max) + 8;
          for (var i = 0; i < cells.length; i++) {
            pieces.add(
              LayoutPiece(
                block,
                cells[i],
                Rect.fromLTWH(i * cellWidth + 4, y + 4, cellWidth - 8, cells[i].height),
                offset,
                offset + row[i].length,
              ),
            );
            offset += row[i].length + 1; // TAB, or LF after the last cell.
          }
          y += rowHeight;
          breaks.add(y);
        }
      } else {
        final indent = block.kind == BlockKind.list || block.kind == BlockKind.quote ? spec.fontSize : 0.0;
        final painter = textPainter(
          block.runs,
          math.max(1, spec.width - indent),
          scale: block.kind == BlockKind.heading ? 1.5 : 1,
        );
        pieces.add(
          LayoutPiece(block, painter, Rect.fromLTWH(indent, y, painter.width, painter.height), block.start, block.end),
        );
        for (final line in painter.computeLineMetrics()) {
          breaks.add(y + line.baseline + line.descent);
        }
        y += painter.height;
      }
      y += spec.fontSize * .5;
      breaks.add(y);
    }
    for (final piece in pieces) {
      piece.artwork.addAll(artwork[piece.painter] ?? []);
    }
    // Greedy page boundaries at line/row edges. An oversized row is sliced;
    // geometry and glyphs remain identical to continuous scrolling.
    final pages = <PageSlice>[];
    var top = 0.0;
    var index = 0;
    while (top < y) {
      final limit = top + spec.pageHeight;
      var bottom = top;
      while (index < breaks.length && breaks[index] <= limit) {
        if (breaks[index] > bottom) bottom = breaks[index];
        index++;
      }
      if (bottom <= top) bottom = math.min(limit, y);
      pages.add(PageSlice(top, bottom));
      top = bottom;
    }
    if (pages.isEmpty) pages.add(const PageSlice(0, 0));
    return ChapterLayout._(chapter, spec, List.unmodifiable(pieces), List.unmodifiable(pages), y);
  }

  int hitTest(Offset point) {
    if (pieces.isEmpty) return 0;
    var nearest = pieces.first;
    var distance = double.infinity;
    for (final piece in pieces) {
      final dx = math.max(math.max(piece.rect.left - point.dx, point.dx - piece.rect.right), 0.0);
      final dy = math.max(math.max(piece.rect.top - point.dy, point.dy - piece.rect.bottom), 0.0);
      final d = dx * dx + dy * dy;
      if (d < distance) {
        distance = d;
        nearest = piece;
      }
    }
    final offset = nearest.painter?.getPositionForOffset(point - nearest.rect.topLeft).offset ?? 0;
    return (nearest.textStart + offset).clamp(nearest.textStart, nearest.textEnd);
  }

  List<Rect> boxes(TextAnchor anchor) {
    if (!chapter.resolves(anchor)) return const [];
    final result = <Rect>[];
    for (final piece in pieces) {
      final start = math.max(anchor.start, piece.textStart);
      final end = math.min(anchor.end, piece.textEnd);
      if (start >= end) continue;
      if (piece.painter == null) {
        result.add(piece.rect);
        continue;
      }
      result.addAll(
        piece.painter!
            .getBoxesForSelection(
              TextSelection(baseOffset: start - piece.textStart, extentOffset: end - piece.textStart),
            )
            .map((box) => box.toRect().shift(piece.rect.topLeft)),
      );
    }
    return result;
  }

  int pageForOffset(int offset) {
    final piece = pieces.where((p) => p.textEnd > offset).firstOrNull;
    if (piece == null) return pages.length - 1;
    final caret =
        piece.painter?.getOffsetForCaret(
          TextPosition(offset: (offset - piece.textStart).clamp(0, piece.textEnd - piece.textStart)),
          Rect.zero,
        ) ??
        Offset.zero;
    final y = piece.rect.top + caret.dy;
    final page = pages.indexWhere((p) => p.bottom > y);
    return page < 0 ? pages.length - 1 : page;
  }

  void paint(Canvas canvas, {int? page, TextAnchor? highlight}) {
    final slice = page == null ? PageSlice(0, height) : pages[page];
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, spec.width, page == null ? height : spec.pageHeight));
    canvas.translate(0, -slice.top);
    canvas.clipRect(Rect.fromLTWH(0, slice.top, spec.width, slice.height));
    if (highlight != null) {
      final paint = Paint()..color = MMReaderStyle.white.marginNoteLine;
      for (final rect in boxes(highlight)) {
        canvas.drawRect(rect, paint);
      }
    }
    for (final piece in pieces) {
      if (piece.rect.bottom < slice.top || piece.rect.top > slice.bottom) continue;
      if (piece.painter != null) {
        piece.painter!.paint(canvas, piece.rect.topLeft);
        for (final art in piece.artwork) {
          final rect = art.rect.shift(piece.rect.topLeft);
          if (art.image != null) {
            art.image!.paint(canvas, rect);
          } else {
            canvas.drawRect(rect, Paint()..color = MMColors.light.fill);
          }
        }
      } else if (piece.image != null) {
        piece.image!.paint(canvas, piece.rect);
      } else {
        canvas.drawRect(piece.rect, Paint()..color = MMColors.light.fill);
      }
    }
    canvas.restore();
  }

  void dispose() {
    for (final piece in pieces) {
      piece.painter?.dispose();
    }
  }
}

/// The gesture and paint surface used by both scrolling and paginated readers.
/// The caller owns the layout and the persistent selection.
class ReflowSurface extends StatefulWidget {
  const ReflowSurface({super.key, required this.layout, this.page, this.highlight, required this.onSelection});
  final ChapterLayout layout;
  final int? page;
  final TextAnchor? highlight;
  final ValueChanged<TextAnchor> onSelection;
  @override
  State<ReflowSurface> createState() => _ReflowSurfaceState();
}

class _ReflowSurfaceState extends State<ReflowSurface> {
  int? start;
  void select(Offset local, bool begin) {
    final layout = widget.layout;
    final offset = layout.hitTest(local + Offset(0, widget.page == null ? 0 : layout.pages[widget.page!].top));
    if (begin) start = offset;
    if (start == null) return;
    widget.onSelection(layout.chapter.anchor(math.min(start!, offset), math.max(start!, offset)));
  }

  @override
  void didUpdateWidget(ReflowSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) start = null;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: (details) => select(details.localPosition, true),
    onPanUpdate: (details) => select(details.localPosition, false),
    onPanEnd: (_) => start = null,
    child: CustomPaint(
      size: Size(widget.layout.spec.width, widget.page == null ? widget.layout.height : widget.layout.spec.pageHeight),
      painter: _ChapterPainter(widget.layout, widget.page, widget.highlight),
    ),
  );
}

class _ChapterPainter extends CustomPainter {
  _ChapterPainter(this.layout, this.page, this.anchor);
  final ChapterLayout layout;
  final int? page;
  final TextAnchor? anchor;
  @override
  void paint(Canvas canvas, Size size) => layout.paint(canvas, page: page, highlight: anchor);
  @override
  bool shouldRepaint(_ChapterPainter old) => old.layout != layout || old.page != page || old.anchor != anchor;
}
