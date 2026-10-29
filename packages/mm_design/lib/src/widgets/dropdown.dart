import 'package:flutter/material.dart';

import '../foundation/adaptive.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';

/// Shared anchored dropdown, based on the reader's document comparison menu.
/// Rich entries (such as a live slider) use the same surface as command lists.
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
  });

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

  void _closed() {
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final button = context.mmTouch ? context.mmToolbarButton : MMSizes.readerToolbarButton;
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
          foregroundColor: _open ? c.accent : c.icon,
          backgroundColor: _open ? c.accentTint : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MMRadii.row)),
        ),
        iconSize: MMSpacing.l,
        icon: widget.icon,
        color: c.glassOpaque,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MMRadii.dropdown),
          side: BorderSide(color: c.hairline, width: .5),
        ),
        clipBehavior: Clip.antiAlias,
        menuPadding: const EdgeInsets.all(MMSpacing.xs),
        onOpened: () => setState(() => _open = true),
        onCanceled: _closed,
        onSelected: (value) {
          _closed();
          widget.onSelected?.call(value);
        },
        itemBuilder: widget.itemBuilder,
        child: widget.child,
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
        constraints: BoxConstraints(minHeight: context.mmTouch ? MMSizes.touchTarget : widget.height),
        child: super.build(context),
      ),
    ),
  );
}
