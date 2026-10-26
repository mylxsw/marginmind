import 'package:flutter/material.dart';

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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: chrome?.onDragStart == null ? null : (_) => chrome!.onDragStart!(),
      onDoubleTap: chrome?.onTitleDoubleTap,
      child: SizedBox(
        height: MMSizes.toolbarHeight,
        child: AnimatedPadding(
          duration: MMMotion.layout,
          curve: MMMotion.layoutCurve,
          padding: EdgeInsets.only(left: 20 + (chrome?.toolbarLeadingInset ?? 0), right: 12),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Expanded(
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
              const SizedBox(width: 16),
              for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10), actions[i]],
            ],
          ),
        ),
      ),
    );
  }
}

/// A glass capsule that groups related toolbar buttons.
class MMToolbarGroup extends StatelessWidget {
  const MMToolbarGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MMGlass(
      padding: const EdgeInsets.all(3),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Toolbar button (34×30, radius 15). Selected uses the accent tint, never a
/// solid fill.
class MMToolbarButton extends StatelessWidget {
  const MMToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.label,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  /// Optional text shown next to the icon (e.g. a sort pop-up).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return MMInteractive(
      onTap: onPressed,
      selected: selected,
      tooltip: tooltip,
      semanticLabel: tooltip,
      builder: (context, s) {
        final fg = !s.enabled ? c.label.withValues(alpha: 0.3) : (selected ? c.accent : c.label);
        final bg = selected
            ? c.accentTint
            : s.pressed
            ? c.pressed
            : s.hovered
            ? c.hover
            : Colors.transparent;
        return AnimatedContainer(
          duration: MMMotion.quick,
          height: MMSizes.toolbarButton.height,
          constraints: BoxConstraints(minWidth: MMSizes.toolbarButton.width),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(MMRadii.capsuleButton),
            border: s.focused ? Border.all(color: c.accent, width: 2) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              if (label != null) ...[const SizedBox(width: 6), Text(label!, style: t.callout.copyWith(color: fg))],
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
