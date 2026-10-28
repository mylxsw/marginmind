import 'dart:async';

import 'package:flutter/foundation.dart';

import 'open_document.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart' show AnnotationPage, InkPoint, InkStroke, InkTool, PageRect;
import 'package:pdfrx/pdfrx.dart';

import 'excerpt_text.dart';
import 'ink.dart';
import 'pdf_navigation.dart';
import 'pdf_pixel_grid.dart';
import 'preview_cache.dart';

/// A highlight to draw on a page.
@immutable
class MMPdfHighlight {
  const MMPdfHighlight({
    required this.id,
    required this.page,
    required this.rects,
    required this.color,
    this.underline,
    this.emphasized = false,
    this.framed = false,
    this.dashed = false,
    this.marker,
  });

  final String id;
  final int page;
  final List<PageRect> rects;

  /// Fill (already translucent).
  final Color color;

  /// 2px underline marking "has a card", or null.
  final Color? underline;

  /// Linked-highlight flash or selection ring.
  final bool emphasized;

  /// An area excerpt: outlined in [underline] (or [color]) instead of
  /// covering the figure with a fill.
  final bool framed;

  /// [underline] is drawn dashed: text a note is attached to, not excerpted.
  final bool dashed;

  /// A round mark in the page's right margin beside the first rect, filled
  /// with this color; tapping it is tapping the highlight.
  final Color? marker;
}

/// A rectangle dragged with the area tool, clamped to the page it started on.
@immutable
class MMPdfArea {
  const MMPdfArea({required this.page, required this.rect, required this.viewportRect});

  final int page;
  final PageRect rect;

  /// Bounds in the PDF viewport coordinates.
  final Rect viewportRect;
}

/// Text the user selected, with page geometry in reading order.
@immutable
class MMPdfSelection {
  const MMPdfSelection({
    int? page,
    List<PageRect>? rects,
    List<AnnotationPage>? pages,
    required this.text,
    this.viewportRect,
  }) : assert(pages != null || (page != null && rects != null)),
       _pages = pages,
       _page = page,
       _rects = rects;

  final List<AnnotationPage>? _pages;
  final int? _page;
  final List<PageRect>? _rects;
  List<AnnotationPage> get pages => _pages ?? [AnnotationPage(page: _page!, rects: _rects!)];

  /// The first page is the navigation target for the entire excerpt.
  int get page => pages.first.page;
  List<PageRect> get rects => pages.first.rects;
  final String text;

  /// Bounding rect in the PDF viewport coordinates.
  final Rect? viewportRect;
}

/// Commands from outside (e.g. "reveal this excerpt") into an [MMPdfView],
/// and what the view reports back: page, outline and in-document search.
/// Listeners are notified (never during a build) when any of it changes.
class MMPdfViewController extends ChangeNotifier {
  _MMPdfViewState? _state;
  final _history = PageHistory();
  bool _disposed = false;
  int _page = 1;
  int _pageCount = 0;
  List<MMPdfOutlineItem> _outline = const [];

  /// Page shown at the top of the viewport (1-based).
  int get currentPage => _page;
  int get pageCount => _pageCount;

  /// The document's own table of contents; empty when it has none.
  List<MMPdfOutlineItem> get outline => _outline;

  bool get isReady => _state?._ready ?? false;

  /// Scrolls so that [rects] on [page] are centered (left-aligned when wider than the viewport).
  Future<void> reveal(int page, List<PageRect> rects) async => _state?._reveal(page, rects);

  /// Same as [reveal], and remembers where the reader was for [goBack].
  Future<void> jumpToRect(int page, List<PageRect> rects) async {
    _history.record(_page);
    await _state?._reveal(page, rects);
    _notify();
  }

  Future<void> goToPage(int page, {bool alignTop = false}) async =>
      _state?._controller.goToPage(pageNumber: page, anchor: alignTop ? PdfPageAnchor.top : null);

  /// Direct manipulation: no animated jumps queue up while scrubbing.
  Future<void> scrubToPage(int page) async {
    if (!isReady || _pageCount == 0) return;
    await _state!._controller.goToPage(
      pageNumber: page.clamp(1, _pageCount),
      anchor: PdfPageAnchor.top,
      duration: Duration.zero,
    );
  }

  /// Deliberate jump to [page] (clamped to the document); [goBack] returns.
  /// The page's top edge lands at the top of the viewport unless [alignTop]
  /// is false (the last page then rests at the bottom).
  Future<void> jumpToPage(int page, {bool alignTop = true}) async {
    if (!isReady || _pageCount == 0) return;
    final target = page.clamp(1, _pageCount);
    if (target == _page) {
      // Already on the page, perhaps only partly in view: bring its top in.
      if (alignTop) await goToPage(target, alignTop: true);
      return;
    }
    _history.record(_page);
    await goToPage(target, alignTop: alignTop);
    _notify();
  }

  Future<void> firstPage() => jumpToPage(1);

  Future<void> lastPage() => jumpToPage(_pageCount, alignTop: false);

  bool get canGoBack => _history.canGoBack;

  /// Returns to the page before the latest jump.
  Future<void> goBack() async {
    final target = _history.back();
    if (target == null) return;
    await goToPage(target);
    _notify();
  }

  Future<void> clearSelection() async => _state?._clearSelection();

  Future<void> zoomIn() async {
    if (isReady) await _state!._controller.zoomUp();
  }

  Future<void> zoomOut() async {
    if (isReady) await _state!._controller.zoomDown();
  }

  /// PDF points map 1:1 to logical pixels, independent of display DPR.
  Future<void> actualSize() async {
    if (!isReady) return;
    final pdf = _state!._controller;
    await pdf.setZoom(pdf.centerPosition, 1);
  }

  Future<void> fitWidth() async {
    if (!isReady) return;
    final pdf = _state!._controller;
    await pdf.goTo(pdf.calcMatrixFitWidthForPage(pageNumber: pdf.pageNumber ?? 1));
  }

  Future<void> fitPage() async {
    if (!isReady) return;
    final pdf = _state!._controller;
    await pdf.goTo(pdf.calcMatrixForFit(pageNumber: pdf.pageNumber ?? 1));
  }

  /// Document-scoped thumbnail cache for sidebar consumers (GUL-496).
  /// Width is in physical pixels, rounded up to a 64px bucket; max 1024.
  /// Returns read-only PNG bytes, or null if unavailable or invalidated.
  /// Consumers must discard results when their document/page changes.
  Future<Uint8List?> renderPreview(int page, {int pixelWidth = 160}) async {
    if (!isReady) return null;
    return _state!._previews.get(page, pixelWidth: pixelWidth);
  }

  /// Renders [rect] of [page] as PNG bytes at [scale] pixels per point
  /// (longest side capped at [maxPixels]); null if the view is not ready or
  /// the page cannot be rendered.
  Future<Uint8List?> captureArea(int page, PageRect rect, {double scale = 3, int maxPixels = 3000}) async =>
      _state?._capture(page, rect, scale, maxPixels);

  /// The text of [page] in reading order, or null when the view is not ready
  /// or the page has no text layer.
  Future<String?> pageText(int page) async => _state?._pageText(page);

  // ---- search -----------------------------------------------------------------

  String _query = '';
  int _matchCount = 0;
  int? _matchIndex;
  bool _searching = false;

  String get searchQuery => _query;
  int get matchCount => _matchCount;

  /// 0-based position of the current match, null without matches.
  int? get matchIndex => _matchIndex;
  bool get isSearching => _searching;

  /// Looks for [query] in the whole document and highlights every hit; an
  /// empty query clears the search.
  void search(String query) {
    _query = query;
    final state = _state;
    if (state == null || !state._ready) {
      _notify();
      return;
    }
    final searcher = state._searcher;
    if (searcher == null) return;
    if (query.isEmpty) {
      searcher.resetTextSearch();
    } else {
      searcher.startTextSearch(query, searchImmediately: true);
    }
    _syncSearch();
  }

  Future<void> nextMatch() async {
    if (_matchCount == 0) return;
    await _state?._searcher?.goToNextMatch();
    _syncSearch();
  }

  Future<void> previousMatch() async {
    if (_matchCount == 0) return;
    await _state?._searcher?.goToPrevMatch();
    _syncSearch();
  }

  void clearSearch() => search('');

  void _syncSearch() {
    final searcher = _state?._searcher;
    _matchCount = searcher?.matches.length ?? 0;
    _matchIndex = _matchCount == 0 ? null : searcher?.currentIndex;
    _searching = searcher?.isSearching ?? false;
    _notify();
  }

  // ---- reported by the view ------------------------------------------------------

  void _attach(_MMPdfViewState state) {
    _state = state;
    _history.clear();
    _page = 1;
    _pageCount = 0;
    _outline = const [];
    _matchCount = 0;
    _matchIndex = null;
    _searching = false;
    _notify();
  }

  void _detach(_MMPdfViewState state) {
    if (_state != state) return;
    _state = null;
    _notify();
  }

  void _reportPage(int page) {
    if (_page == page) return;
    _page = page;
    _notify();
  }

  void _reportReady(int pageCount, List<MMPdfOutlineItem> outline) {
    _pageCount = pageCount;
    _outline = outline;
    _notify();
  }

  /// Lets widget tests that have no PDF engine stand in for an open
  /// document: pretends the view reported these values.
  @visibleForTesting
  void debugReport({int? pageCount, int? page, List<MMPdfOutlineItem>? outline}) {
    if (pageCount != null) _pageCount = pageCount;
    if (page != null) _page = page;
    if (outline != null) _outline = outline;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A lazily rendered page preview for the reader sidebar. Draws nothing
/// until [controller] has an open document.
class MMPdfThumbnail extends StatefulWidget {
  const MMPdfThumbnail({
    super.key,
    required this.controller,
    required this.page,
    required this.width,
    required this.height,
    this.backgroundColor = const Color(0xFFFFFFFF),
  });

  final MMPdfViewController controller;
  final int page;
  final double width;
  final double height;
  final Color backgroundColor;

  @override
  State<MMPdfThumbnail> createState() => _MMPdfThumbnailState();
}

class _MMPdfThumbnailState extends State<MMPdfThumbnail> {
  (PdfDocument, int, int)? _request;
  Future<Uint8List?>? _image;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller._state;
      final document = state?._ready == true ? state!._controller.document : null;
      final width = (widget.width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 1024);
      final request = document == null ? null : (document, widget.page, width);
      if (request != _request) {
        _request = request;
        _image = request == null ? null : widget.controller.renderPreview(widget.page, pixelWidth: width);
      }
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: ColoredBox(
          color: widget.backgroundColor,
          child: request == null
              ? null
              : FutureBuilder<Uint8List?>(
                  key: ValueKey(request),
                  future: _image,
                  builder: (context, snapshot) => snapshot.data == null
                      ? const SizedBox()
                      : Image.memory(snapshot.data!, fit: BoxFit.contain, gaplessPlayback: false),
                ),
        ),
      );
    },
  );
}

/// One page of the PDF at [filePath], opened on its own (no reader needed),
/// with [covers] drawn over it in [coverColor]. Draws nothing while the file
/// loads or when it cannot be read.
class MMPdfPagePreview extends StatelessWidget {
  const MMPdfPagePreview({
    super.key,
    required this.filePath,
    required this.page,
    this.covers = const [],
    required this.coverColor,
    this.backgroundColor = const Color(0xFFFFFFFF),
  });

  final String filePath;
  final int page;
  final List<PageRect> covers;
  final Color coverColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return PdfDocumentViewBuilder.file(
      filePath,
      builder: (context, document) {
        if (document == null || page < 1 || page > document.pages.length) return const SizedBox.shrink();
        final size = document.pages[page - 1];
        return AspectRatio(
          aspectRatio: size.width / size.height,
          child: LayoutBuilder(
            builder: (context, box) {
              final sx = box.maxWidth / size.width;
              final sy = box.maxHeight / size.height;
              return Stack(
                children: [
                  Positioned.fill(
                    child: PdfPageView(
                      document: document,
                      pageNumber: page,
                      maximumDpi: 144,
                      backgroundColor: backgroundColor,
                      decoration: BoxDecoration(color: backgroundColor),
                    ),
                  ),
                  for (final r in covers)
                    Positioned(
                      left: r.left * sx,
                      top: (size.height - r.top) * sy,
                      width: (r.right - r.left) * sx,
                      height: (r.top - r.bottom) * sy,
                      child: ColoredBox(color: coverColor),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// PDF pages with text selection and clickable highlights.
class MMPdfView extends StatefulWidget {
  const MMPdfView({
    super.key,
    required this.filePath,
    required this.controller,
    this.highlights = const [],
    this.initialPage = 1,
    this.backgroundColor = const Color(0xFFEDEDF0),
    this.emphasisColor = const Color(0xFF007AFF),
    this.pageColorFilter,
    this.onReady,
    this.onPageChanged,
    this.onSelectionCommitted,
    this.onTextUnavailable,
    this.onSelectionChanged,
    this.onHighlightTap,
    this.onViewportChanged,
    this.areaSelecting = false,
    this.onAreaSelected,
    this.inkStrokes = const [],
    this.inkColors = const [],
    this.ink,
    this.onInkDrawn,
    this.onInkErased,
    this.bottomInset = 0,
  });

  final String filePath;
  final MMPdfViewController controller;
  final List<MMPdfHighlight> highlights;
  final int initialPage;
  final Color backgroundColor;
  final Color emphasisColor;
  final ColorFilter? pageColorFilter;

  /// Called once the document is open, with its page count.
  final ValueChanged<int>? onReady;
  final void Function(int page, int pageCount)? onPageChanged;

  /// The mouse was released with text selected.
  final ValueChanged<MMPdfSelection>? onSelectionCommitted;

  /// A mouse drag on a page with no text layer. Image/ink gestures are excluded.
  final void Function(int page, Offset globalPosition)? onTextUnavailable;

  /// Selection appeared (non-null) or was cleared (null).
  final ValueChanged<bool>? onSelectionChanged;

  /// Highlight bounds are in viewport coordinates, matching selection bounds.
  final void Function(String id, Rect viewportRect)? onHighlightTap;
  final VoidCallback? onViewportChanged;

  /// Dragging draws a rectangle instead of selecting text; scrolling and
  /// zooming keep working.
  final bool areaSelecting;
  final ValueChanged<MMPdfArea>? onAreaSelected;

  /// Pen strokes of this document, drawn above highlights. They never take
  /// pointer events: text selection and highlight clicks work through them.
  final List<InkStroke> inkStrokes;

  /// Stroke colors by [InkStroke.colorIndex].
  final List<Color> inkColors;

  /// The pen in hand; drags then draw (or erase) instead of selecting text.
  /// Scrolling and zooming keep working. Null when not drawing.
  final MMPdfInk? ink;

  /// A stroke was finished. It stays on screen until [inkStrokes] changes.
  final ValueChanged<MMPdfInkDraft>? onInkDrawn;

  /// One eraser gesture (a click or a drag) touched these whole strokes.
  /// They stay hidden until [inkStrokes] changes.
  final ValueChanged<Set<String>>? onInkErased;

  /// Height of chrome floating over the bottom of the view, such as a
  /// phone's glass tab bar: the last page scrolls up clear of it.
  final double bottomInset;

  @override
  State<MMPdfView> createState() => _MMPdfViewState();
}

class _MMPdfViewState extends State<MMPdfView> {
  final _controller = PdfViewerController();

  /// Zoom of the document fitted to the view's width, the reading zoom,
  /// which converts [MMPdfView.bottomInset] to document units; 1 until the
  /// viewer is ready.
  double _fitZoom = 1;

  void _updateFitZoom() {
    if (widget.bottomInset <= 0 || !_controller.isReady) return;
    final document = _controller.documentSize.width;
    if (document <= 0) return;
    final zoom = _controller.viewSize.width / document;
    if (zoom <= 0 || (zoom - _fitZoom).abs() < 0.001) return;
    setState(() => _fitZoom = zoom);
  }

  /// Room below the document for [MMPdfView.bottomInset]; null without one
  /// keeps pdfrx's own bounds.
  EdgeInsets? get _boundaryMargin =>
      widget.bottomInset > 0 ? EdgeInsets.only(bottom: widget.bottomInset / _fitZoom) : null;

  /// Created once the viewer is ready: the searcher needs an open document.
  PdfTextSearcher? _searcher;
  late final _previews = MMPdfPreviewCache(render: _renderPreview);
  final _areaRevision = ValueNotifier<int>(0);
  final _previewTokens = <PdfPageRenderCancellationToken>{};
  Map<int, List<MMPdfHighlight>> _highlightsByPage = {};
  final _overlayCache = <int, (Size, List<MMPdfHighlight>, Color, List<Widget>)>{};

  // ---- ink ---------------------------------------------------------------------

  Map<int, List<InkStroke>> _inkByPage = {};
  Set<String> _inkIds = {};

  /// Strokes being erased, per page, so only that page repaints.
  final _inkHidden = <int, ValueNotifier<Set<String>>>{};
  final _inkRevision = ValueNotifier<int>(0);

  /// The stroke under the pen: page and points in page coordinates.
  (int, List<InkPoint>)? _inkLive;
  Offset? _inkLastLocal;

  /// Finished strokes the parent has not stored yet.
  List<(int, InkStroke)> _inkPending = const [];
  final _erasing = <String>{};
  Timer? _inkSettle;

  void _indexInk() {
    final next = <int, List<InkStroke>>{};
    for (final s in widget.inkStrokes) {
      (next[s.page] ??= []).add(s);
    }
    for (final entry in next.entries) {
      final old = _inkByPage[entry.key];
      if (old != null && _sameStrokes(old, entry.value)) next[entry.key] = old;
    }
    _inkByPage = next;
    final ids = {for (final s in widget.inkStrokes) s.id};
    if (ids.length != _inkIds.length || !ids.containsAll(_inkIds)) {
      // The parent stored (or undid) something: what was waiting is now real.
      final stored = ids.difference(_inkIds).length;
      _inkIds = ids;
      _settleInk(keep: ids, stored: stored);
    }
  }

  /// Drops the oldest [stored] strokes waiting for the parent (all of them
  /// when null); hidden strokes stay hidden only while they still exist in
  /// [keep] (null: unhide everything).
  void _settleInk({Set<String>? keep, int? stored}) {
    if (_inkPending.isNotEmpty && stored != 0) {
      _inkPending = stored == null ? const [] : _inkPending.skip(stored).toList();
      _bumpInk();
    }
    if (_inkPending.isEmpty) {
      _inkSettle?.cancel();
      _inkSettle = null;
    }
    for (final hidden in _inkHidden.values) {
      if (hidden.value.isEmpty) continue;
      final still = keep == null ? <String>{} : hidden.value.where(keep.contains).toSet();
      if (still.length != hidden.value.length) hidden.value = still;
    }
  }

  void _bumpInk() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inkRevision.value++;
      });
    } else {
      _inkRevision.value++;
    }
  }

  /// If the parent never confirms (e.g. the save failed), stop pretending.
  void _awaitParent() {
    _inkSettle?.cancel();
    _inkSettle = Timer(const Duration(seconds: 2), () {
      if (mounted) _settleInk();
    });
  }

  ValueNotifier<Set<String>> _hiddenOn(int page) => _inkHidden[page] ??= ValueNotifier(const {});

  List<(int, InkStroke)> _liveStrokes() {
    final live = _inkLive;
    final ink = widget.ink;
    if (live == null || ink == null || ink.tool == MMPdfInkTool.eraser) return _inkPending;
    final stroke = InkStroke(
      id: '',
      documentId: '',
      page: live.$1,
      // The circle is drawn freehand and regularized on release.
      tool: ink.tool == MMPdfInkTool.arrow ? InkTool.arrow : InkTool.pen,
      colorIndex: ink.colorIndex,
      width: ink.width,
      points: ink.tool == MMPdfInkTool.arrow && live.$2.length > 1 ? [live.$2.first, live.$2.last] : live.$2,
    );
    return [..._inkPending, (live.$1, stroke)];
  }

  /// Page-to-viewport mapping, or null if the page is not laid out.
  InkMapping? _viewportMapping(int pageNumber) {
    if (!_ready || pageNumber < 1 || pageNumber > _controller.layout.pageLayouts.length) return null;
    final page = _controller.document.pages[pageNumber - 1];
    final layout = _controller.layout.pageLayouts[pageNumber - 1];
    return (
      point: (p) => _controller.documentToLocal(PdfPoint(p.x, p.y).toOffsetInDocument(page: page, pageRect: layout)),
      scale: layout.height / page.height * _controller.currentZoom,
    );
  }

  /// The page under [local] (viewport coordinates) and the point on it in
  /// page coordinates. [page] pins the page and clamps to its edges.
  (int, InkPoint, double)? _pagePoint(Offset local, {int? page}) {
    if (!_ready) return null;
    final layouts = _controller.layout.pageLayouts;
    var point = _controller.localToDocument(local);
    final index = page != null ? page - 1 : layouts.indexWhere((r) => r.contains(point));
    if (index < 0 || index >= layouts.length) return null;
    final bounds = layouts[index];
    point = Offset(point.dx.clamp(bounds.left, bounds.right), point.dy.clamp(bounds.top, bounds.bottom));
    final pdfPage = _controller.document.pages[index];
    final p = (point - bounds.topLeft).toPdfPoint(page: pdfPage, scaledPageSize: bounds.size);
    // Viewport pixels per page point.
    final scale = bounds.height / pdfPage.height * _controller.currentZoom;
    return (index + 1, InkPoint(p.x, p.y), scale);
  }

  void _inkStart(Offset local) {
    final ink = widget.ink;
    if (ink == null) return;
    if (ink.tool == MMPdfInkTool.eraser) {
      _erasing.clear();
      _eraseAt(local);
      return;
    }
    final hit = _pagePoint(local);
    _inkLive = hit == null ? null : (hit.$1, [hit.$2]);
    _inkLastLocal = local;
    _bumpInk();
  }

  void _inkUpdate(Offset local) {
    final ink = widget.ink;
    if (ink == null) return;
    if (ink.tool == MMPdfInkTool.eraser) {
      _eraseAt(local);
      return;
    }
    final live = _inkLive;
    if (live == null) return;
    // Sub-pixel jitter adds points, not shape.
    if (_inkLastLocal != null && (local - _inkLastLocal!).distance < 1) return;
    final hit = _pagePoint(local, page: live.$1);
    if (hit == null) return;
    _inkLastLocal = local;
    live.$2.add(hit.$2);
    _bumpInk();
  }

  void _inkEnd() {
    final ink = widget.ink;
    if (ink == null) return;
    if (ink.tool == MMPdfInkTool.eraser) {
      if (_erasing.isEmpty) return;
      final ids = Set.of(_erasing);
      _erasing.clear();
      _awaitParent();
      widget.onInkErased?.call(ids);
      return;
    }
    final live = _inkLive;
    _inkLive = null;
    _inkLastLocal = null;
    _bumpInk();
    if (live == null) return;
    final draft = _draft(ink, live.$1, live.$2);
    if (draft == null) return;
    _inkPending = [..._inkPending, (draft.page, draft.toStroke(id: '', documentId: ''))];
    _awaitParent();
    widget.onInkDrawn?.call(draft);
  }

  void _inkCancel() {
    _erasing.clear();
    if (_inkLive == null) return;
    _inkLive = null;
    _inkLastLocal = null;
    _bumpInk();
  }

  MMPdfInkDraft? _draft(MMPdfInk ink, int page, List<InkPoint> points) {
    if (points.length < 2) return null;
    final xs = points.map((p) => p.x), ys = points.map((p) => p.y);
    final extent = math.max(xs.reduce(math.max) - xs.reduce(math.min), ys.reduce(math.max) - ys.reduce(math.min));
    // A click or a twitch is not a stroke.
    if (extent < 2) return null;
    MMPdfInkDraft pen() => MMPdfInkDraft(
      page: page,
      tool: InkTool.pen,
      colorIndex: ink.colorIndex,
      width: ink.width,
      points: simplifyInk(points),
    );
    switch (ink.tool) {
      case MMPdfInkTool.freehand:
        return pen();
      case MMPdfInkTool.ellipse:
        // ⇧ keeps the hand-drawn shape.
        if (HardwareKeyboard.instance.isShiftPressed) return pen();
        return MMPdfInkDraft(
          page: page,
          tool: InkTool.ellipse,
          colorIndex: ink.colorIndex,
          width: ink.width,
          ellipse: inkEllipseBounds(points, padding: ink.width / 2 + 1),
        );
      case MMPdfInkTool.arrow:
        return MMPdfInkDraft(
          page: page,
          tool: InkTool.arrow,
          colorIndex: ink.colorIndex,
          width: ink.width,
          points: [points.first, points.last],
        );
      case MMPdfInkTool.eraser:
        return null;
    }
  }

  void _eraseAt(Offset local) {
    final hit = _pagePoint(local);
    if (hit == null) return;
    final (page, point, scale) = hit;
    final strokes = _inkByPage[page];
    if (strokes == null) return;
    final hidden = _hiddenOn(page);
    // About 6 screen pixels around the pointer, whatever the zoom.
    final radius = 6 / scale;
    final touched = {
      for (final s in strokes)
        if (!hidden.value.contains(s.id) && inkStrokeHit(s, point, radius)) s.id,
    };
    if (touched.isEmpty) return;
    _erasing.addAll(touched);
    hidden.value = {...hidden.value, ...touched};
  }

  Widget? _inkOverlay(Rect pageRect, PdfPage page) {
    final strokes = _inkByPage[page.pageNumber];
    if (strokes == null || widget.inkColors.isEmpty) return null;
    return Positioned.fill(
      key: const ValueKey('ink'),
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: InkPagePainter(
              strokes: strokes,
              colors: widget.inkColors,
              hidden: _hiddenOn(page.pageNumber),
              map: (size) => (
                point: (p) => PdfPoint(p.x, p.y).toOffset(page: page, scaledPageSize: size),
                scale: size.height / page.height,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _indexHighlights() {
    final next = <int, List<MMPdfHighlight>>{};
    for (final h in widget.highlights) {
      (next[h.page] ??= []).add(h);
    }
    for (final entry in next.entries) {
      final old = _highlightsByPage[entry.key];
      if (old != null && _sameHighlights(old, entry.value)) next[entry.key] = old;
    }
    _highlightsByPage = next;
    _overlayCache.removeWhere((page, value) => !identical(next[page], value.$2));
  }

  Future<Uint8List?> _renderPreview(int number, int width) async {
    if (!_ready || number > _controller.document.pages.length) return null;
    final page = _controller.document.pages[number - 1];
    final token = page.createCancellationToken();
    _previewTokens.add(token);
    PdfImage? image;
    ui.Image? bitmap;
    try {
      image = await page.render(
        cancellationToken: token,
        width: width,
        height: math.max(1, (page.height * width / page.width).round()),
        fullWidth: width.toDouble(),
        fullHeight: page.height * width / page.width,
        backgroundColor: 0xffffffff,
      );
      if (image == null || token.isCanceled) return null;
      bitmap = await image.createImage();
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } finally {
      bitmap?.dispose();
      image?.dispose();
      _previewTokens.remove(token);
    }
  }

  void _invalidatePreviews() {
    _previews.clear();
    for (final token in _previewTokens) {
      token.cancel();
    }
  }

  PdfTextSelection? _selection;
  List<AnnotationPage>? _cleanSelection;
  bool _ready = false;
  int _selectionEpoch = 0;
  int _pageCount = 0;
  (int, List<PageRect>)? _pendingReveal;

  /// Area drag, in document coordinates: (page index, start, current end).
  (int, Offset, Offset)? _area;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _indexHighlights();
    _indexInk();
    _controller.addListener(_viewportChanged);
  }

  @override
  void didUpdateWidget(MMPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _indexHighlights();
    if (oldWidget.filePath != widget.filePath) {
      _inkLive = null;
      _erasing.clear();
      _settleInk();
    }
    _indexInk();
    if (widget.ink == null || widget.ink!.tool != oldWidget.ink?.tool) _inkCancel();
    if (oldWidget.filePath != widget.filePath) {
      _ready = false;
      _invalidatePreviews();
      _overlayCache.clear();
      _selection = null;
      _area = null;
      _pendingReveal = null;
      _selectionEpoch++;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
    if (!widget.areaSelecting && _area != null) _changeArea(null);
  }

  void _paintMatches(ui.Canvas canvas, Rect pageRect, PdfPage page) =>
      _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);

  void _beginPagePaint(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    canvas.save();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Only the supersampled preview is snapped. Above the allocation limit,
    // pdfrx's partial tiles retain their own coordinate system.
    final plan = pdfPreviewPlan(Size(page.width, page.height), _controller.currentZoom, dpr);
    if (plan.deviceSize == null) return;
    final origin = _controller.documentToGlobal(pageRect.topLeft);
    final end = _controller.documentToGlobal(pageRect.bottomRight);
    if (origin != null && end != null) {
      alignPdfPage(canvas, pageRect, Rect.fromPoints(origin, end), dpr, deviceSize: plan.deviceSize);
    }
  }

  void _endPagePaint(ui.Canvas canvas, Rect pageRect, PdfPage page) => canvas.restore();

  void _searchChanged() => widget.controller._syncSearch();

  void _viewportChanged() {
    _selectionEpoch++;
    // The area rectangle is anchored to the document while it scrolls; the
    // viewer may adjust its transform during layout, so repaint after it.
    if (_inkLive != null || _inkPending.isNotEmpty) _bumpInk();
    if (_area != null) {
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) _areaRevision.value++;
        });
      } else {
        _areaRevision.value++;
      }
    }
    widget.onViewportChanged?.call();
  }

  @override
  void dispose() {
    _controller.removeListener(_viewportChanged);
    _searcher?.removeListener(_searchChanged);
    _searcher?.dispose();
    widget.controller._detach(this);
    _invalidatePreviews();
    _areaRevision.dispose();
    _inkSettle?.cancel();
    _inkRevision.dispose();
    for (final hidden in _inkHidden.values) {
      hidden.dispose();
    }
    super.dispose();
  }

  Future<void> _reveal(int page, List<PageRect> rects) async {
    if (!_ready) {
      _pendingReveal = (page, rects);
      return;
    }
    if (page < 1 || page > _controller.pageCount) return;
    if (rects.isEmpty) {
      await _controller.goToPage(pageNumber: page, anchor: PdfPageAnchor.top);
      return;
    }
    final l = rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
    final r = rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
    final t = rects.map((r) => r.top).reduce((a, b) => a > b ? a : b);
    final b = rects.map((r) => r.bottom).reduce((a, b) => a < b ? a : b);
    final layout = _controller.layout.pageLayouts[page - 1];
    final target = PdfRect(
      l,
      t,
      r,
      b,
    ).toRect(page: _controller.pages[page - 1], scaledPageSize: layout.size).shift(layout.topLeft);
    // Center in document coordinates without fitting the excerpt to the viewport.
    // An excerpt wider than the viewport would lose both ends: start at its left edge.
    final zoom = _controller.currentZoom;
    final wide = target.width * zoom > _controller.viewSize.width;
    final center = wide ? Offset(target.left + _controller.viewSize.width / 2 / zoom, target.center.dy) : target.center;
    await _controller.goTo(_controller.calcMatrixFor(center, zoom: zoom));
  }

  Future<void> _loadOutline(PdfDocument document) async {
    List<PdfOutlineNode> nodes;
    try {
      nodes = await document.loadOutline();
    } catch (_) {
      return;
    }
    if (!mounted || !_ready) return;
    MMPdfOutlineItem convert(PdfOutlineNode node) => MMPdfOutlineItem(
      title: node.title.trim(),
      page: node.dest?.pageNumber ?? 0,
      children: [for (final child in node.children) convert(child)],
    );
    widget.controller._reportReady(_pageCount, [for (final node in nodes) convert(node)]);
  }

  Future<String?> _pageText(int pageNumber) async {
    if (!_ready || pageNumber < 1 || pageNumber > _controller.document.pages.length) return null;
    try {
      final text = (await _controller.document.pages[pageNumber - 1].loadStructuredText()).fullText;
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Rendered pixels of [rect] on [pageNumber], encoded as PNG.
  Future<Uint8List?> _capture(int pageNumber, PageRect rect, double scale, int maxPixels) async {
    if (!_ready || pageNumber < 1 || pageNumber > _controller.document.pages.length) return null;
    final page = _controller.document.pages[pageNumber - 1];
    final area = PdfRect(rect.left, rect.top, rect.right, rect.bottom).toRect(page: page);
    if (area.isEmpty) return null;
    final s = math.min(scale, maxPixels / math.max(area.width, area.height));
    final target = Rect.fromLTRB(area.left * s, area.top * s, area.right * s, area.bottom * s);
    final pdfImage = await page.render(
      x: target.left.round(),
      y: target.top.round(),
      width: math.max(1, target.width.round()),
      height: math.max(1, target.height.round()),
      fullWidth: page.width * s,
      fullHeight: page.height * s,
      backgroundColor: 0xffffffff,
    );
    if (pdfImage == null) return null;
    ui.Image? image;
    try {
      image = await pdfImage.createImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } finally {
      image?.dispose();
      pdfImage.dispose();
    }
  }

  void _changeArea((int, Offset, Offset)? area) {
    _area = area;
    _areaRevision.value++;
  }

  void _areaStart(DragStartDetails d) {
    if (!_ready) return;
    final point = _controller.localToDocument(d.localPosition);
    final index = _controller.layout.pageLayouts.indexWhere((r) => r.contains(point));
    _changeArea(index < 0 ? null : (index, point, point));
  }

  void _areaUpdate(DragUpdateDetails d) {
    final area = _area;
    if (area == null) return;
    final bounds = _controller.layout.pageLayouts[area.$1];
    final point = _controller.localToDocument(d.localPosition);
    final clamped = Offset(point.dx.clamp(bounds.left, bounds.right), point.dy.clamp(bounds.top, bounds.bottom));
    _changeArea((area.$1, area.$2, clamped));
  }

  void _areaEnd() {
    final area = _area;
    if (area == null) return;
    _changeArea(null);
    final viewport = _areaViewportRect(area);
    // A click or a sliver is not an area.
    if (viewport.width < 6 || viewport.height < 6) return;
    final pageRect = _controller.layout.pageLayouts[area.$1];
    final page = _controller.document.pages[area.$1];
    final r = Rect.fromPoints(
      area.$2,
      area.$3,
    ).shift(-pageRect.topLeft).toPdfRect(page: page, scaledPageSize: pageRect.size);
    widget.onAreaSelected?.call(
      MMPdfArea(
        page: page.pageNumber,
        rect: PageRect(
          math.min(r.left, r.right),
          math.max(r.top, r.bottom),
          math.max(r.left, r.right),
          math.min(r.top, r.bottom),
        ),
        viewportRect: viewport,
      ),
    );
  }

  Rect _areaViewportRect((int, Offset, Offset) area) =>
      Rect.fromPoints(_controller.documentToLocal(area.$2), _controller.documentToLocal(area.$3));

  Future<void> _clearSelection() async {
    _selectionEpoch++;
    if (_cleanSelection != null) setState(() => _cleanSelection = null);
    if (_controller.isReady) await _controller.textSelectionDelegate.clearTextSelection();
  }

  Future<void> _commitSelection() async {
    if ((widget.areaSelecting || widget.ink != null) && _textPointerKind != PointerDeviceKind.touch) return;
    final epoch = ++_selectionEpoch;
    // pdfrx settles the selection a frame after the pointer is released.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || epoch != _selectionEpoch) return;
    final selection = _controller.isReady ? _controller.textSelectionDelegate : _selection;
    if (selection == null || !selection.hasSelectedText) return;
    final ranges = await selection.getSelectedTextRanges();
    if (!mounted || epoch != _selectionEpoch || ranges.isEmpty) return;
    final selectedPages = ranges.map((r) => r.pageNumber).toSet();
    // Bound IO to selected pages and immediate neighbours; never scan a book.
    final evidencePages = <int>{
      for (final n in selectedPages)
        for (final neighbour in [n - 1, n, n + 1])
          if (neighbour >= 1 && neighbour <= _controller.document.pages.length) neighbour,
    };
    final evidence = <ExcerptPageText>[];
    for (final n in evidencePages) {
      final page = _controller.document.pages[n - 1];
      // Reuse selected structured text so indices are exactly those of ranges.
      PdfPageText structured;
      try {
        structured = selectedPages.contains(n)
            ? ranges.firstWhere((r) => r.pageNumber == n).pageText
            : await page.loadStructuredText();
      } catch (_) {
        // A neighbour failing to load must not prevent an excerpt.
        continue;
      }
      if (!mounted || epoch != _selectionEpoch) return;
      evidence.add(
        ExcerptPageText(
          page: n,
          height: page.height,
          text: structured.fullText,
          rects: [for (final r in structured.charRects) PageRect(r.left, r.top, r.right, r.bottom)],
        ),
      );
    }
    final excerpt = buildExcerptText(evidence, [for (final r in ranges) ExcerptTextSpan(r.pageNumber, r.start, r.end)]);
    setState(() => _cleanSelection = excerpt.pages);
    // pdfrx caches its canvas painter across inherited Theme changes. Repaint
    // after the transparent native selection color has reached the viewer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && epoch == _selectionEpoch && _controller.isReady) _controller.invalidate();
    });
    final pages = excerpt.pages;
    final text = excerpt.text;
    Rect? bounds;
    for (final page in pages) {
      for (final r in page.rects) {
        final rect = _controller.calcRectForRectInsidePage(
          pageNumber: page.page,
          rect: PdfRect(r.left, r.top, r.right, r.bottom),
        );
        bounds = bounds?.expandToInclude(rect) ?? rect;
      }
    }
    if (text.trim().isEmpty || bounds == null) {
      // A margin-only selection must also dismiss any previous toolbar.
      await _clearSelection();
      return;
    }
    final viewportRect = Rect.fromPoints(
      _controller.documentToLocal(bounds.topLeft),
      _controller.documentToLocal(bounds.bottomRight),
    );
    // A selection may start above the viewport after dragging across pages.
    final visible = viewportRect.intersect(Offset.zero & context.size!);
    widget.onSelectionCommitted?.call(
      MMPdfSelection(
        pages: List.unmodifiable(pages),
        text: text,
        viewportRect: visible.isEmpty ? viewportRect : visible,
      ),
    );
  }

  List<Widget> _pageOverlays(BuildContext context, Rect pageRect, PdfPage page) {
    final highlights = _highlightOverlays(context, pageRect, page);
    final ink = _inkOverlay(pageRect, page);
    final selected = _cleanSelection?.where((p) => p.page == page.pageNumber);
    if (selected == null || selected.isEmpty) return ink == null ? highlights : [...highlights, ink];
    // Transient selection is kept outside the persistent highlight LRU.
    return [
      for (final selection in selected)
        for (final r in selection.rects)
          Positioned.fromRect(
            rect: PdfRect(r.left, r.top, r.right, r.bottom).toRect(page: page, scaledPageSize: pageRect.size),
            child: IgnorePointer(child: ColoredBox(color: widget.emphasisColor.withValues(alpha: 0.25))),
          ),
      ...highlights,
      ?ink,
    ];
  }

  List<Widget> _highlightOverlays(BuildContext context, Rect pageRect, PdfPage page) {
    final scaled = pageRect.size;
    final highlights = _highlightsByPage[page.pageNumber];
    if (highlights == null) return const [];
    final cached = _overlayCache[page.pageNumber];
    if (cached != null &&
        (cached.$1.width - scaled.width).abs() < .000001 &&
        (cached.$1.height - scaled.height).abs() < .000001 &&
        identical(cached.$2, highlights) &&
        cached.$3 == widget.emphasisColor) {
      _overlayCache.remove(page.pageNumber);
      _overlayCache[page.pageNumber] = cached;
      return cached.$4;
    }
    bool tap(MMPdfHighlight h) {
      // With the pen out, a click on a highlight is drawing.
      if (widget.ink != null) return false;
      // Cancel a pending text-selection commit from this click.
      _selectionEpoch++;
      final bounds = h.rects
          .map(
            (r) => _controller.calcRectForRectInsidePage(
              pageNumber: h.page,
              rect: PdfRect(r.left, r.top, r.right, r.bottom),
            ),
          )
          .reduce((a, b) => a.expandToInclude(b));
      widget.onHighlightTap?.call(
        h.id,
        Rect.fromPoints(_controller.documentToLocal(bounds.topLeft), _controller.documentToLocal(bounds.bottomRight)),
      );
      return true;
    }

    final overlays = <Widget>[
      for (final h in highlights)
        for (final r in h.rects)
          Builder(
            builder: (context) {
              final rect = PdfRect(r.left, r.top, r.right, r.bottom).toRect(page: page, scaledPageSize: scaled);
              return Positioned.fromRect(
                rect: rect.inflate(1),
                child: PdfOverlayInteractionRegion(
                  onTap: (_) => tap(h),
                  child: IgnorePointer(
                    child: h.dashed && !h.emphasized
                        ? CustomPaint(
                            painter: _DashedUnderlinePainter(h.underline ?? h.color),
                            child: ColoredBox(color: h.color),
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: h.framed ? h.color.withValues(alpha: h.color.a * 0.25) : h.color,
                              borderRadius: BorderRadius.circular(2),
                              border: h.emphasized
                                  ? Border.all(color: widget.emphasisColor, width: 2)
                                  : h.framed
                                  ? Border.all(color: h.underline ?? h.color, width: 2)
                                  : (h.underline == null
                                        ? null
                                        : Border(bottom: BorderSide(color: h.underline!, width: 2))),
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
      for (final h in highlights)
        if (h.marker != null && h.rects.isNotEmpty)
          Builder(
            builder: (context) {
              final first = h.rects.first;
              final rect = PdfRect(
                first.left,
                first.top,
                first.right,
                first.bottom,
              ).toRect(page: page, scaledPageSize: scaled);
              final size = (scaled.width * 0.03).clamp(14.0, 22.0);
              return Positioned(
                key: ValueKey('pdf-marker-${h.id}'),
                left: scaled.width - size * 1.6,
                top: rect.center.dy - size / 2,
                width: size,
                height: size,
                child: PdfOverlayInteractionRegion(
                  onTap: (_) => tap(h),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: h.marker, shape: BoxShape.circle),
                      child: Icon(Icons.sticky_note_2_outlined, size: size * 0.62, color: Colors.white),
                    ),
                  ),
                ),
              );
            },
          ),
    ];
    if (_overlayCache.length >= 16) _overlayCache.remove(_overlayCache.keys.first);
    _overlayCache[page.pageNumber] = (scaled, highlights, widget.emphasisColor, overlays);
    return overlays;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: Theme.of(context).textSelectionTheme.copyWith(
                selectionColor: _cleanSelection == null
                    ? Theme.of(context).textSelectionTheme.selectionColor
                    : Colors.transparent,
              ),
            ),
            child: _viewer(),
          ),
        ),
        if (widget.areaSelecting)
          Positioned.fill(
            // Translucent: wheel and trackpad scrolling still reach the
            // viewer, while this recognizer wins pointer drags first.
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              opaque: false,
              hitTestBehavior: HitTestBehavior.translucent,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                dragStartBehavior: DragStartBehavior.down,
                supportedDevices: const {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                },
                onPanStart: _areaStart,
                onPanUpdate: _areaUpdate,
                onPanEnd: (_) => _areaEnd(),
                onPanCancel: () => _changeArea(null),
              ),
            ),
          ),
        if (widget.ink case final ink?)
          Positioned.fill(
            // Translucent like the area tool: scrolling still reaches the viewer.
            child: MouseRegion(
              cursor: ink.tool == MMPdfInkTool.eraser ? SystemMouseCursors.cell : SystemMouseCursors.precise,
              opaque: false,
              hitTestBehavior: HitTestBehavior.translucent,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                dragStartBehavior: DragStartBehavior.down,
                supportedDevices: const {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                },
                // The eraser bites on pointer down, so a click erases too;
                // a click then ends as a cancelled drag.
                onPanDown: ink.tool == MMPdfInkTool.eraser ? (d) => _inkStart(d.localPosition) : null,
                onPanStart: ink.tool == MMPdfInkTool.eraser ? null : (d) => _inkStart(d.localPosition),
                onPanUpdate: (d) => _inkUpdate(d.localPosition),
                onPanEnd: (_) => _inkEnd(),
                onPanCancel: ink.tool == MMPdfInkTool.eraser ? _inkEnd : _inkCancel,
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: InkLivePainter(
                  strokes: _liveStrokes,
                  colors: widget.inkColors,
                  map: _viewportMapping,
                  repaint: _inkRevision,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: ValueListenableBuilder<int>(
            valueListenable: _areaRevision,
            builder: (context, value, child) {
              final area = _area;
              return IgnorePointer(
                child: Stack(
                  children: [
                    if (area != null)
                      Positioned.fromRect(
                        rect: _areaViewportRect(area),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.emphasisColor.withValues(alpha: 0.12),
                            border: Border.all(color: widget.emphasisColor, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Offset? _textDragStart;
  PointerDeviceKind? _textPointerKind;

  Future<void> _textPointerUp(PointerUpEvent event) async {
    final start = _textDragStart;
    _textDragStart = null;
    unawaited(_commitSelection());
    if (start == null ||
        widget.onTextUnavailable == null ||
        !_ready ||
        widget.areaSelecting ||
        widget.ink != null ||
        (event.localPosition - start).distance < kTouchSlop) {
      return;
    }
    final epoch = _selectionEpoch;
    final point = _controller.localToDocument(start);
    final index = _controller.layout.pageLayouts.indexWhere((rect) => rect.contains(point));
    if (index < 0) return;
    try {
      final text = await _controller.document.pages[index].loadStructuredText();
      if (mounted && epoch == _selectionEpoch && text.fullText.trim().isEmpty) {
        widget.onTextUnavailable?.call(index + 1, event.position);
      }
    } catch (_) {
      // Failure to read a text layer must not interrupt pointer handling.
    }
  }

  Widget _viewer() {
    return Listener(
      onPointerDown: (event) {
        _textDragStart = event.localPosition;
        _textPointerKind = event.kind;
        _selectionEpoch++;
        if (_cleanSelection != null) setState(() => _cleanSelection = null);
      },
      onPointerUp: _textPointerUp,
      onPointerCancel: (_) => _textDragStart = null,
      child: PdfViewer(
        kIsWeb
            ? PdfDocumentRefByLoader((_) => openDocument(widget.filePath), key: PdfDocumentRefKey(widget.filePath))
            : PdfDocumentRefFile(widget.filePath),
        controller: _controller,
        initialPageNumber: widget.initialPage,
        params: PdfViewerParams(
          backgroundColor: widget.backgroundColor,
          pageImageColorFilter: widget.pageColorFilter,
          onViewSizeChanged: (size, previous, controller) {
            Future.microtask(() {
              if (mounted) _updateFitZoom();
            });
            if (previous == null || size.width == previous.width) return;
            final center = controller.value.calcPosition(previous);
            // pdfrx calls this after layout in a microtask. A post-frame
            // callback here can wait indefinitely for another scheduled frame.
            Future.microtask(() {
              if (!mounted || !_ready || controller.viewSize != size) return;
              final fit = controller.calcMatrixFitWidthForPage(pageNumber: controller.pageNumber ?? 1);
              controller.goTo(
                controller.calcMatrixFor(
                  Offset(controller.documentSize.width / 2, center.dy),
                  zoom: fit?.getMaxScaleOnAxis() ?? controller.currentZoom,
                ),
                duration: Duration.zero,
              );
            });
          },
          margin: 16,
          boundaryMargin: _boundaryMargin,
          // Remove pdfrx's default 80% reduction in mouse-wheel movement.
          scrollByMouseWheel: 1,
          // Match PDFium's integer bitmap to the aligned device rectangle.
          getPageRenderingScale: (context, page, controller, estimatedScale) => pdfPreviewPlan(
            Size(page.width, page.height),
            controller.currentZoom,
            MediaQuery.devicePixelRatioOf(context),
          ).scale,
          // Retain pdfrx's adjacent-page prefetch and 100 MiB image-cache budget.
          pageDropShadow: const BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 2)),
          pageOverlaysBuilder: _pageOverlays,
          pageBackgroundPaintCallbacks: [_beginPagePaint],
          pagePaintCallbacks: [_paintMatches, _endPagePaint],
          textSelectionParams: PdfTextSelectionParams(
            // Tool overlays claim mouse/Pencil drags. Keep pdfrx's touch
            // long-press selection and handles available underneath them.
            enabled: true,
            showContextMenuAutomatically: false,
            onTextSelectionChange: (selection) {
              _selection = selection;
              if (!selection.hasSelectedText && _cleanSelection != null) setState(() => _cleanSelection = null);
              widget.onSelectionChanged?.call(selection.hasSelectedText);
            },
          ),
          onViewerReady: (document, controller) {
            _ready = true;
            Future.microtask(() {
              if (mounted) _updateFitZoom();
            });
            _searcher = PdfTextSearcher(_controller)..addListener(_searchChanged);
            _pageCount = document.pages.length;
            widget.controller._reportReady(_pageCount, const []);
            _loadOutline(document);
            widget.onReady?.call(_pageCount);
            final pending = _pendingReveal;
            _pendingReveal = null;
            if (pending != null) _reveal(pending.$1, pending.$2);
          },
          onPageChanged: (page) {
            if (page == null) return;
            widget.controller._reportPage(page);
            widget.onPageChanged?.call(page, _pageCount);
          },
        ),
      ),
    );
  }
}

// Preserve page-list identity when a parent rebuilds with equivalent objects.
bool _sameHighlights(List<MMPdfHighlight> a, List<MMPdfHighlight> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.id != y.id ||
        x.color != y.color ||
        x.underline != y.underline ||
        x.emphasized != y.emphasized ||
        x.framed != y.framed ||
        x.dashed != y.dashed ||
        x.marker != y.marker ||
        x.rects.length != y.rects.length) {
      return false;
    }
    for (var j = 0; j < x.rects.length; j++) {
      final r = x.rects[j], s = y.rects[j];
      if (r.left != s.left || r.top != s.top || r.right != s.right || r.bottom != s.bottom) return false;
    }
  }
  return true;
}

/// A 1.5pt dashed line along the bottom edge.
class _DashedUnderlinePainter extends CustomPainter {
  const _DashedUnderlinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final y = size.height - 0.75;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedUnderlinePainter old) => old.color != color;
}

bool _sameStrokes(List<InkStroke> a, List<InkStroke> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    // Strokes are immutable and never edited in place: the id is the content.
    if (a[i].id != b[i].id) return false;
  }
  return true;
}
