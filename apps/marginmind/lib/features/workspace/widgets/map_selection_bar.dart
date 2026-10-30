import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

String mapEditReasonText(BuildContext context, MapEditReason reason) {
  final l = context.l10n;
  return switch (reason) {
    MapEditReason.tooFewCards => l.mapEditTooFewCards,
    MapEditReason.missingCard => l.mapEditMissingCard,
    MapEditReason.centerTopic => l.mapEditCenterTopic,
    MapEditReason.imageCard => l.mapEditImageCard,
    MapEditReason.summaryTopic => l.mapEditSummaryTopic,
    MapEditReason.unsupportedCard => l.mapEditUnsupportedCard,
    MapEditReason.notMerged => l.mapEditNotMerged,
    MapEditReason.differentParents => l.mapEditDifferentParents,
    MapEditReason.overlappingSummary => l.mapEditOverlappingSummary,
    MapEditReason.missingSummary => l.mapEditMissingSummary,
  };
}

class MapSelectionBar extends StatelessWidget {
  const MapSelectionBar({
    super.key,
    required this.count,
    required this.mergeReason,
    required this.summaryReason,
    required this.onMerge,
    required this.onSummary,
    required this.onRelation,
    required this.onDelete,
    required this.onMergeHover,
    required this.onColor,
  });
  final int count;
  final MapEditReason? mergeReason, summaryReason;
  final VoidCallback onMerge, onSummary, onRelation, onDelete;
  final ValueChanged<bool> onMergeHover;
  final ValueChanged<MMAnnotationColor>? onColor;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Only an unavailable action explains itself: dimmed, its tooltip and a
    // click say why. An available one is just its label.
    Widget action(String label, VoidCallback? callback, String? reason) {
      if (reason == null) return MMButton(label: label, onPressed: callback, variant: MMButtonVariant.plain);
      return Tooltip(
        message: reason,
        child: Opacity(
          opacity: 0.45,
          child: MMButton(
            label: label,
            onPressed: () => MMHud.show(context, reason, icon: MMIcons.info),
            variant: MMButtonVariant.plain,
          ),
        ),
      );
    }

    return MMGlass(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.selectedNodes(count), style: context.mmText.footnote),
          const MMToolbarDivider(),
          MouseRegion(
            onEnter: (_) => onMergeHover(true),
            onExit: (_) => onMergeHover(false),
            child: action(
              l.selectionMerge,
              mergeReason == null ? onMerge : null,
              mergeReason == null ? null : mapEditReasonText(context, mergeReason!),
            ),
          ),
          action(
            l.selectionSummary,
            summaryReason == null ? onSummary : null,
            summaryReason == null ? null : mapEditReasonText(context, summaryReason!),
          ),
          action(l.selectionRelation, count == 2 ? onRelation : null, count == 2 ? null : l.relationNeedsTwo),
          if (onColor != null)
            for (final color in MMAnnotationColor.values)
              Tooltip(
                message: l.colorName(color),
                child: InkWell(
                  onTap: () => onColor!(color),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color.color, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
          action(l.selectionDelete, onDelete, null),
        ],
      ),
    );
  }
}

/// Above a single selected node: what is done to that node. Each action
/// is named by its label; the tooltip adds only the shortcut.
class MapNodeBar extends StatelessWidget {
  const MapNodeBar({
    super.key,
    required this.onChild,
    required this.onSibling,
    required this.onNote,
    required this.onImage,
    required this.onRelation,
    required this.onDelete,
    this.onAssistant,
  });

  final VoidCallback onChild, onSibling, onNote, onImage, onRelation, onDelete;

  /// Opens the assistant's actions for the node, anchored below [anchor].
  final ValueChanged<Offset>? onAssistant;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget action(String key, String label, VoidCallback onPressed, String tooltip) => Tooltip(
      message: tooltip,
      child: MMButton(
        key: ValueKey('node-bar-$key'),
        label: label,
        onPressed: onPressed,
        variant: MMButtonVariant.plain,
      ),
    );

    return MMGlass(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          action('child', l.nodeBarChild, onChild, '${l.addChildTopic}  ⇥'),
          action('sibling', l.nodeBarSibling, onSibling, '${l.addSiblingAfter}  ↩'),
          action('note', l.nodeBarNote, onNote, '${l.addNote}  ⌥⌘N'),
          action('image', l.nodeBarImage, onImage, l.insertImage),
          action('relation', l.selectionRelation, onRelation, '${l.addRelation}  ⌥⌘R'),
          if (onAssistant != null) ...[
            const MMToolbarDivider(),
            Builder(
              builder: (context) => action('assistant', l.nodeBarAssistant, () {
                final box = context.findRenderObject()! as RenderBox;
                onAssistant!(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
              }, l.askAssistant),
            ),
          ],
          const MMToolbarDivider(),
          action('delete', l.selectionDelete, onDelete, '${l.removeFromMap}  ⌫'),
        ],
      ),
    );
  }
}
