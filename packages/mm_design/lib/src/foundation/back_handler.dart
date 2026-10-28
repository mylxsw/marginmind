import 'package:flutter/widgets.dart';

/// Handles the system back action (Android's back button or gesture) while
/// its page is the current route: [onBack] returns whether it handled it.
/// Handlers mounted later are asked first, so a menu closes before its page
/// closes a sheet, and the page before the app navigates up. A route above
/// the page (a sheet or dialog) is popped by the navigator before any
/// handler is asked.
class MMBackHandler extends StatefulWidget {
  const MMBackHandler({super.key, required this.onBack, required this.child});

  final bool Function() onBack;
  final Widget child;

  @override
  State<MMBackHandler> createState() => _MMBackHandlerState();
}

class _MMBackHandlerState extends State<MMBackHandler> {
  @override
  void initState() {
    super.initState();
    _BackDispatcher.instance.add(this);
  }

  @override
  void dispose() {
    _BackDispatcher.instance.remove(this);
    super.dispose();
  }

  bool _handle() {
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return false;
    return widget.onBack();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One binding observer for all handlers: the binding asks observers in the
/// order they were added, so the navigator's (added by the app) goes first
/// and the handlers are then asked newest first.
class _BackDispatcher with WidgetsBindingObserver {
  _BackDispatcher._();

  static final instance = _BackDispatcher._();

  final _handlers = <_MMBackHandlerState>[];

  void add(_MMBackHandlerState handler) {
    if (_handlers.isEmpty) WidgetsBinding.instance.addObserver(this);
    _handlers.add(handler);
  }

  void remove(_MMBackHandlerState handler) {
    _handlers.remove(handler);
    if (_handlers.isEmpty) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  Future<bool> didPopRoute() async {
    for (final handler in _handlers.reversed.toList()) {
      if (handler._handle()) return true;
    }
    return false;
  }
}
