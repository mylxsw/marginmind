import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart' show PageRect;
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
}

/// Text the user selected, on one page.
@immutable
class MMPdfSelection {
  const MMPdfSelection({required this.page, required this.rects, required this.text, this.viewportRect});

  final int page;
  final List<PageRect> rects;
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
  }

  void _viewportChanged() {
    _selectionEpoch++;
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

  Future<void> _clearSelection() async {
    _selectionEpoch++;
    if (_controller.isReady) await _controller.textSelectionDelegate.clearTextSelection();
  }

  Future<void> _commitSelection() async {
    final epoch = ++_selectionEpoch;
    // pdfrx settles the selection a frame after the pointer is released.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || epoch != _selectionEpoch) return;
    final selection = _controller.isReady ? _controller.textSelectionDelegate : _selection;
    if (selection == null || !selection.hasSelectedText) return;
    final ranges = await selection.getSelectedTextRanges();
    if (!mounted || epoch != _selectionEpoch || ranges.isEmpty) return;
    // One annotation per page: keep the page where the selection starts.
    final first = ranges.first.pageNumber;
    final onPage = ranges.where((r) => r.pageNumber == first).toList();
    final rects = <PageRect>[
      for (final range in onPage)
        for (final f in range.enumerateFragmentBoundingRects())
          PageRect(f.bounds.left, f.bounds.top, f.bounds.right, f.bounds.bottom),
    ];
    final text = onPage.map((r) => r.text).join();
    if (text.trim().isEmpty || rects.isEmpty) return;
    final bounds = rects
        .map(
          (r) =>
              _controller.calcRectForRectInsidePage(pageNumber: first, rect: PdfRect(r.left, r.top, r.right, r.bottom)),
        )
        .reduce((a, b) => a.expandToInclude(b));
    final viewportRect = Rect.fromPoints(
      _controller.documentToLocal(bounds.topLeft),
      _controller.documentToLocal(bounds.bottomRight),
    );
    widget.onSelectionCommitted?.call(
      MMPdfSelection(page: first, rects: rects, text: text, viewportRect: viewportRect),
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
                          color: h.color,
                          borderRadius: BorderRadius.circular(2),
                          border: h.emphasized
                              ? Border.all(color: widget.emphasisColor, width: 2)
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
