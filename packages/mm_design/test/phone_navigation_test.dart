import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

Future<void> host(
  WidgetTester tester,
  Widget child, {
  bool phone = true,
  bool touch = true,
  bool dark = false,
  bool reduce = false,
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? MMTheme.dark() : MMTheme.light(),
      home: MMInput(
        touchPlatform: touch,
        phone: phone,
        child: MMAppearance(
          reduceTransparency: reduce,
          child: Material(child: child),
        ),
      ),
    ),
  );
}

Widget tabs({int? selected = 0}) => Align(
  alignment: Alignment.bottomCenter,
  child: MMTabBar(
    selected: selected,
    onSelected: (_) {},
    tabs: const [
      MMTab(icon: MMIcons.library, label: 'Library'),
      MMTab(icon: MMIcons.review, label: 'Review'),
    ],
  ),
);

void main() {
  testWidgets('navigation grows for accessibility text and keeps actions usable', (tester) async {
    var taps = 0;
    await host(
      tester,
      MediaQuery(
        data: const MediaQueryData(size: Size(393, 852), textScaler: TextScaler.linear(3)),
        child: Column(
          children: [
            MMPhoneNavigationAction(label: 'Done', onPressed: () => taps++),
            MMPhoneNavigationAction(label: 'Library', icon: MMIcons.chevronLeft, onPressed: () => taps++),
            Expanded(child: tabs()),
          ],
        ),
      ),
    );
    expect(tester.getSize(find.byType(MMPhoneNavigationAction).first).height, greaterThanOrEqualTo(60));
    await tester.tap(find.text('Done'));
    await tester.tap(find.text('Library').first);
    expect(taps, 2);
    expect(tester.getSize(find.byKey(const ValueKey('mm-tab-bar-glass'))).height, greaterThan(64));
    expect(tester.takeException(), isNull);
  });

  test('accent hue remains legible with custom system colors', () {
    for (final dark in [false, true]) {
      for (final color in [Colors.red, Colors.yellow, Colors.green, Colors.blue, Colors.white, Colors.black]) {
        final fg = MMPhoneNavigation.selectedAccent(color, dark).computeLuminance();
        final bg = MMPhoneNavigation.lens(dark).computeLuminance();
        expect((fg > bg ? fg + .05 : bg + .05) / (fg > bg ? bg + .05 : fg + .05), greaterThanOrEqualTo(4.5));
      }
    }
  });

  for (final dark in [false, true]) {
    testWidgets('phone glass, lens contrast and reduced transparency dark=$dark', (tester) async {
      await host(tester, tabs(), dark: dark);
      expect(tester.getRect(find.byKey(const ValueKey('mm-tab-bar-glass'))), const Rect.fromLTWH(22, 762, 349, 64));
      expect(tester.widget<MMLiquidGlass>(find.byType(MMLiquidGlass)).phoneStyle, MMPhoneGlass.regular);
      final lens = MMPhoneNavigation.lens(dark);
      final accent = MMPhoneNavigation.selectedAccent(tester.element(find.byType(MMTabBar)).mmColors.accent, dark);
      final light = accent.computeLuminance(), base = lens.computeLuminance();
      final contrast = (light > base ? light + .05 : base + .05) / (light > base ? base + .05 : light + .05);
      expect(lens.a, 1, reason: 'cover colors cannot bleed through selected text');
      expect(contrast, greaterThanOrEqualTo(4.5));
      await host(tester, tabs(), dark: dark, reduce: true);
      expect(find.byType(BackdropFilter), findsNothing);
    });
  }

  testWidgets('tablet compact, desktop and landscape phone retain the legacy material', (tester) async {
    for (final device in [
      (false, true, const Size(393, 852)),
      (false, false, const Size(1280, 820)),
      (true, true, const Size(852, 393)),
    ]) {
      await host(tester, tabs(), phone: device.$1, touch: device.$2, size: device.$3);
      expect(find.byType(MMLiquidGlass), findsNothing);
      expect(find.byType(MMGlass), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('mm-tab-bar-glass'))).height, MMSizes.tabBarAndroid);
    }
  });

  testWidgets('spring lens moves, safe bottom is a maximum and reduced motion is immediate', (tester) async {
    await host(tester, tabs());
    tester.view.padding = const FakeViewPadding(bottom: 34);
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('mm-tab-bar-glass'))).bottom, 818);
    await host(tester, tabs(selected: 1));
    await tester.pump(const Duration(milliseconds: 100));
    final lens = tester.widget<AnimatedPositioned>(find.byKey(const ValueKey('mm-tab-highlight')));
    expect(lens.curve, MMPhoneNavigation.tabCurve);
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(const ValueKey('mm-tab-highlight'))).dx,
      closeTo(tester.getCenter(find.byKey(const ValueKey('mm-tab-1'))).dx, .1),
    );
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await host(tester, tabs(selected: 0));
    expect(tester.widget<AnimatedPositioned>(find.byKey(const ValueKey('mm-tab-highlight'))).duration, Duration.zero);
  });

  testWidgets('full-height drawer opens from edge, follows a drag, cancels and dismisses', (tester) async {
    var open = false;
    late StateSetter set;
    await host(
      tester,
      StatefulBuilder(
        builder: (context, update) {
          set = update;
          return MMPhoneDrawer(
            open: open,
            onChanged: (value) => update(() => open = value),
            dismissLabel: 'Close',
            drawer: const ColoredBox(
              color: Colors.white,
              child: Center(child: Text('Drawer')),
            ),
            child: const Center(child: Text('Content')),
          );
        },
      ),
    );
    expect(find.byKey(const ValueKey('phone-drawer-scrim')), findsNothing);
    final pen = await tester.startGesture(const Offset(2, 400), kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(180, 0));
    await pen.up();
    await tester.pumpAndSettle();
    expect(open, isFalse, reason: 'edge opening must not steal pen annotation gestures');
    await tester.dragFrom(const Offset(2, 400), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(open, isTrue);
    expect(tester.getRect(find.byKey(const ValueKey('phone-drawer-panel'))), const Rect.fromLTWH(0, 0, 328, 852));
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('phone-drawer-panel'))).dx, lessThan(0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(open, isTrue);
    await tester.tapAt(const Offset(370, 400));
    await tester.pumpAndSettle();
    expect(open, isFalse);
    set(() => open = true);
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(220, 400), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(open, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows, counts, selection and large review queues fit narrow spaces', (tester) async {
    var taps = 0;
    await host(
      tester,
      Column(
        children: [
          MMPhoneNavigationGroup(
            title: 'Learn',
            children: [
              MMPhoneNavigationRow(
                item: MMSidebarItem(
                  icon: MMIcons.review,
                  label: 'Review',
                  selected: true,
                  trailing: const MMBadge('3'),
                  onTap: () => taps++,
                ),
              ),
              const MMPhoneNavigationRow(
                item: MMSidebarItem(icon: MMIcons.studyNote, label: 'Notes', trailing: Icon(Icons.chevron_right)),
              ),
            ],
          ),
          const MMPhoneReviewProgress(total: 1000, completed: 500, label: 'Progress'),
          const MMPhoneReviewProgress(total: 0, completed: 0, label: 'Empty'),
        ],
      ),
    );
    expect(tester.getSize(find.byType(MMPhoneNavigationRow).first).height, 46);
    await tester.tap(find.text('Review'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
