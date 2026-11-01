import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('$kind first tap is immediate and second tap reports only double callbacks', (tester) async {
      var singles = 0, doubleDowns = 0, doubles = 0, doubleUps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RawGestureDetector(
            gestures: {
              MMImmediateTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<MMImmediateTapGestureRecognizer>(
                MMImmediateTapGestureRecognizer.new,
                (tap) {
                  tap.onTapUp = (_) {
                    singles++;
                  };
                  tap.onDoubleTapDown = (_) {
                    doubleDowns++;
                  };
                  tap.onDoubleTapUp = (_) {
                    doubleUps++;
                  };
                  tap.onDoubleTap = () {
                    doubles++;
                  };
                },
              ),
            },
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      );
      await tester.tapAt(const Offset(100, 100), kind: kind);
      expect(singles, 1);
      await tester.pump(const Duration(milliseconds: 60));
      final second = await tester.startGesture(const Offset(100, 100), kind: kind);
      expect(doubleDowns, 1);
      await second.up();
      expect(singles, 1);
      expect(doubles, 1);
      expect(doubleUps, 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(singles, 1);
    });
  }
  testWidgets('a child button is immediate and neither toggles nor double-activates its parent', (tester) async {
    var child = 0, parent = 0, doubleParent = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MMInteractive(
          immediateTap: true,
          onTap: () => parent++,
          onDoubleTap: () => doubleParent++,
          builder: (_, _) => Center(
            child: MMButton(label: 'Child', onPressed: () => child++),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Child'));
    expect(child, 1);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Child'));
    expect(child, 2);
    expect(parent, 0);
    expect(doubleParent, 0);
    await tester.pump(const Duration(milliseconds: 400));
  });
  testWidgets('drag and long press still win over an immediate tap', (tester) async {
    var taps = 0, pans = 0, holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RawGestureDetector(
          gestures: {
            MMImmediateTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<MMImmediateTapGestureRecognizer>(
              MMImmediateTapGestureRecognizer.new,
              (tap) {
                tap.onTap = () {
                  taps++;
                };
                tap.onDoubleTap = () {};
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (_) => pans++,
            onLongPress: () => holds++,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(100, 100), const Offset(100, 0));
    expect(pans, greaterThan(0));
    expect(taps, 0);
    await tester.longPressAt(const Offset(100, 100));
    expect(holds, 1);
    expect(taps, 0);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
