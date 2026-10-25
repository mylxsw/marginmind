import 'package:flutter/material.dart';

/// Visual state passed to [MMInteractive.builder].
@immutable
class MMInteractionState {
  const MMInteractionState({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.selected = false,
    this.enabled = true,
  });

  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool selected;
  final bool enabled;
}

/// Shared hover / press / keyboard behavior for every clickable component.
///
/// macOS keeps the arrow cursor on buttons, so the default cursor is
/// [SystemMouseCursors.basic]. Enter and Space activate when focused.
class MMInteractive extends StatefulWidget {
  const MMInteractive({
    super.key,
    required this.builder,
    this.onTap,
    this.onTapDown,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.selected = false,
    this.enabled = true,
    this.semanticLabel,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.cursor = SystemMouseCursors.basic,
    this.isButton = true,
  });

  final Widget Function(BuildContext context, MMInteractionState state) builder;
  final VoidCallback? onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSecondaryTap;
  final bool selected;
  final bool enabled;
  final String? semanticLabel;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool canRequestFocus;
  final MouseCursor cursor;
  final bool isButton;

  @override
  State<MMInteractive> createState() => _MMInteractiveState();
}

class _MMInteractiveState extends State<MMInteractive> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled =>
      widget.enabled && (widget.onTap != null || widget.onDoubleTap != null || widget.onTapDown != null);

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final state = MMInteractionState(
      hovered: _hovered && _enabled,
      pressed: _pressed && _enabled,
      focused: _focused,
      selected: widget.selected,
      enabled: _enabled,
    );

    Widget child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled
          ? (_) {
              _setPressed(true);
              widget.onTapDown?.call();
            }
          : null,
      onTapUp: _enabled ? (_) => _setPressed(false) : null,
      onTapCancel: _enabled ? () => _setPressed(false) : null,
      onTap: _enabled ? widget.onTap : null,
      onDoubleTap: _enabled ? widget.onDoubleTap : null,
      onSecondaryTap: widget.onSecondaryTap,
      child: widget.builder(context, state),
    );

    child = FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: _enabled && widget.canRequestFocus,
      mouseCursor: _enabled ? widget.cursor : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            (widget.onTap ?? widget.onDoubleTap)?.call();
            return null;
          },
        ),
      },
      child: child,
    );

    child = Semantics(
      button: widget.isButton,
      selected: widget.selected,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: child,
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, excludeFromSemantics: widget.semanticLabel != null, child: child);
    }
    return child;
  }
}
