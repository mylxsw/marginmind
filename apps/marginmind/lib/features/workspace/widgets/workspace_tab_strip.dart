import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
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
  WorkspaceTabKind.statistics => context.l10n.statistics,
};

IconData _tabIcon(WorkspaceTab tab) => switch (tab.kind) {
  WorkspaceTabKind.documentMap => MMIcons.document,
  WorkspaceTabKind.note => MMIcons.studyNote,
  WorkspaceTabKind.vocabulary => MMIcons.vocabulary,
  WorkspaceTabKind.review => MMIcons.review,
  WorkspaceTabKind.statistics => MMIcons.statistics,
};

TextStyle _tabTextStyle(BuildContext context) =>
    DefaultTextStyle.of(context).style.merge(context.mmTouchPlatform ? context.mmText.body : context.mmText.callout);

double _tabWidth(BuildContext context, String title) {
  // Reserve the close slot and measure the stronger selected weight so
  // activating or hovering a tab never shifts its neighbours.
  final painter = TextPainter(
    text: TextSpan(
      text: title,
      style: _tabTextStyle(context).copyWith(fontWeight: FontWeight.w600),
    ),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.localeOf(context),
  )..layout();
  final width = math.min(224.0, painter.width.ceilToDouble() + (context.mmTouchPlatform ? 87 : 66));
  painter.dispose();
  return width;
}

class WorkspaceTabStrip extends ConsumerStatefulWidget {
  const WorkspaceTabStrip({super.key, required this.studySetId});
  final String studySetId;
  @override
  ConsumerState<WorkspaceTabStrip> createState() => _WorkspaceTabStripState();
}

class _WorkspaceTabStripState extends ConsumerState<WorkspaceTabStrip> {
  final _scroll = ScrollController();
  String? _lastActive;
  double? _lastWidth;
  List<double> _lastTabWidths = const [];
  String get studySetId => widget.studySetId;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(workspaceProvider(studySetId).select((s) => s.tabs));
    ref.watch(workspaceContentProvider(studySetId));
    final state = ref.read(workspaceProvider(studySetId));
    final owner = ref.read(workspaceProvider(studySetId).notifier);
    return LayoutBuilder(
      builder: (context, bounds) {
        final count = state.tabs.open.length;
        final titles = [for (final tab in state.tabs.open) workspaceTabTitle(context, state, tab)];
        final widths = [for (final title in titles) _tabWidth(context, title)];
        final tabsWidth = count == 0 ? 0.0 : widths.fold(0.0, (total, width) => total + width) + (count - 1) * 4 + 24;
        final overflow = tabsWidth > bounds.maxWidth;
        // Same size MMDropdownButton gives its icon button; a squeezed strip drops the
        // open-tabs menu rather than overflow (the tab list still scrolls).
        final menuWidth =
            (context.mmTouch || context.mmTouchPlatform ? context.mmToolbarButton : MMSizes.readerToolbarButton).width;
        final showMenu = overflow && bounds.maxWidth >= menuWidth;
        if (_lastActive != state.tabs.activeId ||
            _lastWidth != bounds.maxWidth ||
            !listEquals(_lastTabWidths, widths)) {
          _lastActive = state.tabs.activeId;
          _lastWidth = bounds.maxWidth;
          _lastTabWidths = widths;
          final activeIndex = state.tabs.open.indexWhere((tab) => tab.id == state.tabs.activeId);
          final duration = MMAppearance.duration(context, MMMotion.standard);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && activeIndex >= 0 && _scroll.hasClients) {
              final center =
                  12 +
                  widths.take(activeIndex).fold(0.0, (total, width) => total + width) +
                  activeIndex * 4 +
                  widths[activeIndex] / 2;
              final target = (center - _scroll.position.viewportDimension / 2).clamp(
                0.0,
                _scroll.position.maxScrollExtent,
              );
              if (duration == Duration.zero) {
                _scroll.jumpTo(target);
              } else {
                _scroll.animateTo(target, duration: duration, curve: Curves.easeInOut);
              }
            }
          });
        }
        final tabs = ReorderableListView.builder(
          key: const ValueKey('workspace-main-tabs'),
          scrollController: _scroll,
          primary: false,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) {
            final reorderedWidths = [...widths];
            reorderedWidths.insert(newIndex, reorderedWidths.removeAt(oldIndex));
            _lastTabWidths = reorderedWidths;
            owner.reorderTabs(oldIndex, newIndex);
          },
          proxyDecorator: (child, index, animation) => child,
          itemCount: count,
          itemExtentBuilder: (index, _) => widths[index] + (index < count - 1 ? 4 : 0),
          itemBuilder: (context, i) => Padding(
            key: ValueKey('workspace-tab-item-${state.tabs.open[i].id}'),
            padding: EdgeInsets.only(right: i < count - 1 ? 4 : 0),
            child: Center(
              child: _WorkspaceTab(
                key: ValueKey('workspace-tab-${state.tabs.open[i].id}'),
                index: i,
                tab: state.tabs.open[i],
                title: titles[i],
                selected: state.tabs.open[i].id == state.tabs.activeId,
                width: widths[i],
                onSelect: () => owner.activateTab(state.tabs.open[i]),
                onClose: () => owner.closeTab(state.tabs.open[i].id),
              ),
            ),
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (overflow)
              Expanded(child: tabs)
            else ...[
              const Expanded(child: MMWindowDragRegion()),
              SizedBox(width: tabsWidth, child: tabs),
              const Expanded(child: MMWindowDragRegion(key: ValueKey('workspace-tab-drag-area'))),
            ],
            if (showMenu)
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
    required this.index,
    required this.tab,
    required this.title,
    required this.selected,
    required this.width,
    required this.onSelect,
    required this.onClose,
  });
  final int index;
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
    final type = _tabTextStyle(context).copyWith(
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
          width: widget.width,
          height: touch ? 44 : 30,
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
                borderRadius: BorderRadius.circular(touch ? 8 : 6),
                boxShadow: widget.selected && c.brightness == Brightness.light
                    ? const [BoxShadow(color: Color(0x0C000000), blurRadius: 3, offset: Offset(0, 1))]
                    : null,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(touch ? 8 : 6),
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
                    child: _dragHandle(
                      context,
                      SizedBox(
                        height: touch ? 44 : 30,
                        child: MMInteractive(
                          selected: widget.selected,
                          semanticLabel: widget.title,
                          onTap: widget.onSelect,
                          builder: (context, interaction) => Padding(
                            padding: EdgeInsets.only(left: touch ? 12 : 10, right: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _tabIcon(widget.tab),
                                  size: touch ? 15 : 14,
                                  color: widget.selected ? c.accent : c.icon,
                                ),
                                SizedBox(width: touch ? 8 : 6),
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
                                        locale: Localizations.localeOf(context),
                                      )..layout(maxWidth: bounds.maxWidth);
                                      final truncated = painter.didExceedMaxLines;
                                      painter.dispose();
                                      return truncated
                                          ? Tooltip(
                                              message: widget.title,
                                              triggerMode: TooltipTriggerMode.manual,
                                              child: text,
                                            )
                                          : text;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  Widget _dragHandle(BuildContext context, Widget child) => Listener(
    onPointerDown: (event) {
      // A quick finger swipe still scrolls, including on a touch-capable
      // desktop; a mouse can reorder immediately on any platform.
      final recognizer = event.kind == PointerDeviceKind.mouse
          ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
          : DelayedMultiDragGestureRecognizer(debugOwner: this);
      SliverReorderableList.of(context).startItemDragReorder(
        index: widget.index,
        event: event,
        recognizer: recognizer..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
      );
    },
    child: child,
  );
}
