import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'mind_map_canvas.dart';
import 'notices.dart';
import 'outline_view.dart';

/// Map pane: the mind map (or outline) plus floating glass controls — map
/// picker and view switch top-left, node actions top-right, zoom bottom-right.
class MapPane extends ConsumerStatefulWidget {
  const MapPane({super.key, required this.studySetId});

  final String studySetId;

  @override
  ConsumerState<MapPane> createState() => _MapPaneState();
}

class _MapPaneState extends ConsumerState<MapPane> {
  final _transform = TransformationController();
  final _focus = FocusNode(debugLabel: 'MindMap');

  @override
  void dispose() {
    _transform.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final size = context.size ?? const Size(800, 600);
    final center = Offset(size.width / 2, size.height / 2);
    final current = mapScale(_transform.value);
    final target = (current * factor).clamp(0.3, 2.5);
    final f = target / current;
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_transform.value);
    setState(() {});
  }

  /// Every card is edited in place, on the map and in the outline.
  void rename(String cardId) => ref.read(workspaceProvider(widget.studySetId).notifier).beginEditing(cardId);

  /// A new topic opens for editing in place; Esc removes it again.
  Future<void> addTopic({bool asChild = false}) => ref
      .read(workspaceProvider(widget.studySetId).notifier)
      .addTopicAndEdit(context.l10n.newTopicName, asChild: asChild);

  /// A new note under the selection, open for editing like a new topic.
  Future<void> addNote() =>
      ref.read(workspaceProvider(widget.studySetId).notifier).addNoteAndEdit(context.l10n.newNoteText);

  void _command(MindMapCommand command) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    switch (command) {
      case MindMapCommand.siblingAfter || MindMapCommand.siblingBefore:
        controller.addTopicAndEdit(l.newTopicName, siblingBefore: command == MindMapCommand.siblingBefore);
      case MindMapCommand.parent:
        controller.addTopicAndEdit(l.newTopicName, asParent: true);
      case MindMapCommand.promote:
        controller.promoteSelected();
      default:
        break;
    }
  }

  void _showNodeMenu(String? cardId, Offset position, Future<void> Function() remove) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final content = controller.content;
    final card = cardId == null ? null : content.card(cardId);
    final node = cardId == null ? null : content.node(cardId);
    final hasChildren = content.childrenOf(cardId).isNotEmpty;

    showMMMenu(
      context,
      position: position,
      entries: [
        if (card != null) ...[
          MMMenuItem(card.kind == CardKind.note ? l.editNote : l.renameTitle, () => rename(card.id), shortcut: 'F2'),
          if (card.kind == CardKind.excerpt)
            MMMenuItem(l.revealSource, () => controller.revealCard(card.id), shortcut: '⌘L'),
          const MMMenuDivider(),
        ],
        MMMenuItem(l.addChildTopic, () => addTopic(asChild: true), shortcut: '⇥'),
        MMMenuItem(l.addNote, addNote),
        if (card != null && hasChildren) ...[
          const MMMenuDivider(),
          MMMenuItem((node?.collapsed ?? false) ? l.expandNode : l.collapseNode, () {
            controller.toggleCollapsed(card.id);
          }),
        ],
        if (card != null) ...[
          const MMMenuDivider(),
          MMMenuItem(l.moveUp, () => controller.shiftSelected(-1), shortcut: '⌘↑'),
          MMMenuItem(l.moveDown, () => controller.shiftSelected(1), shortcut: '⌘↓'),
          const MMMenuDivider(),
          MMMenuItem(l.removeFromMap, remove, destructive: true, shortcut: '⌫'),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final provider = workspaceProvider(widget.studySetId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final loadedContent = ref.watch(contentProvider(widget.studySetId)).value;
    // The controller's copy includes its own writes before the stream
    // delivers them, so a node created for editing is there at once.
    final content = loadedContent == null ? StudySetContent.empty : controller.content;
    final rootTitle = ref.watch(studySetProvider(widget.studySetId))?.title ?? '';
    final targetId = StudySetEditor.excerptTarget(content, state.selectedCardId);
    final targetTitle = targetId == null ? rootTitle : (content.card(targetId)?.title ?? rootTitle);
    final scale = mapScale(_transform.value);

    Future<void> remove() async {
      final notice = await controller.removeSelected();
      if (context.mounted) showNotice(context, notice, rootTitle: rootTitle);
    }

    return ColoredBox(
      color: state.mapView == MapViewMode.map ? c.canvas : c.windowBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: state.mapView == MapViewMode.map
                ? MindMapCanvas(
                    content: content,
                    rootTitle: rootTitle,
                    selectedCardId: state.selectedCardId,
                    flashCardId: state.flashCardId,
                    transformation: _transform,
                    focusNode: _focus,
                    loaded: loadedContent != null,
                    onSelect: controller.selectCard,
                    onReveal: controller.revealCard,
                    onRename: rename,
                    onDelete: remove,
                    onMove: (id, parent, index) => controller.moveCard(id, parent, index: index),
                    onToggleCollapsed: controller.toggleCollapsed,
                    onNavigate: controller.selectNeighbor,
                    onShift: controller.shiftSelected,
                    onAddChild: () => addTopic(asChild: true),
                    onCommand: _command,
                    editingCardId: state.editingCardId,
                    onEditDone: controller.finishEditing,
                    onEditCancel: controller.cancelEditing,
                    onContextMenu: (id, position) => _showNodeMenu(id, position, remove),
                  )
                : OutlineView(
                    content: content,
                    rootTitle: rootTitle,
                    selectedCardId: state.selectedCardId,
                    focusNode: _focus,
                    onSelect: controller.selectCard,
                    onReveal: controller.revealCard,
                    onRename: rename,
                    onDelete: remove,
                    onAddChild: () => addTopic(asChild: true),
                    onShift: controller.shiftSelected,
                    onCommand: _command,
                    editingCardId: state.editingCardId,
                    onEditDone: controller.finishEditing,
                    onEditCancel: controller.cancelEditing,
                  ),
          ),
          if (content.cards.isEmpty && state.mapView == MapViewMode.map)
            Positioned(
              left: 0,
              right: 0,
              bottom: 72,
              child: IgnorePointer(
                child: Column(
                  children: [
                    Text(l.mapEmptyTitle, style: t.headline),
                    const SizedBox(height: 4),
                    Text(l.mapEmptyMessage, textAlign: TextAlign.center, style: t.footnote),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 12,
            top: 10,
            child: MMGlass(
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.fromLTRB(3, 3, 4, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 34,
                    padding: const EdgeInsets.only(left: 12, right: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.mainMap, style: t.headline),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(
                            l.newExcerptTarget(targetTitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.footnote,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const MMToolbarDivider(),
                  MMSegmentedControl<MapViewMode>(
                    value: state.mapView,
                    onChanged: controller.setMapView,
                    segments: [
                      MMSegment(value: MapViewMode.map, label: l.mapView),
                      MMSegment(value: MapViewMode.outline, label: l.outlineView),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 10,
            child: MMToolbarGroup(
              children: [
                MMToolbarButton(icon: MMIcons.addTopic, tooltip: l.addTopic, onPressed: addTopic),
                MMToolbarButton(icon: MMIcons.addNote, tooltip: l.addNote, onPressed: addNote),
                MMToolbarButton(
                  icon: MMIcons.trash,
                  tooltip: l.removeFromMap,
                  onPressed: state.selectedCardId == null ? null : remove,
                ),
              ],
            ),
          ),
          if (state.mapView == MapViewMode.map)
            Positioned(
              right: 12,
              bottom: 12,
              child: MMGlass(
                borderRadius: BorderRadius.circular(16),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MMIconButton(
                      icon: MMIcons.zoomOut,
                      tooltip: l.zoomOut,
                      size: 26,
                      iconSize: 13,
                      color: c.label,
                      onPressed: () => _zoom(1 / 1.25),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${(scale * 100).round()}%', textAlign: TextAlign.center, style: t.callout),
                    ),
                    MMIconButton(
                      icon: MMIcons.zoomIn,
                      tooltip: l.zoomIn,
                      size: 26,
                      iconSize: 13,
                      color: c.label,
                      onPressed: () => _zoom(1.25),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
