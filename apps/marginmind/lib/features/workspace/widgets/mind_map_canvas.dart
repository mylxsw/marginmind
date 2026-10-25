import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

import '../../../shared/l10n.dart';
import '../../../app/app_commands.dart';

part 'mind_map_cache.dart';

/// Id used for the root node (the study set itself) in layout and widgets.
const rootNodeId = '__root__';

/// Zoom of a map transform. Pan/zoom only scale x and y, so
/// `getMaxScaleOnAxis` (which also counts z, always 1) would be wrong.
double mapScale(Matrix4 m) => m.storage[0];

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
  final String? flashCardId;
  final TransformationController transformation;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onReveal;

  /// Double-click, F2, Space or typing on a selected node. The caller
  /// answers by setting [editingCardId] for topics edited in place.
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

  /// Topic whose title is shown as a text field.
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

class _MindMapCanvasState extends State<MindMapCanvas> with SingleTickerProviderStateMixin {
  bool _centered = false;
  TreeLayoutResult? _layout;
  final _cache = MindMapRenderCache();

  /// Moves nodes from where they were drawn to a new layout, so neighbors
  /// make way smoothly while a title grows.
  late final _motion = AnimationController(vsync: this, duration: MMMotion.standard, value: 1);
  Map<String, Rect> _from = const {};

  _NodeField? _field;

  /// Text typed on a selected topic; it replaces the title in the field the
  /// caller opens next.
  String? _typed;

  @override
  void initState() {
    super.initState();
    _syncField();
    _motion.addListener(() {
      if (_field == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _field != null) _ensureVisible(_field!.id);
      });
    });
  }

  @override
  void dispose() {
    final field = _field;
    if (field != null && !field.ended) {
      // Closing the map confirms the edit, like clicking elsewhere.
      final done = widget.onEditDone;
      final text = field.controller.text;
      if (done != null) Future.microtask(() => done(text));
    }
    field?.dispose();
    _motion.dispose();
    super.dispose();
  }

  /// Opens or closes the text field to match [MindMapCanvas.editingCardId].
  void _syncField() {
    final id = widget.editingCardId;
    if (id == _field?.id) return;
    // Each field gets its own focus node: one that is already focused would
    // not open a text input connection for the next field.
    final old = _field;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _field = null;
    final typed = _typed;
    _typed = null;
    if (id == null) return;
    final text = typed ?? widget.content.card(id)?.title ?? '';
    final controller = TextEditingController(text: text)
      ..selection = typed == null
          ? TextSelection(baseOffset: 0, extentOffset: text.length)
          : TextSelection.collapsed(offset: text.length);
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    final field = _NodeField(id, controller, FocusNode(debugLabel: 'MindMapNodeField'));
    field.focus.addListener(() => _onFieldFocus(field));
    _field = field;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _field != field) return;
      field.focus.requestFocus();
      _ensureVisible(id);
    });
  }

  /// Focus left the field (a click elsewhere, another pane): confirm. Not
  /// when the app goes to the background; focus comes back on return.
  void _onFieldFocus(_NodeField field) {
    if (field.focus.hasFocus) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _endField(field, commit: true, refocus: false);
  }

  void _endField(_NodeField? field, {required bool commit, required bool refocus}) {
    if (field == null || field != _field || field.ended) return;
    field.ended = true;
    if (refocus) widget.focusNode.requestFocus();
    if (commit) {
      widget.onEditDone?.call(field.controller.text);
    } else {
      widget.onEditCancel?.call();
    }
  }

  /// Printable text without ⌘ / Ctrl / ⌥; excludes the private-use range
  /// macOS reports for function and arrow keys.
  static bool _isTyping(KeyEvent event) {
    final character = event.character;
    if (character == null || character.isEmpty) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isControlPressed || keyboard.isAltPressed) return false;
    return character.runes.every((r) => r >= 0x20 && r != 0x7f && (r < 0xf700 || r > 0xf8ff));
  }

  bool _isTopic(String? id) => id != null && _cache._specs[id]?.kind == _Kind.topic;

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
    if (id != _field?.id) return drawn;
    return Rect.fromLTWH(drawn.left, drawn.center.dy - target.height / 2, target.width, target.height);
  }

  Widget _fieldNode(String id, _NodeSpec spec, LayoutRect target) {
    final field = _field!;
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
        editor: MMInlineTextField(
          controller: field.controller,
          focusNode: field.focus,
          style: context.mmText.headline,
          semanticLabel: spec.title,
          onSubmitted: () => _endField(field, commit: true, refocus: true),
          onCancel: () => _endField(field, commit: false, refocus: true),
          onTapOutside: () => _endField(field, commit: true, refocus: false),
        ),
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
    _syncField();
    _typed = null;
    if (widget.selectedCardId != oldWidget.selectedCardId || widget.flashCardId != oldWidget.flashCardId) {
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
            .clamp(0.01, 1.0);
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
      case MindMapCommand.siblingAfter ||
          MindMapCommand.siblingBefore ||
          MindMapCommand.parent ||
          MindMapCommand.promote:
        if (selected != null) widget.onCommand?.call(command);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _build);

  /// A node can't be dropped onto itself or its own descendants.
  bool _canDrop(String dragged, String target) {
    if (dragged == target) return false;
    if (target == rootNodeId) return true;
    String? id = target;
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      if (id == dragged) return false;
      id = widget.content.node(id)?.parentId;
    }
    return true;
  }

  void _drop(String dragged, String target, _Zone zone) {
    if (target == rootNodeId || zone == _Zone.child) {
      widget.onMove(dragged, target == rootNodeId ? null : target, null);
      return;
    }
    final parent = widget.content.node(target)?.parentId;
    final siblings = [
      for (final n in widget.content.childrenOf(parent))
        if (n.cardId != dragged) n.cardId,
    ];
    final i = siblings.indexOf(target);
    widget.onMove(dragged, parent, zone == _Zone.before ? i : i + 1);
  }

  Widget _draggable(String id, _NodeSpec spec, Widget child) {
    if (id == rootNodeId) return child;
    final scale = mapScale(widget.transformation.value);
    return Draggable<String>(
      data: id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => widget.onSelect(id),
      feedback: Transform.translate(
        offset: const Offset(-12, -12),
        child: Opacity(
          opacity: 0.85,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: spec.size,
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
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }

  Widget _build(BuildContext context, BoxConstraints viewport) {
    final l = context.l10n;
    final c = context.mmColors;
    final field = _field;
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
    final collapsed = _cache._collapsed;
    final expandable = _cache._expandable;
    if (field != null && specs.containsKey(field.id)) {
      field.seen = true;
    } else if (field != null && field.seen && !field.ended) {
      // The node went away (deleted, folded away) while it was being edited.
      WidgetsBinding.instance.addPostFrameCallback((_) => _endField(field, commit: false, refocus: false));
    }
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
            child: _DropZone(
              id: e.key,
              canAccept: (dragged) => _canDrop(dragged, e.key),
              onDrop: (dragged, zone) => _drop(dragged, e.key, zone),
              child: _draggable(
                e.key,
                specs[e.key]!,
                _NodeView(
                  spec: specs[e.key]!,
                  selected: e.key == (widget.selectedCardId ?? rootNodeId),
                  flashing: e.key == widget.flashCardId,
                  onTap: () {
                    widget.focusNode.requestFocus();
                    widget.onSelect(e.key == rootNodeId ? null : e.key);
                  },
                  onDoubleTap: e.key == rootNodeId ? null : () => widget.onRename(e.key),
                  onSecondaryTapUp: widget.onContextMenu == null
                      ? null
                      : (position) {
                          widget.focusNode.requestFocus();
                          final id = e.key == rootNodeId ? null : e.key;
                          widget.onSelect(id);
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
            if (_field == null) _command(intent.command);
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (_, event) {
          // Keys the text field leaves alone must not act on the map.
          if (event is! KeyDownEvent || _field != null) return KeyEventResult.ignored;
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
            if (!_isTopic(selected) || !_isTyping(event)) return KeyEventResult.ignored;
            _typed = event.character;
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
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) => Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('mind-map-edges'),
                          painter: _EdgesPainter(result, c.line, _motion.isAnimating ? _from : const {}, _motion.value),
                        ),
                      ),
                    ),
                    for (final e in result.rects.entries)
                      if (e.key == field?.id)
                        _fieldNode(e.key, specs[e.key]!, e.value)
                      else
                        Positioned.fromRect(key: ValueKey(e.key), rect: _drawn(e.key, e.value), child: nodes[e.key]!),
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
  });

  /// Replaces the title while it is edited in place; the node then takes
  /// no gestures of its own.
  final Widget? editor;
  final ValueChanged<Offset>? onSecondaryTapUp;
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
      _Kind.topic => editor == null ? Center(child: Text(spec.title, style: t.headline)) : Center(child: editor),
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

    if (editor != null) return _decorated(c, bg, radius, shadow, ring, body, padding);
    return GestureDetector(
      onSecondaryTapUp: onSecondaryTapUp == null ? null : (d) => onSecondaryTapUp!(d.globalPosition),
      child: _interactive(context, c, bg, radius, shadow, ring, body, padding),
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

/// A node title open for editing. [ended] is set as soon as the edit is
/// confirmed or cancelled; the field stays on screen until the caller
/// clears [MindMapCanvas.editingCardId], so the saved title replaces it
/// without a flash of the old one.
class _NodeField {
  _NodeField(this.id, this.controller, this.focus);

  final String id;
  final TextEditingController controller;
  final FocusNode focus;
  bool ended = false;

  /// The node has been on the map; until then the content may lag behind
  /// the write that created it.
  bool seen = false;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

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

enum _Zone { before, child, after }

/// Accepts dragged nodes. The top and bottom quarter of a node insert
/// before / after it (a line shows where); the middle makes it the parent
/// (a ring shows it). The root only accepts children.
class _DropZone extends StatefulWidget {
  const _DropZone({required this.id, required this.canAccept, required this.onDrop, required this.child});

  final String id;
  final bool Function(String dragged) canAccept;
  final void Function(String dragged, _Zone zone) onDrop;
  final Widget child;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  _Zone? _zone;

  _Zone _zoneAt(Offset global) {
    if (widget.id == rootNodeId) return _Zone.child;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _Zone.child;
    final y = box.globalToLocal(global).dy / box.size.height;
    return y < 0.25
        ? _Zone.before
        : y > 0.75
        ? _Zone.after
        : _Zone.child;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => widget.canAccept(d.data),
      onMove: (d) {
        final zone = _zoneAt(d.offset);
        if (zone != _zone) setState(() => _zone = zone);
      },
      onLeave: (_) => setState(() => _zone = null),
      onAcceptWithDetails: (d) {
        final zone = _zoneAt(d.offset);
        setState(() => _zone = null);
        widget.onDrop(d.data, zone);
      },
      builder: (context, candidates, _) {
        final zone = candidates.isEmpty ? null : _zone;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: widget.child),
            if (zone == _Zone.child)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.accent, width: 2),
                    ),
                  ),
                ),
              ),
            if (zone == _Zone.before || zone == _Zone.after)
              Positioned(
                left: 0,
                right: 0,
                top: zone == _Zone.before ? -6 : null,
                bottom: zone == _Zone.after ? -6 : null,
                child: IgnorePointer(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
          ],
        );
      },
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
