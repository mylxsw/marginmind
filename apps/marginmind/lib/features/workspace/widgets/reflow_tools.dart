import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_reflow/mm_reflow.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../reflow_geometry.dart';
import '../workspace_controller.dart';
import 'notices.dart';

typedef ReflowCapture = Future<Uint8List?> Function(RenderRepaintBoundary boundary, Rect region, double ratio);
final reflowCaptureProvider = Provider<ReflowCapture>((ref) => captureReflowRegion);

/// Capture only the requested visible pixels, never allocate a whole chapter.
Future<Uint8List?> captureReflowRegion(RenderRepaintBoundary boundary, Rect region, double ratio) async {
  final clipped = region.intersect(Offset.zero & boundary.size);
  if (clipped.isEmpty || boundary is! ReflowCaptureBoundary) return null;
  final scale = math.min(ratio, math.sqrt(4 * 1024 * 1024 / (clipped.width * clipped.height)));
  final image = await boundary.capture(clipped, scale);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

class ReflowCaptureBoundary extends RenderRepaintBoundary {
  Future<ui.Image> capture(Rect region, double scale) {
    final decorations = <_TransientDecorationLayer>[];
    void visit(Layer current) {
      if (current is _TransientDecorationLayer) {
        decorations.add(current);
        current.exclude(true);
      }
      if (current is ContainerLayer) {
        var child = current.firstChild;
        while (child != null) {
          visit(child);
          child = child.nextSibling;
        }
      }
    }

    visit(layer!);
    // Scene construction is synchronous. Restore retained layers before any
    // subsequent screen frame; only the exported scene omits the decorations.
    try {
      return Future.value((layer! as OffsetLayer).toImageSync(region, pixelRatio: scale));
    } finally {
      for (final decoration in decorations) {
        decoration.exclude(false);
      }
    }
  }
}

/// Reader-only paint whose layer is omitted from screenshot excerpts.
class ReflowTransientDecoration extends SingleChildRenderObjectWidget {
  const ReflowTransientDecoration({super.key, required super.child});
  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) => _TransientDecorationBoundary();
}

class _TransientDecorationBoundary extends RenderRepaintBoundary {
  @override
  OffsetLayer updateCompositedLayer({required covariant OffsetLayer? oldLayer}) =>
      oldLayer ?? _TransientDecorationLayer();
}

class _TransientDecorationLayer extends OffsetLayer {
  bool _excluding = false;
  void exclude(bool value) {
    _excluding = value;
    markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (!_excluding) super.addToScene(builder);
  }
}

class _CaptureBoundary extends SingleChildRenderObjectWidget {
  const _CaptureBoundary({super.key, required super.child});
  @override
  ReflowCaptureBoundary createRenderObject(BuildContext context) => ReflowCaptureBoundary();
}

/// Area gestures span the visible viewport, including multiple mounted chapters.
class ReflowAreaCapture extends ConsumerStatefulWidget {
  const ReflowAreaCapture({
    super.key,
    required this.studySetId,
    required this.documentId,
    required this.spec,
    required this.view,
    required this.anchors,
    required this.child,
  });
  final String studySetId, documentId;
  final LayoutSpec spec;
  final Object view;
  final List<TextAnchor> Function(Rect globalRegion) anchors;
  final Widget child;
  @override
  ConsumerState<ReflowAreaCapture> createState() => _ReflowAreaCaptureState();
}

class _ReflowAreaCaptureState extends ConsumerState<ReflowAreaCapture> {
  final _boundary = GlobalKey();
  Offset? _start;
  Rect? _region;
  int _generation = 0;
  @override
  void didUpdateWidget(ReflowAreaCapture old) {
    super.didUpdateWidget(old);
    if (old.spec != widget.spec || old.documentId != widget.documentId || old.view != widget.view) {
      _generation++;
      _start = null;
      _region = null;
    }
  }

  Future<void> _capture() async {
    final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final rect = _region;
    _start = null;
    setState(() => _region = null);
    if (boundary == null || rect == null) return;
    final region = rect.intersect(Offset.zero & boundary.size);
    if (region.shortestSide < MMSpacing.s) return;
    final anchors = widget.anchors(
      Rect.fromPoints(boundary.localToGlobal(region.topLeft), boundary.localToGlobal(region.bottomRight)),
    );
    if (anchors.isEmpty) return;
    final generation = ++_generation;
    final spec = widget.spec;
    final ratio = math.min(
      MediaQuery.devicePixelRatioOf(context),
      math.sqrt(4 * 1024 * 1024 / (region.width * region.height)),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _generation || !boundary.attached) return;
    try {
      final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
      final notice = await workspace.excerptTextArea(
        widget.documentId,
        anchors,
        () => ref.read(reflowCaptureProvider)(boundary, region, ratio),
        capture: TextCapture(
          width: region.width,
          height: region.height,
          fontSize: spec.fontSize,
          lineHeight: spec.lineHeight,
          viewportWidth: boundary.size.width,
          pixelRatio: ratio,
        ),
      );
      if (mounted) showNotice(context, notice, rootTitle: '');
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider(widget.studySetId));
    return Stack(
      children: [
        _CaptureBoundary(
          key: _boundary,
          child: ColoredBox(color: widget.spec.readerStyle.paperColor, child: widget.child),
        ),
        if (state.tool == AnnotationTool.area)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('reflow-area-surface'),
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: (d) {
                ref.read(workspaceProvider(widget.studySetId).notifier).dismissPending();
                _start = d.localPosition;
              },
              onPanUpdate: (d) {
                if (_start != null) setState(() => _region = Rect.fromPoints(_start!, d.localPosition));
              },
              onPanEnd: (_) => _capture(),
              onPanCancel: () => setState(() {
                _start = null;
                _region = null;
              }),
              child: Stack(
                children: [
                  if (_region != null)
                    Positioned.fromRect(
                      rect: _region!,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: context.mmColors.accent, width: MMSpacing.xxs),
                            color: context.mmColors.accentTint,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ReflowTools extends ConsumerStatefulWidget {
  const ReflowTools({
    super.key,
    required this.studySetId,
    required this.documentId,
    required this.layout,
    required this.page,
    required this.child,
  });
  final String studySetId, documentId;
  final ChapterLayout layout;
  final int? page;
  final Widget child;
  @override
  ConsumerState<ReflowTools> createState() => _ReflowToolsState();
}

class _ReflowToolsState extends ConsumerState<ReflowTools> {
  final _points = <Offset>[];
  final _erased = <String>{};
  ChapterLayout? _drawingLayout;
  WorkspaceController get workspace => ref.read(workspaceProvider(widget.studySetId).notifier);
  Offset chapter(Offset p) => widget.page == null ? p : widget.layout.toChapter(p, widget.page!);

  void _start(Offset p) {
    workspace.dismissPending();
    _drawingLayout = widget.layout;
    _points.clear();
    _erased.clear();
    _move(p);
  }

  void _move(Offset p) {
    if (_drawingLayout != widget.layout || widget.layout.isDisposed) return;
    final state = ref.read(workspaceProvider(widget.studySetId));
    final point = chapter(p);
    setState(() {
      if (_points.length < InkStroke.maxPoints) _points.add(point);
      if (state.inkTool == MMPdfInkTool.eraser) {
        for (final stroke in workspace.content.inkStrokes.where((s) => s.documentId == widget.documentId)) {
          final anchor = stroke.textAnchor;
          if (anchor == null) continue;
          final transform = paragraphInkTransform(widget.layout, anchor);
          if (transform == null) continue;
          final local = (point - transform.origin) / transform.scale;
          if (inkStrokeHit(stroke, InkPoint(local.dx, local.dy), MMSpacing.m / transform.scale)) _erased.add(stroke.id);
        }
      }
    });
  }

  Future<void> _end() async {
    final layout = _drawingLayout;
    _drawingLayout = null;
    if (layout != widget.layout || layout?.isDisposed != false || _points.isEmpty) {
      _cancel();
      return;
    }
    final state = ref.read(workspaceProvider(widget.studySetId));
    final points = List.of(_points), erased = Set.of(_erased);
    _cancel();
    try {
      if (state.tool == AnnotationTool.ink) {
        if (state.inkTool == MMPdfInkTool.eraser) {
          await workspace.eraseInkStrokes(erased);
        } else {
          await workspace.addParagraphInk(
            paragraphInk(
              layout!,
              points,
              documentId: widget.documentId,
              newId: ref.read(editorProvider).newId,
              tool: switch (state.inkTool) {
                MMPdfInkTool.ellipse => InkTool.ellipse,
                MMPdfInkTool.arrow => InkTool.arrow,
                _ => InkTool.pen,
              },
              colorIndex: state.inkColor.index,
              width: state.inkWidth.points,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    }
  }

  void _cancel() => setState(() {
    _points.clear();
    _erased.clear();
    _drawingLayout = null;
  });

  @override
  void didUpdateWidget(ReflowTools old) {
    super.didUpdateWidget(old);
    if (old.layout != widget.layout || old.page != widget.page) {
      _points.clear();
      _erased.clear();
      _drawingLayout = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider(widget.studySetId));
    final drawing = state.tool == AnnotationTool.ink;
    final strokes = workspace.content.inkStrokes.where(
      (s) => s.documentId == widget.documentId && s.textAnchor != null,
    );
    return Stack(
      children: [
        RepaintBoundary(
          child: ColoredBox(
            color: widget.layout.spec.readerStyle.paperColor,
            child: CustomPaint(
              foregroundPainter: ReflowInkPainter(widget.layout, widget.page, strokes.toList(), _erased),
              child: widget.child,
            ),
          ),
        ),
        if (drawing)
          Positioned.fill(
            child: MMStylusRegion(
              enabled: context.mmTablet,
              onDown: _start,
              onMove: _move,
              onUp: (point) {
                _move(point);
                _end();
              },
              onCancel: _cancel,
              child: GestureDetector(
                key: const ValueKey('reflow-tool-surface'),
                dragStartBehavior: DragStartBehavior.down,
                behavior: context.mmTablet ? HitTestBehavior.translucent : HitTestBehavior.opaque,
                supportedDevices: context.mmTablet ? const {PointerDeviceKind.mouse} : null,
                onPanStart: (d) => _start(d.localPosition),
                onPanUpdate: (d) => _move(d.localPosition),
                onPanEnd: (_) => _end(),
                onPanCancel: _cancel,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DraftPainter(
                      widget.layout,
                      widget.page,
                      List.of(_points),
                      state.inkColor.stroke,
                      state.inkWidth.points,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ReflowInkPainter extends CustomPainter {
  ReflowInkPainter(this.layout, this.page, this.strokes, this.erased);
  final ChapterLayout layout;
  final int? page;
  final List<InkStroke> strokes;
  final Set<String> erased;
  @override
  void paint(Canvas canvas, Size size) {
    if (layout.isDisposed) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (page != null) {
      canvas.clipRect(
        Rect.fromLTWH(
          layout.spec.padding.left,
          layout.spec.padding.top,
          layout.spec.contentWidth,
          layout.spec.contentHeight,
        ),
      );
    }
    for (final stroke in strokes) {
      if (erased.contains(stroke.id)) continue;
      final t = paragraphInkTransform(layout, stroke.textAnchor!);
      if (t == null) continue;
      Offset map(Offset p) => page == null ? p : layout.toPage(p, page!);
      final origin = map(t.origin);
      final e = stroke.ellipse;
      paintInk(
        canvas,
        tool: stroke.tool,
        points: [for (final p in stroke.points) origin + Offset(p.x, p.y) * t.scale],
        ellipse: e == null
            ? null
            : Rect.fromPoints(origin + Offset(e.left, e.bottom) * t.scale, origin + Offset(e.right, e.top) * t.scale),
        color: MMInkColor.values[stroke.colorIndex.clamp(0, MMInkColor.values.length - 1)].stroke,
        width: stroke.width * t.scale,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ReflowInkPainter old) => true;
}

class _DraftPainter extends CustomPainter {
  _DraftPainter(this.layout, this.page, this.points, this.color, this.width);
  final ChapterLayout layout;
  final int? page;
  final List<Offset> points;
  final Color color;
  final double width;
  @override
  void paint(Canvas canvas, Size size) {
    if (layout.isDisposed) return;
    paintInk(
      canvas,
      tool: InkTool.pen,
      points: [for (final p in points) page == null ? p : layout.toPage(p, page!)],
      color: color,
      width: width,
    );
  }

  @override
  bool shouldRepaint(_DraftPainter old) => true;
}
