import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Handles the system back action (Android's back button or gesture) while
/// its page is the current route: [onBack] returns whether it handled it.
/// Handlers mounted later are asked first, so a menu closes before its page
/// closes a sheet, and the page before the app navigates up. A route above
/// the page (a sheet or dialog) is popped by the navigator instead. Needs an
/// [MMBackScope] on the page.
class MMBackHandler extends StatefulWidget {
  const MMBackHandler({super.key, required this.onBack, required this.child});

  final bool Function() onBack;
  final Widget child;

  static final _handlers = <_MMBackHandlerState>[];

  /// Asks the handlers, newest first; whether one handled the action.
  static bool dispatch() {
    for (final handler in _handlers.reversed.toList()) {
      if (handler._handle()) return true;
    }
    return false;
  }

  @override
  State<MMBackHandler> createState() => _MMBackHandlerState();
}

class _MMBackHandlerState extends State<MMBackHandler> {
  @override
  void initState() {
    super.initState();
    MMBackHandler._handlers.add(this);
  }

  @override
  void dispose() {
    MMBackHandler._handlers.remove(this);
    super.dispose();
  }

  bool _handle() {
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return false;
    return widget.onBack();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Claims the system back action for the page it is on and passes it to the
/// [MMBackHandler]s; when none handles it the app leaves, as the system
/// would. Android only sends back to an app that says it can pop, so the
/// claim must be made up front.
class MMBackScope extends StatelessWidget {
  const MMBackScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !MMBackHandler.dispatch()) SystemNavigator.pop();
    },
    child: child,
  );
}
