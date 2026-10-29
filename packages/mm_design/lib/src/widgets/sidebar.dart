import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../foundation/appearance.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'context_menu_region.dart';
import 'window_scaffold.dart';

/// Floating glass sidebar (macOS 26): inset 8 from the window edges,
/// radius 16, with room at the top for the system window buttons.
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
    final reduce = MMAppearance.reduceTransparencyOf(context);
    final chrome = MMWindowChrome.maybeOf(context);
    const radius = BorderRadius.all(Radius.circular(MMRadii.sidebar));

    Widget panel = Container(
      decoration: BoxDecoration(
        color: reduce ? c.sidebarOpaque : c.sidebar,
        borderRadius: radius,
        border: Border.all(color: c.hairline, width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: chrome?.onDragStart == null ? null : (_) => chrome!.onDragStart!(),
            onDoubleTap: chrome?.onTitleDoubleTap,
            child: SizedBox(
              height: MMSizes.windowButtonsHeight,
              child: Row(children: [const Spacer(), ?topTrailing]),
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
      margin: const EdgeInsets.fromLTRB(MMSizes.sidebarInset, MMSizes.sidebarInset, 0, MMSizes.sidebarInset),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          for (final s in c.sidebarShadow)
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
    this.trailing,
    this.showTrailingOnHover = false,
  });

  final String title;
  final List<Widget> children;
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
                child: Semantics(header: true, child: Text(widget.title, style: context.mmText.subheadline)),
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

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final item = MMInteractive(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      selected: selected,
      builder: (context, s) => AnimatedContainer(
        duration: MMMotion.quick,
        height: context.mmSidebarRow,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? c.selectedRow : (s.hovered ? c.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(MMRadii.row),
          border: s.focused ? Border.all(color: c.accent, width: 2) : null,
        ),
        child: Row(
          children: [
            SizedBox(width: 18, child: Icon(icon, size: 15, color: iconColor ?? c.accent)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: context.mmText.body, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
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
