import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../theme/mm_theme.dart';
import '../icons/mm_icons.dart';
import 'toolbar.dart';
import '../tokens/metrics.dart';

/// Which panes of an [MMSplitView] are visible.
enum MMSplitMode { primary, split, secondary }

/// Two panes side by side, or [primary] above [secondary] with
/// [Axis.vertical], and a draggable divider (1px visual, 8px hit area, 44
/// under touch; double-click resets to 50 : 50). Hidden panes stay mounted, so
/// switching layouts keeps scroll positions and other state.
///
/// When the window is too narrow for both minimum widths, `split` falls
/// back to the primary pane.
class MMSplitView extends StatelessWidget {
  const MMSplitView({
    super.key,
    required this.primary,
    required this.secondary,
    this.mode = MMSplitMode.split,
    this.onModeChanged,
    this.primaryLabel = 'Source Only',
    this.secondaryLabel = 'Map Only',
    this.splitLabel = 'Split',
    this.fraction = 0.5,
    this.onFractionChanged,
    this.minPrimaryWidth = MMSizes.readerMinWidth,
    this.minSecondaryWidth = MMSizes.mapMinWidth,
    this.collapseWhenNarrow = true,
    this.axis = Axis.horizontal,
  });

  /// [Axis.vertical] stacks the panes; the minimum sizes are then heights.
  final Axis axis;

  final Widget primary;
  final Widget secondary;
  final MMSplitMode mode;
  final ValueChanged<MMSplitMode>? onModeChanged;
  final String primaryLabel, secondaryLabel, splitLabel;

  /// Share of the width given to [primary] in split mode.
  final double fraction;
  final ValueChanged<double>? onFractionChanged;
  final double minPrimaryWidth;
  final double minSecondaryWidth;

  /// If false, share the available space instead of hiding the map.
  final bool collapseWhenNarrow;

  /// The mode actually shown at [width].
  static MMSplitMode effectiveMode(MMSplitMode mode, double width, double minPrimary, double minSecondary) {
    if (mode == MMSplitMode.split && width < minPrimary + minSecondary + 1) return MMSplitMode.primary;
    return mode;
  }

  /// What a window of [windowWidth] actually shows: when [mode] is `split`
  /// and the panes do not fit beside the sidebar ([sidebarWidth] wide, if
  /// [sidebarVisible]), the sidebar collapses first; if they still do not
  /// fit, the layout falls back to the primary pane alone.
  static ({bool sidebarVisible, MMSplitMode mode}) resolveNarrow({
    required MMSplitMode mode,
    required bool sidebarVisible,
    required double windowWidth,
    required double sidebarWidth,
    double minPrimary = MMSizes.readerMinWidth,
    double minSecondary = MMSizes.mapMinWidth,
  }) {
    if (mode != MMSplitMode.split) return (sidebarVisible: sidebarVisible, mode: mode);
    final needed = minPrimary + minSecondary + 1;
    if (windowWidth - (sidebarVisible ? sidebarWidth : 0) >= needed) {
      return (sidebarVisible: sidebarVisible, mode: mode);
    }
    if (windowWidth >= needed) return (sidebarVisible: false, mode: mode);
    return (sidebarVisible: sidebarVisible, mode: MMSplitMode.primary);
  }

  /// Width of the primary pane in split mode, respecting both minimums.
  static double primaryWidth(double width, double fraction, double minPrimary, double minSecondary) {
    final max = width - 1 - minSecondary;
    return (width * fraction).clamp(minPrimary, max < minPrimary ? minPrimary : max);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final vertical = axis == Axis.vertical;
    final hit = context.mmDividerHit;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = vertical ? constraints.maxHeight : constraints.maxWidth;
        final m = collapseWhenNarrow ? effectiveMode(mode, w, minPrimaryWidth, minSecondaryWidth) : mode;
        final showP = m != MMSplitMode.secondary;
        final showS = m != MMSplitMode.primary;
        final split = showP && showS;
        final scale = !collapseWhenNarrow && w < minPrimaryWidth + minSecondaryWidth + 1
            ? ((w - 1) / (minPrimaryWidth + minSecondaryWidth)).clamp(0.0, 1.0)
            : 1.0;
        final minPrimary = minPrimaryWidth * scale;
        final minSecondary = minSecondaryWidth * scale;
        final pw = split ? primaryWidth(w, fraction, minPrimary, minSecondary) : w;
        Widget sized(double extent, Widget child) =>
            vertical ? SizedBox(height: extent, child: child) : SizedBox(width: extent, child: child);
        final panes = [
          // A hidden pane stays mounted but cannot keep keyboard focus.
          Offstage(
            offstage: !showP,
            child: ExcludeFocus(excluding: !showP, child: sized(showP ? pw : 0, primary)),
          ),
          if (split) sized(1, ColoredBox(color: c.separator)),
          Offstage(
            offstage: !showS,
            child: ExcludeFocus(excluding: !showS, child: sized(showS ? (split ? w - pw - 1 : w) : 0, secondary)),
          ),
        ];
        final divider = MouseRegion(
          cursor: vertical ? SystemMouseCursors.resizeRow : SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: vertical ? null : (d) => _drag(w, pw, d.delta.dx, minPrimary, minSecondary),
            onVerticalDragUpdate: vertical ? (d) => _drag(w, pw, d.delta.dy, minPrimary, minSecondary) : null,
            onDoubleTap: () => onFractionChanged!(0.5),
            child: Semantics(label: 'Divider', slider: true, child: const SizedBox.expand()),
          ),
        );
        final button = context.mmToolbarButton;

        return Stack(
          children: [
            vertical
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: panes)
                : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: panes),
            if (split && onFractionChanged != null)
              vertical
                  ? Positioned(top: pw + 0.5 - hit / 2, left: 0, right: 0, height: hit, child: divider)
                  : Positioned(left: pw + 0.5 - hit / 2, top: 0, bottom: 0, width: hit, child: divider),
            if (onModeChanged != null && !vertical)
              Positioned(
                left: split
                    ? (pw - button.width).clamp(0, w - button.width * 2)
                    : showP
                    ? null
                    : MMSpacing.s,
                right: !split && showP ? MMSpacing.s : null,
                bottom: MMSizes.toolbarHeight + MMSpacing.m,
                child: _modeButtons(split),
              ),
            // Stacked panes: the switch sits at the right end of the divider,
            // or at the bottom right of the single pane.
            if (onModeChanged != null && vertical)
              Positioned(
                right: MMSpacing.s,
                top: split ? (pw - button.height - 6 - MMSpacing.s).clamp(0.0, w) : null,
                bottom: split ? null : MMSizes.toolbarHeight + MMSpacing.m,
                child: _modeButtons(split),
              ),
          ],
        );
      },
    );
  }

  void _drag(double extent, double primary, double delta, double minPrimary, double minSecondary) {
    final next = primaryWidth(extent, (primary + delta) / extent, minPrimary, minSecondary);
    onFractionChanged!(next / extent);
  }

  Widget _modeButtons(bool split) {
    final vertical = axis == Axis.vertical;
    return MMToolbarGroup(
      children: [
        if (split) ...[
          MMToolbarButton(
            icon: vertical ? MMIcons.chevronUp : MMIcons.chevronLeft,
            tooltip: secondaryLabel,
            onPressed: () => onModeChanged!(MMSplitMode.secondary),
          ),
          MMToolbarButton(
            icon: vertical ? MMIcons.chevronDown : MMIcons.chevronRight,
            tooltip: primaryLabel,
            onPressed: () => onModeChanged!(MMSplitMode.primary),
          ),
        ] else
          MMToolbarButton(
            icon: MMIcons.layoutSplit,
            tooltip: splitLabel,
            onPressed: () => onModeChanged!(MMSplitMode.split),
          ),
      ],
    );
  }
}
