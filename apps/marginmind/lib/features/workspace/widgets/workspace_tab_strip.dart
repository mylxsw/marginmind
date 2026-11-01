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
  final width = math.min(224.0, painter.width.ceilToDouble() + (context.mmTouchPlatform ? 103 : 82));
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
        final tabsWidth = count == 0 ? 0.0 : widths.fold(0.0, (total, width) => total + width) + 24;
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
                  12 + widths.take(activeIndex).fold(0.0, (total, width) => total + width) + widths[activeIndex] / 2;
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
          itemExtentBuilder: (index, _) => widths[index],
          itemBuilder: (context, i) => Padding(
            key: ValueKey('workspace-tab-item-${state.tabs.open[i].id}'),
            padding: EdgeInsets.only(
              top: math.min(
                context.mmTouchPlatform ? 6 : 8,
                math.max(0, bounds.maxHeight - (context.mmTouchPlatform ? 44 : 30)),
              ),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _WorkspaceTab(
                key: ValueKey('workspace-tab-${state.tabs.open[i].id}'),
                index: i,
                tab: state.tabs.open[i],
                title: titles[i],
                selected: state.tabs.open[i].id == state.tabs.activeId,
                showSeparator:
                    i < count - 1 &&
                    state.tabs.open[i].id != state.tabs.activeId &&
                    state.tabs.open[i + 1].id != state.tabs.activeId,
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
    required this.showSeparator,
    required this.width,
    required this.onSelect,
    required this.onClose,
  });
  final int index;
  final WorkspaceTab tab;
  final String title;
  final bool selected, showSeparator;
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
          height: double.infinity,
          child: MMInteractive(
            isButton: false,
            canRequestFocus: false,
            // The outer surface only paints shared hover/press feedback.
            onTap: widget.onSelect,
            builder: (context, interaction) => AnimatedContainer(
              key: ValueKey('workspace-tab-surface-${widget.tab.id}'),
              duration: interaction.pressed ? Duration.zero : MMAppearance.duration(context, MMMotion.quick),
              decoration: ShapeDecoration(
                color: widget.selected
                    ? c.windowBackground
                    : interaction.pressed
                    ? c.pressed
                    : _hovered
                    ? c.hover
                    : Colors.transparent,
                shape: _ChromeTabShape(side: _focused ? BorderSide(color: c.accent, width: 1.5) : BorderSide.none),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.showSeparator && !_hovered)
                    Positioned(
                      right: 0,
                      top: 10,
                      bottom: 10,
                      child: ColoredBox(color: c.separator, child: const SizedBox(width: 1)),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                        color: widget.selected ? c.label : c.icon,
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

/// Rounded shoulders and concave feet join the active tab to the content.
class _ChromeTabShape extends ShapeBorder {
  const _ChromeTabShape({this.side = BorderSide.none});
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    const foot = 8.0;
    const shoulder = 10.0;
    final l = rect.left, r = rect.right, t = rect.top, b = rect.bottom;
    return Path()
      ..moveTo(l, b)
      ..quadraticBezierTo(l + foot, b, l + foot, b - foot)
      ..lineTo(l + foot, t + shoulder)
      ..quadraticBezierTo(l + foot, t, l + foot + shoulder, t)
      ..lineTo(r - foot - shoulder, t)
      ..quadraticBezierTo(r - foot, t, r - foot, t + shoulder)
      ..lineTo(r - foot, b - foot)
      ..quadraticBezierTo(r - foot, b, r, b)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.solid) {
      canvas.drawPath(getOuterPath(rect.deflate(side.width / 2)), side.toPaint());
    }
  }

  @override
  ShapeBorder scale(double t) => _ChromeTabShape(side: side.scale(t));
}
