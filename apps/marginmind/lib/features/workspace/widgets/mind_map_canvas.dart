import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

import '../../../shared/l10n.dart';

/// Id used for the root node (the study set itself) in layout and widgets.
const rootNodeId = '__root__';

/// The mind map: measured nodes laid out by mm_layout, curved connectors,
/// pan and zoom. Selection and actions are reported to the caller.
class MindMapCanvas extends StatefulWidget {
  const MindMapCanvas({
    super.key,
    required this.content,
    required this.rootTitle,
    required this.selectedCardId,
    required this.flashCardId,
    required this.transformation,
    required this.onSelect,
    required this.onReveal,
    required this.onRename,
    required this.onDelete,
    required this.focusNode,
    this.loaded = true,
  });

  /// False until the content has been read from disk; the first fit waits
  /// for it so it measures the real tree.
  final bool loaded;

  final StudySetContent content;
  final String rootTitle;
  final String? selectedCardId;
  final String? flashCardId;
  final TransformationController transformation;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onReveal;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;
  final FocusNode focusNode;

  @override
  State<MindMapCanvas> createState() => _MindMapCanvasState();
}

class _MindMapCanvasState extends State<MindMapCanvas> {
  bool _centered = false;
  TreeLayoutResult? _layout;
  Size _viewport = Size.zero;

  /// First time the map is shown: scale down (to 60% at most) so the whole
  /// tree fits, and center it. Later the user's pan/zoom is kept.
  void _fitOnce(TreeLayoutResult result, BoxConstraints viewport) {
    if (_centered || !widget.loaded || !viewport.hasBoundedHeight || !viewport.hasBoundedWidth) return;
    _centered = true;
    final w = viewport.maxWidth, h = viewport.maxHeight;
    final scale = math.min(1.0, math.min((w - 24) / result.width, (h - 24) / result.height)).clamp(0.6, 1.0);
    final root = result.rects[rootNodeId]!;
    final fitsWidth = result.width * scale <= w;
    final dx = fitsWidth ? (w - result.width * scale) / 2 : w * 0.04 - (root.left - 24) * scale;
    final dy = h / 2 - root.centerY * scale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.transformation.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    });
  }

  @override
  void didUpdateWidget(MindMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.flashCardId;
    if (id != null && id != oldWidget.flashCardId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(id));
    }
  }

  /// Pans (keeping the zoom) so a newly created or linked node is on screen.
  void _ensureVisible(String id) {
    final rect = _layout?.rects[id];
    if (!mounted || rect == null || _viewport.isEmpty) return;
    final m = widget.transformation.value;
    final scale = m.getMaxScaleOnAxis();
    final tx = m.storage[12], ty = m.storage[13];
    final left = rect.left * scale + tx, right = rect.right * scale + tx;
    final top = rect.top * scale + ty, bottom = rect.bottom * scale + ty;
    const margin = 32.0;
    var dx = 0.0, dy = 0.0;
    if (right > _viewport.width - margin) dx = _viewport.width - margin - right;
    if (left + dx < margin) dx = margin - left;
    if (bottom > _viewport.height - margin) dy = _viewport.height - margin - bottom;
    if (top + dy < margin + 48) dy = margin + 48 - top;
    if (dx == 0 && dy == 0) return;
    widget.transformation.value = m.clone()..setTranslationRaw(tx + dx, ty + dy, 0);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _build);

  Widget _build(BuildContext context, BoxConstraints viewport) {
    final l = context.l10n;
    final c = context.mmColors;
    final specs = <String, _NodeSpec>{};

    LayoutNode build(String id, _NodeSpec spec) {
      specs[id] = spec;
      final children = widget.content.childrenOf(id == rootNodeId ? null : id);
      return LayoutNode(
        id: id,
        width: spec.size.width,
        height: spec.size.height,
        children: [
          for (final n in children)
            if (widget.content.card(n.cardId) case final card?)
              build(card.id, _NodeSpec.forCard(card, widget.content, l)),
        ],
      );
    }

    final tree = build(rootNodeId, _NodeSpec.root(widget.rootTitle.isEmpty ? l.appName : widget.rootTitle));
    final result = const TreeLayout(levelGap: 56, siblingGap: 14, padding: 72).layout(tree);
    _layout = result;
    _viewport = Size(viewport.maxWidth, viewport.maxHeight);
    _fitOnce(result, viewport);

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
          widget.onDelete();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter && widget.selectedCardId != null) {
          widget.onRename(widget.selectedCardId!);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          widget.onSelect(null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InteractiveViewer(
        transformationController: widget.transformation,
        constrained: false,
        minScale: 0.3,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(600),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            widget.focusNode.requestFocus();
            widget.onSelect(null);
          },
          child: SizedBox(
            width: math.max(result.width, 600),
            height: math.max(result.height, 400),
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _EdgesPainter(result, c.line))),
                for (final e in result.rects.entries)
                  Positioned(
                    left: e.value.left,
                    top: e.value.top,
                    width: e.value.width,
                    height: e.value.height,
                    child: _NodeView(
                      spec: specs[e.key]!,
                      selected: e.key == (widget.selectedCardId ?? rootNodeId),
                      flashing: e.key == widget.flashCardId,
                      onTap: () {
                        widget.focusNode.requestFocus();
                        widget.onSelect(e.key == rootNodeId ? null : e.key);
                      },
                      onDoubleTap: e.key == rootNodeId ? null : () => widget.onRename(e.key),
                      onReveal: specs[e.key]!.kind == _Kind.excerpt ? () => widget.onReveal(e.key) : null,
                      revealLabel: l.revealSource,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Kind { root, topic, excerpt, note }

/// What a node shows, and its measured size (layout needs sizes up front).
class _NodeSpec {
  _NodeSpec._(this.kind, this.title, this.quote, this.meta, this.color, this.size);

  final _Kind kind;
  final String title;
  final String? quote;
  final String? meta;
  final MMAnnotationColor? color;
  final Size size;

  static const excerptWidth = 240.0;
  static const _excerptTextWidth = excerptWidth - 12 - 38 - 16;

  factory _NodeSpec.root(String title) {
    final w = _measure(title, MMTypography.title3, 360).width;
    return _NodeSpec._(_Kind.root, title, null, null, null, Size(w + 40, 42));
  }

  factory _NodeSpec.forCard(Card card, StudySetContent content, AppLocalizations l) {
    switch (card.kind) {
      case CardKind.topic:
        final s = _measure(card.title, MMTypography.headline, 220 - 28);
        return _NodeSpec._(_Kind.topic, card.title, null, null, null, Size(s.width + 32, s.height + 18));
      case CardKind.note:
        final s = _measure(card.title, MMTypography.body.copyWith(height: 19 / 13), 230 - 44);
        return _NodeSpec._(_Kind.note, card.title, null, null, null, Size(s.width + 48, s.height + 16));
      case CardKind.excerpt:
        final a = content.annotation(card.annotationId ?? '');
        final doc = a == null ? null : content.document(a.documentId);
        final quote = a?.quote ?? '';
        final lines = math.min(4, _lines(quote, MMTypography.readingExcerpt, _excerptTextWidth));
        final height = 11 + 17 + 6 + (lines * 20 + 12) + 6 + 14 + 11 + 2;
        return _NodeSpec._(
          _Kind.excerpt,
          card.title.isEmpty ? l.untitledExcerpt : card.title,
          quote,
          doc == null ? null : '${doc.title} · ${l.pageNumber(a!.page)}',
          MMAnnotationColor.fromIndex(a?.colorIndex ?? 0),
          Size(excerptWidth, height.toDouble()),
        );
    }
  }

  static Size _measure(String text, TextStyle style, double maxWidth) {
    final p = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return Size(p.width.ceilToDouble(), p.height.ceilToDouble());
  }

  static int _lines(String text, TextStyle style, double width) {
    final p = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    return math.max(1, p.computeLineMetrics().length);
  }
}

class _NodeView extends StatelessWidget {
  const _NodeView({
    required this.spec,
    required this.selected,
    required this.flashing,
    required this.onTap,
    required this.onDoubleTap,
    required this.onReveal,
    required this.revealLabel,
  });

  final _NodeSpec spec;
  final bool selected;
  final bool flashing;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onReveal;
  final String revealLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final ring = [
      if (selected || flashing) BoxShadow(color: c.accent, spreadRadius: 3),
      if (flashing) BoxShadow(color: c.accentTint, spreadRadius: 9),
    ];
    final (Color bg, double radius, List<BoxShadow> shadow) = switch (spec.kind) {
      _Kind.root => (
        c.rootNode,
        14.0,
        [const BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      _Kind.topic => (Color.alphaBlend(c.fill, c.canvas), 12.0, const <BoxShadow>[]),
      _Kind.excerpt => (c.card, 12.0, c.cardShadow),
      _Kind.note => (Color.alphaBlend(c.quaternaryFill, c.canvas), 12.0, const <BoxShadow>[]),
    };

    final Widget body = switch (spec.kind) {
      _Kind.root => Center(
        child: Text(
          spec.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.title3.copyWith(color: c.onRootNode),
        ),
      ),
      _Kind.topic => Center(child: Text(spec.title, style: t.headline)),
      _Kind.note => Row(
        children: [
          Opacity(opacity: 0.6, child: Icon(MMIcons.pen, size: 13, color: c.label)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(spec.title, style: t.body.copyWith(height: 19 / 13)),
          ),
        ],
      ),
      _Kind.excerpt => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: spec.color!.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  spec.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.headline.copyWith(height: 17 / 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: spec.color!.cardTint,
              borderRadius: BorderRadius.circular(MMRadii.excerpt),
            ),
            child: Text(spec.quote ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, style: t.readingExcerpt),
          ),
          const SizedBox(height: 6),
          Text(spec.meta ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
        ],
      ),
    };

    final padding = switch (spec.kind) {
      _Kind.root => const EdgeInsets.symmetric(horizontal: 18),
      _Kind.topic => const EdgeInsets.symmetric(horizontal: 14),
      _Kind.excerpt => const EdgeInsets.fromLTRB(12, 11, 38, 11),
      _Kind.note => const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    };

    return MMInteractive(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      selected: selected,
      semanticLabel: spec.title,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.standard,
        padding: padding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [...shadow, ...ring],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: body),
            if (onReveal != null)
              Positioned(
                top: -3,
                right: -30,
                child: MMIconButton(
                  icon: MMIcons.revealSource,
                  tooltip: revealLabel,
                  size: 22,
                  iconSize: 11,
                  onPressed: onReveal,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter(this.layout, this.color);

  final TreeLayoutResult layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final e in layout.edges) {
      final a = layout.rects[e.parentId]!;
      final b = layout.rects[e.childId]!;
      final start = Offset(a.right, a.centerY);
      final end = Offset(b.left, b.centerY);
      final midX = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EdgesPainter old) => old.layout != layout || old.color != color;
}
