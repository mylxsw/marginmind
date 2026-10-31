import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

/// A touch window of [size] with a home indicator inset.
Future<void> _phone(WidgetTester tester, Widget child, {Size size = const Size(400, 800), bool touch = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 40, bottom: 30);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: MMTheme.light(),
      builder: (context, child) => MMInput(touchPlatform: touch, phone: true, child: child!),
      home: child,
    ),
  );
}

void main() {
  group('MMInput', () {
    testWidgets('phone only on a touch platform; touch input follows every device', (tester) async {
      late BuildContext inner;
      await _phone(
        tester,
        Builder(
          builder: (context) {
            inner = context;
            return const SizedBox.expand();
          },
        ),
        touch: false,
      );
      expect(MMInput.of(inner).phone, isFalse);
      expect(MMInput.touchInputOf(inner), isFalse);
      // A touchscreen laptop: touch menus, pointer-sized controls.
      await tester.tapAt(const Offset(50, 50));
      await tester.pump();
      expect(MMInput.touchInputOf(inner), isTrue);
      expect(inner.mmTouch, isFalse);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(MMInput.touchInputOf(inner), isFalse);
      await mouse.removePointer();
      expect(const MMInputState(touch: true), const MMInputState(touch: true, touchInput: true));
      expect(const MMInputState(phone: true).hashCode, isNot(const MMInputState().hashCode));
    });
  });

  group('MMTabBar', () {
    Widget bar(ValueChanged<int> onSelected, {int? selected = 1}) => Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MMTabBar(
          selected: selected,
          onSelected: onSelected,
          tabs: const [
            MMTab(icon: MMIcons.library, label: 'Library'),
            MMTab(icon: MMIcons.reading, label: 'Source'),
            MMTab(icon: MMIcons.review, label: 'Review', enabled: false),
          ],
        ),
      ),
    );

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('${platform.name}: equal tabs over the home indicator; disabled tabs ignore taps', (tester) async {
        final taps = <int>[];
        await _phone(tester, bar(taps.add));
        final rect = tester.getRect(find.byType(MMTabBar));
        final height = MMSizes.phoneTabBarHeight;
        expect(rect.height, height + 30);
        expect(MMTabBar.heightOf(tester.element(find.byType(MMTabBar))), height + 30);
        // A capsule floating above the home indicator, inset from the sides.
        final capsule = tester.getRect(find.byKey(const ValueKey('mm-tab-bar-glass')));
        expect(
          capsule,
          Rect.fromLTRB(
            MMSizes.phoneTabBarHorizontalInset,
            800 - 30 - height,
            400 - MMSizes.phoneTabBarHorizontalInset,
            800 - 30,
          ),
        );
        expect(tester.getSize(find.byKey(const ValueKey('mm-tab-0'))).width, closeTo((capsule.width - 8) / 3, 0.01));
        // Android's hit areas stay at least 48 dp.
        expect(tester.getSize(find.byKey(const ValueKey('mm-tab-0'))).height, greaterThanOrEqualTo(48));
        await tester.tap(find.text('Library'));
        await tester.tap(find.text('Review'));
        expect(taps, [0]);
        await tester.pumpWidget(MaterialApp(theme: MMTheme.light(), home: bar(taps.add, selected: null)));
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(platform));
    }
  });

  group('MMBottomSheet', () {
    testWidgets('a compact sheet or dialog rises from the bottom; dragging down or Esc pops it', (tester) async {
      late BuildContext context;
      await _phone(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      );
      final sheet = find.byKey(const ValueKey('mm-bottom-sheet'));
      final result = showMMSheet<String>(
        context: context,
        builder: (_) => MMSheet(
          title: 'Rename',
          actions: [MMButton(label: 'OK', onPressed: () {})],
          child: Column(children: [for (var i = 0; i < 40; i++) Text('line $i')]),
        ),
      );
      await tester.pumpAndSettle();
      // Fits the window below the safe area top; the long body scrolls.
      final rect = tester.getRect(sheet);
      expect(rect.bottom, 800);
      expect(rect.top, 40 + MMSpacing.s);
      expect(find.text('OK'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // A short drag springs back.
      await tester.drag(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 20));
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      await tester.drag(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(await result, isNull);

      showMMDialog<void>(
        context: context,
        builder: (_) => const SizedBox(height: 120, child: Text('Settings')),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).height, MMSizes.bottomSheetHandle + 120 + 30);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    });

    testWidgets('a regular window keeps the centered sheet', (tester) async {
      late BuildContext context;
      await _phone(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
        size: const Size(1300, 900),
      );
      showMMSheet<void>(
        context: context,
        builder: (_) => const MMSheet(title: 'Wide', child: SizedBox()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsNothing);
      expect(find.text('Wide'), findsOneWidget);
    });

    testWidgets('an expanding sheet drags between medium and full height and dismisses', (tester) async {
      var dismissed = 0;
      await _phone(
        tester,
        Stack(
          children: [
            Positioned.fill(
              child: MMBottomSheet(expand: true, scrim: true, onDismiss: () => dismissed++, child: const Text('Panel')),
            ),
          ],
        ),
      );
      final sheet = find.byKey(const ValueKey('mm-bottom-sheet'));
      final handle = find.byKey(const ValueKey('mm-bottom-sheet-handle'));
      const room = 800 - 40 - MMSpacing.s;
      expect(tester.getSize(sheet).height, moreOrLessEquals(room * MMSizes.bottomSheetMedium));
      // A fling up goes full; a fling down returns to medium.
      await tester.fling(handle, const Offset(0, -60), 1500);
      await tester.pumpAndSettle();
      expect(tester.getSize(sheet).height, moreOrLessEquals(room));
      await tester.fling(handle, const Offset(0, 60), 1500);
      await tester.pumpAndSettle();
      expect(tester.getSize(sheet).height, moreOrLessEquals(room * MMSizes.bottomSheetMedium));
      expect(dismissed, 0);
      await tester.fling(handle, const Offset(0, 60), 1500);
      await tester.pumpAndSettle();
      expect(dismissed, 1);
      await tester.tapAt(const Offset(200, 60));
      expect(dismissed, 2);
    });
  });

  group('action sheet', () {
    Future<BuildContext> pump(WidgetTester tester, {bool touch = true}) async {
      late BuildContext context;
      await _phone(
        tester,
        MMContextMenuHost(
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      if (touch) {
        await tester.tapAt(const Offset(200, 400));
      } else {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(10, 10));
        await mouse.moveTo(const Offset(20, 20));
        await mouse.removePointer();
      }
      await tester.pump();
      return context;
    }

    List<MMMenuEntry> entries(List<String> log) => [
      const MMMenuHeader('Card'),
      MMMenuItem('Rename', () => log.add('rename'), checked: true),
      const MMMenuDivider(),
      MMMenuItem('Disabled', null),
      MMMenuItem('Delete', () => log.add('delete'), destructive: true),
    ];

    for (final touch in [true, false]) {
      testWidgets('a compact window lists the items above Cancel (${touch ? 'touch' : 'mouse'})', (tester) async {
        final log = <String>[];
        final context = await pump(tester, touch: touch);
        final sheet = find.byKey(const ValueKey('mm-action-sheet'));
        showMMMenu(context, position: const Offset(10, 10), entries: entries(log));
        await tester.pumpAndSettle();
        expect(sheet, findsOneWidget);
        expect(tester.getRect(sheet).bottom, 800 - 30);
        expect(
          tester.getSize(find.ancestor(of: find.text('Rename'), matching: find.byType(MMInteractive))).height,
          MMSizes.actionSheetRow,
        );
        expect(find.byIcon(MMIcons.check), findsOneWidget);
        expect(find.text('Card'), findsOneWidget);
        await tester.tap(find.text('Disabled'));
        await tester.pumpAndSettle();
        expect(sheet, findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(log, ['delete']);
        expect(sheet, findsNothing);

        showMMMenu(context, position: const Offset(10, 10), entries: entries(log));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(log, ['delete']);
      });
    }
  });

  group('MMBackHandler', () {
    testWidgets('newest handler first, only while its page is current; then the app leaves', (tester) async {
      final log = <String>[];
      var innerHandles = true;
      var outerHandles = true;
      late BuildContext context;
      await _phone(
        tester,
        MMBackScope(
          child: MMBackHandler(
            onBack: () {
              log.add('outer');
              return outerHandles;
            },
            child: MMBackHandler(
              onBack: () {
                log.add('inner');
                return innerHandles;
              },
              child: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      // The page claims back, so Android sends it to the app.
      expect(await tester.binding.handlePopRoute(), isTrue);
      expect(log, ['inner']);
      innerHandles = false;
      await tester.binding.handlePopRoute();
      expect(log, ['inner', 'inner', 'outer']);

      // A dialog above the page is popped by the navigator.
      showMMDialog<void>(context: context, builder: (_) => const Text('Dialog'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Dialog'), findsNothing);
      expect(log, ['inner', 'inner', 'outer']);

      // Nothing handles it: the app leaves.
      outerHandles = false;
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.binding.handlePopRoute();
      expect(calls, contains('SystemNavigator.pop'));
    });

    testWidgets('an open touch menu closes first', (tester) async {
      late BuildContext context;
      var page = 0;
      await _phone(
        tester,
        MMBackScope(
          child: MMBackHandler(
            onBack: () {
              page++;
              return true;
            },
            child: MMContextMenuHost(
              child: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
        size: const Size(800, 800),
      );
      await tester.tapAt(const Offset(100, 100));
      showMMMenu(context, position: const Offset(100, 100), entries: [MMMenuItem('Action', () {})]);
      await tester.pumpAndSettle();
      expect(find.text('Action'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Action'), findsNothing);
      expect(page, 0);
      await tester.binding.handlePopRoute();
      expect(page, 1);
    });
  });

  group('MMWindowScaffold', () {
    testWidgets('floats the bottom bar over the content until the keyboard rises; the sheet covers both', (
      tester,
    ) async {
      await _phone(
        tester,
        const MMWindowBottomBar(
          bar: SizedBox(key: ValueKey('bar'), height: 60),
          extent: 60,
          child: MMWindowScaffold(
            toolbar: SizedBox(height: 40),
            body: SizedBox.expand(key: ValueKey('body')),
            sheet: SizedBox.expand(key: ValueKey('sheet')),
          ),
        ),
      );
      final body = tester.getRect(find.byKey(const ValueKey('body')));
      final bar = tester.getRect(find.byKey(const ValueKey('bar')));
      expect(bar.bottom, 800);
      // A body that does not extend is laid out between the glass toolbar
      // and the bar's extent.
      expect(body.bottom, bar.top);
      expect(body.top, 40 + MMSizes.toolbarHeight);
      expect(tester.getRect(find.byKey(const ValueKey('sheet'))), const Rect.fromLTWH(0, 0, 400, 800));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(find.byKey(const ValueKey('bar')), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('body'))).bottom, 500);
    });
  });
}
