import 'package:flutter/material.dart';

import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';

/// Which panes of an [MMSplitView] are visible.
enum MMSplitMode { primary, split, secondary }

/// Two panes side by side with a draggable divider (1px visual, 8px hit
/// area; double-click resets to 50 : 50). Hidden panes stay mounted, so
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
    this.fraction = 0.5,
    this.onFractionChanged,
    this.minPrimaryWidth = MMSizes.readerMinWidth,
    this.minSecondaryWidth = MMSizes.mapMinWidth,
  });

  final Widget primary;
  final Widget secondary;
  final MMSplitMode mode;

  /// Share of the width given to [primary] in split mode.
  final double fraction;
  final ValueChanged<double>? onFractionChanged;
  final double minPrimaryWidth;
  final double minSecondaryWidth;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final m = effectiveMode(mode, w, minPrimaryWidth, minSecondaryWidth);
        final showP = m != MMSplitMode.secondary;
        final showS = m != MMSplitMode.primary;
        final split = showP && showS;
        final pw = split ? primaryWidth(w, fraction, minPrimaryWidth, minSecondaryWidth) : w;

        return Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A hidden pane stays mounted but cannot keep keyboard focus.
                Offstage(
                  offstage: !showP,
                  child: ExcludeFocus(
                    excluding: !showP,
                    child: SizedBox(width: showP ? pw : 0, child: primary),
                  ),
                ),
                if (split) SizedBox(width: 1, child: ColoredBox(color: c.separator)),
                Offstage(
                  offstage: !showS,
                  child: ExcludeFocus(
                    excluding: !showS,
                    child: SizedBox(width: showS ? (split ? w - pw - 1 : w) : 0, child: secondary),
                  ),
                ),
              ],
            ),
            if (split && onFractionChanged != null)
              Positioned(
                left: pw + 0.5 - MMSizes.dividerHitWidth / 2,
                top: 0,
                bottom: 0,
                width: MMSizes.dividerHitWidth,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      final next = primaryWidth(w, (pw + d.delta.dx) / w, minPrimaryWidth, minSecondaryWidth);
                      onFractionChanged!(next / w);
                    },
                    onDoubleTap: () => onFractionChanged!(0.5),
                    child: Semantics(label: 'Divider', slider: true, child: const SizedBox.expand()),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
