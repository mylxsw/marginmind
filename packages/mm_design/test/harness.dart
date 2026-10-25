import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

/// Wraps [child] in an app with the MarginMind theme.
Widget harness(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? MMTheme.light() : MMTheme.dark(),
    home: MMHudHost(
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Colors painted just outside a selected color dot found by [dot]: the gap
/// ring (1pt past its edge) and the outer ring (2.75pt past it), sampled on
/// the dot's horizontal center line.
Future<(Color gap, Color ring)> dotRingColors(WidgetTester tester, Finder dot) async {
  final box = tester.renderObject<RenderBox>(dot);
  RenderObject node = box;
  while (!node.isRepaintBoundary) {
    node = node.parent!;
  }
  final boundary = node as RenderBox;
  final center = boundary.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  const ratio = 4.0;
  final image = (await tester.runAsync(
    () => (boundary.debugLayer! as OffsetLayer).toImage(Offset.zero & boundary.size, pixelRatio: ratio),
  ))!;
  final bytes = (await tester.runAsync(() => image.toByteData()))!;
  Color at(double dx) {
    final x = ((center.dx + dx) * ratio).floor();
    final y = (center.dy * ratio).floor();
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  }

  final radius = box.size.width / 2;
  final colors = (at(radius + 1), at(radius + 2.75));
  image.dispose();
  return colors;
}

/// Whether [actual] matches [expected] within rounding of the rasterizer.
Matcher sameColor(Color expected) => predicate<Color>(
  (actual) =>
      (actual.r - expected.r).abs() < 0.02 &&
      (actual.g - expected.g).abs() < 0.02 &&
      (actual.b - expected.b).abs() < 0.02,
  'color close to $expected',
);
