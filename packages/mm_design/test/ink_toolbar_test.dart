import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  test('ink palette and widths', () {
    expect(MMInkColor.values, hasLength(6));
    expect(MMInkColor.red.color, const Color(0xFFFF3B30));
    expect(MMInkColor.black.color, const Color(0xFF1D1D1F));
    expect(MMInkColor.blue.stroke.a, closeTo(0.9, 0.01));
    expect(MMInkColor.fromIndex(99), MMInkColor.black);
    expect(MMInkColor.fromIndex(-1), MMInkColor.red);
    expect([for (final w in MMInkWidth.values) w.points], [1.5, 2.5, 4]);
  });

  testWidgets('swatches, stroke widths and a text-only button report taps', (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      harness(
        MMFloatingToolbar(
          children: [
            MMFloatingToolbarSwatch(
              color: MMInkColor.red.color,
              tooltip: 'Red',
              selected: true,
              onPressed: () => taps.add('red'),
            ),
            MMFloatingToolbarSwatch(color: MMInkColor.blue.color, tooltip: 'Blue', onPressed: null),
            MMFloatingToolbarStrokeWidth(width: 4, tooltip: 'Bold', selected: true, onPressed: () => taps.add('bold')),
            MMFloatingToolbarStrokeWidth(width: 1.5, tooltip: 'Thin', onPressed: () => taps.add('thin')),
            MMToolbarButton(icon: null, label: 'Done', tooltip: 'Done', onPressed: () => taps.add('done')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Red'));
    await tester.tap(find.byTooltip('Blue'));
    await tester.tap(find.byTooltip('Bold'));
    await tester.tap(find.byTooltip('Thin'));
    await tester.tap(find.text('Done'));
    expect(taps, ['red', 'bold', 'thin', 'done']);

    // The dot is as thick as the stroke; the selected one uses the accent.
    final dots = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.constraints?.maxWidth == 10 || c.constraints?.maxWidth == 5);
    expect(dots, hasLength(2));
    final c = tester.element(find.text('Done')).mmColors;
    final bold = dots.firstWhere((d) => d.constraints!.maxWidth == 10).decoration! as BoxDecoration;
    expect(bold.color, c.accent);
    final red = tester
        .widgetList<Container>(find.descendant(of: find.byTooltip('Red'), matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.shape == BoxShape.circle);
    expect(red.boxShadow, hasLength(2), reason: 'selected ring');
    expect(find.byType(Icon), findsNothing);
  });
}
