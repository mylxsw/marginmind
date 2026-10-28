import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Tracks the latest physical input on hybrid devices without using width as
/// a proxy. iPad starts with visible controls before its first interaction.
class MMInputMode extends StatefulWidget {
  const MMInputMode({super.key, required this.child});
  final Widget child;

  static bool touchOf(BuildContext context) {
    final mode = context.dependOnInheritedWidgetOfExactType<_InputMode>();
    // Pointer-down and menu activation can happen in the same frame.
    if (mode != null) return mode.state._touch ?? mode.touch;
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
  }

  @override
  State<MMInputMode> createState() => _MMInputModeState();
}

class _MMInputModeState extends State<MMInputMode> {
  bool? _touch;

  void _update(PointerEvent event) {
    final touch =
        event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (_touch != touch) setState(() => _touch = touch);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _update,
    onPointerHover: _update,
    child: _InputMode(state: this, touch: _touch ?? MMInputMode.touchOf(context), child: widget.child),
  );
}

class _InputMode extends InheritedWidget {
  const _InputMode({required this.state, required this.touch, required super.child});
  final _MMInputModeState state;
  final bool touch;
  @override
  bool updateShouldNotify(_InputMode oldWidget) => touch != oldWidget.touch;
}
