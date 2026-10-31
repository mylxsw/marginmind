import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

/// A window of [size] with status bar and home indicator insets, on a
/// touch platform unless [touch] is false.
Future<void> _window(
  WidgetTester tester,
  Widget child, {
  bool touch = true,
  bool reduceTransparency = false,
  Brightness brightness = Brightness.light,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 40, bottom: 30);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? MMTheme.light() : MMTheme.dark(),
      builder: (context, child) => MMInput(
        touchPlatform: touch,
        phone: true,
        child: MMAppearance(reduceTransparency: reduceTransparency, child: child!),
      ),
      home: Material(child: child),
    ),
  );
}

List<BackdropFilter> _backdrops(WidgetTester tester) =>
    tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).toList();

void main() {
  group('glass material', () {
    testWidgets('a pointer platform keeps the plain blur', (tester) async {
      await _window(tester, const Center(child: MMGlass(child: Text('glass'))), touch: false);
      expect(find.byType(MMLiquidGlass), findsNothing);
      expect(_backdrops(tester).single.filter, ImageFilter.blur(sigmaX: 24, sigmaY: 24));
    });

    for (final brightness in Brightness.values) {
      testWidgets('a touch platform raises saturation under the blur and adds a rim (${brightness.name})', (
        tester,
      ) async {
        await _window(
          tester,
          const Center(child: MMLiquidGlass(child: Text('glass'))),
          brightness: brightness,
        );
        expect(find.byType(MMLiquidGlass), findsOneWidget);
        expect(_backdrops(tester).single.filter, MMLiquidGlass.liquidFilter(24));
        final rim = tester
            .widgetList<CustomPaint>(
              find.descendant(of: find.byType(MMLiquidGlass), matching: find.byType(CustomPaint)),
            )
            .where((p) => p.foregroundPainter != null);
        expect(rim, hasLength(1));
        expect(rim.single.foregroundPainter!.shouldRepaint(rim.single.foregroundPainter!), isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('glass on glass blurs the backdrop once', (tester) async {
      await _window(
        tester,
        const Center(
          child: MMLiquidGlass(
            padding: EdgeInsets.all(8),
            child: MMLiquidGlass(child: Text('inner')),
          ),
        ),
      );
      expect(find.byType(MMLiquidGlass), findsNWidgets(2));
      expect(_backdrops(tester), hasLength(1));

      await _window(tester, const MMGlassBar(child: MMToolbarGroup(children: [Text('group')])));
      expect(_backdrops(tester), hasLength(1));
      expect(find.byKey(const ValueKey('mm-glass-bar')), findsOneWidget);
    });

    testWidgets('a zero blur only tints', (tester) async {
      await _window(tester, const Center(child: MMLiquidGlass(blurSigma: 0, child: Text('badge'))));
      expect(_backdrops(tester), isEmpty);
      await _window(tester, const MMGlassBar(blurSigma: 0, child: Text('bar')));
      expect(_backdrops(tester), isEmpty);
    });

    testWidgets('Reduce transparency falls back to opaque fills', (tester) async {
      await _window(
        tester,
        const Column(
          children: [
            MMGlassBar(child: Text('bar')),
            MMLiquidGlass(child: Text('glass')),
          ],
        ),
        reduceTransparency: true,
      );
      expect(_backdrops(tester), isEmpty);
      final c = tester.element(find.text('glass')).mmColors;
      final fills = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: find.byType(MMLiquidGlass), matching: find.byType(DecoratedBox)),
          )
          .map((d) => (d.decoration as BoxDecoration).color)
          .nonNulls;
      expect(fills, contains(c.glassOpaque));
      final bar = tester.widget<DecoratedBox>(find.byKey(const ValueKey('mm-glass-bar')));
      expect((bar.decoration as BoxDecoration).color, c.windowBackground);
    });

    test('saturation keeps grays gray and leaves alpha alone', () {
      final m = MMLiquidGlass.saturationMatrix(MMLiquidGlass.saturation);
      for (var row = 0; row < 3; row++) {
        expect(m[row * 5] + m[row * 5 + 1] + m[row * 5 + 2], closeTo(1, 1e-9));
      }
      expect(m.sublist(15), [0, 0, 0, 1, 0]);
      final identity = MMLiquidGlass.saturationMatrix(1);
      for (var i = 0; i < 20; i++) {
        expect(identity[i], closeTo(i % 6 == 0 ? 1 : 0, 1e-9), reason: 'entry $i');
      }
    });
  });

  group('floating tab bar', () {
    Widget bar(int? selected, ValueChanged<int> onSelected) => Align(
      alignment: Alignment.bottomCenter,
      child: MMTabBar(
        selected: selected,
        onSelected: onSelected,
        tabs: const [
          MMTab(icon: MMIcons.library, label: 'Library'),
          MMTab(icon: MMIcons.reading, label: 'Source'),
          MMTab(icon: MMIcons.mindMap, label: 'Map'),
          MMTab(icon: MMIcons.review, label: 'Review'),
        ],
      ),
    );

    testWidgets('the highlight slides to the selected tab and hides without one', (tester) async {
      await _window(tester, bar(1, (_) {}));
      final highlight = find.byKey(const ValueKey('mm-tab-highlight'));
      expect(
        tester.getRect(highlight).center.dx,
        closeTo(tester.getRect(find.byKey(const ValueKey('mm-tab-1'))).center.dx, 0.01),
      );

      await _window(tester, bar(3, (_) {}));
      await tester.pump(const Duration(milliseconds: 50));
      final moving = tester.getRect(highlight).center.dx;
      await tester.pumpAndSettle();
      final target = tester.getRect(find.byKey(const ValueKey('mm-tab-3'))).center.dx;
      expect(tester.getRect(highlight).center.dx, closeTo(target, 0.01));
      expect(moving, lessThan(target), reason: 'slides rather than jumps');

      await _window(tester, bar(null, (_) {}));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(find.descendant(of: highlight, matching: find.byType(AnimatedOpacity))).opacity,
        0,
      );
    });

    testWidgets('a pressed tab swells, and settles back on release', (tester) async {
      final taps = <int>[];
      await _window(tester, bar(0, taps.add));
      double scale() => tester
          .widget<AnimatedScale>(
            find.descendant(of: find.byKey(const ValueKey('mm-tab-2')), matching: find.byType(AnimatedScale)),
          )
          .scale;
      expect(scale(), 1);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('mm-tab-2'))));
      await tester.pump();
      expect(scale(), greaterThan(1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scale(), 1);
      expect(taps, [2]);
    });

    testWidgets('without a home indicator the capsule keeps a gap to the edge', (tester) async {
      await _window(tester, bar(0, (_) {}));
      tester.view.padding = FakeViewPadding.zero;
      await tester.pump();
      final capsule = tester.getRect(find.byKey(const ValueKey('mm-tab-bar-glass')));
      expect(capsule.bottom, 800 - MMSizes.tabBarBottomGap);
      expect(MMTabBar.heightOf(tester.element(find.byType(MMTabBar))), capsule.height + MMSizes.tabBarBottomGap);
    });
  });

  group('touch window chrome', () {
    late BuildContext body;
    Widget scaffold({
      bool extend = true,
      bool sidebar = false,
      bool overlay = true,
      VoidCallback? onDismiss,
      PreferredSizeWidget? toolbarBottom,
      Widget? bar = const SizedBox(key: ValueKey('bar'), height: 90),
    }) => MMWindowBottomBar(
      bar: bar,
      extent: bar == null ? 0 : 90,
      child: MMWindowScaffold(
        extendBody: extend,
        toolbar: const SizedBox(key: ValueKey('toolbar'), height: MMSizes.toolbarHeight),
        toolbarBottom: toolbarBottom,
        sidebar: sidebar ? const SizedBox.expand(key: ValueKey('sidebar')) : null,
        sidebarOverlay: overlay,
        onSidebarDismiss: onDismiss,
        body: Builder(
          builder: (context) {
            body = context;
            return const SizedBox.expand(key: ValueKey('body'));
          },
        ),
      ),
    );

    testWidgets('an extended body fills the window beneath the glass toolbar and the floating bar', (tester) async {
      await _window(tester, scaffold());
      expect(tester.getRect(find.byKey(const ValueKey('body'))), const Rect.fromLTWH(0, 0, 400, 800));
      expect(MMChromeInsets.of(body), const EdgeInsets.only(top: 40 + MMSizes.toolbarHeight, bottom: 90));
      expect(MediaQuery.paddingOf(body), EdgeInsets.zero);
      // The glass reaches behind the status bar; the toolbar sits below it.
      expect(
        tester.getRect(find.byKey(const ValueKey('mm-glass-bar'))),
        const Rect.fromLTWH(0, 0, 400, 40 + MMSizes.toolbarHeight),
      );
      expect(tester.getRect(find.byKey(const ValueKey('toolbar'))).top, 40);
      expect(tester.getRect(find.byKey(const ValueKey('bar'))).bottom, 800);

      // The soft keyboard hides the bar; the body ends on the keyboard.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(find.byKey(const ValueKey('bar')), findsNothing);
      expect(MMChromeInsets.of(body).bottom, 0);
      expect(tester.getRect(find.byKey(const ValueKey('body'))).bottom, 500);
    });

    testWidgets('a strip below the toolbar shares its glass and deepens the inset', (tester) async {
      await _window(
        tester,
        scaffold(
          bar: null,
          toolbarBottom: const PreferredSize(
            preferredSize: Size.fromHeight(44),
            child: SizedBox(key: ValueKey('strip'), height: 44),
          ),
        ),
      );
      expect(tester.getRect(find.byKey(const ValueKey('strip'))).top, 40 + MMSizes.toolbarHeight);
      expect(tester.getRect(find.byKey(const ValueKey('mm-glass-bar'))).bottom, 40 + MMSizes.toolbarHeight + 44);
      // Without a bar the body keeps clear of the home indicator.
      expect(MMChromeInsets.of(body), const EdgeInsets.only(top: 40 + MMSizes.toolbarHeight + 44, bottom: 30));
    });

    testWidgets('a body that does not extend sits between the bars', (tester) async {
      await _window(tester, scaffold(extend: false));
      expect(
        tester.getRect(find.byKey(const ValueKey('body'))),
        const Rect.fromLTRB(0, 40 + MMSizes.toolbarHeight, 400, 800 - 90),
      );
      expect(MMChromeInsets.of(body), EdgeInsets.zero);
    });

    testWidgets('the drawer and its scrim cover the floating bar', (tester) async {
      var dismissed = 0;
      await _window(tester, scaffold(sidebar: true, onDismiss: () => dismissed++));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('bar'))).translate(150, 0));
      expect(dismissed, 1);
      expect(tester.getRect(find.byKey(const ValueKey('sidebar'))).top, 40);
    });

    testWidgets('an inline sidebar takes the leading inset and stays inside the safe area', (tester) async {
      tester.view.padding = const FakeViewPadding(left: 20, top: 40, bottom: 30);
      await _window(tester, scaffold(sidebar: true, overlay: false), size: const Size(900, 600));
      tester.view.padding = const FakeViewPadding(left: 20, top: 40, bottom: 30);
      await tester.pumpAndSettle();
      final sidebar = tester.getRect(find.byKey(const ValueKey('sidebar')));
      expect(sidebar.left, 20);
      expect(sidebar.top, 40);
      expect(tester.getRect(find.byKey(const ValueKey('body'))).left, sidebar.right);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pointer window keeps its column and ignores extendBody', (tester) async {
      await _window(
        tester,
        scaffold(
          toolbarBottom: const PreferredSize(preferredSize: Size.fromHeight(44), child: SizedBox(height: 44)),
          bar: null,
        ),
        touch: false,
        size: const Size(1300, 900),
      );
      expect(find.byKey(const ValueKey('mm-glass-bar')), findsNothing);
      expect(find.byType(MMLiquidGlass), findsNothing);
      expect(MMChromeInsets.of(body), EdgeInsets.zero);
      // Toolbar, strip, then the body, all inside the safe area.
      final toolbar = tester.getRect(find.byKey(const ValueKey('toolbar')));
      expect(tester.getRect(find.byKey(const ValueKey('body'))).top, toolbar.bottom + 44);
    });

    testWidgets('stacked panes each keep the inset of the end they reach', (tester) async {
      late BuildContext top;
      late BuildContext bottom;
      await _window(
        tester,
        MMChromeInsets(
          insets: const EdgeInsets.only(top: 96, bottom: 90),
          child: MMSplitView(
            mode: MMSplitMode.split,
            axis: Axis.vertical,
            primary: Builder(
              builder: (context) {
                top = context;
                return const SizedBox.expand();
              },
            ),
            secondary: Builder(
              builder: (context) {
                bottom = context;
                return const SizedBox.expand();
              },
            ),
            minPrimaryWidth: 100,
            minSecondaryWidth: 100,
          ),
        ),
      );
      expect(MMChromeInsets.of(top), const EdgeInsets.only(top: 96));
      expect(MMChromeInsets.of(bottom), const EdgeInsets.only(bottom: 90));
    });
  });

  group('sheets', () {
    testWidgets('phone and pointer bottom sheets use opaque surfaces', (tester) async {
      const sheet = Stack(
        children: [Positioned.fill(child: MMBottomSheet(child: SizedBox(height: 120)))],
      );
      await _window(tester, sheet);
      expect(
        find.ancestor(of: find.byKey(const ValueKey('mm-bottom-sheet')), matching: find.byType(MMLiquidGlass)),
        findsNothing,
      );
      expect(tester.widget(find.byKey(const ValueKey('mm-bottom-sheet'))), isA<DecoratedBox>());
      expect(_backdrops(tester), isEmpty);

      await _window(tester, sheet, touch: false);
      expect(tester.widget(find.byKey(const ValueKey('mm-bottom-sheet'))), isA<DecoratedBox>());
      expect(_backdrops(tester), isEmpty);
    });

    testWidgets('a touch action sheet uses the shared opaque material', (tester) async {
      late BuildContext context;
      await _window(
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
      await tester.tapAt(const Offset(200, 400));
      await tester.pump();
      showMMMenu(context, position: const Offset(10, 10), entries: [MMMenuItem('Rename', () {})]);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const ValueKey('mm-action-sheet')), matching: find.byType(MMLiquidGlass)),
        findsNothing,
      );
    });
  });
}
