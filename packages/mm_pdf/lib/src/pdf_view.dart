import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mm_core/mm_core.dart' show AnnotationPage, PageRect;
import 'package:pdfrx/pdfrx.dart';

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

/// Commands from outside (e.g. "reveal this excerpt") into an [MMPdfView].
class MMPdfViewController {
  _MMPdfViewState? _state;

  /// Scrolls so that [rects] on [page] are centered.
  Future<void> reveal(int page, List<PageRect> rects) async => _state?._reveal(page, rects);

  Future<void> goToPage(int page) async => _state?._controller.goToPage(pageNumber: page);

  Future<void> clearSelection() async => _state?._clearSelection();

  Future<void> zoomIn() async => _state?._controller.zoomUp();

  Future<void> zoomOut() async => _state?._controller.zoomDown();

  /// Renders [rect] of [page] as PNG bytes at [scale] pixels per point
  /// (longest side capped at [maxPixels]); null if the view is not ready or
  /// the page cannot be rendered.
  Future<Uint8List?> captureArea(int page, PageRect rect, {double scale = 3, int maxPixels = 3000}) async =>
      _state?._capture(page, rect, scale, maxPixels);

  bool get isReady => _state?._ready ?? false;
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
    this.onReady,
    this.onPageChanged,
    this.onSelectionCommitted,
    this.onSelectionChanged,
    this.onHighlightTap,
    this.onViewportChanged,
    this.areaSelecting = false,
    this.onAreaSelected,
  });

  final String filePath;
  final MMPdfViewController controller;
  final List<MMPdfHighlight> highlights;
  final int initialPage;
  final Color backgroundColor;
  final Color emphasisColor;

  /// Called once the document is open, with its page count.
  final ValueChanged<int>? onReady;
  final void Function(int page, int pageCount)? onPageChanged;

  /// The mouse was released with text selected.
  final ValueChanged<MMPdfSelection>? onSelectionCommitted;

  /// Selection appeared (non-null) or was cleared (null).
  final ValueChanged<bool>? onSelectionChanged;

  /// Highlight bounds are in viewport coordinates, matching selection bounds.
  final void Function(String id, Rect viewportRect)? onHighlightTap;
  final VoidCallback? onViewportChanged;

  /// Dragging draws a rectangle instead of selecting text; scrolling and
  /// zooming keep working.
  final bool areaSelecting;
  final ValueChanged<MMPdfArea>? onAreaSelected;

  @override
  State<MMPdfView> createState() => _MMPdfViewState();
}

class _MMPdfViewState extends State<MMPdfView> {
  final _controller = PdfViewerController();
  PdfTextSelection? _selection;
  bool _ready = false;
  int _selectionEpoch = 0;
  int _pageCount = 0;
  (int, List<PageRect>)? _pendingReveal;

  /// Area drag, in document coordinates: (page index, start, current end).
  (int, Offset, Offset)? _area;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _controller.addListener(_viewportChanged);
  }

  @override
  void didUpdateWidget(MMPdfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._state = null;
      widget.controller._state = this;
    }
    if (!widget.areaSelecting && _area != null) _area = null;
  }

  void _viewportChanged() {
    _selectionEpoch++;
    // The area rectangle is anchored to the document while it scrolls; the
    // viewer may adjust its transform during layout, so repaint after it.
    if (_area != null) {
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else {
        setState(() {});
      }
    }
    widget.onViewportChanged?.call();
  }

  @override
  void dispose() {
    _controller.removeListener(_viewportChanged);
    if (widget.controller._state == this) widget.controller._state = null;
    super.dispose();
  }

  Future<void> _reveal(int page, List<PageRect> rects) async {
    if (!_ready) {
      _pendingReveal = (page, rects);
      return;
    }
    if (rects.isEmpty) {
      await _controller.goToPage(pageNumber: page, anchor: PdfPageAnchor.top);
      return;
    }
    final l = rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
    final r = rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
    final t = rects.map((r) => r.top).reduce((a, b) => a > b ? a : b);
    final b = rects.map((r) => r.bottom).reduce((a, b) => a < b ? a : b);
    await _controller.goToRectInsidePage(pageNumber: page, rect: PdfRect(l, t, r, b), anchor: PdfPageAnchor.center);
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

  void _areaStart(DragStartDetails d) {
    if (!_ready) return;
    final point = _controller.localToDocument(d.localPosition);
    final index = _controller.layout.pageLayouts.indexWhere((r) => r.contains(point));
    setState(() => _area = index < 0 ? null : (index, point, point));
  }

  void _areaUpdate(DragUpdateDetails d) {
    final area = _area;
    if (area == null) return;
    final bounds = _controller.layout.pageLayouts[area.$1];
    final point = _controller.localToDocument(d.localPosition);
    final clamped = Offset(point.dx.clamp(bounds.left, bounds.right), point.dy.clamp(bounds.top, bounds.bottom));
    setState(() => _area = (area.$1, area.$2, clamped));
  }

  void _areaEnd() {
    final area = _area;
    if (area == null) return;
    setState(() => _area = null);
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
    if (_controller.isReady) await _controller.textSelectionDelegate.clearTextSelection();
  }

  Future<void> _commitSelection() async {
    if (widget.areaSelecting) return;
    final epoch = ++_selectionEpoch;
    // pdfrx settles the selection a frame after the pointer is released.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || epoch != _selectionEpoch) return;
    final selection = _controller.isReady ? _controller.textSelectionDelegate : _selection;
    if (selection == null || !selection.hasSelectedText) return;
    final ranges = await selection.getSelectedTextRanges();
    if (!mounted || epoch != _selectionEpoch || ranges.isEmpty) return;
    final pageNumbers = ranges.map((r) => r.pageNumber).toSet().toList()..sort();
    final pages = <AnnotationPage>[];
    final texts = <String>[];
    Rect? bounds;
    for (final page in pageNumbers) {
      final onPage = ranges.where((r) => r.pageNumber == page);
      final rects = <PageRect>[
        for (final range in onPage)
          for (final f in range.enumerateFragmentBoundingRects())
            PageRect(f.bounds.left, f.bounds.top, f.bounds.right, f.bounds.bottom),
      ];
      if (rects.isEmpty) continue;
      pages.add(AnnotationPage(page: page, rects: List.unmodifiable(rects)));
      texts.add(onPage.map((r) => r.text).join());
      for (final r in rects) {
        final rect = _controller.calcRectForRectInsidePage(
          pageNumber: page,
          rect: PdfRect(r.left, r.top, r.right, r.bottom),
        );
        bounds = bounds?.expandToInclude(rect) ?? rect;
      }
    }
    final text = texts.join('\n');
    if (text.trim().isEmpty || bounds == null) return;
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
    final scaled = pageRect.size;
    return [
      for (final h in widget.highlights)
        if (h.page == page.pageNumber)
          for (final r in h.rects)
            Builder(
              builder: (context) {
                final rect = PdfRect(r.left, r.top, r.right, r.bottom).toRect(page: page, scaledPageSize: scaled);
                return Positioned.fromRect(
                  rect: rect.inflate(1),
                  child: PdfOverlayInteractionRegion(
                    onTap: (_) {
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
                        Rect.fromPoints(
                          _controller.documentToLocal(bounds.topLeft),
                          _controller.documentToLocal(bounds.bottomRight),
                        ),
                      );
                      return true;
                    },
                    child: IgnorePointer(
                      child: DecoratedBox(
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    final area = _area;
    return Stack(
      children: [
        Positioned.fill(child: _viewer()),
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
                  PointerDeviceKind.touch,
                },
                onPanStart: _areaStart,
                onPanUpdate: _areaUpdate,
                onPanEnd: (_) => _areaEnd(),
                onPanCancel: () => setState(() => _area = null),
              ),
            ),
          ),
        if (area != null)
          Positioned.fromRect(
            rect: _areaViewportRect(area),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.emphasisColor.withValues(alpha: 0.12),
                  border: Border.all(color: widget.emphasisColor, width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _viewer() {
    return Listener(
      onPointerUp: (_) => _commitSelection(),
      child: PdfViewer.file(
        widget.filePath,
        controller: _controller,
        initialPageNumber: widget.initialPage,
        params: PdfViewerParams(
          backgroundColor: widget.backgroundColor,
          margin: 16,
          pageDropShadow: const BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 2)),
          pageOverlaysBuilder: _pageOverlays,
          textSelectionParams: PdfTextSelectionParams(
            enabled: !widget.areaSelecting,
            showContextMenuAutomatically: false,
            onTextSelectionChange: (selection) {
              _selection = selection;
              widget.onSelectionChanged?.call(selection.hasSelectedText);
            },
          ),
          onViewerReady: (document, controller) {
            _ready = true;
            _pageCount = document.pages.length;
            widget.onReady?.call(_pageCount);
            final pending = _pendingReveal;
            _pendingReveal = null;
            if (pending != null) _reveal(pending.$1, pending.$2);
          },
          onPageChanged: (page) {
            if (page != null) widget.onPageChanged?.call(page, _pageCount);
          },
        ),
      ),
    );
  }
}
