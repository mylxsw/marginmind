import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

Widget _app(Widget child, {bool touchPlatform = false}) => MaterialApp(
  theme: MMTheme.light(),
  home: MMInput(
    touchPlatform: touchPlatform,
    child: Material(child: child),
  ),
);

void _setWindow(WidgetTester tester, Size size, {EdgeInsets safe = EdgeInsets.zero}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(left: safe.left, top: safe.top, right: safe.right, bottom: safe.bottom);
  addTearDown(tester.view.reset);
}

void main() {
  group('MMSizeClass', () {
    test('breakpoints at 600 and 1180, landscape for regular', () {
      expect(MMSizeClass.fromSize(const Size(599.9, 300)), MMSizeClass.compact);
      expect(MMSizeClass.fromSize(const Size(600, 1000)), MMSizeClass.medium);
      expect(MMSizeClass.fromSize(const Size(1179.9, 600)), MMSizeClass.medium);
      expect(MMSizeClass.fromSize(const Size(1180, 1180)), MMSizeClass.regular);
      expect(MMSizeClass.fromSize(const Size(1180, 1200)), MMSizeClass.medium);
      expect(MMSizeClass.fromSize(const Size(2000, 1000)), MMSizeClass.regular);
    });

    testWidgets('pointer desktops stay regular; touch windows classify their safe area', (tester) async {
      _setWindow(tester, const Size(1200, 900), safe: const EdgeInsets.only(left: 30));
      late MMSizeClass desktop, touch;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              desktop = MMSizeClass.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(desktop, MMSizeClass.regular);
      await tester.pumpWidget(
        _app(
          touchPlatform: true,
          Builder(
            builder: (context) {
              touch = MMSizeClass.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(touch, MMSizeClass.medium, reason: '1200 − 30 is below 1180');
    });
  });

  group('MMInput', () {
    testWidgets('defaults to pointer without a scope', (tester) async {
      late MMInputState state;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            state = MMInput.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(state, MMInputState.pointer);
      expect(state.hashCode, MMInputState.pointer.hashCode);
    });

    testWidgets('a touch platform follows the last pointer; a desktop ignores it', (tester) async {
      late BuildContext inner;
      Widget probe() => Builder(
        builder: (context) {
          inner = context;
          return const SizedBox.expand();
        },
      );
      await tester.pumpWidget(_app(probe(), touchPlatform: true));
      expect(inner.mmTouch, isTrue);
      expect(inner.mmToolbarButton, const Size.square(MMSizes.touchTarget));
      expect(inner.mmSidebarRow, MMSizes.touchTarget);
      expect(inner.mmDividerHit, MMSizes.touchTarget);
      expect(inner.mmToolbarIcon, MMSizes.touchTarget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      expect(inner.mmTouch, isFalse);
      expect(MMInput.of(inner).touchPlatform, isTrue);
      expect(
        inner.mmToolbarButton,
        const Size.square(MMSizes.touchTarget),
        reason: 'tablet geometry stays stable with a trackpad',
      );
      await mouse.removePointer();

      final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await pen.down(const Offset(30, 30));
      await pen.up();
      await tester.pump();
      expect(inner.mmTouch, isTrue);

      final trackpad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await trackpad.panZoomStart(const Offset(40, 40));
      await trackpad.panZoomEnd();
      await tester.pump();
      expect(inner.mmTouch, isFalse);

      await tester.tapAt(const Offset(50, 50));
      await tester.pump();
      expect(inner.mmTouch, isTrue);

      // Leaving the touch platform resets to pointer sizes for good.
      await tester.pumpWidget(_app(probe()));
      expect(inner.mmTouch, isFalse);
      await tester.tapAt(const Offset(50, 50));
      await tester.pump();
      expect(inner.mmTouch, isFalse);
      expect(inner.mmSidebarRow, MMSizes.sidebarRow);
      expect(inner.mmDividerHit, MMSizes.dividerHitWidth);
      expect(inner.mmToolbarIcon, 28);
    });
  });

  group('touch-sized controls', () {
    Widget controls() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MMToolbarButton(key: const ValueKey('button'), icon: MMIcons.add, tooltip: 'Add', onPressed: () {}),
        MMColorMenuButton(
          key: const ValueKey('color'),
          selected: MMAnnotationColor.values.first,
          labelOf: (c) => c.name,
          tooltip: 'Color',
          onChanged: (_) {},
        ),
        SizedBox(
          width: 200,
          child: MMSidebarItem(key: const ValueKey('row'), icon: MMIcons.add, label: 'Row', onTap: () {}),
        ),
        SizedBox(
          width: 300,
          child: MMSegmentedControl<int>(
            key: const ValueKey('segments'),
            expand: true,
            segments: const [
              MMSegment(value: 0, label: 'A'),
              MMSegment(value: 1, label: 'B'),
            ],
            value: 0,
            onChanged: (_) {},
          ),
        ),
      ],
    );

    testWidgets('grow to 44 pt under touch', (tester) async {
      await tester.pumpWidget(_app(Center(child: controls()), touchPlatform: true));
      expect(tester.getSize(find.byKey(const ValueKey('button'))), const Size.square(MMSizes.touchTarget));
      expect(tester.getSize(find.byKey(const ValueKey('color'))).height, MMSizes.touchTarget);
      expect(tester.getSize(find.byKey(const ValueKey('row'))).height, MMSizes.touchTarget);
      final segments = find.byKey(const ValueKey('segments'));
      expect(tester.getSize(segments), const Size(300, MMSizes.touchTarget));
      final a = tester.getSize(find.ancestor(of: find.text('A'), matching: find.byType(AnimatedContainer)).first);
      expect(a.width, closeTo((300 - 4) / 2, .01));
    });

    testWidgets('keep desktop sizes with a pointer', (tester) async {
      await tester.pumpWidget(_app(Center(child: controls())));
      expect(tester.getSize(find.byKey(const ValueKey('button'))), MMSizes.toolbarButton);
      expect(tester.getSize(find.byKey(const ValueKey('color'))).height, MMSizes.toolbarButton.height);
      expect(tester.getSize(find.byKey(const ValueKey('row'))).height, MMSizes.sidebarRow);
      expect(tester.getSize(find.byKey(const ValueKey('segments'))).height, MMSizes.segmented);
    });
  });

  group('MMWindowScaffold', () {
    Widget scaffold({bool overlay = false, bool open = true, bool windowButtons = true, VoidCallback? onDismiss}) =>
        MMWindowScaffold(
          sidebarOverlay: overlay,
          sidebarVisible: open,
          showsWindowButtons: windowButtons,
          onSidebarDismiss: onDismiss,
          sidebar: const MMSidebar(children: [Text('Side')]),
          toolbar: const MMToolbar(key: ValueKey('toolbar'), title: 'Title'),
          body: const SizedBox.expand(key: ValueKey('body')),
        );

    testWidgets('keeps sidebar, toolbar and body inside the safe area', (tester) async {
      _setWindow(tester, const Size(900, 700), safe: const EdgeInsets.fromLTRB(40, 30, 50, 20));
      await tester.pumpWidget(_app(scaffold()));
      final toolbar = tester.getRect(find.byKey(const ValueKey('toolbar')));
      expect(toolbar.top, 30);
      expect(toolbar.right, 900 - 50);
      expect(tester.getRect(find.byKey(const ValueKey('body'))).bottom, 700 - 20);
      expect(tester.getRect(find.byType(MMSidebar)).left, 40);
      // The background still fills the window.
      expect(tester.getSize(find.byType(ColoredBox).first), const Size(900, 700));
    });

    testWidgets('leaves room for window buttons only where they are drawn', (tester) async {
      _setWindow(tester, const Size(900, 700));
      double inset() => tester
          .widget<AnimatedPadding>(
            find.descendant(of: find.byKey(const ValueKey('toolbar')), matching: find.byType(AnimatedPadding)),
          )
          .padding
          .resolve(TextDirection.ltr)
          .left;
      await tester.pumpWidget(_app(scaffold(open: false)));
      await tester.pumpAndSettle();
      expect(inset(), 20 + MMSizes.windowButtonsWidth);
      await tester.pumpWidget(_app(scaffold(open: false, windowButtons: false)));
      await tester.pumpAndSettle();
      expect(inset(), 20);
      await tester.pumpWidget(_app(scaffold()));
      await tester.pumpAndSettle();
      expect(inset(), 20);
    });

    testWidgets('an overlay sidebar floats over the content and dismisses from the scrim', (tester) async {
      _setWindow(tester, const Size(700, 900));
      var dismissed = 0;
      await tester.pumpWidget(_app(scaffold(overlay: true, open: false, onDismiss: () => dismissed++)));
      await tester.pumpAndSettle();
      expect(find.text('Side').hitTestable(), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('body'))).left, 0);
      await tester.pumpWidget(_app(scaffold(overlay: true, onDismiss: () => dismissed++)));
      await tester.pumpAndSettle();
      expect(find.text('Side').hitTestable(), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('body'))).left, 0);
      await tester.tapAt(const Offset(650, 450));
      expect(dismissed, 1);
      // A tap on the drawer itself does not dismiss it.
      await tester.tap(find.text('Side'));
      expect(dismissed, 1);
    });
  });

  testWidgets('the drawer scrim reaches into the safe area insets', (tester) async {
    _setWindow(tester, const Size(874, 402), safe: const EdgeInsets.fromLTRB(62, 0, 62, 20));
    var dismissed = 0;
    await tester.pumpWidget(
      _app(
        MMWindowScaffold(
          sidebarOverlay: true,
          onSidebarDismiss: () => dismissed++,
          sidebar: const MMSidebar(children: [Text('Side')]),
          toolbar: const MMToolbar(key: ValueKey('toolbar'), title: 'Title'),
          body: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(MMSidebar)).left, 62);
    expect(tester.getRect(find.byKey(const ValueKey('toolbar'))).left, 62);
    await tester.tapAt(const Offset(850, 200));
    expect(dismissed, 1);
  });

  group('MMDrawer', () {
    testWidgets('slides in from the end edge with an inset, at most the available width', (tester) async {
      _setWindow(tester, const Size(500, 600));
      Widget drawer(bool open) => _app(
        Stack(
          children: [
            MMDrawer(
              open: open,
              end: true,
              inset: 8,
              width: 600,
              child: const SizedBox.expand(key: ValueKey('panel')),
            ),
          ],
        ),
      );
      await tester.pumpWidget(drawer(true));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('panel'))), const Rect.fromLTRB(8, 8, 492, 592));
      await tester.pumpWidget(drawer(false));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('panel'))).left, greaterThanOrEqualTo(500));
    });
  });

  group('MMSplitView vertical', () {
    Widget view({
      MMSplitMode mode = MMSplitMode.split,
      double fraction = .5,
      ValueChanged<double>? onFraction,
      ValueChanged<MMSplitMode>? onMode,
      bool touch = false,
    }) => _app(
      touchPlatform: touch,
      SizedBox(
        width: 600,
        height: 800,
        child: MMSplitView(
          axis: Axis.vertical,
          mode: mode,
          fraction: fraction,
          minPrimaryWidth: 200,
          minSecondaryWidth: 200,
          onFractionChanged: onFraction,
          onModeChanged: onMode,
          primary: const SizedBox.expand(key: ValueKey('top')),
          secondary: const SizedBox.expand(key: ValueKey('bottom')),
        ),
      ),
    );

    testWidgets('stacks the panes and drags the divider vertically', (tester) async {
      _setWindow(tester, const Size(600, 800));
      var fraction = .5;
      await tester.pumpWidget(view(onFraction: (f) => fraction = f, touch: true));
      final top = tester.getRect(find.byKey(const ValueKey('top')));
      final bottom = tester.getRect(find.byKey(const ValueKey('bottom')));
      expect(top, const Rect.fromLTWH(0, 0, 600, 400));
      expect(bottom, const Rect.fromLTWH(0, 401, 600, 399));
      final divider = find.bySemanticsLabel('Divider');
      expect(tester.getSize(divider), const Size(600, MMSizes.touchTarget));
      await tester.drag(divider, const Offset(0, 100));
      expect(fraction, greaterThan(.55));
      // The drag clamps to the bottom pane's minimum.
      await tester.drag(divider, const Offset(0, 1000));
      expect(fraction * 800, lessThanOrEqualTo(800 - 1 - 200 + .01));
      fraction = 0;
      await tester.tap(divider);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(divider);
      await tester.pumpAndSettle();
      expect(fraction, .5);
    });

    testWidgets('a pointer gets the thin divider', (tester) async {
      _setWindow(tester, const Size(600, 800));
      await tester.pumpWidget(view(onFraction: (_) {}));
      expect(tester.getSize(find.bySemanticsLabel('Divider')).height, MMSizes.dividerHitWidth);
    });

    testWidgets('mode buttons move to the divider end and to the single pane', (tester) async {
      _setWindow(tester, const Size(600, 800));
      final modes = <MMSplitMode>[];
      await tester.pumpWidget(view(onMode: modes.add));
      await tester.tap(find.byTooltip('Map Only'));
      await tester.tap(find.byTooltip('Source Only'));
      expect(modes, [MMSplitMode.secondary, MMSplitMode.primary]);
      final up = tester.getRect(find.byIcon(MMIcons.chevronUp));
      expect(up.bottom, lessThan(400));
      expect(up.right, greaterThan(500));
      await tester.pumpWidget(view(mode: MMSplitMode.secondary, onMode: modes.add));
      expect(tester.getSize(find.byKey(const ValueKey('bottom'))), const Size(600, 800));
      await tester.tap(find.byTooltip('Split'));
      expect(modes.last, MMSplitMode.split);
    });

    testWidgets('too short for both panes shows the top one', (tester) async {
      _setWindow(tester, const Size(600, 300));
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 600,
            height: 300,
            child: MMSplitView(
              axis: Axis.vertical,
              minPrimaryWidth: 200,
              minSecondaryWidth: 200,
              primary: const SizedBox.expand(key: ValueKey('top')),
              secondary: const SizedBox.expand(key: ValueKey('bottom')),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const ValueKey('top'))), const Size(600, 300));
      expect(find.byKey(const ValueKey('bottom')).hitTestable(), findsNothing);
    });
  });
}
