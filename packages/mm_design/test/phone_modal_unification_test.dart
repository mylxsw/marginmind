import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

Future<void> phone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: MMTheme.light(),
      builder: (_, child) => MMInput(touchPlatform: true, phone: true, child: child!),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  final platforms = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android});
  for (final dark in [false, true]) {
    testWidgets('all modal entry points keep controls and nested menus opaque, dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // A real iPhone host offers native glass. It must never be requested
      // by controls inside the common form surface.
      MMNativePresentation.available = true;
      addTearDown(() => MMNativePresentation.available = false);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? MMTheme.dark() : MMTheme.light(),
          builder: (_, child) => MMInput(touchPlatform: true, phone: true, child: child!),
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const ColoredBox(color: Colors.green, child: SizedBox.expand());
              },
            ),
          ),
        ),
      );
      for (final open in [showMMSheet<void>, showMMDialog<void>, showMMBottomSheet<void>]) {
        final completed = open(
          context: context,
          builder: (_) => MMSheet(
            title: 'Form',
            titleTrailing: MMModalCloseButton(tooltip: 'Close', onPressed: () {}),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MMGlass(child: Text('Preview')),
                const MMLiquidGlass(child: Text('Content')),
                MMSegmentedControl<int>(
                  value: 0,
                  onChanged: (_) {},
                  segments: const [
                    MMSegment(value: 0, label: 'Existing'),
                    MMSegment(value: 1, label: 'New'),
                  ],
                ),
                MMDropdownButton<int>(
                  tooltip: 'Nested menu',
                  onSelected: (_) {},
                  itemBuilder: (_) => const [MMDropdownItem<int>(value: 1, child: Text('Choice'))],
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MMModalSurface), findsOneWidget);
        expect(find.byIcon(MMIcons.close), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(UiKitView), findsNothing);
        final contentContext = tester.element(find.text('Preview'));
        expect(MMFlatSurface.of(contentContext), isTrue);
        expect(contentContext.mmColors.flat, isTrue);
        await tester.tap(find.byTooltip('Nested menu'));
        await tester.pumpAndSettle();
        expect(find.byType(MMModalSurface), findsNWidgets(2));
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(UiKitView), findsNothing);
        await tester.tap(find.text('Choice'));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await completed;
        expect(tester.takeException(), isNull);
      }
    }, variant: platforms);
  }
  testWidgets('floating form protects edits across keyboard, rotation, scrim, drag and Back', (tester) async {
    late BuildContext context;
    final allow = ValueNotifier(false);
    addTearDown(allow.dispose);
    await phone(
      tester,
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox.expand();
        },
      ),
    );
    final result = showMMSheet<void>(
      context: context,
      builder: (_) => ValueListenableBuilder(
        valueListenable: allow,
        builder: (_, canPop, _) => PopScope(
          canPop: canPop,
          child: const MMSheet(
            title: 'Draft',
            child: MMTextField(placeholder: 'Value'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final frame = find.byKey(const ValueKey('mm-bottom-sheet'));
    final medium = tester.getRect(frame);
    expect(medium.left, greaterThan(0));
    expect(medium.right, lessThan(390));
    expect(medium.bottom, lessThanOrEqualTo(844 - 34));
    expect(medium.height, lessThan(844 * .7));
    final input = find.byType(TextField);
    await tester.enterText(input, 'Keep my draft');
    final editor = tester.state(input);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getRect(frame).bottom, lessThanOrEqualTo(844 - 300));
    expect(tester.state(input), same(editor));
    tester.view.physicalSize = const Size(844, 390);
    tester.view.padding = const FakeViewPadding(left: 44, right: 44, bottom: 21);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(tester.state(input), same(editor));
    expect(find.text('Keep my draft'), findsOneWidget);
    expect(tester.getRect(frame).bottom, lessThanOrEqualTo(130));
    expect(tester.getRect(input).bottom, lessThanOrEqualTo(tester.getRect(frame).bottom));
    expect(input.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 60));
    await tester.pumpAndSettle();
    expect(frame, findsOneWidget);
    await tester.fling(find.byKey(const ValueKey('mm-bottom-sheet-handle')), const Offset(0, 600), 1400);
    await tester.pumpAndSettle();
    expect(frame, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(frame, findsOneWidget);
    allow.value = true;
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(frame, findsNothing);
    await result;
  }, variant: platforms);

  testWidgets('phone dropdown keeps submenus in one sheet and Back returns to the parent', (tester) async {
    final events = <String>[];
    await phone(
      tester,
      MMDropdownButton<int>(
        tooltip: 'Options',
        onOpened: () => events.add('open'),
        onClosed: () => events.add('close'),
        onSelected: (value) => events.add('select:$value'),
        itemBuilder: (_) => [
          const MMDropdownItem<int>(value: 1, enabled: false, child: Text('Disabled')),
          const MMDropdownSubmenu<int>(
            label: 'More options',
            entries: [(value: 2, label: 'Second choice', selected: true)],
          ),
        ],
      ),
    );
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsOneWidget);
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(events, ['open']);
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Second choice'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('More options'), findsOneWidget);
    expect(find.text('Second choice'), findsNothing);
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second choice'));
    await tester.pumpAndSettle();
    expect(events, ['open', 'close', 'select:2']);
    expect(find.byKey(const ValueKey('mm-bottom-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: platforms);
}
