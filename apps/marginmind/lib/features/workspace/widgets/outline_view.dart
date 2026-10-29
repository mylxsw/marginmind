import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import 'card_field.dart';

/// Finder-style outline of the map: indentation per level, accent-filled
/// selection. Rows are edited in place with the map's shortcuts, so a tree
/// can be written with the keyboard alone. Double-click reveals an excerpt
/// in the source or edits a topic / note.
class OutlineView extends StatefulWidget {
  const OutlineView({
    super.key,
    required this.content,
    this.mapId = MindMap.defaultId,
    required this.rootTitle,
    required this.selectedCardId,
    required this.focusNode,
    required this.onSelect,
    required this.onReveal,
    required this.onRename,
    required this.onDelete,
    required this.onAddChild,
    required this.onShift,
    this.onCommand,
    this.selectedCardIds = const {},
    this.onToggleSelection,
    this.editingCardId,
    this.onEditDone,
    this.onEditCancel,
  });

  final StudySetContent content;
  final String mapId;
  final String rootTitle;
  final String? selectedCardId;
  final Set<String> selectedCardIds;
  final ValueChanged<String>? onToggleSelection;
  final FocusNode focusNode;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onReveal;

  /// Double-click, F2, Space or typing on a selected row. The caller
  /// answers by setting [editingCardId].
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  /// Tab: new child topic under the selection.
  final VoidCallback onAddChild;

  /// ⌘↑ / ⌘↓.
  final ValueChanged<int> onShift;

  /// Sibling, parent and promote commands, as on the map.
  final ValueChanged<MindMapCommand>? onCommand;

  /// Card whose title (a note's text) is shown as a text field.
  final String? editingCardId;
  final CardEditDone? onEditDone;
  final VoidCallback? onEditCancel;

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<OutlineView> with CardFieldHost<OutlineView> {
  final _rowKeys = <String?, GlobalKey>{};
  final _scroll = ScrollController();
  static const _padding = EdgeInsets.fromLTRB(16, 76, 16, 72);

  /// Rows top to bottom (null = the root), for ↑ / ↓.
  List<String?> _order = const [null];
  Map<String?, int> _indices = const {null: 0};
  Map<String?, List<MapNode>> _children = const {};
  Map<String, MapNode> _nodes = const {};
  List<_OutlineEntry> _entries = const [];
  final _rows = <String?, _OutlineRow>{};
  StudySetContent? _content;
  String? _mapId;
  Object? _rowEnvironment;

  /// Content is immutable. Index it once per snapshot instead of scanning
  /// every node/card again on each selection or editor keystroke.
  void _updateEntries() {
    if (identical(_content, widget.content) && _mapId == widget.mapId) return;
    _content = widget.content;
    _mapId = widget.mapId;
    final content = widget.content;
    final cards = {for (final card in content.cards) card.id: card};
    final annotations = {for (final annotation in content.annotations) annotation.id: annotation};
    final notes = {for (final note in content.researchNotes) note.id: note};
    final children = <String?, List<MapNode>>{};
    _nodes = {};
    for (final node in content.nodes) {
      if (node.mapId != widget.mapId) continue;
      (children[node.parentId] ??= []).add(node);
      _nodes[node.cardId] = node;
    }
    for (final siblings in children.values) {
      siblings.sort((a, b) => a.order.compareTo(b.order));
    }
    _children = children;
    final entries = <_OutlineEntry>[const _OutlineEntry(depth: 0)];
    final pending = [for (final node in (children[null] ?? const <MapNode>[]).reversed) (node, 1)];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final (node, depth) = pending.removeLast();
      final card = cards[node.cardId];
      if (card == null || !seen.add(card.id)) continue;
      entries.add(
        _OutlineEntry(
          depth: depth,
          card: card,
          annotation: annotations[card.annotationId],
          researchTitle: notes[card.researchNoteId]?.title ?? '',
        ),
      );
      for (final child in (children[card.id] ?? const <MapNode>[]).reversed) {
        pending.add((child, depth + 1));
      }
    }
    _entries = entries;
    _order = [for (final entry in entries) entry.card?.id];
    _indices = {for (var i = 0; i < _order.length; i++) _order[i]: i};
    _rowKeys.removeWhere((id, _) => !_indices.containsKey(id));
    _rows.clear();
  }

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

  @override
  void initState() {
    super.initState();
    syncField();
    // Switching to the outline hands it the keyboard, as the map has it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && field == null) widget.focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(OutlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncField();
    typed = null;
    if (widget.selectedCardId != oldWidget.selectedCardId) {
      final id = widget.selectedCardId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(id));
    }
  }

  @override
  void dispose() {
    disposeField();
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls just enough to show a row clear of the floating controls
  /// (the list's own padding).
  void _ensureVisible(String? id) {
    final box = _rowKeys[id]?.currentContext?.findRenderObject();
    if (!mounted || box is! RenderBox || !box.attached || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.of(box);
    final position = _scroll.position;
    final top = viewport.getOffsetToReveal(box, 0).offset - _padding.top;
    final bottom = viewport.getOffsetToReveal(box, 1).offset + _padding.bottom;
    final target = (position.pixels > top ? top : (position.pixels < bottom ? bottom : position.pixels)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    if (MMAppearance.reduceMotionOf(context)) {
      position.jumpTo(target);
    } else {
      position.animateTo(target, duration: MMMotion.standard, curve: MMMotion.layoutCurve);
    }
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
      case MindMapCommand.up || MindMapCommand.down:
        if (selected != null) widget.onShift(command == MindMapCommand.up ? -1 : 1);
      case MindMapCommand.copy || MindMapCommand.cut || MindMapCommand.paste:
        widget.onCommand?.call(command);
      case MindMapCommand.siblingAfter ||
          MindMapCommand.siblingBefore ||
          MindMapCommand.parent ||
          MindMapCommand.promote ||
          MindMapCommand.merge:
        if (selected != null) widget.onCommand?.call(command);
      // The outline always shows the whole tree and has no viewport to fit.
      // Relations and summaries are drawn on the map only.
      case MindMapCommand.fold ||
          MindMapCommand.expand ||
          MindMapCommand.fit ||
          MindMapCommand.center ||
          MindMapCommand.relation ||
          MindMapCommand.summary:
        break;
    }
  }

  /// ↑ / ↓ move row by row; ← goes to the parent, → to the first child.
  void _navigate(AxisDirection direction) {
    final selected = widget.selectedCardId;
    final String? target;
    switch (direction) {
      case AxisDirection.up || AxisDirection.down:
        final i = (_indices[selected] ?? -1) + (direction == AxisDirection.up ? -1 : 1);
        if (i < 0 || i >= _order.length) return;
        target = _order[i];
      case AxisDirection.left:
        if (selected == null) return;
        target = _nodes[selected]?.parentId;
      case AxisDirection.right:
        final children = _children[selected] ?? const <MapNode>[];
        if (children.isEmpty) return;
        target = children.first.cardId;
    }
    widget.onSelect(target);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    // Keys the text field leaves alone must not act on the outline.
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) || field != null) return KeyEventResult.ignored;
    for (final entry in mindMapShortcuts.entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        // Navigation repeats below; mutation shortcuts remain single-shot.
        if (event is KeyDownEvent) _command(entry.value);
        return KeyEventResult.handled;
      }
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) widget.onSelect(null);
      return KeyEventResult.handled;
    }
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => AxisDirection.left,
      LogicalKeyboardKey.arrowRight => AxisDirection.right,
      LogicalKeyboardKey.arrowUp => AxisDirection.up,
      LogicalKeyboardKey.arrowDown => AxisDirection.down,
      _ => null,
    };
    if (direction != null) {
      _navigate(direction);
      return KeyEventResult.handled;
    }
    final selected = widget.selectedCardId;
    if (event is! KeyDownEvent || selected == null || widget.content.card(selected) == null || !isTypingKey(event)) {
      return KeyEventResult.ignored;
    }
    typed = event.character;
    widget.onRename(selected);
    return KeyEventResult.handled;
  }

  GlobalKey _keyFor(String? id) => _rowKeys.putIfAbsent(id, GlobalKey.new);

  void _tap(String? id, bool additive) {
    widget.focusNode.requestFocus();
    if (id != null && additive && widget.onToggleSelection != null) {
      widget.onToggleSelection!(id);
    } else {
      widget.onSelect(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.mmText;
    final f = field;
    _updateEntries();
    final environment = (l, Theme.of(context), widget.rootTitle);
    if (_rowEnvironment != environment) {
      _rowEnvironment = environment;
      _rows.clear();
    }
    final rows = <Widget>[];
    for (final entry in _entries) {
      final card = entry.card;
      final id = card?.id;
      final selected = id == widget.selectedCardId || (id != null && widget.selectedCardIds.contains(id));
      final cached = _rows[id];
      // Identical widgets let Flutter skip the unchanged row subtrees,
      // including text layout. Only the old/new selections need updating.
      if (cached != null && cached.selected == selected && cached.editor == null && (f == null || f.id != id)) {
        rows.add(cached);
        continue;
      }
      if (card == null) {
        rows.add(
          _rows[id] = _OutlineRow(
            key: _keyFor(null),
            depth: 0,
            label: widget.rootTitle,
            bold: true,
            selected: selected,
            onTap: (additive) => _tap(null, additive),
          ),
        );
        continue;
      }
      final annotation = entry.annotation;
      final isExcerpt = card.kind == CardKind.excerpt;
      final quote = widget.content.segmentsOf(card).map((s) => s.text).join('\n');
      final isImage = card.kind == CardKind.image;
      final bold = card.kind == CardKind.topic;
      rows.add(
        _rows[id] = _OutlineRow(
          key: _keyFor(id),
          depth: entry.depth,
          label: isExcerpt
              ? (card.title.isEmpty ? quote : card.title)
              : isImage && card.title.isEmpty && f?.id != id
              ? l.imageExcerpt
              : card.kind == CardKind.research
              ? l.researchNoteLabel(entry.researchTitle)
              : notePlainText(card.title, card.textFormat),
          sub: isExcerpt && (card.title.isNotEmpty || f?.id == id) ? quote : null,
          meta: annotation == null ? null : l.pageNumber(annotation.page),
          dot: isExcerpt || isImage ? MMAnnotationColor.fromIndex(annotation?.colorIndex ?? 0).color : null,
          bold: bold,
          suspended: card.suspended,
          selected: selected,
          onTap: (additive) => _tap(card.id, additive),
          onDoubleTap: () =>
              isExcerpt || (isImage && annotation != null) ? widget.onReveal(card.id) : widget.onRename(card.id),
          editor: f?.id == id
              ? fieldEditor(
                  f!,
                  style: _OutlineRow.labelStyle(t, bold: bold),
                  kind: card.kind,
                  label: card.title,
                )
              : null,
        ),
      );
    }
    if (f != null) trackField(shown: _indices.containsKey(f.id));
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
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.focusNode.requestFocus,
          // Every row is built, so any of them can be scrolled to.
          child: SingleChildScrollView(
            controller: _scroll,
            padding: _padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rows,
                if (rows.length == 1)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.outlineEmpty, textAlign: TextAlign.center, style: t.footnote),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineEntry {
  const _OutlineEntry({required this.depth, this.card, this.annotation, this.researchTitle = ''});
  final int depth;
  final Card? card;
  final Annotation? annotation;
  final String researchTitle;
}

class _OutlineRow extends StatefulWidget {
  const _OutlineRow({
    super.key,
    required this.depth,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
    this.sub,
    this.meta,
    this.dot,
    this.bold = false,
    this.suspended = false,
    this.editor,
  });

  final int depth;
  final String label;
  final String? sub;
  final String? meta;
  final Color? dot;
  final bool bold;

  /// Kept out of review: the label is shown in the secondary color.
  final bool suspended;
  final bool selected;
  final ValueChanged<bool> onTap;
  final VoidCallback? onDoubleTap;

  /// Replaces the label while it is edited in place.
  final Widget? editor;

  static TextStyle labelStyle(MMTextStyles t, {required bool bold}) =>
      t.body.copyWith(fontWeight: bold ? FontWeight.w600 : FontWeight.w400, height: 20 / 13);

  @override
  State<_OutlineRow> createState() => _OutlineRowState();
}

class _OutlineRowState extends State<_OutlineRow> {
  bool _selectedOnPointerDown = false;
  bool _tapAdditive = false;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final editing = widget.editor != null;
    // The field keeps the row's normal colors so the text stays readable.
    final fg = widget.selected && !editing
        ? c.onAccent
        : widget.suspended
        ? c.secondaryLabel
        : c.label;
    final fg2 = widget.selected && !editing ? c.onAccent.withValues(alpha: 0.85) : c.secondaryLabel;
    return Listener(
      onPointerDown: (event) {
        final keyboard = HardwareKeyboard.instance;
        _tapAdditive = keyboard.isShiftPressed || keyboard.isMetaPressed || keyboard.isControlPressed;
        // Mouse selection must not wait for the double-tap recognizer.
        // Touch keeps gesture recognition so scrolling does not select rows.
        _selectedOnPointerDown =
            !editing && event.kind == PointerDeviceKind.mouse && event.buttons == kPrimaryMouseButton;
        if (_selectedOnPointerDown) widget.onTap(_tapAdditive);
      },
      child: MMInteractive(
        onTapDown: editing
            ? null
            : () {
                if (!_selectedOnPointerDown) widget.onTap(_tapAdditive);
              },
        onDoubleTap: editing ? null : widget.onDoubleTap,
        selected: widget.selected,
        canRequestFocus: false,
        builder: (context, s) => Container(
          padding: EdgeInsets.fromLTRB(8 + widget.depth * 20.0, 5, 8, 5),
          decoration: BoxDecoration(
            color: editing
                ? c.accentTint
                : widget.selected
                ? c.accentFill
                : (s.hovered ? c.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(MMRadii.row),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 8),
                decoration: BoxDecoration(
                  color: widget.dot,
                  shape: BoxShape.circle,
                  border: widget.dot == null ? Border.all(color: fg2) : null,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    widget.editor ??
                        Text(
                          widget.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _OutlineRow.labelStyle(t, bold: widget.bold).copyWith(color: fg),
                        ),
                    if (widget.sub != null)
                      Text(
                        widget.sub!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.readingExcerpt.copyWith(color: fg2),
                      ),
                  ],
                ),
              ),
              if (widget.meta != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 3),
                  child: Text(widget.meta!, style: t.footnote.copyWith(color: fg2)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
