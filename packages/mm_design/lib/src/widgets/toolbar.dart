import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'glass.dart';
import 'search_field.dart';
import 'window_scaffold.dart';

/// Unified window toolbar (height 56): title and subtitle on the left,
/// glass control groups on the right. Dragging empty space moves the window;
/// double-clicking it zooms, like a native title bar.
class MMToolbar extends StatelessWidget {
  const MMToolbar({super.key, required this.title, this.subtitle, this.actions = const [], this.leading});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = context.mmText;
    final chrome = MMWindowChrome.maybeOf(context);
    return SizedBox(
      height: MMSizes.toolbarHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A background sibling cannot compete with button gestures. An
          // ancestor double-tap recognizer holds their taps for 300ms.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: chrome?.onDragStart == null ? null : (_) => chrome!.onDragStart!(),
            onDoubleTap: chrome?.onTitleDoubleTap,
          ),
          AnimatedPadding(
            duration: MMMotion.layout,
            curve: MMMotion.layoutCurve,
            padding: EdgeInsets.only(left: 20 + (chrome?.toolbarLeadingInset ?? 0), right: 12),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Expanded(
                  child: IgnorePointer(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.title3, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (subtitle != null)
                          Text(subtitle!, style: t.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10), actions[i]],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A glass capsule that groups related toolbar buttons.
class MMToolbarGroup extends StatelessWidget {
  const MMToolbarGroup({super.key, required this.children, this.compact = false});

  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return MMGlass(
      padding: EdgeInsets.all(compact && !context.mmTouch ? 2 : 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Toolbar button (34×30, radius 15; 44×44 under touch). Selected uses the accent tint, never a
/// solid fill.
class MMToolbarButton extends StatelessWidget {
  const MMToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.label,
    this.count = 0,
    this.tint,
    this.compact = false,
  }) : assert(icon != null || label != null);

  /// A feature color for icon and label (research), in place of the label
  /// color, also while selected (the open assistant).
  final Color? tint;

  /// Null for a text-only button (e.g. "Done"); [label] is then required.
  final IconData? icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  /// Denser desktop chrome; touch controls keep their full hit area.
  final bool compact;

  /// Optional text shown next to the icon (e.g. a sort pop-up).
  final String? label;

  /// Quiet inline count, hidden at zero and sharing the button's foreground.
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final size = compact && !context.mmTouch ? const Size(30, 26) : context.mmToolbarButton;
    return MMInteractive(
      onTap: onPressed,
      selected: selected,
      tooltip: tooltip,
      semanticLabel: tooltip,
      builder: (context, s) {
        final fg = !s.enabled ? c.label.withValues(alpha: 0.3) : (selected ? (tint ?? c.accent) : (tint ?? c.label));
        final bg = selected
            ? c.accentTint
            : s.pressed
            ? c.pressed
            : s.hovered
            ? c.hover
            : Colors.transparent;
        return AnimatedContainer(
          duration: MMMotion.quick,
          height: size.height,
          constraints: BoxConstraints(minWidth: size.width),
          padding: EdgeInsets.symmetric(horizontal: label != null ? 10 : (count > 0 ? MMSpacing.xs : 0)),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(MMRadii.capsuleButton),
            border: s.focused ? Border.all(color: c.accent, width: 2) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, size: 16, color: fg),
              if (icon != null && label != null) const SizedBox(width: 6),
              if (label != null) Text(label!, style: t.callout.copyWith(color: fg)),
              if (count > 0) ...[
                const SizedBox(width: MMSpacing.xxs),
                Text(
                  '$count',
                  style: t.footnote.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: fg,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Thin separator between buttons inside one [MMToolbarGroup].
class MMToolbarDivider extends StatelessWidget {
  const MMToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: context.mmColors.separator,
    );
  }
}

/// Search field in a glass capsule, sized for the toolbar.
class MMToolbarSearchField extends StatelessWidget {
  const MMToolbarSearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.width = 200,
  });

  final String placeholder;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: MMGlass(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: MMSearchField(
          placeholder: placeholder,
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          height: MMSizes.toolbarGroupHeight - 1,
          filled: false,
        ),
      ),
    );
  }
}
