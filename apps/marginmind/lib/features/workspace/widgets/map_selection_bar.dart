import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../../app/app_commands.dart';

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
    this.onAssistant,
  });
  final int count;
  final ValueChanged<Rect>? onAssistant;
  final MapEditReason? mergeReason, summaryReason;
  final VoidCallback onMerge, onSummary, onRelation, onDelete;
  final ValueChanged<bool> onMergeHover;
  final ValueChanged<MMAnnotationColor>? onColor;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMGlass(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            onEnter: (_) => onMergeHover(true),
            onExit: (_) => onMergeHover(false),
            child: _MapAction(
              id: 'merge',
              label: l.selectionMerge,
              shortcut: _shortcut(MindMapCommand.merge),
              nodeIcon: MMNodeAction.merge,
              onPressed: onMerge,
              reason: mergeReason == null ? null : mapEditReasonText(context, mergeReason!),
            ),
          ),
          _MapAction(
            id: 'summary',
            label: l.selectionSummary,
            shortcut: describeShortcut(
              mindMapShortcuts.entries.firstWhere((e) => e.value == MindMapCommand.summary).key,
            ),
            nodeIcon: MMNodeAction.summary,
            onPressed: onSummary,
            reason: summaryReason == null ? null : mapEditReasonText(context, summaryReason!),
          ),
          _MapAction(
            id: 'relation',
            label: l.addRelation,
            shortcut: _shortcut(MindMapCommand.relation),
            nodeIcon: MMNodeAction.relation,
            onPressed: onRelation,
            reason: count == 2 ? null : l.relationNeedsTwo,
          ),
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
          if (onAssistant != null) ...[const MMToolbarDivider(), _AssistantAction(onAssistant: onAssistant!)],
          const MMToolbarDivider(),
          _MapAction(id: 'delete', label: l.removeFromMap, shortcut: '⌫', icon: MMIcons.trash, onPressed: onDelete),
        ],
      ),
    );
  }
}

/// Icon-only actions; hover and accessibility labels describe the command.
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
    this.root = false,
  });

  final VoidCallback onChild, onSibling, onNote, onImage, onRelation, onDelete;
  final bool root;

  /// Opens the assistant's actions for the node, anchored below [anchor].
  final ValueChanged<Rect>? onAssistant;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return TextFieldTapRegion(
      child: MMGlass(
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MapAction(
              id: 'child',
              label: l.addChildTopic,
              shortcut: '⇥',
              nodeIcon: MMNodeAction.child,
              onPressed: onChild,
            ),
            _MapAction(
              id: 'sibling',
              label: l.addSiblingAfter,
              shortcut: '↩',
              nodeIcon: MMNodeAction.sibling,
              onPressed: onSibling,
            ),
            if (!root)
              _MapAction(
                id: 'note',
                label: l.addNote,
                shortcut: describeShortcut(AppShortcuts.addNote),
                icon: MMIcons.addNote,
                onPressed: onNote,
              ),
            _MapAction(id: 'image', label: l.insertImage, icon: MMIcons.image, onPressed: onImage),
            if (!root)
              _MapAction(
                id: 'relation',
                label: l.addRelation,
                shortcut: _shortcut(MindMapCommand.relation),
                nodeIcon: MMNodeAction.relation,
                onPressed: onRelation,
              ),
            if (onAssistant != null) ...[const MMToolbarDivider(), _AssistantAction(onAssistant: onAssistant!)],
            if (!root) ...[
              const MMToolbarDivider(),
              _MapAction(id: 'delete', label: l.removeFromMap, shortcut: '⌫', icon: MMIcons.trash, onPressed: onDelete),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stable entry points for map commands; unavailable actions stay in place.
class MapCommandBar extends StatelessWidget {
  const MapCommandBar({
    super.key,
    this.onChild,
    this.onSibling,
    this.onRelation,
    this.onSummary,
    this.onNote,
    this.onImage,
    this.onTags,
    this.onDetails,
    this.summaryReason,
  });

  final VoidCallback? onChild, onSibling, onRelation, onSummary, onNote, onImage, onTags, onDetails;
  final MapEditReason? summaryReason;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return TextFieldTapRegion(
      child: MMLiquidGlass(
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MapAction(
              keyPrefix: 'map-command',
              id: 'child',
              label: l.addChildTopic,
              shortcut: '⇥',
              nodeIcon: MMNodeAction.child,
              onPressed: onChild,
            ),
            _MapAction(
              keyPrefix: 'map-command',
              id: 'sibling',
              label: l.addSiblingAfter,
              shortcut: '↩',
              nodeIcon: MMNodeAction.sibling,
              onPressed: onSibling,
            ),
            const MMToolbarDivider(),
            _MapAction(
              keyPrefix: 'map-command',
              id: 'relation',
              label: l.addRelation,
              shortcut: _shortcut(MindMapCommand.relation),
              nodeIcon: MMNodeAction.relation,
              onPressed: onRelation,
            ),
            _MapAction(
              keyPrefix: 'map-command',
              id: 'summary',
              label: l.addSummary,
              shortcut: _shortcut(MindMapCommand.summary),
              nodeIcon: MMNodeAction.summary,
              onPressed: onSummary,
              reason: summaryReason == null ? null : mapEditReasonText(context, summaryReason!),
            ),
            const MMToolbarDivider(),
            _MapAction(
              keyPrefix: 'map-command',
              id: 'note',
              label: l.addNote,
              shortcut: describeShortcut(AppShortcuts.addNote),
              icon: MMIcons.addNote,
              onPressed: onNote,
            ),
            _MapAction(
              keyPrefix: 'map-command',
              id: 'image',
              label: l.insertImage,
              icon: MMIcons.image,
              onPressed: onImage,
            ),
            _MapAction(keyPrefix: 'map-command', id: 'tags', label: l.cardTags, icon: MMIcons.tag, onPressed: onTags),
            _MapAction(
              keyPrefix: 'map-command',
              id: 'details',
              label: l.showCardDetails,
              shortcut: describeShortcut(AppShortcuts.cardDetails),
              icon: MMIcons.info,
              onPressed: onDetails,
            ),
          ],
        ),
      ),
    );
  }
}

/// The same icon-only action is used by single- and multi-node menus.
class _MapAction extends StatelessWidget {
  const _MapAction({
    required this.id,
    required this.label,
    required this.onPressed,
    this.shortcut,
    this.icon,
    this.nodeIcon,
    this.reason,
    this.tint,
    this.keyPrefix = 'node-bar',
  });
  final String id, label;
  final String? shortcut, reason;
  final IconData? icon;
  final MMNodeAction? nodeIcon;
  final Color? tint;
  final VoidCallback? onPressed;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final hint = '$label${shortcut == null ? '' : '  $shortcut'}${reason == null ? '' : '\n$reason'}';
    void invoke() => reason == null ? onPressed?.call() : MMHud.show(context, reason!, icon: MMIcons.info);
    final key = ValueKey('$keyPrefix-$id');
    final button = nodeIcon == null
        ? MMToolbarButton(key: key, icon: icon, tooltip: hint, onPressed: onPressed == null ? null : invoke, tint: tint)
        : MMToolbarPreviewButton(
            key: key,
            tooltip: hint,
            onPressed: onPressed == null ? null : invoke,
            preview: (color) => MMNodeActionIcon(nodeIcon!, color: color),
          );
    return reason == null || onPressed == null ? button : Opacity(opacity: 0.45, child: button);
  }
}

class _AssistantAction extends StatelessWidget {
  const _AssistantAction({required this.onAssistant});
  final ValueChanged<Rect> onAssistant;

  @override
  Widget build(BuildContext context) => _MapAction(
    id: 'assistant',
    label: context.l10n.askAssistant,
    shortcut: describeShortcut(AppShortcuts.askAssistant),
    icon: MMIcons.ai,
    tint: context.mmColors.research,
    onPressed: () {
      final box = context.findRenderObject()! as RenderBox;
      onAssistant(box.localToGlobal(Offset.zero) & box.size);
    },
  );
}

String _shortcut(MindMapCommand command) =>
    describeShortcut(mindMapShortcuts.entries.firstWhere((entry) => entry.value == command).key);
