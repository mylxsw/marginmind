import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Opt-in reading behavior. Null in MMPdfView preserves the viewer's old path.
enum MMPdfScrollProfile { phone }

/// Screen-pixel pan inertia, isolated from wheel and scale gestures by pdfrx.
class MMPhoneScrollPhysics extends BouncingScrollPhysics {
  const MMPhoneScrollPhysics({super.parent, this.userGestureInProgress});

  /// pdfrx applies this hook to ballistic frame deltas too. Rubber-band only
  /// direct input; filtering a spring's output again would leave it off its edge.
  final bool Function()? userGestureInProgress;

  static const velocityMultiplier = 1.6;
  static const decelerationPerMillisecond = .998;
  static final dragPerSecond = math.pow(decelerationPerMillisecond, 1000).toDouble();
  static const maxSpringVelocity = 1600.0;
  // pdfrx stops before applying the final simulation frame. Settle far below a
  // screen pixel so even a coarse frame interval cannot leave a visible gap.
  static const edgeTolerance = Tolerance(distance: .01, velocity: .1);
  static final edgeSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: 1);

  @override
  MMPhoneScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      MMPhoneScrollPhysics(parent: buildParent(ancestor), userGestureInProgress: userGestureInProgress);

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      userGestureInProgress?.call() == true ? super.applyPhysicsToUserOffset(position, offset) : offset;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final tolerance = toleranceFor(position);
    if (position.outOfRange) {
      return ScrollSpringSimulation(
        edgeSpring,
        position.pixels,
        position.pixels.clamp(position.minScrollExtent, position.maxScrollExtent),
        velocity.clamp(-maxSpringVelocity, maxSpringVelocity),
        tolerance: edgeTolerance,
      );
    }
    if (velocity.abs() < tolerance.velocity || position.maxScrollExtent <= position.minScrollExtent) return null;
    return _PhoneSimulation(
      position: position.pixels,
      velocity: velocity * velocityMultiplier,
      min: position.minScrollExtent,
      max: position.maxScrollExtent,
      tolerance: tolerance,
    );
  }
}

/// Exponential friction until an edge, then a bounded, critically damped return.
/// Limiting transferred velocity prevents a fast fling from springing a page away.
class _PhoneSimulation extends Simulation {
  _PhoneSimulation({
    required double position,
    required double velocity,
    required double min,
    required double max,
    required super.tolerance,
  }) {
    _friction = FrictionSimulation(MMPhoneScrollPhysics.dragPerSecond, position, velocity, tolerance: tolerance);
    final edge = velocity > 0 ? max : min;
    if (velocity > 0 ? _friction.finalX > max : _friction.finalX < min) {
      _edgeTime = _friction.timeAtX(edge);
      _spring = ScrollSpringSimulation(
        MMPhoneScrollPhysics.edgeSpring,
        edge,
        edge,
        _friction.dx(_edgeTime).clamp(-MMPhoneScrollPhysics.maxSpringVelocity, MMPhoneScrollPhysics.maxSpringVelocity),
        tolerance: MMPhoneScrollPhysics.edgeTolerance,
      );
    }
  }

  late final FrictionSimulation _friction;
  double _edgeTime = double.infinity;
  ScrollSpringSimulation? _spring;

  @override
  double x(double time) => time >= _edgeTime ? _spring!.x(time - _edgeTime) : _friction.x(time);
  @override
  double dx(double time) => time >= _edgeTime ? _spring!.dx(time - _edgeTime) : _friction.dx(time);
  @override
  bool isDone(double time) => time >= _edgeTime ? _spring!.isDone(time - _edgeTime) : _friction.isDone(time);
}
