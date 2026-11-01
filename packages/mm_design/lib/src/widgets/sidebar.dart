import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../foundation/appearance.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'context_menu_region.dart';
import 'flat_surface.dart';
import 'window_scaffold.dart';

/// Edge-to-edge desktop navigation; touch drawers retain their floating glass.
/// Both leave room at the top for the system window buttons.
class MMSidebar extends StatelessWidget {
  const MMSidebar({
    super.key,
    required this.children,
    this.topTrailing,
    this.header,
    this.footer,
    this.width = MMSizes.sidebarWidth,
  });

  /// Scrollable content, usually [MMSidebarSection]s.
  final List<Widget> children;

  /// Shown at the right of the window-button row (e.g. the hide button).
  final Widget? topTrailing;

  /// Fixed content under the window-button row (e.g. a search field).
  final Widget? header;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final flat = !MMInput.of(context).touchPlatform;
    final reduce = flat || MMAppearance.reduceTransparencyOf(context) || MMFlatSurface.of(context);
    final chrome = MMWindowChrome.maybeOf(context);
    final radius = flat ? BorderRadius.zero : const BorderRadius.all(Radius.circular(MMRadii.sidebar));

    Widget panel = Container(
      decoration: BoxDecoration(
        color: reduce ? c.sidebarOpaque : c.sidebar,
        borderRadius: radius,
        border: flat ? null : Border.all(color: MMFlatSurface.of(context) ? c.border : c.hairline, width: 0.5),
      ),
      // Desktop removes the outer inset; keep window-button controls at y=26.
      padding: EdgeInsets.fromLTRB(10, flat ? 12 : 3.5, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: MMSizes.windowButtonsHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Title gestures belong behind controls so double-click
                // recognition never holds a button's first click.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: chrome?.onDragStart == null ? null : (_) => chrome!.onDragStart!(),
                  onDoubleTap: chrome?.onTitleDoubleTap,
                ),
                Row(children: [const Spacer(), ?topTrailing]),
              ],
            ),
          ),
          if (header != null) Padding(padding: const EdgeInsets.only(top: 10), child: header),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(top: 2, bottom: 8), children: children),
          ),
          ?footer,
        ],
      ),
    );
    if (!reduce) {
      panel = BackdropFilter(filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), child: panel);
    }
    return Container(
      width: width,
      margin: flat
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(MMSizes.sidebarInset, MMSizes.sidebarInset, 0, MMSizes.sidebarInset),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          for (final s in flat || MMFlatSurface.of(context) ? <BoxShadow>[] : c.sidebarShadow)
            BoxShadow(color: s.color, offset: s.offset, blurRadius: s.blurRadius, blurStyle: BlurStyle.outer),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: panel),
    );
  }
}

/// A titled group of sidebar rows.
class MMSidebarSection extends StatefulWidget {
  const MMSidebarSection({
    super.key,
    required this.title,
    required this.children,
    this.titleTrailing,
    this.trailing,
    this.showTrailingOnHover = false,
  });

  final String title;
  final List<Widget> children;
  final Widget? titleTrailing;
  final Widget? trailing;

  /// Reveal the action over the whole section, keeping its space reserved.
  /// Touch input and keyboard focus keep the action visible without hovering.
  final bool showTrailingOnHover;

  @override
  State<MMSidebarSection> createState() => _MMSidebarSectionState();
}

class _MMSidebarSectionState extends State<MMSidebarSection> {
  bool _hovered = false;
  bool _actionFocused = false;

  @override
  Widget build(BuildContext context) {
    final showAction = !widget.showTrailingOnHover || _hovered || _actionFocused || MMInput.touchInputOf(context);
    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 2, 4),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.mmText.subheadline,
                        ),
                      ),
                    ),
                    if (widget.titleTrailing != null) ...[const SizedBox(width: 4), widget.titleTrailing!],
                  ],
                ),
              ),
              if (widget.trailing != null)
                Focus(
                  canRequestFocus: false,
                  onFocusChange: (focused) => setState(() => _actionFocused = focused),
                  child: IgnorePointer(
                    ignoring: !showAction,
                    child: AnimatedOpacity(
                      opacity: showAction ? 1 : 0,
                      duration: MMAppearance.duration(context, MMMotion.quick),
                      alwaysIncludeSemantics: true,
                      child: widget.trailing,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final child in widget.children) Padding(padding: const EdgeInsets.only(bottom: 1), child: child),
      ],
    );
    if (!widget.showTrailingOnHover) return section;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: section,
    );
  }
}

/// Sidebar row (height 28; 44 under touch): accent-tinted icon, label, optional count.
/// Selection is a gray rounded fill; text weight does not change.
/// VoiceOver reads the label and the count once each.
enum MMSidebarSelectionStyle { filled, marker, accent }

class MMSidebarItem extends StatelessWidget {
  const MMSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.iconColor,
    this.leading,
    this.labelColor,
    this.selectionStyle = MMSidebarSelectionStyle.filled,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Right click, with the pointer position in global coordinates.
  final ValueChanged<Offset>? onContextMenu;
  final Color? iconColor;
  final Widget? leading;
  final Color? labelColor;
  final MMSidebarSelectionStyle selectionStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final marker = selectionStyle == MMSidebarSelectionStyle.marker;
    final row = Row(
      children: [
        SizedBox(width: 18, child: leading ?? Icon(icon, size: 15, color: iconColor ?? c.accent)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: context.mmText.body.copyWith(
              color: labelColor,
              fontWeight: marker && selected ? FontWeight.w600 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
    final item = MMInteractive(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      selected: selected,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        height: context.mmSidebarRow,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected && !marker
              ? selectionStyle == MMSidebarSelectionStyle.accent
                    ? c.accentTint
                    : c.selectedRow
              : (s.pressed ? c.pressed : (s.hovered ? c.hover : Colors.transparent)),
          borderRadius: BorderRadius.circular(MMRadii.row),
          border: s.focused ? Border.all(color: c.accent, width: 2) : null,
        ),
        child: !marker
            ? row
            : Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  if (marker && selected)
                    Positioned(
                      left: -6,
                      child: Container(
                        width: 2,
                        height: 18,
                        decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(1)),
                      ),
                    ),
                  row,
                ],
              ),
      ),
    );
    if (onContextMenu == null) return item;
    return MMContextMenuRegion(onSecondaryTapUp: (d) => onContextMenu!(d.globalPosition), child: item);
  }
}

/// Plain trailing number in a sidebar row.
class MMCount extends StatelessWidget {
  const MMCount(this.value, {super.key});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$value',
      style: context.mmText.footnote.copyWith(fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

/// Capsule badge for counts that ask for attention (e.g. cards due).
class MMBadge extends StatelessWidget {
  const MMBadge(this.value, {super.key, this.prominent = false});

  final String value;

  /// Accent tint instead of neutral fill.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: prominent ? c.accentTint : c.fill, borderRadius: BorderRadius.circular(9)),
      child: Text(
        value,
        style: context.mmText.subheadline.copyWith(
          color: prominent ? c.accent : c.label,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Compact pill tag marking a Beta feature in menus and section headers.
class MMBetaBadge extends StatelessWidget {
  const MMBetaBadge({super.key, this.label = 'Beta', this.inverted = false});

  final String label;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final bg = inverted ? c.onAccent.withValues(alpha: 0.22) : c.researchTint;
    final fg = inverted ? c.onAccent : c.research;
    return ExcludeSemantics(
      child: Container(
        height: 14,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(
          label,
          style: context.mmText.footnote.copyWith(
            fontSize: 9,
            height: 1.0,
            letterSpacing: -0.1,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}
