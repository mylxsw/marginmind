part of '../mm_reflow.dart';

/// The gesture and paint surface used by both scrolling and paginated readers.
/// The caller owns the layout and the persistent selection.
class ReflowSurface extends StatefulWidget {
  const ReflowSurface({
    super.key,
    required this.layout,
    this.page,
    this.highlight,
    required this.onSelection,
    this.activeGeneration,
  });
  final ChapterLayout layout;
  final int? activeGeneration;
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
    if (layout.isDisposed || (widget.activeGeneration != null && widget.activeGeneration != layout.generation)) return;
    final offset = layout.hitTest(local, page: widget.page).start;
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
