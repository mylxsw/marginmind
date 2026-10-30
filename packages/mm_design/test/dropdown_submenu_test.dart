import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('dropdown submenu returns a leaf and closes both menus in $brightness', (tester) async {
      String? selected;
      await tester.pumpWidget(
        harness(
          MMDropdownMenuButton<String>(
            tooltip: 'More',
            icon: MMIcons.more,
            onSelected: (value) => selected = value,
            itemBuilder: (_) => [
              const MMDropdownSubmenu<String>(
                label: 'Layout',
                entries: [
                  (value: 'reading', label: 'Reading', selected: true),
                  (value: 'cornell', label: 'Cornell', selected: false),
                ],
              ),
              const MMDropdownItem(value: 'export', child: Text('Export')),
            ],
          ),
          brightness: brightness,
        ),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Layout'));
      await tester.pumpAndSettle();
      expect(find.text('Reading'), findsOneWidget);
      expect(find.byIcon(MMIcons.check), findsOneWidget);
      await tester.tap(find.text('Cornell'));
      await tester.pumpAndSettle();
      expect(selected, 'cornell');
      expect(find.text('Layout'), findsNothing);
      expect(find.text('Cornell'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('hovering a sibling submenu closes the previous submenu', (tester) async {
    await tester.pumpWidget(
      harness(
        MMDropdownMenuButton<String>(
          tooltip: 'More',
          icon: MMIcons.more,
          itemBuilder: (_) => const [
            MMDropdownSubmenu<String>(
              label: 'Layout',
              entries: [(value: 'reading', label: 'Reading', selected: false)],
            ),
            MMDropdownSubmenu<String>(
              label: 'Contents',
              entries: [(value: 'section', label: 'Section', selected: false)],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layout'));
    await tester.pumpAndSettle();
    expect(find.text('Reading'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Contents')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Section'), findsOneWidget);
    expect(find.text('Reading'), findsNothing);
    await mouse.removePointer();
  });
}
