import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('context region preserves clicks and offers a touch long press with haptics', (tester) async {
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      haptics.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    var taps = 0;
    final menus = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MMContextMenuRegion(
            onSecondaryTapUp: (d) => menus.add(d.globalPosition),
            child: MMInteractive(onTap: () => taps++, builder: (_, _) => const SizedBox(width: 200, height: 100)),
          ),
        ),
      ),
    );
    final target = find.byType(MMInteractive);
    await tester.tap(target);
    expect(taps, 1);
    await tester.longPress(target);
    expect(menus, [tester.getCenter(target)]);
    expect(haptics.where((call) => call.method == 'HapticFeedback.vibrate'), hasLength(1));
    final mouse = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    expect(menus, hasLength(2));
    final hold = await tester.startGesture(tester.getCenter(target), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(seconds: 1));
    await hold.up();
    expect(menus, hasLength(2));
    expect(taps, 2);
  });

  testWidgets('nested regions open only the innermost menu; a scrolling touch opens none', (tester) async {
    var outer = 0, inner = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MMContextMenuRegion(
          onSecondaryTapUp: (_) => outer++,
          child: ListView(
            children: [
              MMContextMenuRegion(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapUp: (_) => inner++,
                child: const SizedBox(
                  key: ValueKey('inner'),
                  height: 200,
                  child: ColoredBox(color: Colors.white),
                ),
              ),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    );
    await tester.longPress(find.byKey(const ValueKey('inner')));
    expect(inner, 1);
    expect(outer, 0);
    await tester.drag(find.byKey(const ValueKey('inner')), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(inner, 1);
    expect(outer, 0);
  });

  testWidgets('hybrid input switches visible controls and menu item heights', (tester) async {
    late BuildContext menuContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light().copyWith(platform: TargetPlatform.macOS),
        home: MMInput(
          touchPlatform: false,
          child: Builder(
            builder: (context) {
              menuContext = context;
              return SizedBox.expand(child: Text(MMInput.touchInputOf(context) ? 'touch' : 'pointer'));
            },
          ),
        ),
      ),
    );
    expect(find.text('pointer'), findsOneWidget);
    final touch = await tester.startGesture(const Offset(100, 100), kind: PointerDeviceKind.touch);
    await touch.up();
    await tester.pump();
    expect(find.text('touch'), findsOneWidget);
    void open() => showMMMenu(menuContext, position: const Offset(50, 50), entries: [MMMenuItem('Action', () {})]);
    open();
    await tester.pumpAndSettle();
    Finder row() => find.ancestor(of: find.text('Action'), matching: find.byType(MMInteractive)).first;
    expect(tester.getSize(row()).height, 44);
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    await mouse.moveTo(const Offset(101, 100));
    await tester.pump();
    expect(find.text('pointer'), findsOneWidget);
    open();
    await tester.pumpAndSettle();
    expect(tester.getSize(row()).height, 24);
    await mouse.removePointer();
  });

  testWidgets('touch menu portal closes on selection, outside tap, Esc and page disposal', (tester) async {
    late BuildContext menuContext;
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MMContextMenuHost(
          child: Builder(
            builder: (context) {
              menuContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    Future<void> open() async {
      showMMMenu(menuContext, position: const Offset(100, 100), entries: [MMMenuItem('Action', () => selected++)]);
      await tester.pumpAndSettle();
      expect(find.text('Action'), findsOneWidget);
    }

    await open();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    await open();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsNothing);
    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsNothing);
    await open();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('window keeps bottom input above the keyboard and restores desktop geometry', (tester) async {
    Future<void> mount(double inset) => tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
          child: const MMWindowScaffold(
            toolbar: SizedBox(height: 40),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(key: ValueKey('input'), width: 200, height: 44),
            ),
          ),
        ),
      ),
    );
    await mount(0);
    final bottom = tester.getBottomLeft(find.byKey(const ValueKey('input'))).dy;
    await mount(240);
    expect(tester.getBottomLeft(find.byKey(const ValueKey('input'))).dy, bottom - 240);
    await mount(0);
    expect(tester.getBottomLeft(find.byKey(const ValueKey('input'))).dy, bottom);
  });
}
