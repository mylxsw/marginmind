import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
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
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.3, 2.5);
    final f = target / current;
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_transform.value);
    setState(() {});
  }

  Future<void> rename(String cardId) async {
    final card = ref.read(workspaceProvider(widget.studySetId).notifier).content.card(cardId);
    if (card != null) await renameCard(card);
  }

  /// Asks for a new title; used right after creating a card too, before the
  /// content stream has delivered it.
  Future<void> renameCard(Card card) async {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final cardId = card.id;
    final title = await showRenameSheet(
      context,
      title: card.kind == CardKind.note ? l.editNote : l.renameTitle,
      initial: card.title,
    );
    if (title != null) await controller.rename(cardId, title);
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
    final content = loadedContent ?? StudySetContent.empty;
    final rootTitle = ref.watch(studySetProvider(widget.studySetId))?.title ?? '';
    final targetId = StudySetEditor.excerptTarget(content, state.selectedCardId);
    final targetTitle = targetId == null ? rootTitle : (content.card(targetId)?.title ?? rootTitle);
    final scale = _transform.value.getMaxScaleOnAxis();

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
                  )
                : OutlineView(
                    content: content,
                    rootTitle: rootTitle,
                    selectedCardId: state.selectedCardId,
                    onSelect: controller.selectCard,
                    onReveal: controller.revealCard,
                    onRename: rename,
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
                MMToolbarButton(
                  icon: MMIcons.addTopic,
                  tooltip: l.addTopic,
                  onPressed: () async {
                    final card = await controller.addTopic(l.newTopicName);
                    if (mounted) await renameCard(card);
                  },
                ),
                MMToolbarButton(
                  icon: MMIcons.addNote,
                  tooltip: l.addNote,
                  onPressed: () async {
                    final card = await controller.addNote(l.newNoteText);
                    if (mounted) await renameCard(card);
                  },
                ),
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
