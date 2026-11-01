import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'adaptive.dart';

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
///
/// A [semanticLabel] names the control on its own: the content's text is left
/// out of the accessibility tree so VoiceOver reads the name once. Without a
/// label the content's text becomes the name; leave it out when the content
/// holds other controls (a star or close button) that must stay reachable.
class MMInteractive extends StatefulWidget {
  const MMInteractive({
    super.key,
    required this.builder,
    this.onTap,
    this.onTapDown,
    this.onDoubleTap,
    this.immediateTap = false,
    this.onSecondaryTap,
    this.selected = false,
    this.enabled = true,
    this.semanticLabel,
    this.semanticValue,
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

  /// Select immediately on the first tap, then activate [onDoubleTap] on the
  /// second. Use for selection surfaces where a double tap builds on selection.
  final bool immediateTap;
  final VoidCallback? onSecondaryTap;
  final bool selected;
  final bool enabled;
  final String? semanticLabel;

  /// Read after the name, e.g. a count or a page number.
  final String? semanticValue;
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

    final content = widget.semanticLabel == null
        ? widget.builder(context, state)
        : ExcludeSemantics(child: widget.builder(context, state));
    Widget child = widget.immediateTap
        ? RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _ImmediateTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<_ImmediateTapGestureRecognizer>(
                _ImmediateTapGestureRecognizer.new,
                (tap) {
                  if (!_enabled || (tap.selected && !widget.selected)) tap.resetSequence();
                  tap
                    ..doubleClickInterval = MMInput.of(context).doubleClickInterval
                    ..selected = widget.selected
                    ..onTapDown = _enabled
                        ? (_) {
                            _setPressed(true);
                            widget.onTapDown?.call();
                          }
                        : null
                    ..onTapUp = _enabled ? (_) => _setPressed(false) : null
                    ..onTapCancel = _enabled ? () => _setPressed(false) : null
                    ..onTap = _enabled ? widget.onTap : null
                    ..onDoubleTap = _enabled ? widget.onDoubleTap : null
                    ..onSecondaryTap = widget.onSecondaryTap;
                },
              ),
            },
            child: content,
          )
        : GestureDetector(
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
            // Only the content: the gesture and focus actions stay on the node.
            child: content,
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
      value: widget.semanticValue,
      onTap: widget.immediateTap && _enabled ? widget.onTap ?? widget.onDoubleTap : null,
      child: child,
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, excludeFromSemantics: widget.semanticLabel != null, child: child);
    }
    return child;
  }
}

/// A normal tap still competes with child controls, drags and long presses.
/// Only double-tap detection changes: it never holds the first tap's arena.
class _ImmediateTapGestureRecognizer extends TapGestureRecognizer {
  VoidCallback? onDoubleTap;
  Duration doubleClickInterval = kDoubleTapTimeout;
  bool selected = false;
  PointerDownEvent? _lastTap;
  Timer? _tapTimeout;
  Timer? _minTapTime;
  bool _doubleTap = false;

  void resetSequence() {
    _doubleTap = false;
    _clearLastTap();
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final last = _lastTap;
    _doubleTap =
        onDoubleTap != null &&
        last != null &&
        _minTapTime?.isActive == false &&
        event.kind == last.kind &&
        event.buttons == kPrimaryButton &&
        (event.position - last.position).distance <= kDoubleTapSlop;
    _clearLastTap();
    super.addAllowedPointer(event);
  }

  void _clearLastTap() {
    _lastTap = null;
    _tapTimeout?.cancel();
    _minTapTime?.cancel();
  }

  @override
  void handleTapUp({required PointerDownEvent down, required PointerUpEvent up}) {
    if (_doubleTap && onDoubleTap != null) {
      _doubleTap = false;
      onTapUp?.call(TapUpDetails(globalPosition: up.position, localPosition: up.localPosition, kind: up.kind));
      invokeCallback<void>('onDoubleTap', onDoubleTap!);
      return;
    }
    if (down.buttons == kPrimaryButton && onDoubleTap != null) {
      _lastTap = down;
      _minTapTime = Timer(kDoubleTapMinTime, () {});
      _tapTimeout = Timer(
        down.kind == PointerDeviceKind.mouse ? doubleClickInterval : kDoubleTapTimeout,
        _clearLastTap,
      );
    }
    super.handleTapUp(down: down, up: up);
  }

  @override
  void handleTapCancel({required PointerDownEvent down, PointerCancelEvent? cancel, required String reason}) {
    _doubleTap = false;
    _clearLastTap();
    super.handleTapCancel(down: down, cancel: cancel, reason: reason);
  }

  @override
  void dispose() {
    _clearLastTap();
    super.dispose();
  }
}
