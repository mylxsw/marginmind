import 'package:flutter/material.dart' hide Card;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/navigation.dart';
import '../../../app/providers.dart';
import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../../../shared/card_image.dart';
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
  final _transforms = <String, TransformationController>{};
  TransformationController get _transform =>
      _transforms.putIfAbsent(ref.read(workspaceProvider(widget.studySetId)).activeMapId, TransformationController.new);

  void _viewCommand(MindMapCommand command) {
    final target = _focus.context;
    if (target != null) Actions.invoke(target, MindMapIntent(command));
  }

  // Survives canvas remounts when switching outline/map or active map.
  int _handledLocateTick = 0;
  final _focus = FocusNode(debugLabel: 'MindMap');

  @override
  void dispose() {
    for (final transform in _transforms.values) {
      transform.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final size = context.size ?? const Size(800, 600);
    final center = Offset(size.width / 2, size.height / 2);
    _transform.value = zoomMapAt(_transform.value, center, factor);
  }

  /// Image cards open a preview; text cards are edited in place.
  void rename(String cardId) {
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final card = controller.content.card(cardId);
    if (card?.kind == CardKind.image && card?.imageFileName != null) {
      showCardImagePreview(context, card!.imageFileName!);
    } else {
      controller.beginEditing(cardId);
    }
  }

  /// A new topic opens for editing in place; Esc removes it again.
  Future<void> addTopic({bool asChild = false}) => ref
      .read(workspaceProvider(widget.studySetId).notifier)
      .addTopicAndEdit(context.l10n.newTopicName, asChild: asChild);

  /// A new note under the selection, open for editing like a new topic.
  Future<void> addNote() =>
      ref.read(workspaceProvider(widget.studySetId).notifier).addNoteAndEdit(context.l10n.newNoteText);

  Future<void> _clipboard(MindMapCommand command) async {
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    try {
      if (command == MindMapCommand.paste) {
        await controller.pasteSelection();
      } else {
        await controller.copySelection(cut: command == MindMapCommand.cut);
      }
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    }
  }

  void _command(MindMapCommand command) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    switch (command) {
      case MindMapCommand.copy || MindMapCommand.cut || MindMapCommand.paste:
        _clipboard(command);
      case MindMapCommand.siblingAfter || MindMapCommand.siblingBefore:
        controller.addTopicAndEdit(l.newTopicName, siblingBefore: command == MindMapCommand.siblingBefore);
      case MindMapCommand.parent:
        controller.addTopicAndEdit(l.newTopicName, asParent: true);
      case MindMapCommand.promote:
        controller.promoteSelected();
      case MindMapCommand.relation:
        controller.addRelation();
      case MindMapCommand.summary:
        controller.addSummaryAndEdit(l.newSummaryLabel);
      case MindMapCommand.expand:
        controller.toggleSelectedExpanded();
      default:
        break;
    }
  }

  void _showNodeMenu(String? cardId, Offset position, Future<void> Function() remove) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final content = controller.content;
    final mapId = ref.read(workspaceProvider(widget.studySetId)).activeMapId;
    final card = cardId == null ? null : content.card(cardId);
    final node = cardId == null ? null : content.node(cardId, mapId: mapId);
    final hasChildren = content.childrenOf(cardId, mapId: mapId).isNotEmpty;
    final now = ref.read(clockProvider)();
    // A leaf is a single card, not a branch.
    final branchDue = card != null && hasChildren && content.dueCount(now, mapId: mapId, branchId: card.id) > 0;
    final suspendable = card != null && (card.suspended || card.kind != CardKind.topic);

    showMMMenu(
      context,
      position: position,
      entries: [
        if (card != null) ...[
          MMMenuItem(l.cardTags, () => showCardTagsSheet(context, ref, widget.studySetId, card.id)),
          MMMenuItem(
            l.showCardDetails,
            () => controller.showDetails(card.id),
            shortcut: describeShortcut(AppShortcuts.cardDetails),
          ),
          MMMenuItem(
            card.kind == CardKind.image
                ? l.previewImage
                : card.kind == CardKind.note
                ? l.editNote
                : l.renameTitle,
            () => rename(card.id),
            shortcut: 'F2',
          ),
          if (content.annotation(card.annotationId ?? '') != null)
            MMMenuItem(l.revealSource, () => controller.revealCard(card.id), shortcut: '⌘L'),
          const MMMenuDivider(),
        ],
        if (branchDue || suspendable) ...[
          if (branchDue)
            MMMenuItem(
              l.reviewBranch,
              () =>
                  ref.read(navigationProvider.notifier).startReview(widget.studySetId, mapId: mapId, branchId: card.id),
            ),
          if (suspendable)
            MMMenuItem(
              card.suspended ? l.resumeCard : l.suspendCard,
              () => controller.setSuspended(card.id, suspended: !card.suspended),
            ),
          const MMMenuDivider(),
        ],
        MMMenuItem(l.addChildTopic, () => addTopic(asChild: true), shortcut: '⇥'),
        MMMenuItem(l.addNote, addNote),
        MMMenuItem(l.insertImage, () => pickAndInsertImages(context, ref, widget.studySetId)),
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
          if (ref
              .read(workspaceProvider(widget.studySetId))
              .selectedCardIds
              .any((id) => content.annotation(content.card(id)?.annotationId ?? '') != null)) ...[
            const MMMenuDivider(),
            for (final color in MMAnnotationColor.values)
              MMMenuItem(
                l.colorName(color),
                () => controller.recolorCards(ref.read(workspaceProvider(widget.studySetId)).selectedCardIds, color),
              ),
          ],
          const MMMenuDivider(),
          MMMenuItem(
            l.addRelation,
            () => _command(MindMapCommand.relation),
            shortcut: describeShortcut(_shortcutOf(MindMapCommand.relation)),
          ),
          MMMenuItem(
            l.addSummary,
            () => _command(MindMapCommand.summary),
            shortcut: describeShortcut(_shortcutOf(MindMapCommand.summary)),
          ),
          const MMMenuDivider(),
          for (final map in content.maps)
            if (map.id != mapId && content.node(card.id, mapId: map.id) == null)
              MMMenuItem(
                l.addToNamedMap(map.title.isEmpty ? l.mainMap : map.title),
                () => controller.placeCardInMap(card.id, map.id),
              ),
          MMMenuItem(l.removeFromMap, remove, destructive: true, shortcut: '⌫'),
        ],
      ],
    );
  }

  static SingleActivator _shortcutOf(MindMapCommand command) =>
      mindMapShortcuts.entries.firstWhere((e) => e.value == command).key;

  /// Right click on a relation line or summary.
  void _showMarkMenu(String markId, Offset position) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final isRelation = controller.content.relations.any((r) => r.id == markId);
    showMMMenu(
      context,
      position: position,
      entries: [
        MMMenuItem(l.editMarkLabel, () => controller.beginMarkEditing(markId), shortcut: 'F2'),
        const MMMenuDivider(),
        MMMenuItem(
          isRelation ? l.deleteRelation : l.deleteSummary,
          controller.removeSelectedMark,
          destructive: true,
          shortcut: '⌫',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final provider = workspaceProvider(widget.studySetId);
    ref.watch(
      provider.select(
        (s) => (
          s.activeMapId,
          s.selectedCardId,
          s.selectedCardIds,
          s.mapView,
          s.flashCardId,
          s.locateCardTick,
          s.editingCardId,
          s.selectedMarkId,
          s.editingMarkId,
          s.connectingFromId,
          s.expandedCardIds,
        ),
      ),
    );
    // Closing the details hands the keyboard back to the map and its node;
    // the view stays where it was.
    ref.listen(provider.select((s) => s.panel), (previous, next) {
      if (previous != RightPanel.details || next != null) return;
      // After the frame: the closing panel first gives up the focus it held.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    });
    final state = ref.read(provider);
    final controller = ref.read(provider.notifier);
    final loadedContent = ref.watch(workspaceContentProvider(widget.studySetId));
    // The controller's copy includes its own writes before the stream
    // delivers them, so a node created for editing is there at once.
    final content = loadedContent == null ? StudySetContent.empty : controller.content;
    final setTitle = ref.watch(studySetProvider(widget.studySetId).select((s) => s?.title)) ?? '';
    final mapTitle = content.map(state.activeMapId)?.title ?? '';
    final rootTitle = mapTitle.isEmpty ? setTitle : mapTitle;
    // Where new excerpts go, marked on the map once there is a document.
    final excerptTargetId = content.documents.isEmpty
        ? null
        : StudySetEditor.excerptTarget(content, state.selectedCardId, mapId: state.activeMapId) ?? rootNodeId;

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
                    key: ValueKey(state.activeMapId),
                    content: content,
                    mapId: state.activeMapId,
                    rootTitle: rootTitle,
                    selectedCardId: state.selectedCardId,
                    selectedCardIds: state.selectedCardIds,
                    onToggleSelection: controller.toggleCardSelection,
                    flashCardId: state.flashCardId,
                    locateCardTick: state.locateCardTick > _handledLocateTick ? state.locateCardTick : 0,
                    onLocated: (tick) {
                      if (tick > _handledLocateTick) _handledLocateTick = tick;
                    },
                    transformation: _transform,
                    focusNode: _focus,
                    loaded: loadedContent != null,
                    onSelect: controller.selectCard,
                    onReveal: controller.revealCard,
                    onRename: rename,
                    onDelete: remove,
                    onSelectMany: controller.selectCards,
                    onMove: (id, parent, index) => controller.moveCards(
                      state.selectedCardIds.contains(id) ? state.selectedCardIds : [id],
                      parent,
                      index: index,
                    ),
                    onToggleCollapsed: controller.toggleCollapsed,
                    onNavigate: controller.selectNeighbor,
                    onShift: controller.shiftSelected,
                    onAddChild: () => addTopic(asChild: true),
                    onCommand: _command,
                    editingCardId: state.editingCardId,
                    onEditDone: controller.finishEditing,
                    onEditCancel: controller.cancelEditing,
                    onContextMenu: (id, position) => _showNodeMenu(id, position, remove),
                    selectedMarkId: state.selectedMarkId,
                    editingMarkId: state.editingMarkId,
                    connectingFromId: state.connectingFromId,
                    onSelectMark: controller.selectMark,
                    onEditMark: controller.beginMarkEditing,
                    onDeleteMark: controller.removeSelectedMark,
                    onMarkEditDone: controller.finishMarkEditing,
                    onMarkEditCancel: controller.cancelMarkEditing,
                    onConnect: controller.connectTo,
                    onCancelConnect: controller.cancelConnecting,
                    onMarkContextMenu: _showMarkMenu,
                    excerptTargetId: excerptTargetId,
                    expandedCardIds: state.expandedCardIds,
                    onToggleExpanded: controller.toggleExpanded,
                    onOpenDetails: controller.showDetails,
                  )
                : OutlineView(
                    key: ValueKey(state.activeMapId),
                    content: content,
                    mapId: state.activeMapId,
                    rootTitle: rootTitle,
                    selectedCardId: state.selectedCardId,
                    selectedCardIds: state.selectedCardIds,
                    onToggleSelection: controller.toggleCardSelection,
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
          if (content.nodes.every((n) => n.mapId != state.activeMapId) && state.mapView == MapViewMode.map)
            Positioned(
              left: 0,
              right: 0,
              bottom: 72,
              child: IgnorePointer(
                child: Text(l.mapEmptyTitle, textAlign: TextAlign.center, style: t.headline),
              ),
            ),
          Positioned(
            left: MMSpacing.m,
            right: MMSpacing.m,
            top: MMSpacing.s,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    mapTitle.isEmpty ? l.mainMap : mapTitle,
                    style: t.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                MMSegmentedControl<MapViewMode>(
                  value: state.mapView,
                  onChanged: controller.setMapView,
                  segments: [
                    MMSegment(value: MapViewMode.map, label: l.mapView),
                    MMSegment(value: MapViewMode.outline, label: l.outlineView),
                  ],
                ),
                const SizedBox(width: MMSpacing.s),
                MMToolbarGroup(
                  children: [
                    MMToolbarButton(icon: MMIcons.addTopic, tooltip: l.addTopic, onPressed: addTopic),
                    MMToolbarButton(icon: MMIcons.addNote, tooltip: l.addNote, onPressed: addNote),
                    MMToolbarButton(
                      icon: MMIcons.trash,
                      tooltip: l.removeFromMap,
                      onPressed: state.selectedMarkId != null
                          ? controller.removeSelectedMark
                          : state.selectedCardId == null
                          ? null
                          : remove,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (state.mapView == MapViewMode.map && excerptTargetId != null)
            Positioned(
              left: MMSpacing.m,
              bottom: MMSpacing.m,
              right: MMSizes.mapViewControlsReservedWidth,
              child: IgnorePointer(
                child: Text(
                  l.newExcerptTarget(
                    excerptTargetId == rootNodeId ? rootTitle : content.card(excerptTargetId)?.title ?? '',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.footnote.copyWith(color: c.secondaryLabel),
                ),
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
                      icon: MMIcons.image,
                      tooltip: l.insertImage,
                      onPressed: () => pickAndInsertImages(context, ref, widget.studySetId),
                    ),
                    const MMToolbarDivider(),
                    MMIconButton(
                      icon: MMIcons.fitMap,
                      tooltip: l.fitMap,
                      onPressed: () => _viewCommand(MindMapCommand.fit),
                    ),
                    MMIconButton(
                      icon: MMIcons.locate,
                      tooltip: l.centerCurrentNode,
                      onPressed: () => _viewCommand(MindMapCommand.center),
                    ),
                    const MMToolbarDivider(),
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
                      child: MMInteractive(
                        tooltip: l.pdfActualSize,
                        semanticLabel: l.pdfActualSize,
                        onTap: () => _zoom(1 / mapScale(_transform.value)),
                        builder: (context, _) => _ZoomLabel(transform: _transform, style: t.callout),
                      ),
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

/// The current zoom. Gestures, "fit" and view following change the
/// transform without rebuilding the pane, and the canvas may adjust it while
/// laying out, so the label rebuilds itself — after the frame if needed.
class _ZoomLabel extends StatefulWidget {
  const _ZoomLabel({required this.transform, required this.style});

  final TransformationController transform;
  final TextStyle style;

  @override
  State<_ZoomLabel> createState() => _ZoomLabelState();
}

class _ZoomLabelState extends State<_ZoomLabel> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ZoomLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform == widget.transform) return;
    oldWidget.transform.removeListener(_changed);
    widget.transform.addListener(_changed);
  }

  @override
  void dispose() {
    widget.transform.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) =>
      Text('${(mapScale(widget.transform.value) * 100).round()}%', textAlign: TextAlign.center, style: widget.style);
}
