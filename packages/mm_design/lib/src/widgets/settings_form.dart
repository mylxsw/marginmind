import 'package:flutter/material.dart';

import '../foundation/interactive.dart';
import '../foundation/adaptive.dart';
import '../icons/mm_icons.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'menu.dart';
import 'control_frame.dart';

/// Title above a settings group, like macOS System Settings.
class MMSettingsHeader extends StatelessWidget {
  const MMSettingsHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(MMSpacing.xs, 22, MMSpacing.xs, 7),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: context.mmText.subheadline.copyWith(fontWeight: FontWeight.w600, color: context.mmColors.secondaryLabel),
      ),
    ),
  );
}

/// An inset grouped card: a quaternary-fill panel (a light wash in dark
/// appearance) whose rows are separated by 1pt lines that start at the
/// row's text. No border or shadow: it sits on the window background.
class MMSettingsGroup extends StatelessWidget {
  const MMSettingsGroup({super.key, required this.children, this.footer});

  final List<Widget> children;

  /// A strip below the rows (links such as “Remove Service”).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final separator = Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Container(height: 1, color: c.separator),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: .05) : c.quaternaryFill,
        borderRadius: BorderRadius.circular(MMRadii.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[if (i > 0) separator, child],
          if (footer != null) ...[
            if (children.isNotEmpty) separator,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: MMSpacing.xs),
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

/// A 40pt row: [label] on the left, the value or control right-aligned.
class MMSettingsRow extends StatelessWidget {
  const MMSettingsRow({super.key, this.label, this.leading, required this.trailing, this.onTap, this.height = 40});

  final String? label;

  /// Replaces [label] when the left side is more than a word.
  final Widget? leading;
  final Widget trailing;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final row = LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(13) > 15;
        final stacked = context.mmTouchPlatform && constraints.maxWidth < (largeText ? 480 : 300);
        if (stacked && (leading != null || label != null)) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: MMSpacing.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                leading ?? Text(label!, style: context.mmText.body),
                const SizedBox(height: MMSpacing.xs),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
            ),
          );
        }
        return SizedBox(
          height: context.mmTouchPlatform && height < 52 ? 52 : height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                if (leading != null)
                  Expanded(child: leading!)
                else if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(right: MMSpacing.m),
                    child: Text(
                      label!,
                      maxLines: 1,
                      style: context.mmText.body.copyWith(color: context.mmColors.label),
                    ),
                  ),
                if (leading == null)
                  Expanded(
                    child: Align(alignment: Alignment.centerRight, child: trailing),
                  )
                else
                  trailing,
              ],
            ),
          ),
        );
      },
    );
    if (onTap == null) return row;
    return MMInteractive(onTap: onTap, semanticLabel: label, builder: (context, s) => row);
  }
}

/// A macOS pop-up button: the chosen value and up-down chevrons; the menu
/// checks the current choice. Value choices use text and a selection mark,
/// without a repeated command icon.
class MMPopUpButton<T> extends StatelessWidget {
  const MMPopUpButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.semanticLabel,
    this.placeholder = '—',
    this.maxWidth = 260,
  });

  final T? value;

  /// Choices with their labels, in menu order.
  final List<(T, String)> items;
  final ValueChanged<T>? onChanged;
  final String semanticLabel;

  /// Shown when [value] is not among [items].
  final String placeholder;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final label = items.where((e) => e.$1 == value).map((e) => e.$2).firstOrNull ?? placeholder;
    final enabled = onChanged != null && items.isNotEmpty;
    return MMInteractive(
      onTap: enabled
          ? () {
              final box = context.findRenderObject()! as RenderBox;
              showMMMenu(
                context,
                position: box.localToGlobal(Offset(0, box.size.height + 2)),
                minWidth: box.size.width,
                entries: [for (final (v, text) in items) MMMenuItem(text, () => onChanged!(v), checked: v == value)],
              );
            }
          : null,
      semanticLabel: semanticLabel,
      semanticValue: label,
      builder: (context, s) => MMControlFrame(
        child: AnimatedContainer(
          duration: MMMotion.quick,
          constraints: BoxConstraints(maxWidth: maxWidth),
          height: context.mmTouchPlatform ? MMSizes.tabletControlVisual : 22,
          padding: const EdgeInsets.only(left: MMSpacing.s, right: MMSpacing.xs),
          decoration: BoxDecoration(
            color: s.hovered ? c.fill : c.quaternaryFill,
            borderRadius: BorderRadius.circular(context.mmTouchPlatform ? MMRadii.field : 6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(color: enabled ? c.label : c.secondaryLabel),
                ),
              ),
              const SizedBox(width: MMSpacing.xs),
              Icon(MMIcons.chevronUpDown, size: context.mmTouchPlatform ? 13 : 11, color: c.icon),
            ],
          ),
        ),
      ),
    );
  }
}
