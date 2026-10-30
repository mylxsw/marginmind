import 'package:flutter/material.dart';

/// Workspace material, captured by routes and overlay menus.
class MMFlatSurface extends InheritedTheme {
  const MMFlatSurface({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MMFlatSurface>() != null;

  @override
  bool updateShouldNotify(MMFlatSurface oldWidget) => false;

  @override
  Widget wrap(BuildContext context, Widget child) => MMFlatSurface(child: child);
}
