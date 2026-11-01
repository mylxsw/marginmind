import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  testWidgets('popup submenu flips left at the window edge without a gap', (tester) async {
    await tester.pumpWidget(
      harness(
        Align(
          alignment: Alignment.topRight,
          child: MMDropdownButton<String>(
            cascading: true,
            tooltip: 'More',
            itemBuilder: (_) => const [
              MMDropdownSubmenu<String>(
                label: 'Appearance',
                entries: [(value: 'white', label: 'White', selected: true)],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    final parent = tester.getRect(find.byType(SubmenuButton));
    final child = tester.getRect(find.byType(MenuItemButton));
    expect(parent.left - child.right, inInclusiveRange(0, 12));
    expect(tester.takeException(), isNull);
  });
  testWidgets('popup submenu opens to the side and selecting a leaf closes the parent', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? selected;
    await tester.pumpWidget(
      harness(
        MMDropdownButton<String>(
          cascading: true,
          tooltip: 'More',
          onSelected: (value) => selected = value,
          itemBuilder: (_) => const [
            MMDropdownSubmenu<String>(
              label: 'Appearance',
              icon: MMIcons.appearance,
              entries: [
                (value: 'white', label: 'White', selected: true),
                (value: 'dark', label: 'Dark', selected: false),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsNothing);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.byIcon(MMIcons.appearance), findsOneWidget, reason: 'The category icon belongs to the parent only');
    expect(find.byIcon(MMIcons.check), findsOneWidget);
    expect(tester.getRect(find.text('Dark')).left, greaterThan(tester.getRect(find.text('Appearance')).right));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(selected, 'dark');
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('Dark'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
  testWidgets('hovering switches submenus and Escape closes the complete menu tree', (tester) async {
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
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Section'), findsNothing);
    expect(find.text('Layout'), findsNothing);
    await mouse.removePointer();
  });
}
