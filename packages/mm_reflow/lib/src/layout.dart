part of '../mm_reflow.dart';

Rect _scaleRect(Rect rect, double scale) =>
    Rect.fromLTRB(rect.left * scale, rect.top * scale, rect.right * scale, rect.bottom * scale);

/// A shaped leaf or table cell. [rect] uses chapter coordinates. [viewport]
/// bounds locally scrollable code/table content; [contentWidth] may exceed it.
class LayoutPiece {
  LayoutPiece(
    this.block,
    this.painter,
    this.rect,
    this.textStart,
    this.textEnd, {
    this.image,
    this.viewport,
    this.contentWidth = 0,
    this.scale = 1,
    this.decorative = false,
    this.sourceOffsets,
  });
  final BookBlock block;
  final TextPainter? painter;
  final Rect rect;
  final int textStart, textEnd;
  final MMBookImage? image;
  final Rect? viewport;
  final double contentWidth, scale;
  final bool decorative;
  final List<int>? sourceOffsets;
  final List<InlineArtwork> artwork = [];

  int _source(int visual) => sourceOffsets == null
      ? (textStart + visual).clamp(textStart, textEnd)
      : sourceOffsets![visual.clamp(0, sourceOffsets!.length - 1)];
  int _visual(int source, {bool end = false}) {
    final offsets = sourceOffsets;
    if (offsets == null) return (source - textStart).clamp(0, textEnd - textStart);
    // Lower bound excludes ruby annotations and indentation from selection.
    var lo = 0, hi = offsets.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (offsets[mid] < source || (!end && offsets[mid] == source)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return (end ? lo : lo - 1).clamp(0, offsets.length - 1);
  }

  Iterable<ui.TextBox> _boxes(int start, int end) sync* {
    final first = _visual(start), last = _visual(end, end: true);
    var segment = first;
    for (var i = first; i < last; i++) {
      if (_source(i) == _source(i + 1)) {
        if (segment < i) yield* painter!.getBoxesForSelection(TextSelection(baseOffset: segment, extentOffset: i));
        segment = i + 1;
      }
    }
    if (segment < last) yield* painter!.getBoxesForSelection(TextSelection(baseOffset: segment, extentOffset: last));
  }
}

/// Artwork is borrowed from [LayoutResources]; dispose it after all layouts and
/// cache entries using it have been released.
class InlineArtwork {
  InlineArtwork(this.image, this.rect);
  final MMBookImage? image;
  final Rect rect;
}

/// A page cuts the already shaped chapter at line/row-group boundaries.
/// Oversized row groups occupy one page with a positive [scrollExtent].
class PageSlice {
  const PageSlice(this.top, this.bottom, {this.header = const [], this.headerHeight = 0, this.scrollExtent = 0});
  final double top, bottom, headerHeight, scrollExtent;
  final List<LayoutPiece> header;
  double get height => bottom - top;
}

class _Geometry {
  _Geometry(this.pieces, this.pages, this.height, this.links, this.workTime, this.maxBatchTime);
  final List<LayoutPiece> pieces;
  final List<PageSlice> pages;
  final double height;
  final List<LayoutLink> links;
  Duration workTime;
  Duration maxBatchTime;
  int references = 1;
  int get estimatedBytes => pieces.fold(0, (n, p) => n + 256 + (p.textEnd - p.textStart) * 64 + p.artwork.length * 64);
  void release() {
    if (--references == 0) {
      for (final piece in pieces) {
        piece.painter?.dispose();
      }
    }
  }
}

/// A disposable lease over chapter geometry. Cached leases share painters;
/// disposing one lease never invalidates a different active lease.
class ChapterLayout {
  ChapterLayout._(this.chapter, this.spec, this.generation, this.revision, this._geometry);
  final BookChapter chapter;
  final LayoutSpec spec;
  final int generation;
  final String revision;
  final _Geometry _geometry;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  List<LayoutPiece> get pieces => _geometry.pieces;
  List<PageSlice> get pages => _geometry.pages;
  List<LayoutLink> get links => _geometry.links;
  double get height => _geometry.height;
  int get estimatedBytes => _geometry.estimatedBytes;
  Duration get workTime => _geometry.workTime;
  Duration get maxBatchTime => _geometry.maxBatchTime;

  /// Synchronous compatibility entry point for offline probes. Interactive
  /// readers use [ReflowEngine.layout], which yields between work batches.
  factory ChapterLayout.layout(
    BookChapter chapter,
    LayoutSpec spec, {
    Map<String, MMBookImage> images = const {},
    LayoutResources? resources,
    int generation = 0,
    String revision = '',
  }) {
    spec.validate();
    final builder = _Typesetter(chapter, spec, resources ?? LayoutResources(images: images));
    try {
      for (final _ in builder.steps()) {
        /* synchronous probe */
      }
      return ChapterLayout._(chapter, spec, generation, revision, builder.finish());
    } catch (_) {
      builder.dispose();
      rethrow;
    }
  }

  ChapterLayout _retain(int generation) {
    _check();
    _geometry.references++;
    return ChapterLayout._(chapter, spec, generation, revision, _geometry);
  }

  void _check() {
    if (_disposed) throw StateError('Layout has been disposed');
  }

  /// Temporary mm_book adapter: a position is a collapsed existing TextAnchor.
  /// GUL-573 replaces this boundary with mm_core.TextPosition; no second domain
  /// position type or persisted screen offsets are introduced here.
  TextAnchor hitTest(
    Offset point, {
    int? page,
    Offset localScroll = Offset.zero,
    Map<String, double> horizontalOffsets = const {},
  }) {
    _check();
    if (page != null) point = toChapter(point, page, localScroll: localScroll);
    if (pieces.isEmpty) return chapter.anchor(0, 0);
    LayoutPiece? nearest;
    var distance = double.infinity;
    for (final piece in pieces) {
      if (piece.decorative) continue;
      final shifted = piece.rect.shift(Offset(-(horizontalOffsets[piece.block.id] ?? 0), 0));
      final dx = math.max(math.max(shifted.left - point.dx, point.dx - shifted.right), 0.0);
      final dy = math.max(math.max(piece.rect.top - point.dy, point.dy - piece.rect.bottom), 0.0);
      final d = dx * dx + dy * dy;
      if (d < distance) {
        distance = d;
        nearest = piece;
      }
    }
    if (nearest == null) return chapter.anchor(0, 0);
    point += Offset(horizontalOffsets[nearest.block.id] ?? 0, 0);
    final visual = nearest.painter?.getPositionForOffset((point - nearest.rect.topLeft) / nearest.scale).offset ?? 0;
    final offset = _snap(nearest._source(visual));
    return chapter.anchor(offset, offset);
  }

  int _snap(int offset) {
    final expanded = chapter.anchor(offset, offset);
    return offset - expanded.start <= expanded.end - offset ? expanded.start : expanded.end;
  }

  /// Preserves separate bidi rectangles; never merges a line across a bidi gap.
  List<LayoutBox> boxes(
    TextAnchor anchor, {
    int? page,
    Offset localScroll = Offset.zero,
    Map<String, double> horizontalOffsets = const {},
  }) {
    _check();
    if (!chapter.resolves(anchor)) return const [];
    final result = <LayoutBox>[];
    for (final piece in pieces) {
      if (piece.decorative) continue;
      final start = math.max(anchor.start, piece.textStart);
      final end = math.min(anchor.end, piece.textEnd);
      if (start >= end) continue;
      final rects = piece.painter == null
          ? [piece.rect]
          : piece._boxes(start, end).map((box) => _scaleRect(box.toRect(), piece.scale).shift(piece.rect.topLeft));
      for (var rect in rects) {
        if (horizontalOffsets.containsKey(piece.block.id)) {
          rect = rect.shift(Offset(-horizontalOffsets[piece.block.id]!, 0));
          rect = rect.intersect(
            Rect.fromLTRB(spec.padding.left, rect.top, spec.width - spec.padding.right, rect.bottom),
          );
          if (rect.isEmpty) continue;
        }
        if (page != null) {
          final slice = pages[page];
          rect = rect.intersect(Rect.fromLTRB(0, slice.top, double.maxFinite, slice.bottom));
          if (rect.isEmpty) continue;
          rect = rect.shift(_pageShift(page, localScroll));
          rect = rect.intersect(
            Rect.fromLTWH(
              spec.padding.left,
              spec.padding.top + slice.headerHeight,
              spec.contentWidth,
              spec.contentHeight - slice.headerHeight,
            ),
          );
          if (rect.isEmpty) continue;
        }
        result.add(LayoutBox(rect, generation, page: page));
      }
    }
    return List.unmodifiable(result);
  }

  /// Returns the source caret/line rectangle, or null for a stale source anchor.
  /// Applies the same scroll transforms as [boxes], without clipping the caret:
  /// callers can use an offscreen rectangle to scroll the position into view.
  LayoutBox? reveal(
    TextAnchor position, {
    int? page,
    Offset localScroll = Offset.zero,
    Map<String, double> horizontalOffsets = const {},
  }) {
    _check();
    if (!chapter.resolves(position)) return null;
    final offset = _snap(position.start);
    final eligible = pieces.where((p) => !p.decorative && p.textStart <= offset && p.textEnd >= offset);
    final piece = eligible.firstOrNull ?? pieces.where((p) => !p.decorative && p.textEnd >= offset).firstOrNull;
    if (piece == null) {
      return LayoutBox(Rect.fromLTWH(spec.padding.left, spec.padding.top, 0, 0), generation, page: page);
    }
    var rect = piece.rect;
    if (piece.painter case final TextPainter painter) {
      final caret = painter.getOffsetForCaret(ui.TextPosition(offset: piece._visual(offset)), Rect.zero);
      final metrics = painter.computeLineMetrics();
      final line = metrics.where((l) => l.baseline + l.descent > caret.dy).firstOrNull;
      rect = Rect.fromLTWH(
        piece.rect.left + caret.dx * piece.scale,
        piece.rect.top + caret.dy * piece.scale,
        1,
        (line?.height ?? spec.fontSize * spec.lineHeight) * piece.scale,
      );
    }
    rect = rect.shift(Offset(-(horizontalOffsets[piece.block.id] ?? 0), 0));
    if (page != null) rect = rect.shift(_pageShift(page, localScroll));
    return LayoutBox(rect, generation, page: page);
  }

  int pageForOffset(int offset) {
    _check();
    if (offset >= chapter.canonicalText.length) return pages.length - 1;
    final y = reveal(
      chapter.anchor(
        _snap(offset.clamp(0, chapter.canonicalText.length)),
        _snap(offset.clamp(0, chapter.canonicalText.length)),
      ),
    )!.rect.top;
    final index = pages.indexWhere((p) => p.bottom > y);
    return index < 0 ? pages.length - 1 : index;
  }

  Offset _pageShift(int page, Offset scroll) =>
      Offset(-scroll.dx, spec.padding.top + pages[page].headerHeight - pages[page].top - scroll.dy);

  /// Convert a viewport point on a page to continuous chapter coordinates.
  Offset toChapter(Offset point, int page, {Offset localScroll = Offset.zero}) => point - _pageShift(page, localScroll);

  /// Convert a continuous chapter point to a page viewport.
  Offset toPage(Offset point, int page, {Offset localScroll = Offset.zero}) => point + _pageShift(page, localScroll);

  ViewportBookmark capture(double top) {
    final position = hitTest(Offset(spec.padding.left, top));
    final rect = reveal(position)!.rect;
    return ViewportBookmark(
      position,
      rect.height == 0 ? 0 : ((top - rect.top) / rect.height).clamp(0, 1),
      revision: revision,
    );
  }

  double? restore(ViewportBookmark bookmark) {
    if (bookmark.revision != null && bookmark.revision != revision) return null;
    final rect = reveal(bookmark.position)?.rect;
    return rect == null ? null : rect.top + rect.height * bookmark.lineFraction;
  }

  /// Resolves same-chapter footnotes/fragment links without executing navigation.
  TextAnchor? target(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.hasScheme || !uri.hasFragment) return null;
    if (uri.path.isNotEmpty && Uri.parse(chapter.id).resolve(uri.path).path != chapter.id) return null;
    final offset = chapter.elementOffsets[uri.fragment];
    return offset == null ? null : chapter.anchor(offset, offset);
  }

  /// Paints the original shaped paragraphs; pagination never reshapes substrings.
  /// [localScroll] exposes oversized pages and horizontally overflowing code or
  /// tables. The reading UI owns scroll controls and clamps to the content extent.
  void paint(
    Canvas canvas, {
    int? page,
    TextAnchor? highlight,
    Offset localScroll = Offset.zero,
    Map<String, double> horizontalOffsets = const {},
  }) {
    _check();
    final slice = page == null ? PageSlice(0, height) : pages[page];
    final shift = page == null ? Offset.zero : _pageShift(page, localScroll);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, spec.width, page == null ? height : spec.pageHeight));
    if (page != null) {
      canvas.clipRect(
        Rect.fromLTWH(
          spec.padding.left,
          spec.padding.top + slice.headerHeight,
          spec.contentWidth,
          spec.contentHeight - slice.headerHeight,
        ),
      );
    } else {
      canvas.clipRect(Rect.fromLTWH(spec.padding.left, 0, spec.contentWidth, height));
    }
    canvas.translate(shift.dx, shift.dy);
    canvas.clipRect(Rect.fromLTRB(localScroll.dx, slice.top, spec.width + localScroll.dx, slice.bottom));
    if (highlight != null) {
      for (final box in boxes(highlight, horizontalOffsets: horizontalOffsets)) {
        canvas.drawRect(box.rect, Paint()..color = spec.readerStyle.marginNoteLine);
      }
    }
    for (final piece in pieces) {
      if (piece.rect.bottom < slice.top || piece.rect.top > slice.bottom) continue;
      canvas.save();
      canvas.translate(-(horizontalOffsets[piece.block.id] ?? 0), 0);
      _paintPiece(canvas, piece);
      canvas.restore();
    }
    canvas.restore();
    if (page != null && slice.header.isNotEmpty) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(spec.padding.left, spec.padding.top, spec.contentWidth, slice.headerHeight));
      final origin = slice.header.map((p) => p.rect.top).reduce(math.min);
      canvas.translate(-localScroll.dx, spec.padding.top - origin);
      for (final p in slice.header) {
        canvas.save();
        canvas.translate(-(horizontalOffsets[p.block.id] ?? 0), 0);
        _paintPiece(canvas, p);
        canvas.restore();
      }
      canvas.restore();
    }
  }

  void _paintPiece(Canvas canvas, LayoutPiece piece) {
    if (piece.painter != null) {
      canvas.save();
      canvas.translate(piece.rect.left, piece.rect.top);
      canvas.scale(piece.scale);
      piece.painter!.paint(canvas, Offset.zero);
      for (final art in piece.artwork) {
        final rect = art.rect;
        if (art.image != null) {
          art.image!.paint(canvas, rect);
        } else {
          canvas.drawRect(rect, Paint()..color = spec.readerStyle.marginGuide);
        }
      }
      canvas.restore();
    } else if (piece.image != null) {
      piece.image!.paint(canvas, piece.rect);
    } else {
      canvas.drawRect(piece.rect, Paint()..color = spec.readerStyle.marginGuide);
    }
  }

  /// Idempotent; caller-owned images outlive every lease/cache entry using them.
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _geometry.release();
    }
  }
}
