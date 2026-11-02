import 'package:flutter/widgets.dart';

import '../foundation/adaptive.dart';
import '../tokens/metrics.dart';

/// Compact visible controls retain a full, non-overlapping touch cell.
/// Phone and tablet controls share the same style. Pointer platforms keep their existing layout unchanged.
class MMControlFrame extends StatelessWidget {
  const MMControlFrame({super.key, required this.child, this.minTouchSize = MMSizes.touchTarget});
  final double minTouchSize;
  final Widget child;

  @override
  Widget build(BuildContext context) => !context.mmTouchPlatform
      ? child
      : ConstrainedBox(
          constraints: BoxConstraints(minWidth: minTouchSize, minHeight: minTouchSize),
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        );
}

/// Segmented controls inside a toolbar share its single outer surface.
class MMControlGroupScope extends InheritedWidget {
  const MMControlGroupScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MMControlGroupScope>() != null;

  @override
  bool updateShouldNotify(MMControlGroupScope oldWidget) => false;
}
