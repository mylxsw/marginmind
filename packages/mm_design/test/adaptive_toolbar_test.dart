import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('measures controls in first frame and invokes overflow commands', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var called = '';
      Widget toolbar(double width) => MaterialApp(
        theme: MMTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 52,
              child: MMAdaptiveToolbar(
                menuLabel: 'Appearance',
                menuIcon: const Text('Aa'),
                items: [
                  for (final (id, priority, label) in [('area', 0, 'Area'), ('select', 10, 'Select')])
                    MMToolbarItem(
                      id: id,
                      priority: priority,
                      child: SizedBox(
                        width: 90,
                        child: TextButton(onPressed: () => called = id, child: Text(label)),
                      ),
                      menuEntry: MMDropdownItem<VoidCallback>(value: () => called = id, child: Text(label)),
                    ),
                ],
                menuEntries: [
                  MMDropdownItem<VoidCallback>(value: () => called = 'settings', child: const Text('Settings')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(toolbar(145));
      expect(tester.takeException(), isNull);
      expect(find.text('Area').hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('Area'), findsNothing);
      expect(find.text('Select').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Area').last);
      await tester.pumpAndSettle();
      expect(called, 'area');
      await tester.pumpWidget(toolbar(60));
      expect(find.text('Select').hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Select').hitTestable(), findsOneWidget);
      await tester.pumpWidget(toolbar(400));
      await tester.pumpAndSettle();
      expect(find.text('Area').hitTestable(), findsOneWidget);
      expect(find.text('Settings'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('labels collapse before commands overflow and restore on resize', (tester) async {
    Widget toolbar(double width) => MaterialApp(
      theme: MMTheme.light(),
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 52,
          child: MMAdaptiveToolbar(
            menuLabel: 'More',
            trailingIds: const {'organize'},
            groups: const [
              {'organize'},
            ],
            items: [
              MMToolbarItem(
                id: 'organize',
                child: SizedBox(
                  width: 150,
                  child: TextButton(onPressed: () {}, child: const Text('Organize Notes')),
                ),
                compactChild: SizedBox(
                  width: 40,
                  child: TextButton(onPressed: () {}, child: const Text('Icon')),
                ),
                menuEntry: MMDropdownItem<VoidCallback>(value: () {}, child: const Text('Organize')),
              ),
              MMToolbarItem(
                id: 'view',
                priority: 10,
                child: SizedBox(
                  width: 60,
                  child: TextButton(onPressed: () {}, child: const Text('View')),
                ),
                menuEntry: MMDropdownItem<VoidCallback>(value: () {}, child: const Text('Change View')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(toolbar(160));
    await tester.pumpAndSettle();
    expect(find.text('Organize Notes').hitTestable(), findsNothing);
    expect(find.text('Icon').hitTestable(), findsOneWidget);
    expect(find.text('View').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(toolbar(400));
    await tester.pumpAndSettle();
    expect(find.text('Organize Notes').hitTestable(), findsOneWidget);
    expect(find.text('Icon').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog captures the flat material from its originating pane', (tester) async {
    var flat = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MMFlatSurface(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMMDialog<void>(
                  context: context,
                  builder: (context) {
                    flat = MMFlatSurface.of(context);
                    return const MMGlass(child: Text('Dialog'));
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(flat, isTrue);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('flat surfaces have opaque fills and no backdrop or shadows', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? MMTheme.dark() : MMTheme.light(),
          home: Scaffold(
            body: MMFlatSurface(
              child: Column(
                children: [
                  const MMGlass(child: Text('Surface')),
                  const MMLiquidGlass(child: Text('Liquid')),
                  const MMGlassBar(child: Text('Bar')),
                  MMSegmentedControl<int>(
                    segments: const [
                      MMSegment(value: 0, label: 'Map'),
                      MMSegment(value: 1, label: 'Outline'),
                    ],
                    value: 0,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
        if (box.decoration case final BoxDecoration decoration) {
          expect(decoration.boxShadow, anyOf(isNull, isEmpty));
          expect(decoration.gradient, isNull);
        }
      }
    }
  });
  test('shared geometry constrains both panes and preserves narrow layouts', () {
    final split = MMSplitView.resolveGeometry(extent: 1000, mode: MMSplitMode.split, fraction: .7);
    expect(split.primaryExtent + split.secondaryExtent + split.dividerExtent, 1000);
    expect(split.secondaryExtent, greaterThanOrEqualTo(MMSizes.mapMinWidth));
    expect(MMSplitView.resolveGeometry(extent: 200, mode: MMSplitMode.split).effectiveMode, MMSplitMode.primary);
    final narrow = MMSplitView.resolveGeometry(extent: 200, mode: MMSplitMode.split, collapseWhenNarrow: false);
    expect(narrow.primaryExtent + narrow.secondaryExtent + narrow.dividerExtent, 200);
  });
}
