import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundation/appearance.dart';
import '../foundation/adaptive.dart';
import '../tokens/phone_glass.dart';
import '../tokens/phone_navigation.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'glass.dart';

@immutable
class MMTab {
  const MMTab({required this.icon, required this.label, this.enabled = true});

  final IconData icon;
  final String label;
  final bool enabled;
}

/// A phone's bottom navigation: a glass capsule floating over the content,
/// inset from the screen sides and clear of the home indicator, with one
/// equal-width button per tab. The selected tab sits on a highlight that
/// slides between tabs; a pressed tab swells slightly. Android gets the
/// same phone material and geometry.
class MMTabBar extends StatelessWidget {
  const MMTabBar({super.key, required this.tabs, required this.selected, required this.onSelected});

  final List<MMTab> tabs;

  /// Index into [tabs]; null when none is current.
  final int? selected;
  final ValueChanged<int> onSelected;

  /// Inset of the highlight inside the capsule.
  static const double _inset = 4;

  /// Space the bar covers above the window's bottom edge in [context]: the
  /// capsule plus its gap to the edge. Content that scrolls beneath the bar
  /// pads its end by this much.
  static double heightOf(BuildContext context) => _height(context) + _bottomGap(context);

  static bool _phone(BuildContext context) =>
      MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact;

  static double _height(BuildContext context) {
    if (!_phone(context)) return _android(context) ? MMSizes.tabBarAndroid : MMSizes.tabBar;
    final style = context.mmText.footnote;
    final labelHeight = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    // Keep all actions reachable at accessibility text sizes.
    return math.max(MMSizes.phoneTabBarHeight, 20 + 2 + _inset * 2 + labelHeight);
  }

  static double _bottomGap(BuildContext context) => math.max(
    MediaQuery.paddingOf(context).bottom,
    _phone(context) ? MMSizes.phoneTabBarBottomInset : MMSizes.tabBarBottomGap,
  );

  static bool _android(BuildContext context) => Theme.of(context).platform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final phone = _phone(context);
    final android = !phone && _android(context);
    final safe = MediaQuery.paddingOf(context);
    final duration = MMAppearance.duration(context, phone ? MMPhoneNavigation.tabDuration : MMMotion.standard);
    final height = _height(context);
    final content = SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - _inset * 2) / math.max(tabs.length, 1);
          final current = selected;
          return Stack(
            children: [
              AnimatedPositioned(
                key: const ValueKey('mm-tab-highlight'),
                duration: duration,
                curve: phone ? MMPhoneNavigation.tabCurve : MMMotion.layoutCurve,
                left: _inset + width * (current ?? 0),
                top: _inset,
                bottom: _inset,
                width: width,
                child: AnimatedOpacity(
                  duration: duration,
                  opacity: current == null ? 0 : 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: phone
                          ? MMPhoneNavigation.lens(Theme.of(context).brightness == Brightness.dark)
                          : c.accentTint,
                      borderRadius: BorderRadius.circular((height - _inset * 2) / 2),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(_inset),
                child: Row(
                  children: [
                    for (final (i, tab) in tabs.indexed)
                      Expanded(
                        child: _TabButton(
                          key: ValueKey('mm-tab-$i'),
                          tab: tab,
                          selected: i == current,
                          android: android,
                          phone: phone,
                          onTap: tab.enabled ? () => onSelected(i) : null,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    final radius = BorderRadius.circular(phone ? MMRadii.phoneTabBar : height / 2);
    return Padding(
      padding: EdgeInsets.only(
        left: safe.left + (phone ? MMSizes.phoneTabBarHorizontalInset : MMSizes.tabBarMargin),
        right: safe.right + (phone ? MMSizes.phoneTabBarHorizontalInset : MMSizes.tabBarMargin),
        bottom: _bottomGap(context),
      ),
      child: phone
          ? MMLiquidGlass(
              key: const ValueKey('mm-tab-bar-glass'),
              phoneStyle: MMPhoneGlass.regular,
              borderRadius: radius,
              child: content,
            )
          : MMGlass(
              key: const ValueKey('mm-tab-bar-glass'),
              borderRadius: radius,
              shadows: [_shadow(context)],
              child: content,
            ),
    );
  }

  /// A soft lift under the floating capsule, lighter than a sheet's.
  static BoxShadow _shadow(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
      blurRadius: 24,
      offset: const Offset(0, 8),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.android,
    required this.phone,
    this.onTap,
  });

  final MMTab tab;
  final bool selected;
  final bool android;
  final bool phone;
  final VoidCallback? onTap;

  /// How much a pressed tab swells.
  static const double pressedScale = 1.08;

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
            ? phone
                  ? MMPhoneNavigation.selectedAccent(c.accent, Theme.of(context).brightness == Brightness.dark)
                  : c.accent
            : c.label;
        return AnimatedScale(
          duration: MMAppearance.duration(context, MMMotion.quick),
          curve: Curves.easeOut,
          scale: s.pressed ? pressedScale : 1,
          child: AnimatedContainer(
            duration: MMAppearance.duration(context, MMMotion.quick),
            decoration: BoxDecoration(
              color: s.pressed ? c.pressed : Colors.transparent,
              borderRadius: BorderRadius.circular(MMRadii.capsule),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tab.icon, size: android ? 22 : 20, color: fg),
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
          ),
        );
      },
    );
  }
}
