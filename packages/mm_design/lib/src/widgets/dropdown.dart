import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../icons/mm_icons.dart';
import 'buttons.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import 'flat_surface.dart';
import 'control_frame.dart';

/// Reports menu lifetime to a host that must keep its anchors stationary.
class MMPopupActivity extends InheritedWidget {
  const MMPopupActivity({super.key, required this.onChanged, required super.child});
  final void Function(Object owner, bool open) onChanged;
  static MMPopupActivity? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MMPopupActivity>();
  @override
  bool updateShouldNotify(MMPopupActivity oldWidget) => onChanged != oldWidget.onChanged;
}

/// Shared anchored dropdown for command lists and rich entries.
class MMDropdownButton<T> extends StatefulWidget {
  const MMDropdownButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.tooltip,
    this.enabled = true,
    this.width = MMSizes.dropdownWidth,
    this.icon,
    this.child,
    this.onOpened,
    this.onClosed,
  });

  final VoidCallback? onOpened, onClosed;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final String? tooltip;
  final bool enabled;
  final double width;
  final Widget? icon, child;

  @override
  State<MMDropdownButton<T>> createState() => _MMDropdownButtonState<T>();
}

class _MMDropdownButtonState<T> extends State<MMDropdownButton<T>> {
  bool _open = false;
  MMPopupActivity? _activity;

  @override
  void dispose() {
    _activity?.onChanged(this, false);
    super.dispose();
  }

  void _closed() {
    _activity?.onChanged(this, false);
    if (mounted) setState(() => _open = false);
    widget.onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    _activity = MMPopupActivity.maybeOf(context);
    final c = context.mmColors;
    // A dock keeps its geometry when input switches between pointer and touch.
    final button = (MMThumbDockScope.of(context) || context.mmTouch || context.mmTablet)
        ? context.mmToolbarButton
        : MMSizes.readerToolbarButton;
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) =>
                Theme.of(context).textTheme.labelMedium!
                    .merge(context.mmText.callout)
                    .copyWith(color: states.contains(WidgetState.disabled) ? c.secondaryLabel : c.label),
          ),
        ),
      ),
      child: PopupMenuButton<T>(
        // Show the complete list together. Material's default 300ms size
        // expansion and staggered row fades delay scanning desktop menus.
        routeSettings: const RouteSettings(name: 'mm-dropdown'),
        popUpAnimationStyle: AnimationStyle.noAnimation,
        enabled: widget.enabled,
        tooltip: widget.tooltip,
        position: PopupMenuPosition.under,
        offset: const Offset(0, MMSpacing.xs),
        constraints: BoxConstraints.tightFor(width: widget.width),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: button,
          fixedSize: button,
          padding: EdgeInsets.zero,
          foregroundColor: _open ? c.accent : c.label,
          disabledForegroundColor: c.label.withValues(alpha: .3),
          backgroundColor: _open ? c.accentTint : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MMRadii.row)),
        ),
        iconSize: MMSpacing.l,
        icon: context.mmTablet ? null : widget.icon,
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MMRadii.dropdown),
          side: BorderSide(color: MMFlatSurface.of(context) ? c.border : c.hairline, width: .5),
        ),
        clipBehavior: Clip.antiAlias,
        menuPadding: const EdgeInsets.all(MMSpacing.xs),
        onOpened: () {
          setState(() => _open = true);
          _activity?.onChanged(this, true);
          widget.onOpened?.call();
        },
        onCanceled: _closed,
        onSelected: (value) {
          _closed();
          widget.onSelected?.call(value);
        },
        itemBuilder: widget.itemBuilder,
        borderRadius: context.mmTablet ? BorderRadius.circular(16) : null,
        child: context.mmTablet
            ? Semantics(
                button: true,
                enabled: widget.enabled,
                child: MMControlFrame(
                  child:
                      widget.child ??
                      Container(
                        width: MMSizes.tabletControlVisual,
                        height: MMSizes.tabletControlVisual,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _open ? c.accentTint : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconTheme(
                          data: IconThemeData(
                            size: MMSizes.tabletToolbarIcon,
                            color: !widget.enabled ? c.label.withValues(alpha: .3) : (_open ? c.accent : c.label),
                          ),
                          child: widget.icon ?? const Icon(Icons.more_vert),
                        ),
                      ),
                ),
              )
            : widget.child,
      ),
    );
  }
}

/// Compact command row with rounded hover/focus feedback and touch sizing.
class MMDropdownItem<T> extends PopupMenuItem<T> {
  const MMDropdownItem({
    super.key,
    super.value,
    super.enabled,
    super.height = MMSizes.dropdownRowHeight,
    super.padding = const EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: MMSpacing.xs),
    super.labelTextStyle,
    required super.child,
  });

  @override
  PopupMenuItemState<T, MMDropdownItem<T>> createState() => _MMDropdownItemState<T>();
}

class _MMDropdownItemState<T> extends PopupMenuItemState<T, MMDropdownItem<T>> {
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    borderRadius: BorderRadius.circular(MMRadii.row),
    clipBehavior: Clip.antiAlias,
    child: IconTheme.merge(
      data: IconThemeData(size: MMSizes.dropdownIcon, color: context.mmColors.label),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: context.mmTouch || context.mmTablet ? MMSizes.touchTarget : widget.height,
        ),
        child: super.build(context),
      ),
    ),
  );
}

/// A dropdown whose entries can include cascading submenus. One MenuAnchor
/// owns the entire tree so sibling hover, focus and Escape share a menu root.
class MMDropdownMenuButton<T> extends StatefulWidget {
  const MMDropdownMenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.itemBuilder,
    this.onSelected,
  });
  final IconData icon;
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final ValueChanged<T>? onSelected;
  @override
  State<MMDropdownMenuButton<T>> createState() => _MMDropdownMenuButtonState<T>();
}

class _MMDropdownMenuButtonState<T> extends State<MMDropdownMenuButton<T>> {
  final _controller = MenuController();
  void _select(T value) {
    _controller.close();
    widget.onSelected?.call(value);
  }

  @override
  Widget build(BuildContext context) => _MMDropdownMenuScope<T>(
    select: _select,
    child: MenuAnchor(
      controller: _controller,
      style: _dropdownMenuStyle(context),
      onOpen: () => setState(() {}),
      onClose: () {
        if (mounted) setState(() {});
      },
      menuChildren: [
        for (final entry in widget.itemBuilder(context))
          if (entry is PopupMenuItem<T>)
            MenuItemButton(
              style: _dropdownMenuItemStyle(context),
              onPressed: entry.enabled && entry.value != null ? () => _select(entry.value as T) : null,
              child: entry.child,
            )
          else if (entry is PopupMenuDivider)
            const Divider()
          else
            entry,
      ],
      builder: (_, controller, _) => MMIconButton(
        icon: widget.icon,
        tooltip: widget.tooltip,
        selected: controller.isOpen,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    ),
  );
}

class _MMDropdownMenuScope<T> extends InheritedWidget {
  const _MMDropdownMenuScope({required this.select, required super.child});
  final ValueChanged<T> select;
  @override
  bool updateShouldNotify(_MMDropdownMenuScope<T> oldWidget) => select != oldWidget.select;
}

MenuStyle _dropdownMenuStyle(BuildContext context) {
  final c = context.mmColors;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(c.surface),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(MMSpacing.xs)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MMRadii.dropdown),
        side: BorderSide(color: MMFlatSurface.of(context) ? c.border : c.hairline, width: .5),
      ),
    ),
  );
}

ButtonStyle _dropdownMenuItemStyle(BuildContext context) => ButtonStyle(
  textStyle: WidgetStatePropertyAll(context.mmText.callout),
  foregroundColor: WidgetStatePropertyAll(context.mmColors.label),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: MMSpacing.xs)),
  minimumSize: WidgetStatePropertyAll(Size(0, context.mmTouch ? MMSizes.touchTarget : MMSizes.dropdownRowHeight)),
  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(MMRadii.row))),
);

/// A cascading entry for MMDropdownMenuButton; leaves return through its callback.
class MMDropdownSubmenu<T> extends PopupMenuEntry<T> {
  const MMDropdownSubmenu({super.key, required this.label, required this.entries});
  final String label;
  final List<({T value, String label, bool selected})> entries;
  @override
  double get height => MMSizes.dropdownRowHeight;
  @override
  bool represents(T? value) => false;
  @override
  State<MMDropdownSubmenu<T>> createState() => _MMDropdownSubmenuState<T>();
}

class _MMDropdownSubmenuState<T> extends State<MMDropdownSubmenu<T>> {
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_MMDropdownMenuScope<T>>()!;
    return SubmenuButton(
      style: _dropdownMenuItemStyle(context),
      menuStyle: _dropdownMenuStyle(context),
      submenuIcon: const WidgetStatePropertyAll(Icon(MMIcons.chevronRight, size: MMSizes.dropdownIcon)),
      menuChildren: [
        for (final entry in widget.entries)
          MenuItemButton(
            style: _dropdownMenuItemStyle(context),
            leadingIcon: SizedBox.square(
              dimension: MMSizes.dropdownIcon,
              child: entry.selected
                  ? Icon(MMIcons.check, size: MMSizes.dropdownIcon, color: context.mmColors.accent)
                  : null,
            ),
            onPressed: () => scope.select(entry.value),
            child: Text(entry.label),
          ),
      ],
      child: Text(widget.label),
    );
  }
}
