import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/native_presentation.dart';

/// A genuine UIKit material, only when the iPhone host registered its factory.
/// Never layer it over another glass surface or put it beneath document text.
class MMNativeGlass extends StatelessWidget {
  const MMNativeGlass({super.key, required this.child, required this.borderRadius, this.padding = EdgeInsets.zero});
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  static bool availableFor(BuildContext context) =>
      MMNativePresentation.available &&
      MMNativeGlassScope.enabledOf(context) &&
      ModalRoute.isCurrentOf(context) != false;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Positioned.fill(
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: UiKitView(
              key: ValueKey(Theme.of(context).brightness),
              viewType: 'marginmind/native_glass',
              creationParamsCodec: const StandardMessageCodec(),
              creationParams: {
                'radius': borderRadius.topLeft.x,
                'dark': Theme.of(context).brightness == Brightness.dark,
              },
            ),
          ),
        ),
      ),
      Padding(padding: padding, child: child),
    ],
  );
}

/// In-tree panels hide their underlying native controls from hybrid
/// composition. Modal Flutter routes use their route's current state instead.
class MMNativeGlassScope extends InheritedWidget {
  const MMNativeGlassScope({super.key, required this.enabled, required super.child});
  final bool enabled;
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MMNativeGlassScope>()?.enabled ?? true;
  @override
  bool updateShouldNotify(MMNativeGlassScope oldWidget) => enabled != oldWidget.enabled;
}
