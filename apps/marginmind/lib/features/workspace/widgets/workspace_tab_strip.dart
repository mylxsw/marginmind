import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

String workspaceTabTitle(BuildContext context, WorkspaceState state, WorkspaceTab tab) => switch (tab.kind) {
  WorkspaceTabKind.documentMap => context.l10n.workspaceDocumentMapTab,
  WorkspaceTabKind.note => state.content?.studyNote(tab.noteId ?? '')?.title ?? context.l10n.notesTitle,
  WorkspaceTabKind.vocabulary => context.l10n.vocabularyTitle,
  WorkspaceTabKind.review => context.l10n.review,
};

IconData _tabIcon(WorkspaceTab tab) => switch (tab.kind) {
  WorkspaceTabKind.documentMap => MMIcons.document,
  WorkspaceTabKind.note => MMIcons.studyNote,
  WorkspaceTabKind.vocabulary => MMIcons.vocabulary,
  WorkspaceTabKind.review => MMIcons.review,
};

class WorkspaceTabStrip extends ConsumerStatefulWidget {
  const WorkspaceTabStrip({super.key, required this.studySetId});
  final String studySetId;
  @override
  ConsumerState<WorkspaceTabStrip> createState() => _WorkspaceTabStripState();
}

class _WorkspaceTabStripState extends ConsumerState<WorkspaceTabStrip> {
  final _keys = <String, GlobalKey>{};
  String? _lastActive;
  double? _lastWidth;
  String get studySetId => widget.studySetId;
  @override
  Widget build(BuildContext context) {
    ref.watch(workspaceProvider(studySetId).select((s) => s.tabs));
    ref.watch(workspaceContentProvider(studySetId));
    final state = ref.read(workspaceProvider(studySetId));
    final owner = ref.read(workspaceProvider(studySetId).notifier);
    final touch = context.mmTouchPlatform;
    _keys.removeWhere((id, _) => !state.tabs.open.any((tab) => tab.id == id));
    for (final tab in state.tabs.open) {
      _keys.putIfAbsent(tab.id, () => GlobalKey());
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final count = state.tabs.open.length;
        final overflow = count > 0 && count * 156 + math.max(0, count - 1) * 4 + 24 > bounds.maxWidth;
        final available = bounds.maxWidth - (overflow ? (touch ? 44 : 28) : 0) - 24 - math.max(0, count - 1) * 4;
        final width = (available / math.max(1, count)).clamp(156.0, 224.0);
        if (_lastActive != state.tabs.activeId || _lastWidth != bounds.maxWidth) {
          _lastActive = state.tabs.activeId;
          _lastWidth = bounds.maxWidth;
          final key = _keys[_lastActive];
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = key?.currentContext;
            if (mounted && target != null) {
              Scrollable.ensureVisible(
                target,
                alignment: .5,
                duration: MMAppearance.duration(context, MMMotion.standard),
              );
            }
          });
        }
        final tabs = SingleChildScrollView(
          key: const ValueKey('workspace-main-tabs'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                _WorkspaceTab(
                  key: ValueKey('workspace-tab-${state.tabs.open[i].id}'),
                  anchor: _keys[state.tabs.open[i].id]!,
                  tab: state.tabs.open[i],
                  title: workspaceTabTitle(context, state, state.tabs.open[i]),
                  selected: state.tabs.open[i].id == state.tabs.activeId,
                  width: width,
                  onSelect: () => owner.activateTab(state.tabs.open[i]),
                  onClose: () => owner.closeTab(state.tabs.open[i].id),
                ),
              ],
            ],
          ),
        );
        final tabsWidth = count == 0 ? 0.0 : count * width + math.max(0, count - 1) * 4 + 24;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (overflow)
              Expanded(child: tabs)
            else ...[
              SizedBox(width: tabsWidth, child: tabs),
              const Expanded(child: MMWindowDragRegion(key: ValueKey('workspace-tab-drag-area'))),
            ],
            if (overflow)
              MMDropdownButton<WorkspaceTab>(
                key: const ValueKey('workspace-tab-overflow'),
                tooltip: context.l10n.workspaceOpenTabs,
                width: 280,
                icon: const Icon(MMIcons.chevronDown, size: 14),
                onSelected: owner.activateTab,
                itemBuilder: (_) => [
                  for (final tab in state.tabs.open)
                    MMDropdownItem<WorkspaceTab>(
                      value: tab,
                      child: Row(
                        children: [
                          Icon(_tabIcon(tab), size: 14, color: context.mmColors.secondaryLabel),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              workspaceTabTitle(context, state, tab),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (tab.id == state.tabs.activeId)
                            Icon(MMIcons.check, size: 14, color: context.mmColors.accent),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// A stable close slot avoids shifting titles when the pointer crosses tabs.
/// Selection and close are sibling controls so both remain accessible.
class _WorkspaceTab extends StatefulWidget {
  const _WorkspaceTab({
    super.key,
    required this.anchor,
    required this.tab,
    required this.title,
    required this.selected,
    required this.width,
    required this.onSelect,
    required this.onClose,
  });
  final GlobalKey anchor;
  final WorkspaceTab tab;
  final String title;
  final bool selected;
  final double width;
  final VoidCallback onSelect, onClose;
  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<_WorkspaceTab> {
  bool _hovered = false, _focused = false;
  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final touch = context.mmTouchPlatform;
    final showClose = touch || widget.selected || _hovered || _focused;
    final type = context.mmText.body.copyWith(
      fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
      color: widget.selected ? c.label : c.secondaryLabel,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => _focused = value),
        child: SizedBox(
          key: widget.anchor,
          width: widget.width,
          height: touch ? 44 : 36,
          child: MMInteractive(
            isButton: false,
            canRequestFocus: false,
            // The outer surface only paints shared hover/press feedback.
            onTap: widget.onSelect,
            builder: (context, interaction) => AnimatedContainer(
              key: ValueKey('workspace-tab-surface-${widget.tab.id}'),
              duration: interaction.pressed ? Duration.zero : MMAppearance.duration(context, MMMotion.quick),
              decoration: BoxDecoration(
                color: interaction.pressed
                    ? c.pressed
                    : widget.selected
                    ? c.card
                    : _hovered
                    ? c.hover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: widget.selected && c.brightness == Brightness.light
                    ? const [BoxShadow(color: Color(0x0C000000), blurRadius: 3, offset: Offset(0, 1))]
                    : null,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _focused
                      ? c.accent
                      : widget.selected
                      ? c.border
                      : Colors.transparent,
                  width: .5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: MMInteractive(
                      selected: widget.selected,
                      semanticLabel: widget.title,
                      onTap: widget.onSelect,
                      builder: (context, interaction) => Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: Row(
                          children: [
                            Icon(_tabIcon(widget.tab), size: 15, color: widget.selected ? c.accent : c.icon),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, bounds) {
                                  final text = Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: type,
                                  );
                                  final painter = TextPainter(
                                    text: TextSpan(text: widget.title, style: type),
                                    maxLines: 1,
                                    ellipsis: '…',
                                    textDirection: Directionality.of(context),
                                    textScaler: MediaQuery.textScalerOf(context),
                                  )..layout(maxWidth: bounds.maxWidth);
                                  final truncated = painter.didExceedMaxLines;
                                  painter.dispose();
                                  return truncated ? Tooltip(message: widget.title, child: text) : text;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    ignoring: !showClose,
                    child: AnimatedOpacity(
                      opacity: showClose ? 1 : 0,
                      alwaysIncludeSemantics: true,
                      duration: MMAppearance.duration(context, MMMotion.quick),
                      child: MMIconButton(
                        key: ValueKey('close-workspace-tab-${widget.tab.id}'),
                        icon: MMIcons.close,
                        iconSize: 11,
                        size: touch ? 44 : 28,
                        tooltip: '${context.l10n.closeTab} · ${widget.title}',
                        onPressed: widget.onClose,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
