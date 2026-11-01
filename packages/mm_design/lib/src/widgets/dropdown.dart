import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.cascading = false,
    this.menuController,
    this.plainIcon = false,
  });

  final VoidCallback? onOpened, onClosed;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final String? tooltip;
  final bool enabled;
  final bool cascading;

  /// Use the standard icon button without a selected tint while the menu is open.
  final bool plainIcon;
  final MenuController? menuController;
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
    if (widget.cascading) {
      return MMDropdownMenuButton<T>(
        icon: (widget.icon is Icon ? (widget.icon as Icon).icon : null) ?? MMIcons.more,
        tooltip: widget.tooltip ?? '',
        enabled: widget.enabled,
        width: widget.width,
        controller: widget.menuController,
        itemBuilder: widget.itemBuilder,
        onSelected: widget.onSelected,
        onOpened: () {
          _activity?.onChanged(this, true);
          widget.onOpened?.call();
        },
        onClosed: _closed,
      );
    }
    // A dock keeps its geometry when input switches between pointer and touch.
    final button = (MMThumbDockScope.of(context) || context.mmTouch || context.mmTouchPlatform)
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
        icon: widget.plainIcon || context.mmTouchPlatform ? null : widget.icon,
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
        borderRadius: context.mmTouchPlatform ? BorderRadius.circular(16) : null,
        child: widget.plainIcon
            ? Builder(
                builder: (context) => MMIconButton(
                  iconWidget: widget.icon ?? const Icon(MMIcons.more),
                  tooltip: widget.tooltip ?? '',
                  onPressed: widget.enabled
                      ? () => context.findAncestorStateOfType<PopupMenuButtonState<T>>()!.showButtonMenu()
                      : null,
                ),
              )
            : context.mmTouchPlatform
            ? Semantics(
                button: true,
                enabled: widget.enabled,
                // An icon button in a thumb dock keeps the dock's button geometry.
                child: SizedBox.fromSize(
                  size: MMThumbDockScope.of(context) && widget.child == null ? button : null,
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
                            child: widget.icon ?? const Icon(MMIcons.more),
                          ),
                        ),
                  ),
                ),
              )
            : widget.child,
      ),
    );
  }
}

/// Non-interactive section title; excluded from keyboard command navigation.
class MMDropdownHeader<T> extends PopupMenuEntry<T> {
  const MMDropdownHeader(this.label, {super.key});
  final String label;
  @override
  double get height => MMSizes.dropdownRowHeight;
  @override
  bool represents(T? value) => false;
  @override
  State<MMDropdownHeader<T>> createState() => _MMDropdownHeaderState<T>();
}

class _MMDropdownHeaderState<T> extends State<MMDropdownHeader<T>> {
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.height),
      child: Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s, vertical: MMSpacing.xs),
          child: Text(
            widget.label,
            style: context.mmText.footnote.copyWith(
              color: context.mmColors.secondaryLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
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
    this.icon,
  });

  final IconData? icon;

  /// Shared content for both popup routes and cascading menus.
  Widget? get menuChild => icon == null
      ? child
      : Row(
          children: [
            Icon(icon, size: MMSizes.dropdownIcon),
            const SizedBox(width: MMSpacing.s),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );

  @override
  PopupMenuItemState<T, MMDropdownItem<T>> createState() => _MMDropdownItemState<T>();
}

class _MMDropdownItemState<T> extends PopupMenuItemState<T, MMDropdownItem<T>> {
  @override
  Widget? buildChild() => widget.menuChild;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    borderRadius: BorderRadius.circular(MMRadii.row),
    clipBehavior: Clip.antiAlias,
    child: IconTheme.merge(
      data: IconThemeData(
        size: MMSizes.dropdownIcon,
        color: widget.enabled ? context.mmColors.label : context.mmColors.secondaryLabel,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: context.mmTouch || context.mmTouchPlatform ? MMSizes.touchTarget : widget.height,
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
    this.onOpened,
    this.onClosed,
    this.enabled = true,
    this.width = MMSizes.dropdownWidth,
    this.controller,
  });
  final IconData icon;
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final ValueChanged<T>? onSelected;
  final VoidCallback? onOpened, onClosed;
  final bool enabled;
  final double width;
  final MenuController? controller;
  @override
  State<MMDropdownMenuButton<T>> createState() => _MMDropdownMenuButtonState<T>();
}

class _MMDropdownMenuButtonState<T> extends State<MMDropdownMenuButton<T>> {
  final _ownedController = MenuController();
  final _buttonFocus = FocusNode();
  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  MenuController get _controller => widget.controller ?? _ownedController;
  void _select(T value) {
    _controller.close();
    widget.onSelected?.call(value);
  }

  @override
  Widget build(BuildContext context) => _MMDropdownMenuScope<T>(
    select: _select,
    child: CallbackShortcuts(
      bindings: {if (_controller.isOpen) const SingleActivator(LogicalKeyboardKey.escape): _controller.close},
      child: MenuAnchor(
        controller: _controller,
        childFocusNode: _buttonFocus,
        consumeOutsideTap: true,
        style: _dropdownMenuStyle(context),
        onOpen: () {
          setState(() {});
          _buttonFocus.requestFocus();
          widget.onOpened?.call();
        },
        onClose: () {
          if (mounted) setState(() {});
          widget.onClosed?.call();
        },
        menuChildren: _dropdownChildren(context, widget.itemBuilder(context), widget.width, _select),
        builder: (_, controller, _) => Focus(
          focusNode: _buttonFocus,
          child: MMIconButton(
            icon: widget.icon,
            tooltip: widget.tooltip,
            selected: controller.isOpen,
            onPressed: !widget.enabled ? null : () => controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
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
    shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: .18)),
    elevation: WidgetStatePropertyAll(MMFlatSurface.of(context) ? 0 : 6),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
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
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled) ? context.mmColors.secondaryLabel : context.mmColors.label,
  ),
  overlayColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.pressed)
        ? context.mmColors.pressed
        : states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)
        ? context.mmColors.hover
        : Colors.transparent,
  ),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
  minimumSize: WidgetStatePropertyAll(Size(0, context.mmTouch ? MMSizes.touchTarget : 32)),
  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(MMRadii.row))),
);

List<Widget> _dropdownChildren<T>(
  BuildContext context,
  List<PopupMenuEntry<T>> entries,
  double width,
  ValueChanged<T> select,
) => [
  for (final entry in entries)
    SizedBox(
      width: width - 12,
      child: switch (entry) {
        PopupMenuItem<T>(:final child) when child is PopupMenuEntry => child,
        PopupMenuItem<T>() => MenuItemButton(
          key: entry.key,
          style: _dropdownMenuItemStyle(context),
          onPressed: entry.enabled && entry.value != null ? () => select(entry.value as T) : null,
          child: entry is MMDropdownItem<T> ? entry.menuChild : entry.child,
        ),
        PopupMenuDivider() => Divider(height: 12, thickness: .5, color: context.mmColors.separator),
        _ => entry,
      },
    ),
];

/// One menu tree owns every level, including focus, hover and edge placement.
class MMDropdownSubmenu<T> extends PopupMenuEntry<T> {
  const MMDropdownSubmenu({
    super.key,
    required this.label,
    required this.entries,
    this.icon,
    this.width = 200,
    this.enabled = true,
    this.selected = false,
  }) : itemBuilder = null;
  const MMDropdownSubmenu.items({
    super.key,
    required this.label,
    required this.itemBuilder,
    this.icon,
    this.width = 200,
    this.enabled = true,
    this.selected = false,
  }) : entries = const [];
  final String label;
  final IconData? icon;
  final double width;
  final bool enabled, selected;
  final List<({T value, String label, bool selected})> entries;
  final PopupMenuItemBuilder<T>? itemBuilder;
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
    final entries =
        widget.itemBuilder?.call(context) ??
        [
          for (final entry in widget.entries)
            MMDropdownItem<T>(
              value: entry.value,
              child: Row(
                children: [
                  Expanded(child: Text(entry.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 16,
                    child: entry.selected ? Icon(MMIcons.check, size: 14, color: context.mmColors.accent) : null,
                  ),
                ],
              ),
            ),
        ];
    return SubmenuButton(
      style: _dropdownMenuItemStyle(context),
      menuStyle: _dropdownMenuStyle(context),
      submenuIcon: const WidgetStatePropertyAll(Icon(MMIcons.chevronRight, size: 12)),
      menuChildren: widget.enabled ? _dropdownChildren(context, entries, widget.width, scope.select) : const [],
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: MMSizes.dropdownIcon, color: widget.selected ? context.mmColors.accent : null),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
