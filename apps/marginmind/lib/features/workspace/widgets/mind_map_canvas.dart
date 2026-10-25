import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

import '../../../shared/l10n.dart';
import '../../../app/app_commands.dart';
import 'card_field.dart';
import 'map_drop.dart';

part 'mind_map_cache.dart';

/// Id used for the root node (the study set itself) in layout and widgets.
const rootNodeId = '__root__';

/// Zoom of a map transform. Pan/zoom only scale x and y, so
/// `getMaxScaleOnAxis` (which also counts z, always 1) would be wrong.
double mapScale(Matrix4 m) => m.storage[0];

/// Zoom limits shared by gestures, the zoom buttons and "fit": fitting a
/// large map may go far below 100%, and zooming out from there must not
/// jump back in.
const mapMinScale = 0.05;
const mapMaxScale = 2.5;

/// While dragging a node, the canvas pans when the pointer is within this
/// distance of its sides (or outside them), up to [_autoScrollSpeed]
/// logical pixels per second.
const _autoScrollEdge = 48.0;
const _autoScrollSpeed = 900.0;

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
    required this.onMove,
    required this.onToggleCollapsed,
    required this.onNavigate,
    required this.onAddChild,
    required this.onShift,
    this.onCommand,
    this.selectedCardIds = const {},
    this.onToggleSelection,
    this.onSelectMany,
    this.editingCardId,
    this.onEditDone,
    this.onEditCancel,
    this.onContextMenu,
    this.loaded = true,
  });

  /// False until the content has been read from disk; the first fit waits
  /// for it so it measures the real tree.
  final bool loaded;

  final StudySetContent content;
  final String rootTitle;
  final String? selectedCardId;
  final Set<String> selectedCardIds;
  final ValueChanged<String>? onToggleSelection;
  final ValueChanged<Set<String>>? onSelectMany;
  final String? flashCardId;
  final TransformationController transformation;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onReveal;

  /// Double-click, F2, Space or typing on a selected node. The caller
  /// answers by setting [editingCardId].
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;
  final FocusNode focusNode;

  /// Drag and drop: move a card under a parent (null = root) at an index
  /// among the new siblings (null = last).
  final void Function(String cardId, String? parentId, int? index) onMove;
  final ValueChanged<String> onToggleCollapsed;
  final ValueChanged<AxisDirection> onNavigate;

  /// Tab: new child topic under the selection.
  final VoidCallback onAddChild;

  /// ⌘↑ / ⌘↓.
  final ValueChanged<int> onShift;

  final ValueChanged<MindMapCommand>? onCommand;

  /// Card whose title (a note's text) is shown as a text field.
  final String? editingCardId;

  /// Enter or clicking elsewhere, with the typed text.
  final ValueChanged<String>? onEditDone;

  /// Esc.
  final VoidCallback? onEditCancel;

  /// Right click on a node (card id, or null for the root).
  final void Function(String? cardId, Offset globalPosition)? onContextMenu;

  @override
  State<MindMapCanvas> createState() => _MindMapCanvasState();
}

class _MindMapCanvasState extends State<MindMapCanvas> with TickerProviderStateMixin, CardFieldHost<MindMapCanvas> {
  bool _centered = false;
  final _tapModifiers = <String, bool>{};
  Offset? _boxStart;
  Offset? _boxEnd;
  Set<String> _boxInitial = {};

  bool get _additive =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  void _select(String? id, {required bool additive}) {
    if (id != null && additive && widget.onToggleSelection != null) {
      widget.onToggleSelection!(id);
    } else {
      widget.onSelect(id);
    }
  }

  TreeLayoutResult? _layout;
  final _cache = MindMapRenderCache();

  /// Moves nodes from where they were drawn to a new layout, so neighbors
  /// make way smoothly while a title grows.
  late final _motion = AnimationController(vsync: this, duration: MMMotion.standard, value: 1);
  Map<String, Rect> _from = const {};

  @override
  String? get editingCardId => widget.editingCardId;
  @override
  StudySetContent get fieldContent => widget.content;
  @override
  FocusNode get hostFocus => widget.focusNode;
  @override
  ValueChanged<String>? get onFieldDone => widget.onEditDone;
  @override
  VoidCallback? get onFieldCancel => widget.onEditCancel;
  @override
  void fieldOpened(String id) => _ensureVisible(id);

  @override
  void initState() {
    super.initState();
    syncField();
    _motion.addListener(() {
      if (field == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && field != null) _ensureVisible(field!.id);
      });
    });
  }

  @override
  void dispose() {
    disposeField();
    _autoScroll.dispose();
    _motion.dispose();
    super.dispose();
  }

  bool _isCard(String? id) => id != null && id != rootNodeId && _cache._specs.containsKey(id);

  /// Records where every node is drawn now when the layout changes, so
  /// the next frames can move them to the new layout. Offsets are kept
  /// relative to the root, which [_keepRootInPlace] holds still.
  void _animateTo(TreeLayoutResult next, TreeLayoutResult? previous) {
    if (previous == null || identical(previous, next)) return;
    if (!_centered || MMAppearance.reduceMotionOf(context)) {
      _from = const {};
      return;
    }
    final shift = _rect(next.rects[rootNodeId]!).topLeft - _rect(previous.rects[rootNodeId]!).topLeft;
    _from = {
      for (final e in next.rects.entries)
        if (previous.rects[e.key] case final old?) e.key: _drawn(e.key, old).shift(shift),
    };
    _motion.forward(from: 0);
  }

  /// Where [id] is drawn in the current frame, on its way to [target].
  Rect _drawn(String id, LayoutRect target) =>
      _lerpRect(_from[id], _rect(target), MMMotion.layoutCurve.transform(_motion.value));

  /// Like [_drawn], but the node being edited takes its new size at once
  /// (the text must fit as it is typed) while it moves with the others.
  Rect _shown(String id, LayoutRect target) {
    final drawn = _drawn(id, target);
    if (id != field?.id) return drawn;
    return Rect.fromLTWH(drawn.left, drawn.center.dy - target.height / 2, target.width, target.height);
  }

  Widget _fieldNode(String id, _NodeSpec spec, LayoutRect target) {
    final f = field!;
    final t = context.mmText;
    final (style, kind, maxLines) = switch (spec.kind) {
      _Kind.note => (t.body.copyWith(height: 19 / 13), CardKind.note, null),
      _Kind.excerpt => (t.headline.copyWith(height: 17 / 13), CardKind.excerpt, 1),
      _ => (t.headline, CardKind.topic, null),
    };
    return Positioned.fromRect(
      key: ValueKey(id),
      rect: _shown(id, target),
      child: _NodeView(
        spec: spec,
        selected: true,
        flashing: false,
        onTap: () {},
        onDoubleTap: null,
        onSecondaryTapUp: null,
        onReveal: null,
        revealLabel: '',
        editor: fieldEditor(f, style: style, kind: kind, label: spec.title, maxLines: maxLines),
      ),
    );
  }

  /// Where the root was in the last layout. When the tree changes shape
  /// (fold, move, add) the view is shifted so the root stays put on screen.
  Offset? _rootAnchor;
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
    syncField();
    typed = null;
    // The tree can change under a drag (undo, another window); the drop
    // must follow what is drawn.
    if (_dragging != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateDrop();
      });
    }
    if (_boxStart == null &&
        (widget.selectedCardId != oldWidget.selectedCardId || widget.flashCardId != oldWidget.flashCardId)) {
      final id = widget.flashCardId != oldWidget.flashCardId && widget.flashCardId != null
          ? widget.flashCardId!
          : widget.selectedCardId ?? rootNodeId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(id));
    }
  }

  void _keepRootInPlace(TreeLayoutResult result) {
    final root = result.rects[rootNodeId]!;
    final anchor = Offset(root.left, root.top);
    final previous = _rootAnchor;
    _rootAnchor = anchor;
    if (!_centered || previous == null || previous == anchor) return;
    final m = widget.transformation.value;
    final scale = mapScale(m);
    final delta = (previous - anchor) * scale;
    widget.transformation.value = m.clone()..setTranslationRaw(m.storage[12] + delta.dx, m.storage[13] + delta.dy, 0);
  }

  /// Pans (keeping the zoom) so a newly created or linked node is on screen.
  void _ensureVisible(String id) {
    final rect = _layout?.rects[id];
    if (!mounted || rect == null || _viewport.isEmpty) return;
    final m = widget.transformation.value;
    final scale = mapScale(m);
    final tx = m.storage[12], ty = m.storage[13];
    final shown = _shown(id, rect);
    final left = shown.left * scale + tx, right = shown.right * scale + tx;
    final top = shown.top * scale + ty, bottom = shown.bottom * scale + ty;
    const margin = MMSpacing.xxxl;
    var dx = 0.0, dy = 0.0;
    if (right > _viewport.width - margin) dx = _viewport.width - margin - right;
    if (left + dx < margin) dx = margin - left;
    if (bottom > _viewport.height - margin) dy = _viewport.height - margin - bottom;
    if (top + dy < margin + MMSpacing.xxxl + MMSpacing.l) dy = margin + MMSpacing.xxxl + MMSpacing.l - top;
    if (dx == 0 && dy == 0) return;
    widget.transformation.value = m.clone()..setTranslationRaw(tx + dx, ty + dy, 0);
  }

  void _command(MindMapCommand command) {
    final selected = widget.selectedCardId;
    switch (command) {
      case MindMapCommand.child:
        widget.onAddChild();
      case MindMapCommand.edit:
        if (selected != null) widget.onRename(selected);
      case MindMapCommand.delete:
        if (selected != null) widget.onDelete();
      case MindMapCommand.fold:
        if (selected != null) widget.onToggleCollapsed(selected);
      case MindMapCommand.up || MindMapCommand.down:
        if (selected != null) widget.onShift(command == MindMapCommand.up ? -1 : 1);
      case MindMapCommand.fit:
        final layout = _layout;
        if (layout == null || _viewport.isEmpty) return;
        final scale = math
            .min(
              (_viewport.width - MMSpacing.xl * 2) / layout.width,
              (_viewport.height - MMSpacing.xl * 2) / layout.height,
            )
            .clamp(mapMinScale, 1.0);
        widget.transformation.value = Matrix4.identity()
          ..translateByDouble(
            (_viewport.width - layout.width * scale) / 2,
            (_viewport.height - layout.height * scale) / 2,
            0,
            1,
          )
          ..scaleByDouble(scale, scale, 1, 1);
      case MindMapCommand.center:
        final rect = _layout?.rects[selected ?? rootNodeId];
        if (rect == null || _viewport.isEmpty) return;
        final m = widget.transformation.value;
        final scale = mapScale(m);
        widget.transformation.value = m.clone()
          ..setTranslationRaw(
            _viewport.width / 2 - (rect.left + rect.width / 2) * scale,
            _viewport.height / 2 - rect.centerY * scale,
            0,
          );
      case MindMapCommand.copy || MindMapCommand.cut || MindMapCommand.paste:
        widget.onCommand?.call(command);
      case MindMapCommand.siblingAfter ||
          MindMapCommand.siblingBefore ||
          MindMapCommand.parent ||
          MindMapCommand.promote:
        if (selected != null) widget.onCommand?.call(command);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _build);

  /// Nodes being dragged (the selection when the grabbed node is in it),
  /// the pointer in global coordinates, and where they would land. The
  /// pointer comes from the canvas listener: `Draggable` reports its first
  /// update at the press position, not where the pointer is.
  Set<String>? _dragging;
  Offset? _dragPointer;
  MapDrop? _drop;
  late final Ticker _autoScroll = createTicker(_autoScrollTick);
  Duration _lastScrollTick = Duration.zero;

  Map<String, Rect> _drawnRects() => {
    for (final e in _layout?.rects.entries ?? const <MapEntry<String, LayoutRect>>[]) e.key: _drawn(e.key, e.value),
  };

  void _startDrag(String id) {
    final moving = widget.selectedCardIds.contains(id) ? widget.selectedCardIds : {id};
    if (!widget.selectedCardIds.contains(id)) widget.onSelect(id);
    setState(() => _dragging = {...moving});
  }

  void _updateDrag() {
    final global = _dragPointer;
    _updateDrop();
    final box = context.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.hasSize) return;
    final scrolling =
        autoScrollVelocity(box.globalToLocal(global), box.size, edge: _autoScrollEdge, maxSpeed: _autoScrollSpeed) !=
        Offset.zero;
    if (scrolling && !_autoScroll.isActive) {
      _lastScrollTick = Duration.zero;
      _autoScroll.start();
    } else if (!scrolling && _autoScroll.isActive) {
      _autoScroll.stop();
    }
  }

  /// Recomputes the drop for the pointer as the map is now drawn; called on
  /// every move and after every auto-scroll step. Outside the canvas there
  /// is no drop.
  void _updateDrop() {
    final pointer = _dragPointer, moving = _dragging;
    final box = context.findRenderObject() as RenderBox?;
    MapDrop? next;
    if (pointer != null && moving != null && box != null && box.hasSize) {
      final local = box.globalToLocal(pointer);
      if ((Offset.zero & box.size).contains(local)) {
        next = MapDrop.resolve(
          point: widget.transformation.toScene(local),
          rects: _drawnRects(),
          content: widget.content,
          moving: moving,
          rootId: rootNodeId,
          gap: _siblingGap,
        );
      }
    }
    if (next != _drop) setState(() => _drop = next);
  }

  void _autoScrollTick(Duration elapsed) {
    final dt = (elapsed - _lastScrollTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastScrollTick = elapsed;
    final pointer = _dragPointer, layout = _layout;
    final box = context.findRenderObject() as RenderBox?;
    if (pointer == null || layout == null || box == null || !box.hasSize || dt <= 0) return;
    final velocity = autoScrollVelocity(
      box.globalToLocal(pointer),
      box.size,
      edge: _autoScrollEdge,
      maxSpeed: _autoScrollSpeed,
    );
    final m = widget.transformation.value;
    final scale = mapScale(m);
    final current = Offset(m.storage[12], m.storage[13]);
    final next = clampAutoScroll(
      current,
      velocity * dt,
      Rect.fromLTWH(current.dx, current.dy, layout.width * scale, layout.height * scale),
      box.size,
      margin: _autoScrollEdge,
    );
    if (next == current) return;
    widget.transformation.value = m.clone()..setTranslationRaw(next.dx, next.dy, 0);
    _updateDrop();
  }

  /// Drops on the target last shown, whatever is under the pointer now.
  /// Without [grabbed] the drag is only cleared.
  void _endDrag(String? grabbed) {
    if (_dragging == null) return;
    final drop = _drop;
    _autoScroll.stop();
    setState(() {
      _dragging = null;
      _drop = null;
    });
    if (drop != null && grabbed != null) widget.onMove(grabbed, drop.parentId, drop.index);
  }

  /// The pointer is released before the drag ends. If the dragged node was
  /// removed or folded away meanwhile, its `Draggable` never reports the
  /// end, so clear what is left once this event has been handled.
  void _afterPointerUp() {
    if (_dragging == null) return;
    scheduleMicrotask(() {
      if (mounted) _endDrag(null);
    });
  }

  Widget _draggable(String id, _NodeSpec spec, Widget child) {
    if (id == rootNodeId) return child;
    final scale = mapScale(widget.transformation.value);
    final count = widget.selectedCardIds.contains(id) ? widget.selectedCardIds.length : 1;
    return Draggable<String>(
      data: id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => _startDrag(id),
      onDragUpdate: (_) => _updateDrag(),
      onDragEnd: (_) => _endDrag(id),
      feedback: Transform.translate(
        offset: const Offset(-12, -12),
        child: Opacity(
          opacity: 0.85,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: spec.size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: _NodeView(
                      spec: spec,
                      selected: true,
                      flashing: false,
                      onTap: () {},
                      onDoubleTap: null,
                      onSecondaryTapUp: null,
                      onReveal: null,
                      revealLabel: '',
                    ),
                  ),
                  if (count > 1) Positioned(top: -MMSpacing.s, right: -MMSpacing.s, child: _CountBadge(count)),
                ],
              ),
            ),
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _build(BuildContext context, BoxConstraints viewport) {
    final l = context.l10n;
    final c = context.mmColors;
    final field = this.field;
    final result = _cache.update(
      draft: field == null ? null : (field.id, field.controller.text),
      content: widget.content,
      rootTitle: widget.rootTitle,
      localizations: l,
      theme: Theme.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.localeOf(context),
      textDirection: Directionality.of(context),
    );
    final specs = _cache._specs;
    _tapModifiers.removeWhere((id, _) => !specs.containsKey(id));
    final collapsed = _cache._collapsed;
    final expandable = _cache._expandable;
    if (field != null) trackField(shown: specs.containsKey(field.id));
    final layoutChanged = !identical(result, _layout);
    _animateTo(result, _layout);
    _layout = result;
    final viewportChanged = _viewport != Size(viewport.maxWidth, viewport.maxHeight);
    _viewport = Size(viewport.maxWidth, viewport.maxHeight);
    _fitOnce(result, viewport);
    _keepRootInPlace(result);
    if ((layoutChanged || viewportChanged) && _centered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureVisible(widget.editingCardId ?? widget.selectedCardId ?? rootNodeId);
      });
    }

    // Built once per frame of content; the animation only moves them.
    final nodes = {
      for (final e in result.rects.entries)
        if (e.key != field?.id)
          e.key: RepaintBoundary(
            child: Opacity(
              opacity: _dragging?.contains(e.key) ?? false ? 0.35 : 1,
              child: _draggable(
                e.key,
                specs[e.key]!,
                _NodeView(
                  spec: specs[e.key]!,
                  selected: widget.selectedCardIds.contains(e.key) || e.key == (widget.selectedCardId ?? rootNodeId),
                  flashing: e.key == widget.flashCardId,
                  onPressStart: () => _tapModifiers[e.key] = _additive,
                  onTap: () {
                    widget.focusNode.requestFocus();
                    _select(e.key == rootNodeId ? null : e.key, additive: _tapModifiers.remove(e.key) ?? false);
                  },
                  onDoubleTap: e.key == rootNodeId ? null : () => widget.onRename(e.key),
                  onSecondaryTapUp: widget.onContextMenu == null
                      ? null
                      : (position) {
                          widget.focusNode.requestFocus();
                          final id = e.key == rootNodeId ? null : e.key;
                          if (id == null || !widget.selectedCardIds.contains(id)) widget.onSelect(id);
                          widget.onContextMenu!(id, position);
                        },
                  onReveal: specs[e.key]!.kind == _Kind.excerpt ? () => widget.onReveal(e.key) : null,
                  revealLabel: l.revealSource,
                ),
              ),
            ),
          ),
    };
    final foldButtons = {
      for (final id in expandable)
        id: _FoldButton(
          hiddenCount: collapsed[id],
          tooltip: collapsed.containsKey(id) ? l.expandNode : l.collapseNode,
          onPressed: () => widget.onToggleCollapsed(id),
        ),
    };

    return Actions(
      actions: <Type, Action<Intent>>{
        MindMapIntent: CallbackAction<MindMapIntent>(
          onInvoke: (intent) {
            if (field == null) _command(intent.command);
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (_, event) {
          // Keys the text field leaves alone must not act on the map.
          if (event is! KeyDownEvent || field != null) return KeyEventResult.ignored;
          final key = event.logicalKey;
          final selected = widget.selectedCardId;
          for (final entry in mindMapShortcuts.entries) {
            if (entry.key.accepts(event, HardwareKeyboard.instance)) {
              _command(entry.value);
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.escape) {
            widget.onSelect(null);
            return KeyEventResult.handled;
          }
          final meta = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
          final direction = switch (key) {
            LogicalKeyboardKey.arrowLeft => AxisDirection.left,
            LogicalKeyboardKey.arrowRight => AxisDirection.right,
            LogicalKeyboardKey.arrowUp => AxisDirection.up,
            LogicalKeyboardKey.arrowDown => AxisDirection.down,
            _ => null,
          };
          if (direction == null) {
            if (!_isCard(selected) || !isTypingKey(event)) return KeyEventResult.ignored;
            typed = event.character;
            widget.onRename(selected!);
            return KeyEventResult.handled;
          }
          if (meta && (direction == AxisDirection.up || direction == AxisDirection.down)) {
            widget.onShift(direction == AxisDirection.up ? -1 : 1);
          } else {
            widget.onNavigate(direction);
          }
          return KeyEventResult.handled;
        },
        child: Listener(
          onPointerDown: (event) {
            if (field != null || widget.onSelectMany == null || event.buttons != 1) return;
            final scene = widget.transformation.toScene(event.localPosition);
            if (result.rects.entries.any((e) => _drawn(e.key, e.value).inflate(MMSpacing.s).contains(scene))) return;
            widget.focusNode.requestFocus();
            setState(() {
              _boxStart = scene;
              _boxEnd = scene;
              _boxInitial = _additive ? {...widget.selectedCardIds} : {};
            });
          },
          onPointerMove: (event) {
            _dragPointer = event.position;
            if (_boxStart == null) return;
            setState(() => _boxEnd = widget.transformation.toScene(event.localPosition));
            final box = Rect.fromPoints(_boxStart!, _boxEnd!);
            widget.onSelectMany!({
              ..._boxInitial,
              for (final e in result.rects.entries)
                if (e.key != rootNodeId && box.overlaps(_drawn(e.key, e.value))) e.key,
            });
          },
          onPointerUp: (_) {
            _afterPointerUp();
            setState(() {
              _boxStart = null;
              _boxEnd = null;
            });
          },
          // Runs before the drag ends, so a cancelled drag drops nothing.
          onPointerCancel: (_) {
            _afterPointerUp();
            setState(() {
              _boxStart = null;
              _boxEnd = null;
              _drop = null;
            });
          },
          child: InteractiveViewer(
            panEnabled: _boxStart == null,
            transformationController: widget.transformation,
            constrained: false,
            minScale: mapMinScale,
            maxScale: mapMaxScale,
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
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) => Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: const ValueKey('mind-map-edges'),
                            painter: _EdgesPainter(
                              result,
                              c.line,
                              _motion.isAnimating ? _from : const {},
                              _motion.value,
                            ),
                          ),
                        ),
                      ),
                      for (final e in result.rects.entries)
                        if (e.key == field?.id)
                          _fieldNode(e.key, specs[e.key]!, e.value)
                        else
                          Positioned.fromRect(key: ValueKey(e.key), rect: _drawn(e.key, e.value), child: nodes[e.key]!),
                      if (_boxStart != null && _boxEnd != null)
                        Positioned.fromRect(
                          rect: Rect.fromPoints(_boxStart!, _boxEnd!),
                          child: IgnorePointer(
                            child: DecoratedBox(
                              key: const ValueKey('map-selection-box'),
                              decoration: BoxDecoration(
                                color: c.accentTint,
                                border: Border.all(color: c.accent),
                              ),
                            ),
                          ),
                        ),
                      if (_drop case final drop?)
                        if (drop.previewRect(_drawnRects(), gap: _siblingGap, thickness: 3) case final rect?)
                          Positioned.fromRect(
                            rect: rect,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                key: const ValueKey('map-drop-preview'),
                                decoration: drop.zone == MapDropZone.child
                                    ? BoxDecoration(
                                        borderRadius: BorderRadius.circular(MMRadii.card),
                                        border: Border.all(color: c.accent, width: 2),
                                      )
                                    : BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
                              ),
                            ),
                          ),
                      for (final id in expandable)
                        if (result.rects[id] case final r?)
                          if (_shown(id, r) case final shown)
                            Positioned(left: shown.right + 3, top: shown.center.dy - 9, child: foldButtons[id]!),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeView extends StatelessWidget {
  const _NodeView({
    required this.spec,
    required this.selected,
    required this.flashing,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTapUp,
    required this.onReveal,
    required this.revealLabel,
    this.editor,
    this.onPressStart,
  });

  /// Replaces the title (a note's text) while it is edited in place; the
  /// node then takes no gestures of its own.
  final Widget? editor;
  final ValueChanged<Offset>? onSecondaryTapUp;
  final _NodeSpec spec;
  final bool selected;
  final bool flashing;
  final VoidCallback onTap;
  final VoidCallback? onPressStart;
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
      _Kind.topic => editor == null ? Center(child: Text(spec.title, style: t.headline)) : Center(child: editor),
      _Kind.note => Row(
        children: [
          Opacity(opacity: 0.6, child: Icon(MMIcons.pen, size: 13, color: c.label)),
          const SizedBox(width: 7),
          Expanded(
            child: editor ?? Text(spec.title, style: t.body.copyWith(height: 19 / 13)),
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
                child:
                    editor ??
                    Text(
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

    if (editor != null) return _decorated(c, bg, radius, shadow, ring, body, padding);
    return Listener(
      onPointerDown: (_) => onPressStart?.call(),
      child: GestureDetector(
        onSecondaryTapUp: onSecondaryTapUp == null ? null : (d) => onSecondaryTapUp!(d.globalPosition),
        child: _interactive(context, c, bg, radius, shadow, ring, body, padding),
      ),
    );
  }

  Widget _interactive(
    BuildContext context,
    MMColors c,
    Color bg,
    double radius,
    List<BoxShadow> shadow,
    List<BoxShadow> ring,
    Widget body,
    EdgeInsets padding,
  ) {
    return MMInteractive(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      selected: selected,
      semanticLabel: spec.title,
      builder: (context, s) => _decorated(c, bg, radius, shadow, ring, body, padding),
    );
  }

  Widget _decorated(
    MMColors c,
    Color bg,
    double radius,
    List<BoxShadow> shadow,
    List<BoxShadow> ring,
    Widget body,
    EdgeInsets padding,
  ) {
    return AnimatedContainer(
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
    );
  }
}

Rect _rect(LayoutRect r) => Rect.fromLTWH(r.left, r.top, r.width, r.height);

Rect _lerpRect(Rect? from, Rect to, double t) => from == null || t >= 1 ? to : Rect.lerp(from, to, t)!;

class _EdgesPainter extends CustomPainter {
  _EdgesPainter(this.layout, this.color, this.from, this.t);

  final TreeLayoutResult layout;
  final Color color;

  /// Where nodes started moving from; [t] is the progress toward [layout].
  final Map<String, Rect> from;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final e in layout.edges) {
      final a = _at(e.parentId);
      final b = _at(e.childId);
      final start = Offset(a.right, a.center.dy);
      final end = Offset(b.left, b.center.dy);
      final midX = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  Rect _at(String id) => _lerpRect(from[id], _rect(layout.rects[id]!), MMMotion.layoutCurve.transform(t));

  @override
  bool shouldRepaint(_EdgesPainter old) =>
      old.layout != layout || old.color != color || !identical(old.from, from) || old.t != t;
}

/// Number of nodes being dragged, on the drag feedback.
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs),
      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(9)),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: t.footnote.copyWith(color: c.onAccent, fontWeight: FontWeight.w600, height: 1),
      ),
    );
  }
}

/// Small disclosure dot to the right of a node with children: shows the
/// number of hidden children when collapsed, a minus when expanded.
class _FoldButton extends StatelessWidget {
  const _FoldButton({required this.hiddenCount, required this.tooltip, required this.onPressed});

  final int? hiddenCount;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final collapsed = hiddenCount != null;
    return MMInteractive(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      canRequestFocus: false,
      builder: (context, s) => AnimatedOpacity(
        duration: MMMotion.standard,
        opacity: collapsed || s.hovered ? 1 : 0.45,
        child: Container(
          constraints: const BoxConstraints(minWidth: 18),
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: collapsed ? c.accent : c.card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: collapsed ? c.accent : c.line, width: 1),
          ),
          alignment: Alignment.center,
          child: collapsed
              ? Text(
                  '$hiddenCount',
                  style: t.footnote.copyWith(color: c.onAccent, fontWeight: FontWeight.w600, height: 1),
                )
              : Icon(MMIcons.zoomOut, size: 10, color: c.secondaryLabel),
        ),
      ),
    );
  }
}
