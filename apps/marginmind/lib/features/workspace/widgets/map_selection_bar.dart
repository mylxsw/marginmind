import '../../../shared/assistant_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../../app/app_commands.dart';
import '../../../settings/highlight_palette.dart';
import 'highlight_color_button.dart';

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

class MapSelectionBar extends ConsumerWidget {
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
    this.onSelectMore,
    required this.onColor,
    this.onAssistant,
    this.color,
  });
  final int count;
  final ValueChanged<Rect>? onAssistant;
  final MapEditReason? mergeReason, summaryReason;
  final VoidCallback onMerge, onSummary, onRelation, onDelete;
  final ValueChanged<bool> onMergeHover;
  final VoidCallback? onSelectMore;
  final Future<void> Function(MMAnnotationColor)? onColor;

  /// Null means that the selection contains different colors.
  final MMAnnotationColor? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final palette = ref.watch(highlightPaletteProvider);
    return MMGlass(
      toolbar: true,
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (MMInput.of(context).phone && onSelectMore != null)
            _PhoneNodeAction(id: 'select', label: l.mapSelectionTap, icon: MMIcons.areaSelect, onTap: onSelectMore!),
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
            HighlightColorButton(
              key: const ValueKey('node-bar-color'),
              color: color ?? palette.current,
              mixed: color == null,
              colors: {
                ...MMAnnotationColor.values,
                ...palette.recent().where((c) => c.isCustom),
                if (color?.isCustom == true) color!,
              }.toList(),
              onChanged: onColor!,
            ),
          if (onAssistant != null) ...[const MMToolbarDivider(), _AssistantAction(onAssistant: onAssistant!)],
          const MMToolbarDivider(),
          _MapAction(id: 'delete', label: l.removeFromMap, shortcut: '⌫', icon: MMIcons.trash, onPressed: onDelete),
        ],
      ),
    );
  }
}

/// Icon-only actions; long press, hover and accessibility labels describe them.
class MapNodeBar extends StatelessWidget {
  const MapNodeBar({
    super.key,
    required this.onChild,
    required this.onSibling,
    required this.onNote,
    required this.onImage,
    required this.onRelation,
    required this.onDelete,
    this.onEdit,
    this.onMore,
    this.onAssistant,
    this.root = false,
  });

  final VoidCallback onChild, onSibling, onNote, onImage, onRelation, onDelete;
  final bool root;
  final VoidCallback? onEdit;
  final VoidCallback? onMore;

  /// Opens the assistant's actions for the node, anchored below [anchor].
  final ValueChanged<Rect>? onAssistant;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (MMInput.of(context).phone) {
      return MMGlass(
        key: const ValueKey('phone-map-node-toolbar'),
        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: MMSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null) _PhoneNodeAction(id: 'edit', label: l.mapPhoneEdit, icon: MMIcons.pen, onTap: onEdit!),
            _PhoneNodeAction(id: 'child', label: l.mapPhoneChild, nodeIcon: MMNodeAction.child, onTap: onChild),
            if (!root)
              _PhoneNodeAction(
                id: 'sibling',
                label: l.mapPhoneSibling,
                nodeIcon: MMNodeAction.sibling,
                onTap: onSibling,
              ),
            if (onAssistant != null)
              Builder(
                builder: (context) => _PhoneNodeAction(
                  id: 'assistant',
                  label: l.askAssistant,
                  icon: MMIcons.ai,
                  onTap: () {
                    final box = context.findRenderObject()! as RenderBox;
                    onAssistant!(box.localToGlobal(Offset.zero) & box.size);
                  },
                ),
              ),
            if (onMore != null) _PhoneNodeAction(id: 'more', label: l.mapPhoneMore, icon: MMIcons.more, onTap: onMore!),
          ],
        ),
      );
    }
    if (context.mmTablet) {
      return TextFieldTapRegion(
        child: MMFloatingToolbar(
          children: [
            _MapAction(id: 'child', label: l.addChildTopic, nodeIcon: MMNodeAction.child, onPressed: onChild),
            if (!root)
              _MapAction(id: 'sibling', label: l.addSiblingAfter, nodeIcon: MMNodeAction.sibling, onPressed: onSibling),
            if (onEdit != null) _MapAction(id: 'edit', icon: MMIcons.pen, label: l.renameTitle, onPressed: onEdit),
            if (!root) ...[
              _MapAction(id: 'relation', label: l.addRelation, nodeIcon: MMNodeAction.relation, onPressed: onRelation),
              _MapAction(id: 'note', label: l.addNote, icon: MMIcons.addNote, onPressed: onNote),
            ],
            _MapAction(id: 'image', label: l.insertImage, icon: MMIcons.image, onPressed: onImage),
            if (!root)
              _MapAction(
                id: 'delete',
                label: l.removeFromMap,
                icon: MMIcons.trash,
                tint: context.mmColors.critical,
                onPressed: onDelete,
              ),
            if (onAssistant != null) _AssistantAction(onAssistant: onAssistant!),
          ],
        ),
      );
    }
    return TextFieldTapRegion(
      child: MMGlass(
        toolbar: true,
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
            if (!root) ...[
              _MapAction(
                id: 'relation',
                label: l.addRelation,
                shortcut: _shortcut(MindMapCommand.relation),
                nodeIcon: MMNodeAction.relation,
                onPressed: onRelation,
              ),
              _MapAction(id: 'delete', label: l.removeFromMap, shortcut: '⌫', icon: MMIcons.trash, onPressed: onDelete),
            ],
            const MMToolbarDivider(),
            if (!root)
              _MapAction(
                id: 'note',
                label: l.addNote,
                shortcut: describeShortcut(AppShortcuts.addNote),
                icon: MMIcons.addNote,
                onPressed: onNote,
              ),
            _MapAction(id: 'image', label: l.insertImage, icon: MMIcons.image, onPressed: onImage),
            if (onAssistant != null) _AssistantAction(onAssistant: onAssistant!),
          ],
        ),
      ),
    );
  }
}

class _PhoneNodeAction extends StatelessWidget {
  const _PhoneNodeAction({required this.id, required this.label, this.icon, this.nodeIcon, required this.onTap});
  final String id, label;
  final IconData? icon;
  final MMNodeAction? nodeIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MMInteractive(
    key: ValueKey('node-bar-$id'),
    semanticLabel: label,
    onTap: onTap,
    builder: (context, state) => Container(
      constraints: const BoxConstraints(minHeight: 52),
      width: 56,
      decoration: BoxDecoration(
        color: state.pressed ? context.mmColors.pressed : null,
        borderRadius: BorderRadius.circular(MMRadii.row),
      ),
      padding: const EdgeInsets.symmetric(vertical: MMSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nodeIcon != null)
            MMNodeActionIcon(nodeIcon!, size: 20, color: context.mmColors.label)
          else
            Icon(icon, size: 20, color: context.mmColors.label),
          const SizedBox(height: 3),
          Text(label, style: context.mmText.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
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
      child: MMGlass(
        toolbar: true,
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
    this.iconWidget,
    this.nodeIcon,
    this.reason,
    this.tint,
    this.keyPrefix = 'node-bar',
  });
  final String id, label;
  final String? shortcut, reason;
  final IconData? icon;
  final Widget? iconWidget;
  final MMNodeAction? nodeIcon;
  final Color? tint;
  final VoidCallback? onPressed;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final showShortcut = shortcut != null && !MMInput.of(context).touchPlatform;
    final hint = '$label${showShortcut ? '  $shortcut' : ''}${reason == null ? '' : '\n$reason'}';
    void invoke() => reason == null ? onPressed?.call() : MMHud.show(context, reason!, icon: MMIcons.info);
    final key = ValueKey('$keyPrefix-$id');
    if (MMInput.of(context).phone) {
      return MMInteractive(
        key: key,
        semanticLabel: hint,
        onTap: onPressed == null ? null : invoke,
        builder: (context, state) {
          final color = !state.enabled || reason != null
              ? context.mmColors.secondaryLabel
              : tint ?? context.mmColors.label;
          return Container(
            width: 44,
            height: 52,
            decoration: BoxDecoration(
              color: state.pressed ? context.mmColors.pressed : null,
              borderRadius: BorderRadius.circular(MMRadii.row),
            ),
            alignment: Alignment.center,
            child:
                iconWidget ??
                (nodeIcon != null ? MMNodeActionIcon(nodeIcon!, color: color) : Icon(icon, color: color, size: 20)),
          );
        },
      );
    }
    final button = nodeIcon == null
        ? MMToolbarButton(
            key: key,
            icon: icon,
            iconWidget: iconWidget,
            tooltip: hint,
            onPressed: onPressed == null ? null : invoke,
            tint: tint,
          )
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
    iconWidget: const AssistantIcon(),
    tint: context.mmColors.research,
    onPressed: () {
      final box = context.findRenderObject()! as RenderBox;
      onAssistant(box.localToGlobal(Offset.zero) & box.size);
    },
  );
}

String _shortcut(MindMapCommand command) =>
    describeShortcut(mindMapShortcuts.entries.firstWhere((entry) => entry.value == command).key);
