import 'package:flutter/material.dart';

import '../foundation/appearance.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';

@immutable
class MMTab {
  const MMTab({required this.icon, required this.label, this.enabled = true});

  final IconData icon;
  final String label;
  final bool enabled;
}

/// A phone's bottom navigation: one equal-width button per tab above the
/// home indicator. Android highlights the selected icon with a pill, iOS
/// tints it; both keep the design system's colors and type.
class MMTabBar extends StatelessWidget {
  const MMTabBar({super.key, required this.tabs, required this.selected, required this.onSelected});

  final List<MMTab> tabs;

  /// Index into [tabs]; null when none is current.
  final int? selected;
  final ValueChanged<int> onSelected;

  /// Height of the bar in [context], home indicator inset included.
  static double heightOf(BuildContext context) =>
      (_android(context) ? MMSizes.tabBarAndroid : MMSizes.tabBar) + MediaQuery.paddingOf(context).bottom;

  static bool _android(BuildContext context) => Theme.of(context).platform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final android = _android(context);
    final safe = MediaQuery.paddingOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: android ? c.sidebarOpaque : c.glassOpaque,
        border: android ? null : Border(top: BorderSide(color: c.separator, width: 0.5)),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: safe.left, right: safe.right, bottom: safe.bottom),
        child: SizedBox(
          height: android ? MMSizes.tabBarAndroid : MMSizes.tabBar,
          child: Row(
            children: [
              for (final (i, tab) in tabs.indexed)
                Expanded(
                  child: _TabButton(
                    key: ValueKey('mm-tab-$i'),
                    tab: tab,
                    selected: i == selected,
                    android: android,
                    onTap: tab.enabled ? () => onSelected(i) : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({super.key, required this.tab, required this.selected, required this.android, this.onTap});

  final MMTab tab;
  final bool selected;
  final bool android;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return MMInteractive(
      selected: selected,
      onTap: onTap,
      semanticLabel: tab.label,
      builder: (context, s) {
        final fg = !s.enabled
            ? c.secondaryLabel.withValues(alpha: 0.5)
            : selected
            ? (android ? c.label : c.accent)
            : c.secondaryLabel;
        final icon = Icon(tab.icon, size: android ? 20 : 22, color: selected && android ? c.accent : fg);
        return Opacity(
          opacity: s.pressed ? 0.6 : 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (android)
                AnimatedContainer(
                  duration: MMAppearance.duration(context, MMMotion.standard),
                  width: MMSizes.tabBarPill.width,
                  height: MMSizes.tabBarPill.height,
                  decoration: BoxDecoration(
                    color: selected ? c.accentTint : Colors.transparent,
                    borderRadius: BorderRadius.circular(MMSizes.tabBarPill.height / 2),
                  ),
                  child: icon,
                )
              else
                icon,
              SizedBox(height: android ? 4 : 2),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (android ? t.callout : t.footnote).copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
