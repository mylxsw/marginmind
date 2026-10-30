import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

import '../../../shared/card_image.dart';
import '../../../shared/l10n.dart';
import '../../../shared/note_text.dart';
import '../../../app/app_commands.dart';
import '../../assistant/widgets/dashed_border.dart';
import 'card_field.dart';
import 'map_drop.dart';
import 'mind_map_geometry.dart';
import 'mind_map_style.dart';

export 'mind_map_geometry.dart';
export 'mind_map_style.dart';

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

/// Default zoom for a readable first view. Explicit fit may go below it.
const mapReadableScale = 1.0;

/// [m] zoomed by [factor] (kept within [mapMinScale]..[mapMaxScale]) so the
/// point at [focal] (viewport coordinates) stays where it is.
Matrix4 zoomMapAt(Matrix4 m, Offset focal, double factor) {
  final current = mapScale(m);
  final f = (current * factor).clamp(mapMinScale, mapMaxScale) / current;
  return Matrix4.identity()
    ..translateByDouble(focal.dx, focal.dy, 0, 1)
    ..scaleByDouble(f, f, 1, 1)
    ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
    ..multiply(m);
}

/// The card width handle's hit area, centered on the card's edge.
const _resizeHandleWidth = 10.0;

/// Height of the note format bar, to decide whether it fits above a note.
const _formatBarHeight = 30.0;

/// Mouse wheel ticks scroll 20 logical pixels; ⌘ + wheel zooms by
/// e^(-delta / this) per event, like InteractiveViewer.
const _wheelZoomFactor = 200.0;

/// Explicit location restores the designed text size, retaining closer zoom.
const mapLocateScale = 1.0;

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
    this.mapId = MindMap.defaultId,
    required this.rootTitle,
    required this.selectedCardId,
    required this.flashCardId,
    this.flashCardIds = const {},
    this.locateCardTick = 0,
    this.onLocated,
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
    this.rootSelected = false,
    this.onSelectRoot,
    this.onAssistant,
    this.onToggleSelection,
    this.onSelectMany,
    this.editingCardId,
    this.onEditDone,
    this.onEditCancel,
    this.onContextMenu,
    this.loaded = true,
    this.selectedMarkId,
    this.editingMarkId,
    this.connectingFromId,
    this.onSelectMark,
    this.onEditMark,
    this.onDeleteMark,
    this.onMarkEditDone,
    this.onMarkEditCancel,
    this.onConnect,
    this.onAdjustSummary,
    this.onUpdateRelation,
    this.onReverseRelation,
    this.onCancelConnect,
    this.onMarkContextMenu,
    this.excerptTargetId,
    this.previewCardIds = const {},
    this.expandedCardIds = const {},
    this.onToggleExpanded,
    this.onOpenDetails,
    this.onResize,
    this.selectionToolbar,
    this.mergePreviewCardId,
    this.flashAnnotationId,
    this.onRevealSegment,
    this.previewStyle,
    this.fitInsets,
    this.toolbarTopInset = 60,
    this.touchSelectionMode,
  });

  /// A structure and palette shown in place of the map's own while they are
  /// previewed; nothing is saved.
  final (MapStructure, MapPalette)? previewStyle;

  /// While set, the whole map is kept in view within the viewport less these
  /// insets (the part a popover covers), also as a preview changes it.
  final EdgeInsets? fitInsets;

  /// Bottom of the pane's fixed controls, in viewport coordinates.
  final double toolbarTopInset;

  /// When supplied, the pane provides the touch selection control in its
  /// measured header, instead of a separate floating button.
  final bool? touchSelectionMode;

  /// The selected excerpt, image or research note was resized (P2-C06) by
  /// its handle; null width when the handle is double-clicked (default).
  final void Function(String cardId, double? width)? onResize;
  final Widget? selectionToolbar;
  final String? mergePreviewCardId;
  final String? flashAnnotationId;
  final void Function(String cardId, int index)? onRevealSegment;

  /// Cards shown with their whole text; the others are cut to a preview.
  final Set<String> expandedCardIds;

  /// "Show full text" / "Show less" on a cut card.
  final ValueChanged<String>? onToggleExpanded;

  /// Double click on an excerpt opens its details (other nodes edit in
  /// place, through [onRename]).
  final ValueChanged<String>? onOpenDetails;

  /// The node new excerpts are added under ([rootNodeId] for the root),
  /// marked on the map; null shows no mark.
  final String? excerptTargetId;

  /// Nodes a proposal being hovered would change: outlined with a dashed
  /// line and brought into view.
  final Set<String> previewCardIds;

  /// False until the content has been read from disk; the first fit waits
  /// for it so it measures the real tree.
  final bool loaded;

  final StudySetContent content;
  final String mapId;
  final String rootTitle;
  final String? selectedCardId;
  final bool rootSelected;
  final ValueChanged<Rect>? onAssistant;
  final VoidCallback? onSelectRoot;
  final Set<String> selectedCardIds;
  final ValueChanged<String>? onToggleSelection;
  final ValueChanged<Set<String>>? onSelectMany;
  final String? flashCardId;
  final Set<String> flashCardIds;

  /// Changes for each explicit location, including repeated requests for one card.
  final int locateCardTick;

  /// Acknowledges a request only after its viewport change has been applied.
  final ValueChanged<int>? onLocated;
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
  final CardEditDone? onEditDone;

  /// Esc.
  final VoidCallback? onEditCancel;

  /// Right click on a node (card id, or null for the root).
  final void Function(String? cardId, Offset globalPosition)? onContextMenu;

  /// Selected relation or summary, and the one whose label is a text field.
  final String? selectedMarkId;
  final String? editingMarkId;

  /// A relation being drawn from this card: the next node clicked ends it,
  /// a dashed line follows the pointer until then.
  final String? connectingFromId;

  final ValueChanged<String>? onSelectMark;

  /// Double click on a label, F2, Space or Enter on a selected mark.
  final ValueChanged<String>? onEditMark;
  final VoidCallback? onDeleteMark;

  final void Function(String, String, String)? onAdjustSummary;
  final ValueChanged<MapRelation>? onUpdateRelation;
  final ValueChanged<String>? onReverseRelation;
  final ValueChanged<String>? onMarkEditDone;
  final VoidCallback? onMarkEditCancel;
  final ValueChanged<String>? onConnect;
  final VoidCallback? onCancelConnect;
  final void Function(String markId, Offset globalPosition)? onMarkContextMenu;

  @override
  State<MindMapCanvas> createState() => _MindMapCanvasState();
}

class _MindMapCanvasState extends State<MindMapCanvas> with TickerProviderStateMixin, CardFieldHost<MindMapCanvas> {
  bool _centered = false;
  final _toolbarKey = GlobalKey();
  Timer? _hoverExit;
  void _enterNode(String id) {
    _hoverExit?.cancel();
    _hovered.value = id;
  }

  void _leaveNode(String id) {
    _hoverExit?.cancel();
    _hoverExit = Timer(MMMotion.standard, () {
      if (mounted && _hovered.value == id) _hovered.value = null;
    });
  }

  int _handledLocateTick = 0;
  final _tapModifiers = <String, bool>{};
  Offset? _boxStart;
  Offset? _boxEnd;
  Set<String> _boxInitial = {};
  bool _localTouchSelection = false;
  bool get _touchSelection => widget.touchSelectionMode ?? _localTouchSelection;
  final _touchPointers = <int>{};
  Offset? _touchDragOrigin;
  bool _touchDragMoved = false;
  bool _touchDragCancelled = false;

  String? get _selectedNodeId =>
      widget.selectedMarkId == null ? (widget.rootSelected ? rootNodeId : widget.selectedCardId) : null;

  bool get _additive =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  void _select(String? id, {required bool additive}) {
    if (id == rootNodeId) {
      if (widget.onSelectRoot != null) {
        widget.onSelectRoot!();
      } else {
        widget.onSelect(null);
      }
      return;
    }
    if (id != null && additive && widget.onToggleSelection != null) {
      widget.onToggleSelection!(id);
    } else if (id != null && additive && widget.onSelectMany != null) {
      final selected = {...widget.selectedCardIds};
      if (!selected.remove(id)) selected.add(id);
      widget.onSelectMany!(selected);
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

  /// A merge can grow a card and rebalance whole branches. Keep its start
  /// where the user was reading, rather than anchoring that edit to the root.
  ({String id, Offset position})? _mergeAnchor;

  /// The card under the mouse; its source is shown below it.
  final _hovered = ValueNotifier<String?>(null);

  /// Trackpad pinch: the gesture's scale at the last update.
  double? _pinchScale;

  /// A card being resized by its handle: its id and width while dragged,
  /// kept after the drag until the saved width arrives with the content.
  (String, double)? _resize;
  ({double pointer, double width})? _resizeStart;

  @override
  String? get editingCardId => widget.editingCardId;
  @override
  StudySetContent get fieldContent => widget.content;
  @override
  FocusNode get hostFocus => widget.focusNode;
  @override
  CardEditDone? get onFieldDone => widget.onEditDone;
  @override
  VoidCallback? get onFieldCancel => widget.onEditCancel;
  @override
  void fieldOpened(String id) => _ensureVisible(id);

  /// The label of a relation or summary open for editing.
  CardField? _markField;

  /// Pointer position in the scene while a relation is being drawn.
  Offset? _hover;
  (String, Duration, Offset)? _lastMarkTap;
  Duration _pointerTime = Duration.zero;
  MapRelation? _relationDraft;
  Offset? _rangePointer;
  Map<String, Rect> _rangeRects = const {};
  Set<String> _rangeSide = const {};
  (String, String)? _rangeDraft;
  String? _targetAt(Offset scene) => _layout?.rects.entries
      .where((e) => e.key != rootNodeId && e.key != widget.connectingFromId && _rect(e.value).contains(scene))
      .firstOrNull
      ?.key;

  List<MapRelation> get _drawnRelations => [
    for (final r in _cache._relations) _relationDraft?.id == r.id ? _relationDraft! : r,
  ];

  String _storedLabel(String id) =>
      widget.content.relations.where((r) => r.id == id).firstOrNull?.label ??
      widget.content.summaries.where((s) => s.id == id).firstOrNull?.label ??
      '';

  /// Opens or closes the label field to match [MindMapCanvas.editingMarkId].
  void _syncMarkField() {
    final id = widget.editingMarkId;
    if (id == _markField?.id) return;
    final old = _markField;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _markField = null;
    if (id == null) return;
    final text = _storedLabel(id);
    final controller = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    final next = CardField(id, controller, FocusNode(debugLabel: 'MarkField'));
    next.focus.addListener(() {
      if (next.focus.hasFocus) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      _endMarkField(next, commit: true, refocus: false);
    });
    _markField = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _markField == next) next.focus.requestFocus();
    });
  }

  void _endMarkField(CardField f, {required bool commit, required bool refocus}) {
    if (f != _markField || f.ended) return;
    f.ended = true;
    if (refocus) widget.focusNode.requestFocus();
    if (commit) {
      widget.onMarkEditDone?.call(f.controller.text);
    } else {
      widget.onMarkEditCancel?.call();
    }
  }

  @override
  void initState() {
    super.initState();
    syncField();
    _syncMarkField();
    _motion.addListener(() {
      if (field == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && field != null) _ensureVisible(field!.id);
      });
    });
  }

  @override
  void dispose() {
    _hoverExit?.cancel();
    disposeField();
    final mark = _markField;
    if (mark != null && !mark.ended) {
      final done = widget.onMarkEditDone;
      final text = mark.controller.text;
      if (done != null) Future.microtask(() => done(text));
    }
    mark?.dispose();
    _autoScroll.dispose();
    _motion.dispose();
    _hovered.dispose();
    super.dispose();
  }

  bool _isCard(String? id) => id != null && id != rootNodeId && _cache._specs.containsKey(id);

  /// Records where every node is drawn now when the layout changes, so
  /// the next frames can move them to the new layout. Offsets are kept
  /// relative to the node that [_keepViewportAnchorInPlace] holds still.
  void _animateTo(TreeLayoutResult next, TreeLayoutResult? previous) {
    if (previous == null || identical(previous, next)) return;
    if (!_centered || MMAppearance.reduceMotionOf(context)) {
      _from = const {};
      return;
    }
    final anchor = _mergeAnchor;
    final shift = anchor == null
        ? _rect(next.rects[rootNodeId]!).topLeft - _rect(previous.rects[rootNodeId]!).topLeft
        : _rect(next.rects[anchor.id]!).topLeft - anchor.position;
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

  Widget _fieldNode(String id, _NodeSpec spec, LayoutRect target, _NodeLook? look) {
    final f = field!;
    final t = context.mmText;
    final (style, kind, maxLines) = switch (spec.kind) {
      _Kind.note => (t.body.copyWith(height: 19 / 13), CardKind.note, null),
      _Kind.excerpt => (t.headline.copyWith(height: 17 / 13), CardKind.excerpt, 1),
      _Kind.image => (t.headline.copyWith(height: 17 / 13), CardKind.image, 1),
      _ => (t.headline.copyWith(color: look?.text), CardKind.topic, null),
    };
    return Positioned.fromRect(
      key: ValueKey(id),
      rect: _shown(id, target),
      child: _NodeView(
        spec: spec,
        look: look,
        transformation: widget.transformation,
        selected: true,
        flashing: false,
        onTap: () {},
        onDoubleTap: null,
        onSecondaryTapUp: null,
        onReveal: null,
        revealLabel: '',
        editor: fieldEditor(f, style: style, kind: kind, label: spec.label, maxLines: maxLines),
      ),
    );
  }

  /// Where the root was in the last layout. When the tree changes shape
  /// (fold, move, add) the view is shifted so the root stays put on screen.
  Offset? _rootAnchor;
  Size _viewport = Size.zero;

  /// First view uses readable text and keeps the root visible (centered
  /// when branches grow on both sides). Remounts preserve the user's pan/zoom.
  void _fitOnce(TreeLayoutResult result, BoxConstraints viewport) {
    if (_centered || !widget.loaded || !viewport.hasBoundedHeight || !viewport.hasBoundedWidth) return;
    _centered = true;
    if (widget.transformation.value != Matrix4.identity()) {
      if (widget.locateCardTick > 0 && widget.selectedCardId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _locate(widget.selectedCardId!, widget.locateCardTick);
        });
      }
      return;
    }
    final w = viewport.maxWidth, h = viewport.maxHeight;
    final scene = _sceneSize(result);
    final scale = math.min(1.0, math.min((w - 24) / scene.width, (h - 24) / scene.height)).clamp(mapReadableScale, 1.0);
    final root = result.rects[rootNodeId]!;
    final fitsWidth = scene.width * scale <= w;
    final dx = fitsWidth
        ? (w - scene.width * scale) / 2
        : result.leftSide.isNotEmpty
        ? w / 2 - (root.left + root.width / 2) * scale
        : w * 0.04 - (root.left - 24) * scale;
    // A tree grows down from its root: it starts at the top.
    final dy = result.structure == LayoutStructure.tree && scene.height * scale > h
        ? _topClearance - root.top * scale
        : h / 2 - root.centerY * scale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.transformation.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
      if (widget.locateCardTick > 0 && widget.selectedCardId != null) {
        _locate(widget.selectedCardId!, widget.locateCardTick);
      }
    });
  }

  @override
  void didUpdateWidget(MindMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selectedCardId;
    final oldCard = selected == null ? null : oldWidget.content.card(selected);
    final newCard = selected == null ? null : widget.content.card(selected);
    final previousRect = _layout?.rects[selected];
    if (widget.mapId == oldWidget.mapId && oldCard != null && newCard != null && previousRect != null) {
      final before = math.max(1, oldCard.segments.length);
      final after = math.max(1, newCard.segments.length);
      // Restoring a merge through undo/redo has the same layout change.
      final merging =
          after > before &&
          oldWidget.content.nodes.any(
            (n) => n.mapId == widget.mapId && !widget.content.isPlaced(n.cardId, mapId: widget.mapId),
          );
      final restoring =
          after < before &&
          widget.content.nodes.any(
            (n) => n.mapId == widget.mapId && !oldWidget.content.isPlaced(n.cardId, mapId: widget.mapId),
          );
      if (merging || restoring) {
        _mergeAnchor = (id: selected!, position: _shown(selected, previousRect).topLeft);
      }
    }
    syncField();
    _syncMarkField();
    if (_resizeStart == null && !identical(widget.content, oldWidget.content)) _resize = null;
    if (widget.connectingFromId == null) _hover = null;
    typed = null;
    // The tree can change under a drag (undo, another window); the drop
    // must follow what is drawn.
    if (_dragging != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateDrop();
      });
    }
    if (!setEquals(widget.previewCardIds, oldWidget.previewCardIds) && widget.previewCardIds.isNotEmpty) {
      final id = widget.previewCardIds.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureVisible(id);
      });
    }
    final deselecting = _deselecting;
    if (widget.selectedCardId != oldWidget.selectedCardId || widget.rootSelected != oldWidget.rootSelected) {
      _deselecting = false;
    }
    if (widget.locateCardTick > 0 &&
        widget.locateCardTick != oldWidget.locateCardTick &&
        widget.selectedCardId != null) {
      final id = widget.selectedCardId!;
      final tick = widget.locateCardTick;
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate(id, tick));
    } else if (deselecting && widget.selectedCardId == null && widget.flashCardId == oldWidget.flashCardId) {
      // Deselected: nothing to bring into view.
    } else if (_mergeAnchor == null &&
        _boxStart == null &&
        (widget.selectedCardId != oldWidget.selectedCardId ||
            (widget.flashCardId != null && widget.flashCardId != oldWidget.flashCardId))) {
      final id = widget.flashCardId != oldWidget.flashCardId && widget.flashCardId != null
          ? widget.flashCardId!
          : _selectedNodeId;
      if (id != null) WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(id));
    }
  }

  /// Clearing the selection (empty canvas, Esc) leaves the viewport in place.
  bool _deselecting = false;

  void _deselect() {
    _deselecting = true;
    widget.onSelect(null);
  }

  void _keepViewportAnchorInPlace(TreeLayoutResult result) {
    final root = result.rects[rootNodeId]!;
    final rootPosition = Offset(root.left, root.top);
    final merge = _mergeAnchor;
    final anchor = merge == null ? rootPosition : _rect(result.rects[merge.id]!).topLeft;
    final previous = merge?.position ?? _rootAnchor;
    _rootAnchor = rootPosition;
    if (!_centered || previous == null || previous == anchor) return;
    final m = widget.transformation.value;
    final scale = mapScale(m);
    final delta = (previous - anchor) * scale;
    widget.transformation.value = m.clone()..setTranslationRaw(m.storage[12] + delta.dx, m.storage[13] + delta.dy, 0);
  }

  /// The card with its source label, which hangs beside it on the outer side.
  Rect _withSourceLabel(String id, LayoutRect rect) {
    final card = Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
    final meta = _cache._specs[id]?.meta;
    if (meta == null || _cache._specs[id]!.segments.isNotEmpty) return card;
    final painter = TextPainter(
      text: TextSpan(text: meta, style: context.mmText.footnote),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final extent = _sourceGap(id) + math.min(painter.width + 2 * MMSpacing.xs, rect.width);
    painter.dispose();
    return _layout!.leftSide.contains(id)
        ? Rect.fromLTRB(card.left - extent, card.top, card.right, card.bottom)
        : Rect.fromLTRB(card.left, card.top, card.right + extent, card.bottom);
  }

  /// Centers an explicitly located card, and the source label beside it, at a
  /// readable scale.
  void _locate(String id, int tick) {
    if (tick <= _handledLocateTick) return;
    final rect = _layout?.rects[id];
    if (!mounted || rect == null || _viewport.isEmpty) return;
    final scale = math.max(mapLocateScale, mapScale(widget.transformation.value));
    final bounds = _withSourceLabel(id, rect);
    widget.transformation.value = Matrix4.identity()
      ..translateByDouble(
        _viewport.width / 2 - bounds.center.dx * scale,
        _viewport.height / 2 - rect.centerY * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    _handledLocateTick = tick;
    widget.onLocated?.call(tick);
  }

  /// Pans (keeping the zoom) so a newly created or linked node is on screen:
  /// where it is drawn now, or once the layout animation has [settled] (a
  /// node left of the root grows leftward as it moves).
  void _ensureVisible(String id, {bool settled = false}) {
    final rect = _layout?.rects[id];
    if (!mounted || rect == null || _viewport.isEmpty) return;
    final m = widget.transformation.value;
    final scale = mapScale(m);
    final tx = m.storage[12], ty = m.storage[13];
    final shown = settled ? _rect(rect) : _shown(id, rect);
    final left = shown.left * scale + tx, right = shown.right * scale + tx;
    final top = shown.top * scale + ty, bottom = shown.bottom * scale + ty;
    const margin = MMSpacing.xxxl;
    var dx = 0.0, dy = 0.0;
    if (right > _viewport.width - margin) dx = _viewport.width - margin - right;
    if (left + dx < margin) dx = margin - left;
    if (bottom > _viewport.height - margin) dy = _viewport.height - margin - bottom;
    if (top + dy < _topClearance) dy = _topClearance - top;
    if (dx == 0 && dy == 0) return;
    widget.transformation.value = m.clone()..setTranslationRaw(tx + dx, ty + dy, 0);
  }

  /// Room kept above nodes brought into view: the pane's controls float there.
  double get _topClearance => math.max(
    MMSpacing.xxxl * 2 + MMSpacing.l,
    widget.toolbarTopInset +
        (widget.selectionToolbar == null ? 0 : context.mmToolbarButton.height + 6 + 22 + MMSpacing.s),
  );

  void _command(MindMapCommand command) {
    final selected = widget.selectedCardId;
    if (widget.selectedMarkId case final mark?) {
      switch (command) {
        case MindMapCommand.delete:
          widget.onDeleteMark?.call();
          return;
        case MindMapCommand.edit || MindMapCommand.siblingAfter:
          widget.onEditMark?.call(mark);
          return;
        default:
          break;
      }
    }
    switch (command) {
      case MindMapCommand.child:
        widget.onAddChild();
      case MindMapCommand.edit:
        if (selected != null) widget.onRename(selected);
      case MindMapCommand.delete:
        if (selected != null) widget.onDelete();
      case MindMapCommand.fold:
        if (selected != null) widget.onToggleCollapsed(selected);
      case MindMapCommand.expand:
        if (selected != null) widget.onCommand?.call(command);
      case MindMapCommand.up || MindMapCommand.down:
        if (selected != null) widget.onShift(command == MindMapCommand.up ? -1 : 1);
      case MindMapCommand.fit:
        _fit(widget.fitInsets ?? EdgeInsets.zero);
      case MindMapCommand.center:
        _centerOn(selected ?? rootNodeId, math.max(mapLocateScale, mapScale(widget.transformation.value)));
      case MindMapCommand.copy || MindMapCommand.cut || MindMapCommand.paste:
        widget.onCommand?.call(command);
      case MindMapCommand.siblingAfter:
        if (widget.rootSelected) {
          widget.onAddChild();
        } else if (selected != null) {
          widget.onCommand?.call(command);
        }
      case MindMapCommand.siblingBefore ||
          MindMapCommand.parent ||
          MindMapCommand.promote ||
          MindMapCommand.relation ||
          MindMapCommand.merge ||
          MindMapCommand.summary:
        if (selected != null) widget.onCommand?.call(command);
    }
  }

  /// The least room beside fit insets the map is shown in.
  static const _minFitExtent = 160.0;

  /// Shows the whole map, at most at 100%, in the middle of the viewport
  /// less [insets].
  void _fit(EdgeInsets insets) {
    final layout = _layout;
    if (layout == null || _viewport.isEmpty) return;
    var area = insets.deflateRect(Offset.zero & _viewport);
    // A narrow view has no room beside the insets: the map then fits all of it.
    if (area.width < _minFitExtent) area = Rect.fromLTRB(0, area.top, _viewport.width, area.bottom);
    if (area.height < _minFitExtent) area = Rect.fromLTRB(area.left, 0, area.right, _viewport.height);
    final scene = _sceneSize(layout);
    final scale = math
        .min((area.width - MMSpacing.xl * 2) / scene.width, (area.height - MMSpacing.xl * 2) / scene.height)
        .clamp(mapMinScale, 1.0);
    widget.transformation.value = Matrix4.identity()
      ..translateByDouble(
        area.left + (area.width - scene.width * scale) / 2,
        area.top + (area.height - scene.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// Shows the node [id] in the middle of the view at [scale].
  void _centerOn(String id, double scale) {
    final rect = _layout?.rects[id];
    if (rect == null || _viewport.isEmpty) return;
    widget.transformation.value = Matrix4.identity()
      ..translateByDouble(
        _viewport.width / 2 - (rect.left + rect.width / 2) * scale,
        _viewport.height / 2 - rect.centerY * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// Mouse wheel zooms at the pointer; Shift + wheel pans sideways.
  /// Trackpad pan/zoom gestures retain their native behavior.
  void _pointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && event.kind != PointerDeviceKind.trackpad) {
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        final scroll = e as PointerScrollEvent;
        if (HardwareKeyboard.instance.isShiftPressed) {
          _panBy(-Offset(scroll.scrollDelta.dy, scroll.scrollDelta.dx));
        } else {
          _zoomAt(scroll.localPosition, math.exp(-scroll.scrollDelta.dy / _wheelZoomFactor));
        }
      });
    } else if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (e) => _zoomAt(e.localPosition, (e as PointerScaleEvent).scale),
      );
    }
  }

  void _zoomAt(Offset focal, double factor) {
    if (factor == 1 || factor.isNaN) return;
    widget.transformation.value = zoomMapAt(widget.transformation.value, focal, factor);
  }

  /// Pans by [delta] (viewport pixels), but not past the far side of the map
  /// coming [_autoScrollEdge] into view.
  void _panBy(Offset delta) {
    final layout = _layout;
    if (layout == null || _viewport.isEmpty || delta == Offset.zero) return;
    final m = widget.transformation.value;
    final scale = mapScale(m);
    final current = Offset(m.storage[12], m.storage[13]);
    final scene = _sceneSize(layout);
    final next = clampAutoScroll(
      current,
      delta,
      Rect.fromLTWH(current.dx, current.dy, scene.width * scale, scene.height * scale),
      _viewport,
      margin: _autoScrollEdge,
    );
    if (next == current) return;
    widget.transformation.value = m.clone()..setTranslationRaw(next.dx, next.dy, 0);
  }

  /// Arrow keys follow the drawing: on the left of the root, left goes to
  /// the children and right to the parent, and left from the root goes to
  /// its first branch on the left.
  void _navigate(AxisDirection direction) {
    final layout = _layout;
    final selected = widget.selectedCardId ?? rootNodeId;
    if (layout != null && direction == AxisDirection.left && selected == rootNodeId) {
      final first = layout.edges.where((e) => e.parentId == rootNodeId && layout.leftSide.contains(e.childId));
      if (first.isNotEmpty) widget.onSelect(first.first.childId);
      return;
    }
    if (layout != null && layout.leftSide.contains(selected)) {
      direction = switch (direction) {
        AxisDirection.left => AxisDirection.right,
        AxisDirection.right => AxisDirection.left,
        _ => direction,
      };
    }
    widget.onNavigate(direction);
  }

  /// Space between a card and its source label: clear of its fold button.
  double _sourceGap(String id) => _cache._expandable.contains(id) ? MMSpacing.xl + MMSpacing.s : MMSpacing.s;

  bool _leftRelation(MapRelation r) =>
      _layout != null && _layout!.leftSide.contains(r.fromId) && _layout!.leftSide.contains(r.toId);

  /// The relation line or summary bracket at [scene], if any. Labels are
  /// widgets and take their own clicks.
  String? _markAt(Offset scene) {
    final layout = _layout;
    if (layout == null) return null;
    for (final e in layout.summaries.entries) {
      if (_rect(e.value.bracket).inflate(MMSpacing.xs).contains(scene)) return e.key;
    }
    final rects = _drawnRects();
    final others = _obstacles(rects, layout);
    final slop = MMSpacing.s / math.max(mapScale(widget.transformation.value), 0.5);
    for (final r in _cache._relations.reversed) {
      final a = rects[r.fromId], b = rects[r.toId];
      if (a == null || b == null) continue;
      final curve = mapRelationCurve(
        _relationDraft?.id == r.id ? _relationDraft! : r,
        a,
        b,
        others,
        left: _leftRelation(r),
        root: rects[rootNodeId],
      );
      var previous = curve.$1;
      for (var i = 1; i <= 24; i++) {
        final point = cubicPoint(curve, i / 24);
        if (_distanceToSegment(scene, previous, point) <= slop) return r.id;
        previous = point;
      }
    }
    return null;
  }

  /// The scene: the tree plus any relation line or label reaching past it,
  /// so they are neither clipped nor left out when fitting the map.
  Size _sceneSize(TreeLayoutResult layout) {
    var width = layout.width, height = layout.height;
    if (_cache._relations.isEmpty) return Size(width, height);
    final others = _obstacles({for (final e in layout.rects.entries) e.key: _rect(e.value)}, layout);
    for (final r in _drawnRelations) {
      final from = layout.rects[r.fromId], to = layout.rects[r.toId];
      if (from == null || to == null) continue;
      final curve = mapRelationCurve(
        r,
        _rect(from),
        _rect(to),
        others,
        left: _leftRelation(r),
        root: layout.rects[rootNodeId] == null ? null : _rect(layout.rects[rootNodeId]!),
      );
      for (var i = 0; i <= 8; i++) {
        final p = cubicPoint(curve, i / 8);
        width = math.max(width, p.dx + MMSpacing.l);
        height = math.max(height, p.dy + MMSpacing.l);
      }
      if (r.id == widget.selectedMarkId && _markField == null) {
        final middle = cubicPoint(curve, .5);
        width = math.max(width, math.max(curve.$2.dx, curve.$3.dx) + 20);
        width = math.max(width, math.max(0, middle.dx - 140) + 300);
        height = math.max(
          height,
          math.max(math.max(curve.$1.dy, curve.$4.dy), math.max(curve.$2.dy, curve.$3.dy)) + 80,
        );
      }
      final label = _cache._markLabels[r.id] ?? '';
      if (label.isEmpty && r.id != _markField?.id) continue;
      final box = _relationLabelSize(r.id);
      final middle = cubicPoint(curve, 0.5);
      final right = !relationGoesAround(curve)
          ? middle.dx + box.width / 2
          : _leftRelation(r)
          ? middle.dx
          : middle.dx + MMSpacing.xs + box.width;
      width = math.max(width, right + MMSpacing.l);
      height = math.max(height, middle.dy + box.height / 2 + MMSpacing.l);
    }
    return Size(width, height);
  }

  /// A relation label's box. Labels are laid out on one line, without a
  /// width limit.
  Size _relationLabelSize(String id) {
    final size = _cache._measure(_cache._markLabels[id] ?? '', MMTypography.footnote, double.infinity).size;
    return Size(math.max(size.width, MMSpacing.xxxl) + MMSpacing.xs * 2, size.height + MMSpacing.xxs * 2);
  }

  /// What a relation line between stacked nodes goes around: the nodes and
  /// the summary labels.
  List<Rect> _obstacles(Map<String, Rect> rects, TreeLayoutResult layout) => [
    ...rects.values,
    for (final s in layout.summaries.values) _rect(s.label),
  ];

  /// The middle of a relation's line as drawn now, where its label sits, and
  /// where the label goes: beside it, outward (-1 left, 1 right) for lines
  /// around a column, or on it (0).
  (Offset, int)? _relationMiddle(MapRelation r, List<Rect> others) {
    final from = _layout?.rects[r.fromId], to = _layout?.rects[r.toId];
    if (from == null || to == null) return null;
    final left = _leftRelation(r);
    final curve = mapRelationCurve(
      _relationDraft?.id == r.id ? _relationDraft! : r,
      _drawn(r.fromId, from),
      _drawn(r.toId, to),
      others,
      left: left,
      root: _layout?.rects[rootNodeId] == null ? null : _rect(_layout!.rects[rootNodeId]!),
    );
    return (cubicPoint(curve, 0.5), relationGoesAround(curve) ? (left ? -1 : 1) : 0);
  }

  Offset _scenePoint(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    return widget.transformation.toScene(box.globalToLocal(global));
  }

  Widget _dragHandle(
    String key,
    Offset point, {
    required GestureDragStartCallback onStart,
    required GestureDragUpdateCallback onUpdate,
    required VoidCallback onEnd,
    required VoidCallback onCancel,
    bool round = false,
  }) => Positioned(
    key: ValueKey('position-$key'),
    left: point.dx - 10,
    top: point.dy - 10,
    child: GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onPanStart: onStart,
      onPanUpdate: onUpdate,
      onPanEnd: (_) => onEnd(),
      onPanCancel: onCancel,
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: context.mmColors.canvas,
              border: Border.all(color: context.mmColors.accent, width: 2),
              shape: round ? BoxShape.circle : BoxShape.rectangle,
            ),
          ),
        ),
      ),
    ),
  );

  Map<String, SummaryPlacement> _summaryPlacements(TreeLayoutResult layout) {
    final range = _rangeDraft;
    final summary = widget.content.summaries
        .where((s) => s.id == widget.selectedMarkId && s.mapId == widget.mapId)
        .firstOrNull;
    if (range == null || summary == null) return layout.summaries;
    final original = layout.summaries[summary.id];
    if (original == null) return layout.summaries;
    final siblings = widget.content.childrenOf(summary.parentId, mapId: widget.mapId);
    final from = siblings.indexWhere((n) => n.cardId == range.$1);
    final to = siblings.indexWhere((n) => n.cardId == range.$2);
    Rect? bounds;
    final visited = <String>{};
    void include(String id) {
      if (!visited.add(id)) return;
      if (_rangeRects[id] case final rect?) bounds = bounds?.expandToInclude(rect) ?? rect;
      for (final child in widget.content.childrenOf(id, mapId: widget.mapId)) {
        include(child.cardId);
      }
    }

    for (final node in siblings.sublist(from, to + 1)) {
      include(node.cardId);
    }
    if (bounds == null) return layout.summaries;
    final b = original.bracket;
    return {
      ...layout.summaries,
      summary.id: SummaryPlacement(
        LayoutRect(b.left, bounds!.top, b.width, bounds!.height),
        original.label,
        left: original.left,
      ),
    };
  }

  List<Widget> _interactionWidgets(Map<String, Rect> rects, List<Rect> obstacles) {
    final widgets = <Widget>[];
    if (widget.connectingFromId != null && _hover != null) {
      final target = _targetAt(_hover!);
      if (target != null) {
        widgets.add(
          Positioned.fromRect(
            rect: rects[target]!.inflate(3),
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('relation-target'),
                decoration: BoxDecoration(
                  border: Border.all(color: context.mmColors.accent, width: 2),
                  borderRadius: BorderRadius.circular(MMRadii.card),
                ),
              ),
            ),
          ),
        );
      }
    }
    final summary = widget.content.summaries
        .where((s) => s.mapId == widget.mapId && s.id == widget.selectedMarkId)
        .firstOrNull;
    final placement = _layout == null ? null : _summaryPlacements(_layout!)[summary?.id];
    if (summary != null && placement != null && _markField == null) {
      final bracket = _rect(placement.bracket);
      for (final start in [true, false]) {
        void preview(Offset global) {
          final pointer = _scenePoint(global);
          final range = summaryRangeAt(widget.content, summary, _rangeRects, _rangeSide, pointer, start: start);
          if (range != null) {
            setState(() {
              _rangePointer = pointer;
              _rangeDraft = range;
            });
          }
        }

        final point = Offset(placement.left ? bracket.right : bracket.left, start ? bracket.top : bracket.bottom);
        widgets.add(
          _dragHandle(
            'summary-range-${start ? 'from' : 'to'}',
            point,
            onStart: (d) {
              _rangeRects = Map.of(rects);
              _rangeSide = Set.of(_layout!.leftSide);
              _rangeDraft = null;
              preview(d.globalPosition);
            },
            onUpdate: (d) => preview(d.globalPosition),
            onEnd: () {
              final range = _rangeDraft;
              if (range != null && (range.$1 != summary.fromId || range.$2 != summary.toId)) {
                widget.onAdjustSummary?.call(summary.id, range.$1, range.$2);
              }
              setState(() {
                _rangePointer = null;
                _rangeDraft = null;
              });
            },
            onCancel: () => setState(() {
              _rangePointer = null;
              _rangeDraft = null;
            }),
          ),
        );
      }
    }
    final relation = _drawnRelations.where((r) => r.id == widget.selectedMarkId).firstOrNull;
    if (relation != null && rects[relation.fromId] != null && rects[relation.toId] != null && _markField == null) {
      final a = rects[relation.fromId]!, b = rects[relation.toId]!;
      final curve = mapRelationCurve(relation, a, b, obstacles, left: _leftRelation(relation), root: rects[rootNodeId]);
      for (final first in [true, false]) {
        void preview(Offset global) {
          final point = _scenePoint(global) - (first ? a.center : b.center);
          final c1 = first
              ? RelationControlPoint(point.dx, point.dy)
              : RelationControlPoint(curve.$2.dx - a.center.dx, curve.$2.dy - a.center.dy);
          final c2 = !first
              ? RelationControlPoint(point.dx, point.dy)
              : RelationControlPoint(curve.$3.dx - b.center.dx, curve.$3.dy - b.center.dy);
          setState(() => _relationDraft = relation.copyWith(control1: c1, control2: c2));
        }

        widgets.add(
          _dragHandle(
            'relation-control-${first ? 1 : 2}',
            first ? curve.$2 : curve.$3,
            round: true,
            onStart: (d) => preview(d.globalPosition),
            onUpdate: (d) => preview(d.globalPosition),
            onEnd: () {
              if (_relationDraft case final draft?) widget.onUpdateRelation?.call(draft);
              setState(() => _relationDraft = null);
            },
            onCancel: () => setState(() => _relationDraft = null),
          ),
        );
      }
      final middle = cubicPoint(curve, .5);
      final l = context.l10n;
      Widget button(IconData icon, String label, VoidCallback action) => IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        tooltip: label,
        onPressed: action,
        icon: Icon(icon),
      );
      widgets.add(
        Positioned(
          left: math.max(0, middle.dx - 140),
          top: math.max(math.max(curve.$1.dy, curve.$4.dy), math.max(curve.$2.dy, curve.$3.dy)) + 24,
          child: Material(
            color: context.mmColors.canvas,
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                button(
                  Icons.arrow_forward,
                  l.relationArrowEnd,
                  () => widget.onUpdateRelation?.call(relation.copyWith(arrow: RelationArrow.end)),
                ),
                button(
                  Icons.swap_horiz,
                  l.relationArrowBoth,
                  () => widget.onUpdateRelation?.call(relation.copyWith(arrow: RelationArrow.both)),
                ),
                button(
                  Icons.remove,
                  l.relationArrowNone,
                  () => widget.onUpdateRelation?.call(relation.copyWith(arrow: RelationArrow.none)),
                ),
                button(Icons.flip, l.relationReverse, () => widget.onReverseRelation?.call(relation.id)),
                button(
                  relation.solid ? Icons.horizontal_rule : Icons.more_horiz,
                  l.relationLineStyle,
                  () => widget.onUpdateRelation?.call(relation.copyWith(solid: !relation.solid)),
                ),
                button(Icons.edit, l.editMarkLabel, () => widget.onEditMark?.call(relation.id)),
                button(MMIcons.trash, l.deleteRelation, () => widget.onDeleteMark?.call()),
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// A label of a relation (at the middle of its line) or summary.
  Widget _markLabel(String id, {required bool summary}) {
    final t = context.mmText;
    final f = _markField?.id == id ? _markField : null;
    final palette = summary ? _mapColors(context.mmColors) : null;
    final style = summary ? t.headline.copyWith(color: palette?.onSummary) : t.footnote;
    Widget? editor;
    if (f != null) {
      final width = _cache._measure(f.controller.text, summary ? MMTypography.headline : MMTypography.footnote, 200);
      editor = SizedBox(
        width: math.max(width.size.width, MMSpacing.xxxl) + MMSpacing.xs,
        child: MMInlineTextField(
          controller: f.controller,
          focusNode: f.focus,
          style: style,
          maxLines: summary ? null : 1,
          semanticLabel: summary ? context.l10n.addSummary : context.l10n.addRelation,
          onSubmitted: () => _endMarkField(f, commit: true, refocus: true),
          onCancel: () => _endMarkField(f, commit: false, refocus: true),
          onTapOutside: () => _endMarkField(f, commit: true, refocus: false),
        ),
      );
    }
    return _MarkLabel(
      key: ValueKey('mark-label-$id'),
      text: _cache._markLabels[id] ?? '',
      style: style,
      summary: summary,
      fill: palette?.summary,
      selected:
          id == widget.selectedMarkId ||
          (summary &&
              widget.selectedCardId != null &&
              widget.content.summaries.any((s) => s.id == id && s.cardId == widget.selectedCardId)),
      editor: editor,
      onTap: () {
        widget.focusNode.requestFocus();
        final cardId = summary ? widget.content.summaries.where((s) => s.id == id).firstOrNull?.cardId : null;
        if (cardId != null) {
          if (_additive && widget.onToggleSelection != null) {
            widget.onToggleSelection!(cardId);
          } else {
            widget.onSelect(cardId);
          }
        } else {
          widget.onSelectMark?.call(id);
        }
      },
      onDoubleTap: widget.onEditMark == null ? null : () => widget.onEditMark!(id),
      onSecondaryTapUp: widget.onMarkContextMenu == null
          ? null
          : (position) {
              widget.focusNode.requestFocus();
              widget.onSelectMark?.call(id);
              widget.onMarkContextMenu!(id, position);
            },
    );
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
          mapId: widget.mapId,
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
    final scene = _sceneSize(layout);
    final next = clampAutoScroll(
      current,
      velocity * dt,
      Rect.fromLTWH(current.dx, current.dy, scene.width * scale, scene.height * scale),
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

  Widget _draggable(String id, _NodeSpec spec, _NodeLook? look, Widget child) {
    if (id == rootNodeId) return child;
    final scale = mapScale(widget.transformation.value);
    final count = widget.selectedCardIds.contains(id) ? widget.selectedCardIds.length : 1;
    final feedback = Transform.translate(
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
                    look: look,
                    transformation: widget.transformation,
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
    );
    return _PointerDraggable(
      touch: false,
      data: id,
      feedback: feedback,
      onDragStarted: () => _startDrag(id),
      onDragUpdate: (_) => _updateDrag(),
      onDragEnd: (_) => _endDrag(id),
      child: _PointerDraggable(
        touch: true,
        canStart: () => _touchPointers.length == 1 && _dragging == null,
        data: id,
        feedback: feedback,
        onDragStarted: () {
          _touchDragOrigin = _dragPointer;
          _touchDragMoved = false;
          _startDrag(id);
          final position = _touchDragOrigin;
          if (position != null) widget.onContextMenu?.call(id, position);
        },
        onDragUpdate: (_) {
          if (_touchDragOrigin != null &&
              _dragPointer != null &&
              (_dragPointer! - _touchDragOrigin!).distance > kTouchSlop) {
            if (!_touchDragMoved) dismissMMMenu(context);
            _touchDragMoved = true;
          }
          if (_touchDragMoved) _updateDrag();
        },
        onDragEnd: (_) {
          final showMenu = !_touchDragMoved && !_touchDragCancelled && _dragging != null;
          if (_touchDragCancelled) dismissMMMenu(context);
          _endDrag(showMenu || _touchDragCancelled ? null : id);
          _touchDragOrigin = null;
        },
        child: child,
      ),
    );
  }

  /// The handle on the outer edge of the selected excerpt, image or research
  /// note: dragging it sets the card's width, a double click restores the
  /// default.
  Widget? _resizeHandle(TreeLayoutResult result, AppLocalizations l) {
    final id = widget.selectedCardId;
    if (widget.onResize == null || id == null || field?.id == id || _dragging != null) return null;
    if (widget.selectedCardIds.length > 1 || _cache._specs[id]?.resizable != true) return null;
    final rect = result.rects[id];
    if (rect == null) return null;
    final shown = _shown(id, rect);
    final left = result.leftSide.contains(id);
    final c = context.mmColors;
    return Positioned(
      key: const ValueKey('card-width-handle'),
      left: (left ? shown.left : shown.right) - _resizeHandleWidth / 2,
      top: shown.top + MMSpacing.s,
      width: _resizeHandleWidth,
      height: math.max(0, shown.height - MMSpacing.s * 2),
      child: Semantics(
        label: l.cardWidthHandle,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Measured from where the button went down: the edge stays under the pointer.
            dragStartBehavior: DragStartBehavior.down,
            onDoubleTap: () {
              setState(() => _resize = null);
              widget.onResize!(id, null);
            },
            onHorizontalDragStart: (d) {
              _resizeStart = (pointer: d.globalPosition.dx, width: shown.width);
              setState(() => _resize = (id, shown.width));
            },
            onHorizontalDragUpdate: (d) {
              final start = _resizeStart;
              if (start == null) return;
              // The pointer moves in screen pixels; the card in map points.
              final delta = (d.globalPosition.dx - start.pointer) / mapScale(widget.transformation.value);
              final width = (start.width + (left ? -delta : delta)).clamp(MapNode.minWidth, MapNode.maxWidth);
              if (width != _resize?.$2) setState(() => _resize = (id, width.roundToDouble()));
            },
            onHorizontalDragEnd: (_) => _endResize(),
            onHorizontalDragCancel: _endResize,
            child: Center(
              child: Container(
                width: 3,
                height: math.min(22, math.max(0, shown.height - MMSpacing.s * 2)),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _endResize() {
    final resize = _resize;
    if (_resizeStart == null) return;
    _resizeStart = null;
    if (resize != null) widget.onResize!(resize.$1, resize.$2);
  }

  final _nodeWidgets = <String, ({Object signature, Widget child})>{};

  Widget _nodeWidget(String id, _NodeSpec spec, AppLocalizations l, _NodeLook? look) {
    final signature = (
      look,
      spec.kind,
      spec.title,
      spec.quote,
      spec.meta,
      spec.color,
      spec.size,
      spec.image,
      spec.imageHeight,
      spec.suspended,
      widget.selectedCardIds.contains(id) || id == _selectedNodeId,
      id == widget.flashCardId || widget.flashCardIds.contains(id),
      _dragging?.contains(id) ?? false,
      widget.selectedCardIds.contains(id) ? widget.selectedCardIds.length : 1,
      widget.transformation,
      mapScale(widget.transformation.value),
      widget.onContextMenu != null,
      l.revealSource,
      l.cardSuspended,
      spec.truncated,
      spec.expanded,
      spec.format,
      spec.maxLines,
      spec.segments,
      widget.flashAnnotationId,
      widget.onToggleExpanded != null,
      widget.onOpenDetails != null,
      l.expandCardText,
    );
    final cached = _nodeWidgets[id];
    if (cached != null && cached.signature == signature) return cached.child;
    // Callbacks read the current widget, so retaining an unchanged node never
    // retains a stale selection, command handler or connection target.
    final child = MouseRegion(
      onEnter: (_) => _enterNode(id),
      onExit: (_) => _leaveNode(id),
      child: RepaintBoundary(
        child: Semantics(
          value: spec.suspended ? l.cardSuspended : null,
          child: Opacity(
            opacity: _dragging?.contains(id) ?? false ? 0.35 : 1,
            child: _draggable(
              id,
              spec,
              look,
              _NodeView(
                spec: spec,
                flashAnnotationId: widget.flashAnnotationId,
                onRevealSegment: (index) {
                  widget.focusNode.requestFocus();
                  final additive = _tapModifiers.remove(id) ?? _additive;
                  if (widget.connectingFromId != null) {
                    widget.onConnect?.call(id);
                  } else if (additive) {
                    _select(id, additive: true);
                  } else {
                    widget.onRevealSegment?.call(id, index);
                  }
                },
                look: look,
                transformation: widget.transformation,
                selected: widget.selectedCardIds.contains(id) || id == _selectedNodeId,
                flashing: id == widget.flashCardId || widget.flashCardIds.contains(id),
                longPressEnabled: id == rootNodeId,
                onPressStart: (kind) =>
                    _tapModifiers[id] = _additive || (kind == PointerDeviceKind.touch && _touchSelection),
                onTap: () {
                  widget.focusNode.requestFocus();
                  final additive = _tapModifiers.remove(id) ?? false;
                  if (widget.connectingFromId != null) {
                    if (id == rootNodeId) {
                      widget.onCancelConnect?.call();
                    } else {
                      widget.onConnect?.call(id);
                    }
                    return;
                  }
                  _select(id, additive: additive);
                },
                onDoubleTap: id == rootNodeId
                    ? null
                    : (spec.kind == _Kind.excerpt || spec.kind == _Kind.research) && widget.onOpenDetails != null
                    ? () => widget.onOpenDetails!(id)
                    : () => widget.onRename(id),
                onOpenNote: spec.kind == _Kind.research && widget.onOpenDetails != null
                    ? () {
                        widget.focusNode.requestFocus();
                        widget.onSelect(id);
                        widget.onOpenDetails!(id);
                      }
                    : null,
                onToggleExpanded: widget.onToggleExpanded == null
                    ? null
                    : () {
                        widget.focusNode.requestFocus();
                        widget.onSelect(id);
                        widget.onToggleExpanded!(id);
                      },
                expandLabel: spec.kind == _Kind.research ? l.researchCardOpen : l.expandCardText,
                collapseLabel: l.collapseCardText,
                onSecondaryTapUp: widget.onContextMenu == null
                    ? null
                    : (position) {
                        widget.focusNode.requestFocus();
                        final selected = id == rootNodeId ? null : id;
                        if (selected == null || !widget.selectedCardIds.contains(selected)) {
                          _select(id, additive: false);
                        }
                        widget.onContextMenu!(selected, position);
                      },
                onReveal: spec.kind == _Kind.excerpt || (spec.kind == _Kind.image && spec.meta != null)
                    ? () => widget.onReveal(id)
                    : null,
                revealLabel: l.revealSource,
              ),
            ),
          ),
        ),
      ),
    );
    _nodeWidgets[id] = (signature: signature, child: child);
    return child;
  }

  /// The palette as drawn: a previewed one, or the map's own.
  MMMapColors _mapColors(MMColors c) =>
      mapPaletteOf(widget.previewStyle?.$2 ?? widget.content.map(widget.mapId)?.palette ?? MapPalette.system)
          .of(c.brightness);

  /// Each node's branch, for the layout it was computed for.
  Map<String, int> _branches = const {};
  Set<String> _firstLevel = const {};
  TreeLayoutResult? _branchesLayout;

  /// The insets, layout and viewport the view was last fitted to while
  /// [MindMapCanvas.fitInsets] is set: each change fits again once.
  (EdgeInsets, TreeLayoutResult, Size)? _lastFit;

  /// How a node is colored by the palette: the root, and the topics of the
  /// first level. Null keeps the node's own look.
  _NodeLook? _lookOf(String id, _NodeSpec spec, MMMapColors palette, MMColors c) {
    if (id == rootNodeId) return _look(palette.root, palette.onRoot, null);
    if (spec.kind != _Kind.topic) return null;
    if (widget.content.summaries.any((s) => s.mapId == widget.mapId && s.cardId == id)) {
      return _look(palette.summary ?? Color.alphaBlend(c.fill, c.canvas), palette.onSummary ?? c.label, null);
    }
    final branch = _branches[id];
    if (branch == null || !_firstLevel.contains(id)) return null;
    return _look(palette.topicFill(branch, c), palette.topicText(branch, c), palette.topicBorder(branch));
  }

  Widget _build(BuildContext context, BoxConstraints viewport) {
    final l = context.l10n;
    final c = context.mmColors;
    final field = this.field;
    final result = _cache.update(
      draft: field == null ? null : (field.id, field.controller.text),
      draftFormat: field?.note?.format,
      widthDraft: _resize,
      markDraft: _markField == null ? null : (_markField!.id, _markField!.controller.text),
      content: widget.content,
      mapId: widget.mapId,
      rootTitle: widget.rootTitle,
      localizations: l,
      theme: Theme.of(context),
      baseStyle: DefaultTextStyle.of(context).style,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.localeOf(context),
      textDirection: Directionality.of(context),
      expanded: widget.expandedCardIds,
      structure: widget.previewStyle?.$1,
    );
    final specs = _cache._specs;
    final palette = _mapColors(c);
    if (!identical(_branchesLayout, result)) {
      _branchesLayout = result;
      _branches = mapBranches(
        result,
        rootNodeId,
        summarySources: {
          for (final s in widget.content.summaries.where((s) => s.mapId == widget.mapId)) ?s.cardId: s.fromId,
        },
      );
      _firstLevel = {
        for (final e in result.edges)
          if (e.parentId == rootNodeId) e.childId,
      };
    }
    _tapModifiers.removeWhere((id, _) => !specs.containsKey(id));
    final collapsed = _cache._collapsed;
    final expandable = _cache._expandable;
    if (field != null) trackField(shown: specs.containsKey(field.id));
    final hadLayout = _layout != null;
    final layoutChanged = !identical(result, _layout);
    final merging = _mergeAnchor != null;
    _animateTo(result, _layout);
    _layout = result;
    final viewportChanged = _viewport != Size(viewport.maxWidth, viewport.maxHeight);
    _viewport = Size(viewport.maxWidth, viewport.maxHeight);
    _fitOnce(result, viewport);
    _keepViewportAnchorInPlace(result);
    _mergeAnchor = null;
    final sceneSize = _sceneSize(result);
    final fitting = widget.fitInsets;
    if (fitting != null) {
      final fit = (fitting, result, _viewport);
      if (fit != _lastFit) {
        _lastFit = fit;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.fitInsets == fitting) _fit(fitting);
        });
      }
    } else if (!merging && ((layoutChanged && hadLayout && _centered) || (viewportChanged && field != null))) {
      _lastFit = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final id = widget.editingCardId ?? _selectedNodeId;
        if (mounted && id != null) _ensureVisible(id, settled: true);
      });
    }

    // Built once per frame of content; the animation only moves them.
    _nodeWidgets.removeWhere((id, _) => !specs.containsKey(id));
    final nodes = {
      for (final id in result.rects.keys)
        if (id != field?.id) id: _nodeWidget(id, specs[id]!, l, _lookOf(id, specs[id]!, palette, c)),
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
        MapAssistantIntent: CallbackAction<MapAssistantIntent>(
          onInvoke: (_) {
            final box = _toolbarKey.currentContext?.findRenderObject();
            if (box is RenderBox) widget.onAssistant?.call(box.localToGlobal(Offset.zero) & box.size);
            return null;
          },
        ),
        MindMapIntent: CallbackAction<MindMapIntent>(
          onInvoke: (intent) {
            if (field == null && _markField == null) _command(intent.command);
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (_, event) {
          // Keys the text field leaves alone must not act on the map.
          if ((event is! KeyDownEvent && event is! KeyRepeatEvent) || field != null || _markField != null) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          final selected = widget.selectedCardId;
          // On macOS ⌥Space types a no-break space, and the Option key can
          // reach the keyboard state after it: never take it for Space (edit).
          if (key == LogicalKeyboardKey.space && event.character == '\u00a0') {
            if (event is KeyDownEvent) _command(MindMapCommand.expand);
            return KeyEventResult.handled;
          }
          for (final entry in mindMapShortcuts.entries) {
            if (entry.key.accepts(event, HardwareKeyboard.instance)) {
              // Navigation repeats below; mutation shortcuts remain single-shot.
              if (event is KeyDownEvent) _command(entry.value);
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.escape) {
            if (event is KeyRepeatEvent) return KeyEventResult.handled;
            if (widget.connectingFromId != null) {
              widget.onCancelConnect?.call();
            } else {
              _deselect();
            }
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
            if (event is! KeyDownEvent || !_isCard(selected) || !isTypingKey(event)) return KeyEventResult.ignored;
            typed = event.character;
            widget.onRename(selected!);
            return KeyEventResult.handled;
          }
          if (meta && (direction == AxisDirection.up || direction == AxisDirection.down)) {
            if (event is KeyDownEvent) widget.onShift(direction == AxisDirection.up ? -1 : 1);
          } else {
            _navigate(direction);
          }
          return KeyEventResult.handled;
        },
        child: Listener(
          onPointerSignal: _pointerSignal,
          child: Stack(
            children: [
              Listener(
                onPointerPanZoomStart: (_) => _pinchScale = 1,
                onPointerPanZoomUpdate: (event) {
                  final previous = _pinchScale;
                  if (previous == null || event.scale == previous || event.scale <= 0) return;
                  _pinchScale = event.scale;
                  _zoomAt(event.localPosition, event.scale / previous);
                },
                onPointerPanZoomEnd: (_) => _pinchScale = null,
                onPointerDown: (event) {
                  _pointerTime = event.timeStamp;
                  _dragPointer = event.position;
                  if (event.kind == PointerDeviceKind.touch) {
                    if (_touchPointers.isEmpty) _touchDragCancelled = false;
                    setState(() => _touchPointers.add(event.pointer));
                    return;
                  }
                  if (field != null ||
                      widget.selectedMarkId != null ||
                      widget.onSelectMany == null ||
                      event.buttons != 1) {
                    return;
                  }
                  final scene = widget.transformation.toScene(event.localPosition);
                  if (result.rects.entries.any((e) => _drawn(e.key, e.value).inflate(MMSpacing.s).contains(scene))) {
                    return;
                  }
                  if (_markAt(scene) != null) return;
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
                onPointerUp: (event) {
                  _touchPointers.remove(event.pointer);
                  _afterPointerUp();
                  setState(() {
                    _boxStart = null;
                    _boxEnd = null;
                  });
                },
                // Runs before the drag ends, so a cancelled drag drops nothing.
                onPointerCancel: (event) {
                  if (event.kind == PointerDeviceKind.touch) _touchDragCancelled = true;
                  _touchPointers.remove(event.pointer);
                  _afterPointerUp();
                  setState(() {
                    _boxStart = null;
                    _boxEnd = null;
                    _drop = null;
                  });
                },
                child: InteractiveViewer(
                  panEnabled: _boxStart == null && _rangePointer == null && _relationDraft == null,
                  // Zooming is handled above to preserve the pointer anchor.
                  scaleEnabled: _touchPointers.isNotEmpty,
                  transformationController: widget.transformation,
                  constrained: false,
                  minScale: mapMinScale,
                  maxScale: mapMaxScale,
                  // A finite scene boundary pins small maps when zoomed out.
                  // Manual panning must work at every scale and viewport height.
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: MMContextMenuRegion(
                    behavior: HitTestBehavior.translucent,
                    longPressHitTest: (point) => _markAt(point) != null,
                    onTapUp: (details) {
                      widget.focusNode.requestFocus();
                      final mark = widget.onSelectMark == null ? null : _markAt(details.localPosition);
                      if (mark != null) {
                        final now = _pointerTime;
                        final last = _lastMarkTap;
                        if (widget.selectedMarkId == mark &&
                            last?.$1 == mark &&
                            now - last!.$2 < kDoubleTapTimeout &&
                            (details.localPosition - last.$3).distance * mapScale(widget.transformation.value) <=
                                kDoubleTapSlop) {
                          widget.onEditMark?.call(mark);
                          _lastMarkTap = null;
                        } else {
                          widget.onSelectMark!(mark);
                          _lastMarkTap = (mark, now, details.localPosition);
                        }
                      } else if (widget.connectingFromId != null) {
                        widget.onCancelConnect?.call();
                      } else {
                        _deselect();
                      }
                    },
                    onSecondaryTapUp: widget.onMarkContextMenu == null
                        ? null
                        : (details) {
                            final mark = _markAt(details.localPosition);
                            if (mark == null) return;
                            widget.focusNode.requestFocus();
                            widget.onSelectMark?.call(mark);
                            widget.onMarkContextMenu!(mark, details.globalPosition);
                          },
                    child: MouseRegion(
                      onHover: widget.connectingFromId == null
                          ? null
                          : (event) => setState(() => _hover = event.localPosition),
                      child: SizedBox(
                        width: math.max(sceneSize.width, 600),
                        height: math.max(sceneSize.height, 400),
                        child: AnimatedBuilder(
                          animation: _motion,
                          builder: (context, _) {
                            // All relation labels share the same frame geometry.
                            late final rects = _drawnRects();
                            late final obstacles = _obstacles(rects, result);
                            return Stack(
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
                                        palette: palette,
                                        branches: _branches,
                                        colors: c,
                                      ),
                                    ),
                                  ),
                                ),
                                if (result.summaries.isNotEmpty ||
                                    _cache._relations.isNotEmpty ||
                                    widget.connectingFromId != null)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        key: const ValueKey('mind-map-marks'),
                                        painter: _MarksPainter(
                                          rects: rects,
                                          leftSide: result.leftSide,
                                          relations: _drawnRelations,
                                          summaries: _summaryPlacements(result),
                                          selectedId: widget.selectedMarkId,
                                          line: c.research,
                                          bracket: c.line,
                                          bracketColors: {
                                            for (final s in _cache._summaryBranches.entries)
                                              if (_branches[s.value] case final branch?) s.key: palette.line(branch, c),
                                          },
                                          accent: c.accent,
                                          connectFrom: widget.connectingFromId,
                                          pointer: _hover,
                                        ),
                                      ),
                                    ),
                                  ),
                                for (final e in result.rects.entries)
                                  if (e.key == field?.id)
                                    _fieldNode(e.key, specs[e.key]!, e.value, _lookOf(e.key, specs[e.key]!, palette, c))
                                  else if (!widget.content.summaries.any(
                                    (s) => s.mapId == widget.mapId && s.cardId == e.key,
                                  ))
                                    Positioned.fromRect(
                                      key: ValueKey(e.key),
                                      rect: _drawn(e.key, e.value),
                                      child: nodes[e.key]!,
                                    ),
                                for (final id in widget.previewCardIds)
                                  if (result.rects[id] case final rect?)
                                    Positioned.fromRect(
                                      rect: _drawn(id, rect).inflate(3),
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          key: ValueKey('map-preview-$id'),
                                          painter: DashedBorderPainter(
                                            color: c.research,
                                            radius: MMRadii.card + 3,
                                            width: 2,
                                            dash: 5,
                                            gap: 3,
                                          ),
                                        ),
                                      ),
                                    ),
                                for (final e in result.summaries.entries)
                                  if (e.value.label.width > 0 &&
                                      (field == null ||
                                          !widget.content.summaries.any((s) => s.id == e.key && s.cardId == field.id)))
                                    Positioned.fromRect(
                                      rect: _rect(e.value.label),
                                      child: _markLabel(e.key, summary: true),
                                    ),
                                for (final r in _cache._relations)
                                  if ((_cache._markLabels[r.id] ?? '').isNotEmpty || r.id == _markField?.id)
                                    if (_relationMiddle(r, obstacles) case (final middle, final side))
                                      if (side < 0)
                                        // Outward on the left, but never off the canvas.
                                        Positioned(
                                          left: math.max(
                                            MMSpacing.xs,
                                            middle.dx - MMSpacing.xs - _relationLabelSize(r.id).width,
                                          ),
                                          top: middle.dy,
                                          child: FractionalTranslation(
                                            translation: const Offset(0, -0.5),
                                            child: _markLabel(r.id, summary: false),
                                          ),
                                        )
                                      else
                                        Positioned(
                                          left: middle.dx + side * MMSpacing.xs,
                                          top: middle.dy,
                                          child: FractionalTranslation(
                                            translation: Offset(side == 0 ? -0.5 : 0, -0.5),
                                            child: _markLabel(r.id, summary: false),
                                          ),
                                        ),
                                ..._interactionWidgets(rects, obstacles),
                                if (_drop case final drop?)
                                  if (drop.previewRect(rects, gap: _siblingGap, thickness: 3) case final rect?)
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
                                if (_dragging == null)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: ValueListenableBuilder<String?>(
                                        valueListenable: _hovered,
                                        builder: (context, hovered, _) => Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            for (final id in {hovered, widget.selectedCardId})
                                              if (specs[id]?.segments.isEmpty ?? false)
                                                if (specs[id]?.meta case final meta?)
                                                  if (result.rects[id!] case final r?)
                                                    if (_shown(id, r) case final shown)
                                                      // Beside the card on its outer side, past the fold
                                                      // button: below it would cover the next sibling.
                                                      if (result.leftSide.contains(id))
                                                        Positioned(
                                                          left: shown.left - _sourceGap(id),
                                                          top: shown.top + MMSpacing.xs,
                                                          child: FractionalTranslation(
                                                            translation: const Offset(-1, 0),
                                                            child: _SourceLabel(meta, maxWidth: shown.width),
                                                          ),
                                                        )
                                                      else
                                                        Positioned(
                                                          left: shown.right + _sourceGap(id),
                                                          top: shown.top + MMSpacing.xs,
                                                          child: _SourceLabel(meta, maxWidth: shown.width),
                                                        ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                for (final id in expandable)
                                  if (result.rects[id] case final r?)
                                    if (_shown(id, r) case final shown)
                                      if (result.leftSide.contains(id))
                                        Positioned(
                                          // Keep an in-flight press attached to its node when
                                          // another fold removes or inserts nearby controls.
                                          key: ValueKey('map-fold-$id'),
                                          left: shown.left - 3,
                                          top: shown.center.dy - 9,
                                          child: FractionalTranslation(
                                            translation: const Offset(-1, 0),
                                            child: foldButtons[id]!,
                                          ),
                                        )
                                      else
                                        Positioned(
                                          key: ValueKey('map-fold-$id'),
                                          left: shown.right + 3,
                                          top: shown.center.dy - 9,
                                          child: foldButtons[id]!,
                                        ),
                                ?_resizeHandle(result, l),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // The marquee belongs to the viewport: the finite map scene
              // must not clip it when selecting across empty canvas space.
              if (_boxStart != null && _boxEnd != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: widget.transformation,
                      builder: (context, _) => Stack(
                        children: [
                          Positioned.fromRect(
                            rect: MatrixUtils.transformRect(
                              widget.transformation.value,
                              Rect.fromPoints(_boxStart!, _boxEnd!),
                            ),
                            child: DecoratedBox(
                              key: const ValueKey('map-selection-box'),
                              decoration: BoxDecoration(
                                color: c.accentTint,
                                border: Border.all(color: c.accent),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if ((widget.selectionToolbar != null && field?.note == null && widget.connectingFromId == null) ||
                  widget.mergePreviewCardId != null)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([widget.transformation, _motion]),
                    builder: (context, _) {
                      final selected = [
                        for (final id in {
                          ...widget.selectedCardIds,
                          ?widget.selectedCardId,
                          if (widget.rootSelected) rootNodeId,
                        })
                          if (result.rects[id] case final rect?)
                            MatrixUtils.transformRect(widget.transformation.value, _shown(id, rect)),
                      ];
                      if (selected.isEmpty) return const SizedBox.shrink();
                      final bounds = selected.reduce((a, b) => a.expandToInclude(b));
                      final preview = result.rects[widget.mergePreviewCardId];
                      return Stack(
                        children: [
                          if (preview != null)
                            Positioned.fromRect(
                              rect: MatrixUtils.transformRect(
                                widget.transformation.value,
                                _shown(widget.mergePreviewCardId!, preview),
                              ).inflate(7),
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: DashedBorderPainter(
                                    color: context.mmColors.accent,
                                    radius: 16,
                                    width: 2,
                                    dash: 5,
                                    gap: 4,
                                  ),
                                ),
                              ),
                            ),
                          if (widget.selectionToolbar != null && field?.note == null && widget.connectingFromId == null)
                            Positioned.fill(
                              child: CustomSingleChildLayout(
                                delegate: _SelectionToolbarLayout(bounds, widget.toolbarTopInset),
                                child: SingleChildScrollView(
                                  key: _toolbarKey,
                                  scrollDirection: Axis.horizontal,
                                  child: widget.selectionToolbar!,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              if (field?.note case final note? when specs[field!.id]?.kind == _Kind.note)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([widget.transformation, _motion]),
                    builder: (context, _) {
                      final rect = result.rects[field.id];
                      if (rect == null) return const SizedBox.shrink();
                      final shown = _shown(field.id, rect);
                      final m = widget.transformation.value;
                      final top = MatrixUtils.transformPoint(m, shown.topLeft);
                      final bottom = MatrixUtils.transformPoint(m, shown.bottomLeft);
                      // Above the note, or below it when there is no room.
                      final above = top.dy >= widget.toolbarTopInset + _formatBarHeight + MMSpacing.s;
                      return Stack(
                        children: [
                          Positioned(
                            left: math.max(MMSpacing.xs, top.dx),
                            top: above ? top.dy - MMSpacing.s : bottom.dy + MMSpacing.s,
                            child: FractionalTranslation(
                              translation: Offset(0, above ? -1 : 0),
                              child: NoteFormatBar(controller: note),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              if (widget.touchSelectionMode == null &&
                  MMInput.touchInputOf(context) &&
                  (widget.onToggleSelection != null || widget.onSelectMany != null))
                Positioned(
                  top: MMSizes.toolbarHeight + MMSpacing.xl,
                  right: MMSpacing.s,
                  child: SizedBox(
                    height: 44,
                    child: MMButton(
                      key: const ValueKey('map-multi-select'),
                      label: l.mapMultiSelect,
                      icon: _touchSelection ? MMIcons.check : Icons.checklist,
                      variant: _touchSelection ? MMButtonVariant.primary : MMButtonVariant.secondary,
                      onPressed: () => setState(() => _localTouchSelection = !_localTouchSelection),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeView extends StatelessWidget {
  const _NodeView({
    required this.spec,
    required this.transformation,
    required this.selected,
    required this.flashing,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTapUp,
    required this.onReveal,
    required this.revealLabel,
    this.editor,
    this.onPressStart,
    this.onToggleExpanded,
    this.expandLabel = '',
    this.collapseLabel = '',
    this.onOpenNote,
    this.longPressEnabled = true,
    this.flashAnnotationId,
    this.onRevealSegment,
    this.look,
  });

  /// The palette's colors for the root or a first-level topic.
  final _NodeLook? look;

  /// A research card's "whole note and citations" link.
  final VoidCallback? onOpenNote;
  final bool longPressEnabled;
  final String? flashAnnotationId;
  final ValueChanged<int>? onRevealSegment;

  /// Shows a cut card's whole text, or its preview again.
  final VoidCallback? onToggleExpanded;
  final String expandLabel;
  final String collapseLabel;

  /// Replaces the title (a note's text) while it is edited in place; the
  /// node then takes no gestures of its own.
  final Widget? editor;
  final ValueChanged<Offset>? onSecondaryTapUp;
  final _NodeSpec spec;
  final TransformationController transformation;
  final bool selected;
  final bool flashing;
  final VoidCallback onTap;
  final ValueChanged<PointerDeviceKind>? onPressStart;
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
    final (Color own, double radius, List<BoxShadow> shadow) = switch (spec.kind) {
      _Kind.root => (
        c.rootNode,
        14.0,
        [const BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      _Kind.topic => (Color.alphaBlend(c.fill, c.canvas), 12.0, const <BoxShadow>[]),
      _Kind.excerpt || _Kind.image => (c.card, 12.0, c.cardShadow),
      _Kind.note => (Color.alphaBlend(c.quaternaryFill, c.canvas), 12.0, const <BoxShadow>[]),
      _Kind.research => (c.card, 12.0, c.cardShadow),
    };
    final bg = look?.fill ?? own;

    final Widget content = switch (spec.kind) {
      _Kind.root => Center(
        child: Text(
          spec.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.title3.copyWith(color: look?.text ?? c.onRootNode),
        ),
      ),
      _Kind.topic =>
        editor == null
            ? Center(
                child: Text(spec.title, style: t.headline.copyWith(color: look?.text)),
              )
            : Center(child: editor),
      _Kind.note => Row(
        children: [
          Opacity(opacity: 0.6, child: Icon(MMIcons.pen, size: 13, color: c.label)),
          const SizedBox(width: 7),
          Expanded(child: editor ?? Text.rich(noteSpan(spec.title, spec.format, t.body.copyWith(height: 19 / 13)))),
        ],
      ),
      // One note, also attached to the source: the map shows its title and
      // the start of its text; the whole note opens in the details.
      _Kind.research => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(MMIcons.research, size: 11, color: c.research),
              const SizedBox(width: MMSpacing.xs),
              Expanded(
                child: Text(
                  spec.meta ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.subheadline.copyWith(color: c.research, height: 14 / 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: MMSpacing.xs),
          Text(spec.title, style: _NodeSpec.titleStyle),
          if (spec.quote?.isNotEmpty ?? false) ...[
            const SizedBox(height: MMSpacing.xxs),
            Text(spec.quote!, style: _NodeSpec.researchBodyStyle.copyWith(color: c.secondaryLabel)),
          ],
          const SizedBox(height: MMSpacing.s - MMSpacing.xxs),
          _ExpandToggle(expanded: false, label: expandLabel, onTap: onOpenNote, color: c.research),
        ],
      ),
      // The excerpt is the card: a title row only when there is a title.
      _Kind.excerpt || _Kind.image => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (spec.title.isNotEmpty || editor != null) ...[
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
                        maxLines: spec.expanded ? null : 1,
                        overflow: spec.expanded ? null : TextOverflow.ellipsis,
                        style: t.headline.copyWith(height: 17 / 13),
                      ),
                ),
              ],
            ),
            if (spec.kind != _Kind.image || spec.imageHeight > 0) const SizedBox(height: 6),
          ],
          // A compact map leaves the picture out.
          if (spec.kind == _Kind.image && spec.imageHeight == 0)
            const SizedBox.shrink()
          else if (spec.kind == _Kind.image)
            SizedBox(
              height: spec.imageHeight,
              // A PDF selection is rectangular: masking its corners can
              // remove text or diagram borders right at the selected edge.
              child: ColoredBox(
                color: spec.color!.cardTint,
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: transformation,
                  builder: (context, matrix, _) => CardImage(spec.image ?? '', displayScale: mapScale(matrix)),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: spec.color!.cardTint,
                borderRadius: BorderRadius.circular(MMRadii.excerpt),
              ),
              child: spec.segments.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, segment) in spec.segments.indexed) ...[
                          if (index > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: CustomPaint(
                                size: const Size(double.infinity, 1),
                                painter: _SegmentDivider(c.separator),
                              ),
                            ),
                          GestureDetector(
                            onTap: segment.annotationId == null ? null : () => onRevealSegment?.call(index),
                            child: ColoredBox(
                              color: segment.annotationId != null && segment.annotationId == flashAnnotationId
                                  ? c.accentTint
                                  : Colors.transparent,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 6, right: 6),
                                    width: 6,
                                    height: 6,
                                    // "Own words" segments have no source colour.
                                    decoration: segment.annotationId == null
                                        ? null
                                        : BoxDecoration(shape: BoxShape.circle, color: segment.color.color),
                                  ),
                                  Expanded(
                                    child: Text(
                                      segment.text,
                                      style: segment.annotationId == null ? t.body : t.readingExcerpt,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (spec.meta != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(spec.meta!, style: t.footnote, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    )
                  : Text(
                      spec.quote ?? '',
                      maxLines: spec.expanded ? null : spec.maxLines,
                      overflow: spec.expanded ? null : TextOverflow.ellipsis,
                      style: t.readingExcerpt,
                    ),
            ),
          if (spec.truncated)
            Padding(
              padding: const EdgeInsets.only(top: _NodeSpec.toggleGap),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _ExpandToggle(
                  expanded: spec.expanded,
                  label: spec.expanded ? collapseLabel : expandLabel,
                  onTap: onToggleExpanded,
                ),
              ),
            ),
        ],
      ),
    };

    // A card's content is laid out at its new size at once while the card
    // grows or shrinks to it (expanding, a title row appearing): it is
    // revealed from the top rather than squeezed.
    final sized = spec.kind == _Kind.excerpt || spec.kind == _Kind.image || spec.kind == _Kind.research
        ? ClipRect(
            child: OverflowBox(
              alignment: AlignmentDirectional.topStart,
              minHeight: 0,
              maxHeight: double.infinity,
              child: content,
            ),
          )
        : content;
    // Only the content fades: the selection ring and reveal button stay crisp.
    final body = spec.suspended ? Opacity(opacity: _suspendedOpacity, child: sized) : sized;

    final padding = switch (spec.kind) {
      _Kind.root => const EdgeInsets.symmetric(horizontal: 18),
      _Kind.topic => const EdgeInsets.symmetric(horizontal: 14),
      _Kind.excerpt || _Kind.image => const EdgeInsets.fromLTRB(12, 11, 38, 11),
      _Kind.note => const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      _Kind.research => const EdgeInsets.fromLTRB(15, 10, 12, 10),
    };

    if (editor != null) return _decorated(c, bg, radius, shadow, ring, body, padding);
    return Listener(
      onPointerDown: (event) => onPressStart?.call(event.kind),
      child: MMContextMenuRegion(
        longPressEnabled: longPressEnabled,
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
      immediateTap: true,
      selected: selected,
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
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: look?.border == null ? null : Border.all(color: look!.border!, width: _outlineWidth),
        boxShadow: [...shadow, ...ring],
      ),
      // The reveal button sits in the right padding, inside the node's box
      // so it receives clicks.
      child: Stack(
        children: [
          if (spec.kind == _Kind.research)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(radius)),
                child: ColoredBox(color: c.research),
              ),
            ),
          Positioned.fill(
            child: Padding(padding: padding, child: body),
          ),
          if (onReveal != null)
            Positioned(
              top: padding.top - 3,
              right: padding.right - 30,
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

/// A node's colors from the map palette: fill, text and optional outline.
typedef _NodeLook = ({Color fill, Color text, Color? border});

_NodeLook _look(Color fill, Color text, Color? border) => (fill: fill, text: text, border: border);

/// Width of a first-level topic's outline (the ink palette).
const _outlineWidth = 1.5;

Rect _rect(LayoutRect r) => Rect.fromLTWH(r.left, r.top, r.width, r.height);

Rect _lerpRect(Rect? from, Rect to, double t) => from == null || t >= 1 ? to : Rect.lerp(from, to, t)!;

class _EdgesPainter extends CustomPainter {
  _EdgesPainter(this.layout, this.color, this.from, this.t, {this.palette, this.branches = const {}, this.colors});

  final TreeLayoutResult layout;

  /// The neutral line color; branches take the [palette]'s.
  final Color color;
  final MMMapColors? palette;
  final Map<String, int> branches;
  final MMColors? colors;

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
    for (final connector in mapConnectors(layout, _at, rootId: rootNodeId)) {
      final branch = connector.colorId == null ? null : branches[connector.colorId];
      paint.color = branch == null || palette == null || colors == null ? color : palette!.line(branch, colors!);
      canvas.drawPath(connector.path, paint);
    }
  }

  Rect _at(String id) => _lerpRect(from[id], _rect(layout.rects[id]!), MMMotion.layoutCurve.transform(t));

  @override
  bool shouldRepaint(_EdgesPainter old) =>
      old.layout != layout ||
      old.color != color ||
      !identical(old.from, from) ||
      old.t != t ||
      old.palette != palette ||
      !identical(old.branches, branches) ||
      old.colors != colors;
}

/// "Show full text ⌄" / "Show less ⌃" at the foot of a cut card.
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({required this.expanded, required this.label, required this.onTap, this.color});

  final bool expanded;
  final String label;
  final VoidCallback? onTap;

  /// Accent by default; a research card's link is in the research color and
  /// points on (to the details) instead of down.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final tint = color ?? c.accent;
    final height = MediaQuery.textScalerOf(context).scale(_NodeSpec.toggleLineHeight);
    return MMInteractive(
      onTap: onTap,
      enabled: onTap != null,
      semanticLabel: label,
      canRequestFocus: false,
      builder: (context, state) => SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.mmText.footnote.copyWith(
                  color: tint,
                  decoration: state.hovered ? TextDecoration.underline : null,
                  decorationColor: tint,
                ),
              ),
            ),
            const SizedBox(width: MMSpacing.xxs),
            Icon(
              color != null ? MMIcons.chevronRight : (expanded ? MMIcons.chevronUp : MMIcons.chevronDown),
              size: 9,
              color: tint,
            ),
          ],
        ),
      ),
    );
  }
}

/// A card's source (document and page), shown beside it while it is hovered
/// or selected rather than on every card.
class _SourceLabel extends StatelessWidget {
  const _SourceLabel(this.text, {required this.maxWidth});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(MMRadii.excerpt),
          boxShadow: c.cardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs, vertical: MMSpacing.xxs),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mmText.footnote),
        ),
      ),
    );
  }
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
        opacity: collapsed || s.hovered || MMInput.touchInputOf(context) ? 1 : 0.45,
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

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (length2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / length2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Relation lines (dashed, with an arrow at the target), summary brackets
/// and, while a relation is being drawn, a line to the pointer.
class _MarksPainter extends CustomPainter {
  _MarksPainter({
    required this.rects,
    this.leftSide = const {},
    required this.relations,
    required this.summaries,
    required this.selectedId,
    required this.line,
    required this.bracket,
    this.bracketColors = const {},
    required this.accent,
    this.connectFrom,
    this.pointer,
  });

  final Map<String, Rect> rects;
  final Set<String> leftSide;
  final List<MapRelation> relations;
  final Map<String, SummaryPlacement> summaries;
  final String? selectedId;
  final Color line;
  final Color bracket;

  /// Brackets in their branch's palette color, by summary id.
  final Map<String, Color> bracketColors;
  final Color accent;
  final String? connectFrom;
  final Offset? pointer;

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final e in summaries.entries) {
      final selected = e.key == selectedId;
      canvas.drawPath(
        _bracketPath(_rect(e.value.bracket), left: e.value.left),
        stroke(selected ? accent : bracketColors[e.key] ?? bracket, selected ? 2 : 1.5),
      );
    }
    final others = [...rects.values, for (final s in summaries.values) _rect(s.label)];
    for (final r in relations) {
      final a = rects[r.fromId], b = rects[r.toId];
      if (a == null || b == null) continue;
      final selected = r.id == selectedId;
      final c = mapRelationCurve(
        r,
        a,
        b,
        others,
        left: leftSide.contains(r.fromId) && leftSide.contains(r.toId),
        root: rects[rootNodeId],
      );
      final paint = stroke(selected ? accent : line, selected ? 2 : 1.5);
      final path = Path()
        ..moveTo(c.$1.dx, c.$1.dy)
        ..cubicTo(c.$2.dx, c.$2.dy, c.$3.dx, c.$3.dy, c.$4.dx, c.$4.dy);
      if (r.solid) {
        canvas.drawPath(path, paint);
      } else {
        _dashed(canvas, path, paint);
      }
      if (r.arrow != RelationArrow.none) _arrow(canvas, c.$3, c.$4, paint);
      if (r.arrow == RelationArrow.both) _arrow(canvas, c.$2, c.$1, paint);
    }
    final from = connectFrom == null ? null : rects[connectFrom];
    if (from != null && pointer != null && !from.contains(pointer!)) {
      final c = relationCurveOnSide(
        from,
        Rect.fromCenter(center: pointer!, width: 0, height: 0),
        others,
        left: leftSide.contains(connectFrom),
      );
      final paint = stroke(accent, 1.5);
      final path = Path()
        ..moveTo(c.$1.dx, c.$1.dy)
        ..cubicTo(c.$2.dx, c.$2.dy, c.$3.dx, c.$3.dy, c.$4.dx, c.$4.dy);
      _dashed(canvas, path, paint);
      _arrow(canvas, c.$3, c.$4, paint);
    }
  }

  /// A right curly brace filling [r]: ends at the left, point at the right;
  /// mirrored on the [left] side.
  static Path _bracketPath(Rect r, {bool left = false}) {
    final m = r.left + r.width / 2, cy = r.center.dy;
    final k = math.min(r.width / 2, r.height / 4);
    final path = Path()
      ..moveTo(r.left, r.top)
      ..quadraticBezierTo(m, r.top, m, r.top + k)
      ..lineTo(m, cy - k)
      ..quadraticBezierTo(m, cy, r.right, cy)
      ..quadraticBezierTo(m, cy, m, cy + k)
      ..lineTo(m, r.bottom - k)
      ..quadraticBezierTo(m, r.bottom, r.left, r.bottom);
    if (!left) return path;
    final mirror = Matrix4.identity()
      ..translateByDouble(r.left + r.right, 0, 0, 1)
      ..scaleByDouble(-1, 1, 1, 1);
    return path.transform(mirror.storage);
  }

  static void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  static void _arrow(Canvas canvas, Offset control, Offset tip, Paint paint) {
    final d = tip - control;
    if (d.distance == 0) return;
    final angle = d.direction;
    const spread = 0.45, length = 8.0;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - length * math.cos(angle - spread), tip.dy - length * math.sin(angle - spread))
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - length * math.cos(angle + spread), tip.dy - length * math.sin(angle + spread)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MarksPainter old) =>
      !mapEquals(old.rects, rects) ||
      !identical(old.leftSide, leftSide) ||
      !identical(old.relations, relations) ||
      !identical(old.summaries, summaries) ||
      old.selectedId != selectedId ||
      old.line != line ||
      old.bracket != bracket ||
      !mapEquals(old.bracketColors, bracketColors) ||
      old.accent != accent ||
      old.connectFrom != connectFrom ||
      old.pointer != pointer;
}

/// The label of a summary (filled like a topic) or of a relation (on the
/// canvas color, covering the line beneath it).
class _MarkLabel extends StatelessWidget {
  const _MarkLabel({
    super.key,
    required this.text,
    required this.style,
    required this.summary,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.editor,
    this.fill,
  });

  /// A summary's palette fill, in place of the topic fill.
  final Color? fill;

  final String text;
  final TextStyle style;
  final bool summary;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset>? onSecondaryTapUp;
  final Widget? editor;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    Widget box(Widget child) => DecoratedBox(
      decoration: BoxDecoration(
        color: summary ? fill ?? Color.alphaBlend(c.fill, c.canvas) : c.canvas,
        borderRadius: BorderRadius.circular(summary ? MMRadii.card : MMRadii.excerpt),
        boxShadow: [if (selected) BoxShadow(color: c.accent, spreadRadius: 2)],
      ),
      child: Padding(
        padding: summary
            ? const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s)
            : const EdgeInsets.symmetric(horizontal: MMSpacing.xs, vertical: MMSpacing.xxs),
        child: child,
      ),
    );
    if (editor != null) return box(Center(widthFactor: 1, heightFactor: 1, child: editor));
    return MMContextMenuRegion(
      onSecondaryTapUp: onSecondaryTapUp == null ? null : (d) => onSecondaryTapUp!(d.globalPosition),
      child: MMInteractive(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        immediateTap: true,
        selected: selected,
        semanticLabel: text,
        builder: (context, _) => box(Text(text, style: style)),
      ),
    );
  }
}

/// Both recognizers see pointer down before the first rebuild. Filtering at
/// recognizer creation preserves mouse/Pencil drags on hybrid devices.
class _PointerDraggable extends Draggable<String> {
  const _PointerDraggable({
    required this.touch,
    this.canStart,
    required super.data,
    required super.feedback,
    required super.child,
    required super.onDragStarted,
    required super.onDragUpdate,
    required super.onDragEnd,
  }) : super(dragAnchorStrategy: pointerDragAnchorStrategy, maxSimultaneousDrags: 1);

  final bool touch;
  final bool Function()? canStart;

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) {
    if (!touch) {
      return ImmediateMultiDragGestureRecognizer(
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.unknown,
        },
      )..onStart = onStart;
    }
    return _TouchDragGestureRecognizer(canStart ?? () => true)
      ..onStart = (position) {
        final drag = onStart(position);
        if (drag != null) HapticFeedback.selectionClick();
        return drag;
      };
  }
}

/// Decide before accepting the arena: returning null from onStart is too late
/// to leave the ancestor's scale recognizer available for a held pinch.
class _TouchDragGestureRecognizer extends MultiDragGestureRecognizer {
  _TouchDragGestureRecognizer(this.canStart)
    : super(debugOwner: null, supportedDevices: const {PointerDeviceKind.touch});
  final bool Function() canStart;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _TouchDragPointerState(event, gestureSettings, canStart);

  @override
  String get debugDescription => 'touch node long press';
}

class _TouchDragPointerState extends MultiDragPointerState {
  _TouchDragPointerState(PointerDownEvent event, DeviceGestureSettings? settings, this.canStart)
    : super(event.position, event.kind, settings) {
    _timer = Timer(kLongPressTimeout, () {
      _timer = null;
      if (!canStart()) {
        resolve(GestureDisposition.rejected);
        return;
      }
      _ready = true;
      final starter = _starter;
      if (starter != null) {
        _starter = null;
        starter(initialPosition);
      } else {
        resolve(GestureDisposition.accepted);
      }
    });
  }
  final bool Function() canStart;
  Timer? _timer;
  bool _ready = false;
  GestureMultiDragStartCallback? _starter;

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_ready) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    if (!_ready && pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      _timer?.cancel();
      _timer = null;
      resolve(GestureDisposition.rejected);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _SegmentDivider extends CustomPainter {
  const _SegmentDivider(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 3, size.width), 0), pen);
    }
  }

  @override
  bool shouldRepaint(_SegmentDivider old) => old.color != color;
}

class _SelectionToolbarLayout extends SingleChildLayoutDelegate {
  const _SelectionToolbarLayout(this.bounds, this.topInset);
  final Rect bounds;
  final double topInset;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.max(0, constraints.maxWidth - 16), maxHeight: constraints.maxHeight);
  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (bounds.center.dx - childSize.width / 2).clamp(8.0, math.max(8.0, size.width - childSize.width - 8)),
    // Clear of the add-child button on the node's top corner.
    (bounds.top - childSize.height - 22).clamp(topInset, math.max(topInset, size.height - childSize.height - 8)),
  );
  @override
  bool shouldRelayout(_SelectionToolbarLayout old) => old.bounds != bounds || old.topInset != topInset;
}
