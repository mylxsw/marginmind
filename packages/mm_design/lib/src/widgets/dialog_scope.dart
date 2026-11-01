import 'package:flutter/widgets.dart';

/// Shared control treatment inside modal forms, independent of toolbar controls.
class MMDialogScope extends InheritedWidget {
  const MMDialogScope({super.key, required super.child});

  static bool contains(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MMDialogScope>() != null;

  @override
  bool updateShouldNotify(MMDialogScope oldWidget) => false;
}
