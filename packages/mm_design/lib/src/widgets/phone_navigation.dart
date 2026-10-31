import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;

import '../foundation/appearance.dart';
import '../foundation/interactive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/phone_navigation.dart';
import 'context_menu_region.dart';
import 'sidebar.dart';

/// Full-height phone drawer with edge opening and direct horizontal dragging.
/// The host gates it to phone + compact; tablets keep their existing drawer.
class MMPhoneDrawer extends StatefulWidget {
  const MMPhoneDrawer({
    super.key,
    required this.open,
    required this.onChanged,
    required this.dismissLabel,
    required this.drawer,
    required this.child,
  });

  final bool open;
  final ValueChanged<bool> onChanged;
  final String dismissLabel;
  final Widget drawer;
  final Widget child;

  @override
  State<MMPhoneDrawer> createState() => _MMPhoneDrawerState();
}

class _MMPhoneDrawerState extends State<MMPhoneDrawer> with SingleTickerProviderStateMixin {
  late final _position = AnimationController(vsync: this, value: widget.open ? 1 : 0);
  double _drag = 0;

  @override
  void didUpdateWidget(MMPhoneDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) _settle(widget.open);
  }

  void _settle(bool open) {
    _position.animateTo(
      open ? 1 : 0,
      duration: MMAppearance.duration(context, MMPhoneNavigation.drawerDuration),
      curve: MMPhoneNavigation.drawerCurve,
    );
  }

  void _end(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity.abs() >= MMPhoneNavigation.swipeVelocity
        ? velocity > 0
        : _drag.abs() >= MMPhoneNavigation.swipeDistance
        ? _drag > 0
        : widget.open;
    _settle(open);
    if (open != widget.open) widget.onChanged(open);
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(MMSizes.phoneDrawerWidth, math.max(0.0, constraints.maxWidth - MMSpacing.xxxl));
      void start(DragStartDetails _) {
        _position.stop();
        _drag = 0;
      }

      void update(DragUpdateDetails details) {
        _drag += details.primaryDelta ?? 0;
        if (width > 0) _position.value += (details.primaryDelta ?? 0) / width;
      }

      return AnimatedBuilder(
        animation: _position,
        builder: (context, _) {
          final visible = _position.value > 0 || widget.open;
          return Stack(
            fit: StackFit.expand,
            children: [
              ExcludeFocus(
                excluding: visible,
                child: ExcludeSemantics(excluding: visible, child: widget.child),
              ),
              if (visible)
                Opacity(
                  opacity: _position.value,
                  child: ModalBarrier(
                    key: const ValueKey('phone-drawer-scrim'),
                    color: context.mmColors.scrim,
                    semanticsLabel: widget.dismissLabel,
                    onDismiss: () => widget.onChanged(false),
                  ),
                ),
              if (!widget.open)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: MMPhoneNavigation.edgeWidth,
                  child: GestureDetector(
                    key: const ValueKey('phone-drawer-edge'),
                    supportedDevices: const {PointerDeviceKind.touch},
                    behavior: HitTestBehavior.translucent,
                    excludeFromSemantics: true,
                    onHorizontalDragStart: start,
                    onHorizontalDragUpdate: update,
                    onHorizontalDragEnd: _end,
                    onHorizontalDragCancel: () => _settle(widget.open),
                  ),
                ),
              Positioned(
                left: width * (_position.value - 1),
                top: 0,
                bottom: 0,
                width: width,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: ExcludeFocus(
                    excluding: !widget.open,
                    child: ExcludeSemantics(
                      excluding: !widget.open,
                      child: GestureDetector(
                        key: const ValueKey('phone-drawer-panel'),
                        onHorizontalDragStart: start,
                        onHorizontalDragUpdate: update,
                        onHorizontalDragEnd: _end,
                        onHorizontalDragCancel: () => _settle(widget.open),
                        child: widget.drawer,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// A phone navigation action whose label and touch area grow with Dynamic Type.
class MMPhoneNavigationAction extends StatelessWidget {
  const MMPhoneNavigationAction({super.key, required this.label, required this.onPressed, this.icon, this.color});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => MMInteractive(
    semanticLabel: label,
    onTap: onPressed,
    builder: (context, state) => Container(
      constraints: const BoxConstraints(minHeight: MMSizes.touchTarget),
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs, vertical: MMSpacing.s),
      decoration: BoxDecoration(
        color: state.pressed ? context.mmColors.pressed : null,
        border: state.focused ? Border.all(color: context.mmColors.accent) : null,
        borderRadius: BorderRadius.circular(MMRadii.row),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: MMPhoneNavigation.iconSize, color: color ?? context.mmColors.secondaryLabel),
            const SizedBox(width: MMSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.mmText.title3.copyWith(color: color ?? context.mmColors.secondaryLabel),
            ),
          ),
        ],
      ),
    ),
  );
}

/// iOS grouped rows without secondary copy. Counts remain plain text.
class MMPhoneNavigationGroup extends StatelessWidget {
  const MMPhoneNavigationGroup({super.key, required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: MMSpacing.s),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(header: true, child: Text(title, style: context.mmText.headline)),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: MMSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(MMPhoneNavigation.groupRadius),
          child: ColoredBox(
            color: context.mmColors.card,
            child: Column(
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: MMSizes.touchTarget + MMSpacing.xs),
                      child: Divider(
                        height: MMSizes.hairline,
                        thickness: MMSizes.hairline,
                        color: context.mmColors.separator,
                      ),
                    ),
                  child,
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class MMPhoneNavigationRow extends StatelessWidget {
  const MMPhoneNavigationRow({super.key, required this.item, this.learningCount = false});

  final MMSidebarItem item;
  final bool learningCount;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final trailing = item.trailing;
    final row = MMInteractive(
      semanticLabel: item.label,
      selected: item.selected,
      onTap: item.onTap,
      builder: (context, state) => Container(
        constraints: const BoxConstraints(minHeight: MMPhoneNavigation.rowHeight),
        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.xs),
        decoration: BoxDecoration(
          color: state.pressed
              ? c.pressed
              : item.selected
              ? c.accentTint
              : null,
          border: state.focused ? Border.all(color: c.accent) : null,
        ),
        child: Row(
          children: [
            item.leading ?? Icon(item.icon, size: MMPhoneNavigation.iconSize, color: c.accent),
            const SizedBox(width: MMSpacing.m),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.mmText.body.copyWith(
                  fontSize: MMPhoneNavigation.rowTextSize,
                  fontWeight: item.selected ? FontWeight.w600 : null,
                  color: item.labelColor,
                ),
              ),
            ),
            if (trailing is MMBadge)
              Text(
                trailing.value,
                style: context.mmText.headline.copyWith(color: learningCount ? c.caution : c.secondaryLabel),
              )
            else
              ?trailing,
          ],
        ),
      ),
    );
    return item.onContextMenu == null
        ? row
        : MMContextMenuRegion(onSecondaryTapUp: (details) => item.onContextMenu!(details.globalPosition), child: row);
  }
}

/// Compact review progress: segments carry the position, with one spoken value.
class MMPhoneReviewProgress extends StatelessWidget {
  const MMPhoneReviewProgress({super.key, required this.total, required this.completed, required this.label});
  final int total;
  final int completed;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: '${total == 0 ? 0 : (completed / total * 100).round()}%',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final segments = math.min(total, math.max(1, (constraints.maxWidth / MMSpacing.s).floor()));
        return SizedBox(
          height: MMPhoneNavigation.progressHeight,
          child: Row(
            children: [
              for (var i = 0; i < segments; i++) ...[
                if (i > 0) const SizedBox(width: MMSpacing.xs),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i * total / segments <= completed ? context.mmColors.accent : context.mmColors.fill,
                      borderRadius: BorderRadius.circular(MMRadii.capsule),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
