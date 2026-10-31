import 'package:flutter/material.dart';

/// Workspace material, captured by routes and overlay menus.
class MMFlatSurface extends InheritedTheme {
  const MMFlatSurface({super.key, this.enabled = true, required super.child});

  /// A local opt-out for floating controls within an otherwise flat workspace.
  final bool enabled;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MMFlatSurface>()?.enabled ?? false;

  @override
  bool updateShouldNotify(MMFlatSurface oldWidget) => oldWidget.enabled != enabled;

  @override
  Widget wrap(BuildContext context, Widget child) => MMFlatSurface(enabled: enabled, child: child);
}
