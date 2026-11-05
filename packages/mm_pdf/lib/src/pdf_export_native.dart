import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:mm_core/mm_core.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_dart;
import 'package:pdfrx/pdfrx.dart';

import 'pdf_export.dart';

const canWriteMarks = true;

pdfium_dart.PDFium? _bindings;

/// PDF standard annotation flag: show the annotation when printing.
const _printFlag = 4;

/// Translucency of the highlighter pen, matching the reader's stroke.
const _highlighterAlpha = 90;

const _highlightLightness = .55;

/// Adds marks as standard PDF annotations, so other readers can show, edit and
/// remove them, then drops the pages left out of the range. PDFium's own worker
/// is suspended while this isolate calls it.
Future<void> addMarks(
  PdfDocument document,
  DocumentExportPlan plan,
  MMPdfExportColors colors, {
  void Function(double progress)? onProgress,
  bool Function()? cancelled,
}) async {
  final byPage = _marksByPage(plan, colors);
  final numbers = byPage.keys.toList()..sort();
  await document.useNativeDocumentHandle((handle) async {
    final api = _bindings ??= pdfium_dart.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
    final native = pdfium_dart.FPDF_DOCUMENT.fromAddress(handle);
    for (var i = 0; i < numbers.length; i++) {
      if (cancelled?.call() == true) throw const MMPdfExportCancelled();
      final number = numbers[i];
      if (number > document.pages.length) continue;
      final page = api.FPDF_LoadPage(native, number - 1);
      if (page == nullptr) throw StateError('Cannot load page $number');
      try {
        using((arena) {
          final box = arena<pdfium_dart.FS_RECTF>();
          api.FPDF_GetPageBoundingBox(page, box);
          // Stored coordinates are relative to the page box origin.
          final origin = (
            x: box.ref.left.toDouble(),
            y: box.ref.bottom.toDouble(),
            width: box.ref.right - box.ref.left,
          );
          for (final mark in byPage[number]!) {
            mark.write(api, page, origin, arena);
          }
        });
      } finally {
        api.FPDF_ClosePage(page);
      }
      onProgress?.call((i + 1) / numbers.length);
      // Keep the window responsive through long documents.
      await Future<void>.delayed(Duration.zero);
    }
    if (plan.options.pages case final keep?) {
      for (var index = api.FPDF_GetPageCount(native) - 1; index >= 0; index--) {
        if (!keep.contains(index + 1)) api.FPDFPage_Delete(native, index);
      }
    }
  });
}

Map<int, List<_Mark>> _marksByPage(DocumentExportPlan plan, MMPdfExportColors colors) {
  final result = <int, List<_Mark>>{};
  void add(int page, _Mark mark) => (result[page] ??= []).add(mark);
  for (final a in plan.annotations) {
    for (final p in a.pages) {
      final type = a.quote.trim().isEmpty
          ? pdfium_dart.FPDF_ANNOT_SQUARE
          : switch (a.kind) {
              AnnotationKind.highlight => pdfium_dart.FPDF_ANNOT_HIGHLIGHT,
              // PDF has no dashed underline, and Preview skips Squiggly: every
              // line style becomes the one underline all readers draw.
              AnnotationKind.underline => pdfium_dart.FPDF_ANNOT_UNDERLINE,
            };
      final rgb = colors.mark(a.colorIndex);
      add(p.page, _RectsMark(type, p.rects, type == pdfium_dart.FPDF_ANNOT_HIGHLIGHT ? _soft(rgb) : rgb));
    }
  }
  for (final n in plan.notes) {
    final anchor = n.anchor?.pages.first.rects.first;
    add(n.page, _NoteMark(n.text, anchor?.left, anchor?.top ?? n.lineY!, colors.note(n.colorIndex)));
  }
  for (final s in plan.strokes) {
    add(s.page, _InkMark(_strokePaths(s), s.width, colors.ink(s.colorIndex), s.tool == InkTool.highlighter));
  }
  return result;
}

/// Readers multiply highlights over the text; a full-strength swatch would
/// bury it, so it is mixed with white to match the reader's translucent fill.
int _soft(int rgb) {
  int channel(int shift) {
    final value = (rgb >> shift) & 0xFF;
    return (value + (255 - value) * _highlightLightness).round();
  }

  return channel(16) << 16 | channel(8) << 8 | channel(0);
}

/// The polylines of a stroke; ink annotations have no ellipse or arrow primitive.
List<List<InkPoint>> _strokePaths(InkStroke stroke) {
  final e = stroke.ellipse;
  if (e != null) {
    final cx = (e.left + e.right) / 2, cy = (e.top + e.bottom) / 2;
    final rx = (e.right - e.left).abs() / 2, ry = (e.top - e.bottom).abs() / 2;
    return [
      [
        for (var i = 0; i <= 64; i++)
          InkPoint(cx + rx * math.cos(i * math.pi / 32), cy + ry * math.sin(i * math.pi / 32)),
      ],
    ];
  }
  if (stroke.tool == InkTool.arrow && stroke.points.length >= 2) {
    final tip = stroke.points.last, tail = stroke.points[stroke.points.length - 2];
    final angle = math.atan2(tip.y - tail.y, tip.x - tail.x);
    final size = math.max(6.0, stroke.width * 4);
    InkPoint wing(double delta) =>
        InkPoint(tip.x - size * math.cos(angle + delta), tip.y - size * math.sin(angle + delta));
    return [
      stroke.points,
      [wing(math.pi / 6), tip, wing(-math.pi / 6)],
    ];
  }
  return [stroke.points];
}

typedef _Origin = ({double x, double y, double width});

sealed class _Mark {
  void write(pdfium_dart.PDFium api, pdfium_dart.FPDF_PAGE page, _Origin origin, Arena arena);

  pdfium_dart.FPDF_ANNOTATION create(pdfium_dart.PDFium api, pdfium_dart.FPDF_PAGE page, int type) {
    final annot = api.FPDFPage_CreateAnnot(page, type);
    if (annot == nullptr) throw StateError('Cannot create annotation $type');
    api.FPDFAnnot_SetFlags(annot, _printFlag);
    return annot;
  }

  void color(pdfium_dart.PDFium api, pdfium_dart.FPDF_ANNOTATION annot, int rgb, {int alpha = 255}) {
    api.FPDFAnnot_SetColor(
      annot,
      pdfium_dart.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
      (rgb >> 16) & 0xFF,
      (rgb >> 8) & 0xFF,
      rgb & 0xFF,
      alpha,
    );
  }

  void bounds(
    pdfium_dart.PDFium api,
    pdfium_dart.FPDF_ANNOTATION annot,
    Arena arena,
    double left,
    double bottom,
    double right,
    double top,
  ) {
    final rect = arena<pdfium_dart.FS_RECTF>();
    rect.ref
      ..left = left
      ..bottom = bottom
      ..right = right
      ..top = top;
    api.FPDFAnnot_SetRect(annot, rect);
  }
}

class _RectsMark extends _Mark {
  _RectsMark(this.type, this.rects, this.rgb);
  final int type, rgb;
  final List<PageRect> rects;

  @override
  void write(pdfium_dart.PDFium api, pdfium_dart.FPDF_PAGE page, _Origin origin, Arena arena) {
    final annot = create(api, page, type);
    try {
      color(api, annot, rgb);
      if (type == pdfium_dart.FPDF_ANNOT_SQUARE) api.FPDFAnnot_SetBorder(annot, 0, 0, 1.5);
      var left = double.infinity, bottom = double.infinity, right = -double.infinity, top = -double.infinity;
      final quad = arena<pdfium_dart.FS_QUADPOINTSF>();
      for (final r in rects) {
        final l = r.left + origin.x, b = r.bottom + origin.y, rt = r.right + origin.x, t = r.top + origin.y;
        left = math.min(left, l);
        bottom = math.min(bottom, b);
        right = math.max(right, rt);
        top = math.max(top, t);
        if (type != pdfium_dart.FPDF_ANNOT_SQUARE) {
          quad.ref
            ..x1 = l
            ..y1 = t
            ..x2 = rt
            ..y2 = t
            ..x3 = l
            ..y3 = b
            ..x4 = rt
            ..y4 = b;
          api.FPDFAnnot_AppendAttachmentPoints(annot, quad);
        }
      }
      bounds(api, annot, arena, left, bottom, right, top);
    } finally {
      api.FPDFPage_CloseAnnot(annot);
    }
  }
}

class _NoteMark extends _Mark {
  _NoteMark(this.text, this.x, this.y, this.rgb);

  /// Size of the sticky-note icon, in points.
  static const _icon = 18.0;
  final String text;

  /// The anchored text's left edge; a note on a bare line sits in the right margin.
  final double? x;
  final double y;
  final int rgb;

  @override
  void write(pdfium_dart.PDFium api, pdfium_dart.FPDF_PAGE page, _Origin origin, Arena arena) {
    final annot = create(api, page, pdfium_dart.FPDF_ANNOT_TEXT);
    try {
      color(api, annot, rgb);
      final left = origin.x + math.max(0, x == null ? origin.width - _icon * 1.5 : x! - _icon);
      final top = y + origin.y;
      bounds(api, annot, arena, left, top - _icon, left + _icon, top);
      final units = text.codeUnits;
      final wide = arena<Uint16>(units.length + 1);
      wide.asTypedList(units.length + 1)
        ..setAll(0, units)
        ..[units.length] = 0;
      final key = 'Contents'.toNativeUtf8(allocator: arena).cast<Char>();
      api.FPDFAnnot_SetStringValue(annot, key, wide.cast());
    } finally {
      api.FPDFPage_CloseAnnot(annot);
    }
  }
}

class _InkMark extends _Mark {
  _InkMark(this.paths, this.width, this.rgb, this.highlighter);
  final List<List<InkPoint>> paths;
  final double width;
  final int rgb;
  final bool highlighter;

  @override
  void write(pdfium_dart.PDFium api, pdfium_dart.FPDF_PAGE page, _Origin origin, Arena arena) {
    final annot = create(api, page, pdfium_dart.FPDF_ANNOT_INK);
    try {
      color(api, annot, rgb, alpha: highlighter ? _highlighterAlpha : 255);
      api.FPDFAnnot_SetBorder(annot, 0, 0, width);
      var left = double.infinity, bottom = double.infinity, right = -double.infinity, top = -double.infinity;
      for (final path in paths) {
        if (path.isEmpty) continue;
        final points = arena<pdfium_dart.FS_POINTF>(path.length);
        for (var i = 0; i < path.length; i++) {
          final x = path[i].x + origin.x, y = path[i].y + origin.y;
          points[i]
            ..x = x
            ..y = y;
          left = math.min(left, x);
          right = math.max(right, x);
          bottom = math.min(bottom, y);
          top = math.max(top, y);
        }
        api.FPDFAnnot_AddInkStroke(annot, points, path.length);
      }
      if (left.isFinite) bounds(api, annot, arena, left - width, bottom - width, right + width, top + width);
    } finally {
      api.FPDFPage_CloseAnnot(annot);
    }
  }
}
