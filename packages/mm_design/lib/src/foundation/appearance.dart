import 'package:flutter/widgets.dart';

/// Accessibility preferences that Flutter's MediaQuery does not expose on
/// macOS (Reduce transparency) plus an app-level motion override.
/// The platform layer feeds real system values in.
class MMAppearance extends InheritedWidget {
  const MMAppearance({super.key, required super.child, this.reduceTransparency = false, this.reduceMotion = false});

  final bool reduceTransparency;
  final bool reduceMotion;

  static MMAppearance? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MMAppearance>();

  static bool reduceTransparencyOf(BuildContext context) => maybeOf(context)?.reduceTransparency ?? false;

  /// True when either the app or the system asks for less motion.
  static bool reduceMotionOf(BuildContext context) =>
      (maybeOf(context)?.reduceMotion ?? false) || MediaQuery.maybeDisableAnimationsOf(context) == true;

  /// [duration], or zero when motion should be reduced.
  static Duration duration(BuildContext context, Duration duration) =>
      reduceMotionOf(context) ? Duration.zero : duration;

  @override
  bool updateShouldNotify(MMAppearance oldWidget) =>
      oldWidget.reduceTransparency != reduceTransparency || oldWidget.reduceMotion != reduceMotion;
}
