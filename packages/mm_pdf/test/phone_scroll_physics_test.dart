import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pdf/mm_pdf.dart';

FixedScrollMetrics metrics({double pixels = 5000, double min = 0, double max = 20000}) => FixedScrollMetrics(
  minScrollExtent: min,
  maxScrollExtent: max,
  pixels: pixels,
  viewportDimension: 852,
  axisDirection: AxisDirection.down,
  devicePixelRatio: 1,
);

void main() {
  const physics = MMPhoneScrollPhysics();
  test('mobile release travels 25% farther than the original phone profile in both directions', () {
    expect(physics.applyTo(const ClampingScrollPhysics()).parent, isA<ClampingScrollPhysics>());
    for (final speed in [-6000.0, -1500.0, -100.0, 100.0, 1500.0, 6000.0]) {
      final simulation = physics.createBallisticSimulation(metrics(), speed)!;
      expect(simulation.x(0), closeTo(5000, 1e-8));
      expect(simulation.dx(0), closeTo(speed * 2, 1e-8));
      for (final t in [.001, .016, .1, .5]) {
        expect(simulation.dx(t), closeTo(speed * 2 * math.pow(.998, 1000 * t), 1e-7));
      }
      final rate = math.log((simulation.dx(.5) / simulation.dx(.1)).abs()) / .4;
      expect(rate, closeTo(1000 * math.log(.998), 1e-8));
      final original = FrictionSimulation(math.pow(.998, 1000).toDouble(), 5000, speed * 1.6);
      expect(simulation.x(.5) - 5000, closeTo((original.x(.5) - 5000) * 1.25, 1e-7));
      expect(simulation.isDone(10), isTrue);
    }
  });

  test('rubber band direct input without filtering ballistic spring output', () {
    var direct = true;
    final physics = MMPhoneScrollPhysics(userGestureInProgress: () => direct).applyTo(null);
    final outside = metrics(pixels: -40);
    expect(physics.applyPhysicsToUserOffset(outside, -100).abs(), lessThan(100));
    direct = false;
    expect(physics.applyPhysicsToUserOffset(outside, -100), -100);
  });

  test('slow release and non-scrollable axis do not start an animation', () {
    expect(physics.createBallisticSimulation(metrics(), 0), isNull);
    expect(physics.createBallisticSimulation(metrics(), .01), isNull);
    expect(physics.createBallisticSimulation(metrics(pixels: 0, max: 0), 6000), isNull);
  });

  test('fast flings at either edge settle with less than 30 px spring excursion', () {
    for (final end in [false, true]) {
      final edge = end ? 20000.0 : 0.0;
      final start = edge + (end ? -100 : 100);
      final simulation = physics.createBallisticSimulation(metrics(pixels: start), end ? 8000 : -8000)!;
      for (var frame = 0; frame <= 600; frame++) {
        final x = simulation.x(frame / 120);
        expect(x, inInclusiveRange(-30, 20030));
      }
      expect(simulation.x(5), closeTo(edge, .1));
      expect(simulation.dx(5), closeTo(0, .1));
      expect(simulation.isDone(5), isTrue);
    }
  });

  test('already outside an edge returns without multiplying the release velocity', () {
    for (final start in [-40.0, 20040.0]) {
      final simulation = physics.createBallisticSimulation(metrics(pixels: start), 100)!;
      expect(simulation.x(0), start);
      expect(simulation.dx(0), closeTo(100, 1e-8));
      expect(simulation.x(4), closeTo(start < 0 ? 0 : 20000, .01));
      expect(simulation.isDone(4), isTrue);
    }
  });
}
