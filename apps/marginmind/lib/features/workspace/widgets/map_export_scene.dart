import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';
import 'package:mm_platform/mm_platform.dart';

import 'mind_map_geometry.dart';

/// Raster budgets apply to the final image, not just the individual tiles.
/// A very tall map may require a fractional scale even at the 1× setting.
class MapRasterPlan {
  MapRasterPlan(Size size, double requested) {
    if (!size.width.isFinite || !size.height.isFinite || size.isEmpty || requested <= 0 || !requested.isFinite) {
      throw ArgumentError('Invalid export dimensions');
    }
    scale = math.min(requested, math.min(16384 / size.longestSide, math.sqrt(32000000 / (size.width * size.height))));
    width = (size.width * scale).floor().clamp(1, 16384);
    height = (size.height * scale).floor().clamp(1, 16384);
    reduced = scale < requested;
  }
  late final double scale;
  late final int width, height;
  late final bool reduced;
  bool get large => math.max(width, height) > 8000;
}

/// A complete export drawing tree. It uses the canvas layout engine and design
/// styles, but measures full text and expands collapsed branches. The same tree
/// drives preview, offscreen tiles and the native vector PDF display list.
class MapExportScene extends CustomPainter {
  MapExportScene._(this.layout, this.commands, this.images);
  final TreeLayoutResult layout;
  final List<Map<String, Object?>> commands;
  final Map<String, ui.Image> images;
  Size get size => Size(layout.width, layout.height);

  static MapExportScene build({
    required StudySetContent content,
    required String mapId,
    required String title,
    required MMColors colors,
    required String researchLabel,
    required String Function(Document, int) source,
    bool transparent = false,
    Map<String, ui.Image> images = const {},
    Map<String, Uint8List> imageBytes = const {},
  }) {
    const root = '__export_root__';
    final nodes = <String, _ExportNode>{
      root: _ExportNode(title, '', MMTypography.title3, colors.rootNode, colors.onRootNode),
    };
    final children = <String?, List<MapNode>>{};
    for (final n in content.nodes.where((n) => n.mapId == mapId)) {
      children.putIfAbsent(n.parentId, () => []).add(n);
      final card = content.card(n.cardId);
      if (card == null) continue;
      final a = content.annotation(card.annotationId ?? '');
      final doc = content.document(a?.documentId ?? '');
      final note = content.researchNote(card.researchNoteId ?? '');
      final body = <String>[
        if (card.kind == CardKind.excerpt) a?.quote ?? '',
        if (note != null) ...[
          note.body,
          for (final attachment in content.noteAttachments.where((a) => a.noteId == note.id))
            if (attachment.target case PdfTarget(:final documentId, :final pages))
              if (content.document(documentId) case final document?)
                for (final page in pages) source(document, page.page),
          for (final citation in note.citations)
            if (content.evidence.where((e) => e.id == citation.evidenceId).firstOrNull case final evidence?)
              if (content.researchSources.where((s) => s.id == evidence.sourceId).firstOrNull case final s?)
                '${s.title} · ${s.url} · ${s.fetchedAt.toIso8601String()}',
        ],
        if (doc != null) source(doc, a!.page),
      ].where((s) => s.isNotEmpty).join('\n');
      nodes[n.cardId] = _ExportNode(
        note != null
            ? '$researchLabel · ${note.title}'
            // A formatted note is drawn as its text, without the markup (P2-C07).
            : notePlainText(card.title, card.textFormat),
        body,
        card.kind == CardKind.topic ? MMTypography.headline : MMTypography.body,
        card.kind == CardKind.research ? colors.researchTint : colors.card,
        colors.label,
        width: n.width ?? MMSizes.mapExportNodeWidth,
        serif: card.kind == CardKind.excerpt,
        image: card.imageFileName,
        imageSize: images[card.imageFileName],
        accent: card.kind == CardKind.research ? colors.research : null,
      );
    }
    for (final siblings in children.values) {
      siblings.sort((a, b) => a.order.compareTo(b.order));
    }
    final visiting = <String>{};
    LayoutNode tree(String id) {
      if (!visiting.add(id)) throw StateError('Cyclic map');
      final node = nodes[id]!;
      final result = LayoutNode(
        id: id,
        width: node.size.width,
        height: node.size.height,
        children: [
          for (final n in children[id == root ? null : id] ?? <MapNode>[])
            if (nodes.containsKey(n.cardId)) tree(n.cardId),
        ],
      );
      visiting.remove(id);
      return result;
    }

    final summaries = content.summariesOf(mapId);
    final labels = {
      for (final (s, _) in summaries)
        s.id: _ExportNode(s.label, '', MMTypography.headline, colors.canvas, colors.label),
    };
    final layout = const TreeLayout(balanced: true, padding: MMSizes.mapExportCanvasPadding).layout(
      tree(root),
      summaries: [
        for (final (s, _) in summaries)
          LayoutSummary(
            id: s.id,
            parentId: s.parentId ?? root,
            fromId: s.fromId,
            toId: s.toId,
            width: labels[s.id]!.size.width,
            height: labels[s.id]!.size.height,
          ),
      ],
    );
    final commands = <Map<String, Object?>>[];
    void box(Rect rect, Color color, {double radius = MMRadii.card}) => commands.add({
      'type': 'box',
      'rect': [rect.left, rect.top, rect.width, rect.height],
      'color': color.toARGB32(),
      'radius': radius,
    });
    void curve(List<Offset> points, {bool dashed = false}) => commands.add({
      'type': 'curve',
      'points': [
        for (final p in points) ...[p.dx, p.dy],
      ],
      'color': colors.line.toARGB32(),
      'dashed': dashed,
    });
    Rect rect(LayoutRect r) => Rect.fromLTWH(r.left, r.top, r.width, r.height);
    if (!transparent) box(Rect.fromLTWH(0, 0, layout.width, layout.height), colors.canvas, radius: 0);
    for (final e in layout.edges) {
      final a = rect(layout.rects[e.parentId]!), b = rect(layout.rects[e.childId]!);
      final left = layout.leftSide.contains(e.childId);
      final start = Offset(left ? a.left : a.right, a.center.dy), end = Offset(left ? b.right : b.left, b.center.dy);
      final mid = (start.dx + end.dx) / 2;
      curve([start, Offset(mid, start.dy), Offset(mid, end.dy), end]);
    }
    final relationLabels = <Map<String, Object?>>[];
    for (final r in content.relationsOf(mapId)) {
      final a = layout.rects[r.fromId], b = layout.rects[r.toId];
      if (a == null || b == null) continue;
      final left = layout.leftSide.contains(r.fromId) && layout.leftSide.contains(r.toId);
      final c = relationCurveOnSide(rect(a), rect(b), [
        ...layout.rects.values.map(rect),
        ...layout.summaries.values.map((s) => rect(s.label)),
      ], left: left);
      curve([c.$1, c.$2, c.$3, c.$4], dashed: true);
      final tip = c.$4, before = c.$3;
      final angle = math.atan2(tip.dy - before.dy, tip.dx - before.dx);
      for (final delta in [-0.5, 0.5]) {
        final p = tip - Offset(math.cos(angle + delta), math.sin(angle + delta)) * MMSpacing.s;
        curve([p, p, tip, tip]);
      }
      if (r.label.isNotEmpty) {
        final label = _ExportNode(r.label, '', MMTypography.footnote, colors.canvas, colors.secondaryLabel);
        final middle = cubicPoint(c, .5);
        final side = relationGoesAround(c) ? (left ? -1 : 1) : 0;
        final x = side < 0
            ? middle.dx - label.size.width - MMSpacing.xs
            : side > 0
            ? middle.dx + MMSpacing.xs
            : middle.dx - label.size.width / 2;
        label.emit(relationLabels, Offset(x, middle.dy - label.size.height / 2), imageBytes);
      }
    }
    for (final e in layout.summaries.entries) {
      final b = rect(e.value.bracket);
      final outer = e.value.left ? b.left : b.right, inner = e.value.left ? b.right : b.left;
      curve([Offset(inner, b.top), Offset(outer, b.top), Offset(inner, b.center.dy), Offset(outer, b.center.dy)]);
      curve([Offset(outer, b.center.dy), Offset(inner, b.center.dy), Offset(outer, b.bottom), Offset(inner, b.bottom)]);
      labels[e.key]!.emit(commands, rect(e.value.label).topLeft, imageBytes);
    }
    for (final e in layout.rects.entries) {
      final node = nodes[e.key]!, r = rect(e.value);
      box(r, node.background);
      if (node.accent case final color?) box(Rect.fromLTWH(r.left, r.top, MMSpacing.xs, r.height), color);
      node.emit(commands, r.topLeft, imageBytes);
    }
    commands.addAll(relationLabels);
    var bounds = Rect.fromLTWH(0, 0, layout.width, layout.height);
    for (final c in commands) {
      if (c['points'] case final List<double> points) {
        for (var i = 0; i < points.length; i += 2) {
          bounds = bounds.expandToInclude(
            Rect.fromCircle(center: Offset(points[i], points[i + 1]), radius: MMSpacing.m),
          );
        }
      }
      if (c['type'] == 'text' || c['type'] == 'image') {
        final r = Rect.fromLTWH(
          c['x'] as double,
          c['y'] as double,
          c['width'] as double,
          c['type'] == 'text' ? (c['fontSize'] as double) * 2 : c['height'] as double,
        );
        bounds = bounds.expandToInclude(r.inflate(MMSpacing.m));
      }
    }
    final dx = -math.min(0.0, bounds.left), dy = -math.min(0.0, bounds.top);
    for (final c in commands) {
      if (c['x'] is double) {
        c['x'] = (c['x'] as double) + dx;
        c['y'] = (c['y'] as double) + dy;
      }
      if (c['rect'] case final List<double> r) {
        r[0] += dx;
        r[1] += dy;
      }
      if (c['points'] case final List<double> p) {
        for (var i = 0; i < p.length; i += 2) {
          p[i] += dx;
          p[i + 1] += dy;
        }
      }
    }
    final full = TreeLayoutResult(
      rects: {
        for (final e in layout.rects.entries)
          e.key: LayoutRect(e.value.left + dx, e.value.top + dy, e.value.width, e.value.height),
      },
      edges: layout.edges,
      summaries: {
        for (final e in layout.summaries.entries)
          e.key: SummaryPlacement(
            LayoutRect(
              e.value.bracket.left + dx,
              e.value.bracket.top + dy,
              e.value.bracket.width,
              e.value.bracket.height,
            ),
            LayoutRect(e.value.label.left + dx, e.value.label.top + dy, e.value.label.width, e.value.label.height),
            left: e.value.left,
          ),
      },
      leftSide: layout.leftSide,
      width: bounds.width,
      height: bounds.height,
    );
    if (!transparent) {
      commands[0]['rect'] = <double>[0, 0, bounds.width, bounds.height];
    }
    return MapExportScene._(full, commands, images);
  }

  Map<String, Object?> get vector => {'width': size.width, 'height': size.height, 'commands': commands};

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in commands) {
      final color = Color(c['color'] as int? ?? 0);
      switch (c['type']) {
        case 'box':
          final r = (c['rect'] as List<double>);
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(r[0], r[1], r[2], r[3]), Radius.circular(c['radius'] as double)),
            Paint()..color = color,
          );
        case 'curve':
          final p = c['points'] as List<double>;
          final path = Path()
            ..moveTo(p[0], p[1])
            ..cubicTo(p[2], p[3], p[4], p[5], p[6], p[7]);
          final pen = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          if (c['dashed'] == true) {
            for (final metric in path.computeMetrics()) {
              for (var d = 0.0; d < metric.length; d += 9) {
                canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), pen);
              }
            }
          } else {
            canvas.drawPath(path, pen);
          }
        case 'text':
          final p = _text(
            c['text'] as String,
            TextStyle(
              fontSize: c['fontSize'] as double,
              fontFamily: c['serif'] == true ? 'Songti SC' : null,
              fontWeight: c['bold'] == true ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
            c['width'] as double,
          );
          p.paint(canvas, Offset(c['x'] as double, c['y'] as double));
          p.dispose();
        case 'image':
          final image = images[c['name']];
          if (image != null) {
            paintImage(
              canvas: canvas,
              rect: Rect.fromLTWH(c['x'] as double, c['y'] as double, c['width'] as double, c['height'] as double),
              image: image,
              fit: BoxFit.contain,
            );
          }
      }
    }
  }

  /// Only a tile is attached to a render pipeline. There is no screen-sized
  /// boundary, viewport culling, GPU-sized final image, or live canvas state.
  Future<Uint8List> png(MapRasterPlan plan, {NativeMapExport encoder = const NativeMapExport()}) async {
    const tileSize = 2048;
    final tiles = <Map<String, Object?>>[];
    for (var y = 0; y < plan.height; y += tileSize) {
      for (var x = 0; x < plan.width; x += tileSize) {
        final size = Size(
          math.min(tileSize, plan.width - x).toDouble(),
          math.min(tileSize, plan.height - y).toDouble(),
        );
        final owner = PipelineOwner();
        final boundary = RenderRepaintBoundary(
          child: RenderCustomPaint(painter: _ExportTile(this, plan.scale, Offset(x.toDouble(), y.toDouble()))),
        );
        owner.rootNode = boundary;
        boundary.layout(BoxConstraints.tight(size));
        final layer = OffsetLayer()..attach(owner);
        boundary.scheduleInitialPaint(layer);
        try {
          owner.flushLayout();
          owner.flushCompositingBits();
          owner.flushPaint();
          final image = await boundary.toImage();
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            if (data == null) throw StateError('PNG tile unavailable');
            tiles.add({'x': x, 'y': y, 'bytes': data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)});
          } finally {
            image.dispose();
          }
        } finally {
          owner.rootNode = null;
          layer.detach();
          boundary.dispose();
          owner.dispose();
        }
      }
    }
    return encoder.png(plan.width, plan.height, tiles);
  }

  @override
  bool shouldRepaint(MapExportScene oldDelegate) => oldDelegate != this;
}

TextPainter _text(String text, TextStyle style, double width) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
)..layout(maxWidth: width);

class _ExportNode {
  _ExportNode(
    this.title,
    this.body,
    this.style,
    this.background,
    this.foreground, {
    this.width = MMSizes.mapExportNodeWidth,
    this.serif = false,
    this.image,
    this.imageSize,
    this.accent,
  }) {
    final t = _text(title, style, width - MMSpacing.xxl);
    final b = _text(body, serif ? MMTypography.readingExcerpt : MMTypography.body, width - MMSpacing.xxl);
    titleHeight = title.isEmpty ? 0 : t.height;
    bodyHeight = body.isEmpty ? 0 : b.height;
    imageHeight = image == null
        ? 0
        : imageSize == null
        ? MMSizes.mapExportImageFallbackHeight
        : (width - MMSpacing.xxl) * imageSize!.height / imageSize!.width;
    size = Size(
      width,
      titleHeight +
          bodyHeight +
          imageHeight +
          MMSpacing.xxl +
          (bodyHeight > 0 ? MMSpacing.s : 0) +
          (imageHeight > 0 ? MMSpacing.s : 0),
    );
    t.dispose();
    b.dispose();
  }
  final String title, body;
  final TextStyle style;
  final Color background, foreground;
  final double width;
  final bool serif;
  final String? image;
  final ui.Image? imageSize;
  final Color? accent;
  late final Size size;
  late final double titleHeight, bodyHeight, imageHeight;
  void emit(List<Map<String, Object?>> out, Offset offset, Map<String, Uint8List> bytes) {
    var y = offset.dy + MMSpacing.m;
    void text(String value, TextStyle style, bool serif) {
      if (value.isEmpty) return;
      final painter = _text(value, style, width - MMSpacing.xxl);
      for (final line in painter.computeLineMetrics()) {
        final pos = painter.getPositionForOffset(Offset(line.left + line.width / 2, line.baseline));
        final range = painter.getLineBoundary(pos);
        final text = value.substring(range.start, range.end).replaceAll('\n', '');
        out.add({
          'type': 'text',
          'text': text,
          'x': offset.dx + MMSpacing.m + line.left,
          'y': y + line.baseline - line.ascent,
          'width': width - MMSpacing.xxl + MMSpacing.xs,
          'fontSize': style.fontSize!,
          'bold': (style.fontWeight?.value ?? 400) >= 600,
          'serif': serif,
          'color': foreground.toARGB32(),
        });
      }
      painter.dispose();
    }

    text(title, style, false);
    y += titleHeight;
    if (image != null) {
      y += MMSpacing.s;
      out.add({
        'type': 'image',
        'name': image,
        'bytes': bytes[image],
        'x': offset.dx + MMSpacing.m,
        'y': y,
        'width': width - MMSpacing.xxl,
        'height': imageHeight,
      });
      y += imageHeight;
    }
    if (body.isNotEmpty) {
      y += MMSpacing.s;
      text(body, serif ? MMTypography.readingExcerpt : MMTypography.body, serif);
    }
  }
}

class _ExportTile extends CustomPainter {
  const _ExportTile(this.scene, this.scale, this.offset);
  final MapExportScene scene;
  final double scale;
  final Offset offset;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-offset.dx, -offset.dy);
    canvas.scale(scale);
    scene.paint(canvas, scene.size);
  }

  @override
  bool shouldRepaint(_ExportTile oldDelegate) => true;
}

/// Images are loaded before building the scene, so every tile sees the same
/// decoded image. The caller owns and disposes all returned handles.
Future<(Map<String, ui.Image>, Map<String, Uint8List>)> loadExportImages(
  StudySetContent content,
  String Function(String) resolve,
) async {
  final images = <String, ui.Image>{}, bytes = <String, Uint8List>{};
  try {
    final names = content.cards.map((c) => c.imageFileName).whereType<String>().toSet();
    var totalBytes = 0;
    for (final name in names) {
      final file = File(resolve(name));
      totalBytes += await file.length();
      if (totalBytes > 128 * 1024 * 1024) throw StateError('Export image budget exceeded');
      final data = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      // The SDK owns the encoded buffer until the codec is ready.
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final scale = math.min(
            1.0,
            math.min(2048 / math.max(width, height), math.sqrt(16000000 / names.length / width / height)),
          );
          return ui.TargetImageSize(
            width: math.max(1, (width * scale).floor()),
            height: math.max(1, (height * scale).floor()),
          );
        },
      );
      try {
        images[name] = (await codec.getNextFrame()).image;
        bytes[name] = data;
      } finally {
        codec.dispose();
      }
    }
    return (images, bytes);
  } catch (_) {
    for (final image in images.values) {
      image.dispose();
    }
    rethrow;
  }
}
