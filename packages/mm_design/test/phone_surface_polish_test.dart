import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('dragging an expanded sheet down keeps its header and input intact', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.dark(),
        builder: (_, child) => MMInput(phone: true, touchPlatform: true, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMMBottomSheet<void>(
                context: context,
                builder: (_) => const Column(
                  children: [
                    SizedBox(height: 52, child: Text('Assistant')),
                    Expanded(child: SingleChildScrollView(child: Text('Actions'))),
                    SizedBox(key: ValueKey('input'), height: 52, child: Text('Question')),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final frame = find.byKey(const ValueKey('mm-bottom-sheet'));
    final before = tester.getRect(frame);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('mm-bottom-sheet-handle'))));
    await gesture.moveBy(const Offset(0, 280));
    await tester.pump();
    final during = tester.getRect(frame);
    expect(during.height, before.height);
    expect(during.top, greaterThan(before.top));
    expect(tester.getSize(find.byKey(const ValueKey('input'))).height, 52);
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(frame, findsNothing);
  });
  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('phone leaf and submenu rows align at $width, dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
        addTearDown(tester.view.reset);
        int? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? MMTheme.dark() : MMTheme.light(),
            builder: (context, child) => MMInput(
              phone: true,
              touchPlatform: true,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: MMDropdownButton<int>(
                tooltip: 'Options',
                onSelected: (value) => selected = value,
                itemBuilder: (_) => const [
                  MMDropdownSubmenu<int>(
                    key: ValueKey('submenu'),
                    label: 'Maps',
                    icon: MMIcons.mindMap,
                    entries: [(value: 1, label: 'Main map', selected: true)],
                  ),
                  MMDropdownItem<int>(key: ValueKey('leaf'), value: 2, icon: MMIcons.mapStyle, child: Text('Style')),
                  MMDropdownItem<int>(value: 3, enabled: false, icon: MMIcons.trash, child: Text('Remove')),
                ],
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Options'));
        await tester.pumpAndSettle();
        expect(find.byType(MMPhoneSheetHeader), findsNothing, reason: 'root actions need no duplicate title bar');
        final submenu = tester.getRect(find.byKey(const ValueKey('submenu')));
        final leaf = tester.getRect(find.byKey(const ValueKey('leaf')));
        expect(submenu.height, leaf.height);
        expect(submenu.height, greaterThanOrEqualTo(44));
        expect(tester.getTopLeft(find.text('Maps')).dx, tester.getTopLeft(find.text('Style')).dx);
        final firstIcon = find.byIcon(MMIcons.mindMap);
        final secondIcon = find.byIcon(MMIcons.mapStyle);
        expect(tester.getSize(firstIcon), tester.getSize(secondIcon));
        expect(tester.getTopLeft(firstIcon).dx, tester.getTopLeft(secondIcon).dx);
        final frame = tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet')));
        expect(frame.left, greaterThan(0));
        expect(frame.right, lessThan(width));
        expect(frame.bottom, lessThanOrEqualTo(810));
        expect(find.byType(MMGlass), findsNothing, reason: 'menus use one solid surface');
        expect(find.byIcon(MMIcons.close), findsNothing, reason: 'short phone menus dismiss with the handle or scrim');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(selected, isNull);
        await tester.tap(find.text('Maps'));
        await tester.pumpAndSettle();
        expect(find.byType(MMPhoneSheetHeader), findsOneWidget, reason: 'nested navigation retains its location');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MMPhoneSheetHeader), findsNothing);
        expect(find.byKey(const ValueKey('leaf')), findsOneWidget);
        await tester.tap(find.text('Maps'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(MMPhoneSheetHeader), findsNothing);
        await tester.tap(find.text('Maps'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Main map'));
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsNothing);
        await tester.tap(find.byTooltip('Options'));
        await tester.pumpAndSettle();
        await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 300), 1200);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsNothing);
        expect(selected, 1);
      });
    }
  }
}
