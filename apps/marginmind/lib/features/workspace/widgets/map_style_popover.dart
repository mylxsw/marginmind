import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import 'mind_map_style.dart';

/// The map's structure and palette: four structure thumbnails and six palette
/// thumbnails, named only by their tooltips. Hovering a thumbnail previews it
/// ([onPreview], with the other half of the style unchanged), leaving the
/// popover ends the preview (null), and a click applies it.
class MapStylePopover extends StatefulWidget {
  const MapStylePopover({
    super.key,
    required this.structure,
    required this.palette,
    required this.onPreview,
    required this.onStructure,
    required this.onPalette,
    required this.onClose,
  });

  /// The map's own style, marked as selected.
  final MapStructure structure;
  final MapPalette palette;
  final ValueChanged<(MapStructure, MapPalette)?> onPreview;
  final ValueChanged<MapStructure> onStructure;
  final ValueChanged<MapPalette> onPalette;

  /// Esc, wherever the keyboard focus is while the popover is open.
  final VoidCallback onClose;

  @override
  State<MapStylePopover> createState() => _MapStylePopoverState();
}

class _MapStylePopoverState extends State<MapStylePopover> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  bool _key(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    widget.onClose();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    return MouseRegion(
      onExit: (_) => widget.onPreview(null),
      child: MMGlass(
        key: const ValueKey('map-style-popover'),
        borderRadius: BorderRadius.circular(MMRadii.dropdown),
        padding: const EdgeInsets.all(MMSpacing.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Grid(
              columns: 4,
              children: [
                for (final s in MapStructure.values)
                  _Thumb(
                    key: ValueKey('map-structure-${s.name}'),
                    label: l.mapStructureName(s),
                    height: MMSizes.mapStructureThumbHeight,
                    selected: s == widget.structure,
                    onHover: () => widget.onPreview((s, widget.palette)),
                    onTap: () => widget.onStructure(s),
                    child: CustomPaint(painter: StructureThumbPainter(s, c.secondaryLabel)),
                  ),
              ],
            ),
            const SizedBox(height: MMSpacing.l),
            _Grid(
              columns: 3,
              children: [
                for (final p in MapPalette.values)
                  _Thumb(
                    key: ValueKey('map-palette-${p.name}'),
                    label: l.mapPaletteName(p),
                    height: MMSizes.mapPaletteThumbHeight,
                    selected: p == widget.palette,
                    onHover: () => widget.onPreview((widget.structure, p)),
                    onTap: () => widget.onPalette(p),
                    child: CustomPaint(painter: PaletteThumbPainter(mapPaletteOf(p).of(c.brightness), c)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < children.length; i += columns) ...[
        if (i > 0) const SizedBox(height: MMSpacing.s),
        Row(
          children: [
            for (var j = i; j < i + columns; j++) ...[
              if (j > i) const SizedBox(width: MMSpacing.s),
              Expanded(child: j < children.length ? children[j] : const SizedBox.shrink()),
            ],
          ],
        ),
      ],
    ],
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.label,
    required this.height,
    required this.selected,
    required this.onHover,
    required this.onTap,
    required this.child,
  });

  final String label;
  final double height;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: MMInteractive(
        onTap: onTap,
        selected: selected,
        tooltip: label,
        semanticLabel: label,
        cursor: SystemMouseCursors.click,
        builder: (context, state) => Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(MMRadii.field),
            border: Border.all(
              color: selected
                  ? c.accent
                  : state.hovered
                  ? c.line
                  : c.separator,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A sketch of a structure: the center topic and three branches, drawn the
/// way the structure connects them.
class StructureThumbPainter extends CustomPainter {
  const StructureThumbPainter(this.structure, this.color);

  final MapStructure structure;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 64 × 40 grid, centered.
    final scale = (size.height / 48).clamp(0.5, 2.0);
    canvas
      ..translate(size.width / 2 - 32 * scale, size.height / 2 - 20 * scale)
      ..scale(scale);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final fill = Paint()..color = color;
    final leaf = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    void root(Rect r) => canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), fill);
    void leaves(List<(double, double, double)> rows) {
      for (final (x, y, w) in rows) {
        canvas.drawLine(Offset(x, y), Offset(x + w, y), leaf);
      }
    }

    switch (structure) {
      case MapStructure.mind:
        root(const Rect.fromLTWH(24, 16, 16, 8));
        canvas.drawPath(
          Path()
            ..moveTo(40, 20)
            ..cubicTo(46, 20, 46, 8, 52, 8)
            ..moveTo(40, 20)
            ..lineTo(52, 20)
            ..moveTo(40, 20)
            ..cubicTo(46, 20, 46, 32, 52, 32)
            ..moveTo(24, 20)
            ..cubicTo(18, 20, 18, 10, 12, 10)
            ..moveTo(24, 20)
            ..cubicTo(18, 20, 18, 30, 12, 30),
          line,
        );
        leaves([(52, 8, 8), (52, 20, 8), (52, 32, 8), (4, 10, 8), (4, 30, 8)]);
      case MapStructure.logic:
        root(const Rect.fromLTWH(4, 16, 16, 8));
        canvas.drawPath(
          Path()
            ..moveTo(20, 20)
            ..lineTo(26, 20)
            ..moveTo(26, 8)
            ..lineTo(26, 32)
            ..moveTo(26, 8)
            ..lineTo(34, 8)
            ..moveTo(26, 20)
            ..lineTo(34, 20)
            ..moveTo(26, 32)
            ..lineTo(34, 32),
          line,
        );
        leaves([(36, 8, 12), (36, 20, 16), (36, 32, 10)]);
      case MapStructure.brace:
        root(const Rect.fromLTWH(4, 16, 16, 8));
        canvas.drawPath(
          Path()
            ..moveTo(30, 6)
            ..quadraticBezierTo(26, 6, 26, 10)
            ..lineTo(26, 17)
            ..quadraticBezierTo(26, 20, 23, 20)
            ..quadraticBezierTo(26, 20, 26, 23)
            ..lineTo(26, 30)
            ..quadraticBezierTo(26, 34, 30, 34),
          line,
        );
        leaves([(33, 8, 14), (33, 20, 18), (33, 32, 12)]);
      case MapStructure.tree:
        root(const Rect.fromLTWH(8, 3, 16, 7));
        canvas.drawPath(
          Path()
            ..moveTo(12, 10)
            ..lineTo(12, 33)
            ..moveTo(12, 18)
            ..lineTo(18, 18)
            ..moveTo(12, 26)
            ..lineTo(18, 26)
            ..moveTo(12, 33)
            ..lineTo(18, 33),
          line,
        );
        leaves([(21, 18, 16), (21, 26, 22), (21, 33, 12)]);
    }
  }

  @override
  bool shouldRepaint(StructureThumbPainter old) => old.structure != structure || old.color != color;
}

/// A small map in a palette: the center topic and five branches with their
/// line colors and first-level topics.
class PaletteThumbPainter extends CustomPainter {
  const PaletteThumbPainter(this.palette, this.colors);

  final MMMapColors palette;
  final MMColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.canvas);
    // Drawn on a 90 × 44 grid, centered.
    final scale = size.height / 44;
    canvas
      ..translate(size.width / 2 - 45 * scale, 0)
      ..scale(scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(33, 17, 24, 10), const Radius.circular(4)),
      Paint()..color = palette.root,
    );
    final branches = [
      (57.0, 70.0, 8.0),
      (57.0, 70.0, 22.0),
      (57.0, 70.0, 36.0),
      (33.0, 20.0, 12.0),
      (33.0, 20.0, 32.0),
    ];
    for (var i = 0; i < branches.length; i++) {
      final (from, to, y) = branches[i];
      final mid = (from + to) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(from, 22)
          ..cubicTo(mid, 22, mid, y, to, y),
        Paint()
          ..color = palette.line(i, colors)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      final topic = RRect.fromRectAndRadius(
        Rect.fromLTWH(to > from ? to : to - 14, y - 3.5, 14, 7),
        const Radius.circular(3),
      );
      canvas.drawRRect(topic, Paint()..color = palette.topicFill(i, colors));
      if (palette.topicBorder(i) case final border?) {
        canvas.drawRRect(
          topic,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(PaletteThumbPainter old) => old.palette != palette || old.colors != colors;
}
