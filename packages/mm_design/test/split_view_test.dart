import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  test('split falls back to the primary pane when too narrow', () {
    expect(MMSplitView.effectiveMode(MMSplitMode.split, 700, 420, 360), MMSplitMode.primary);
    expect(MMSplitView.effectiveMode(MMSplitMode.split, 900, 420, 360), MMSplitMode.split);
    expect(MMSplitView.effectiveMode(MMSplitMode.secondary, 300, 420, 360), MMSplitMode.secondary);
  });

  group('resolveNarrow', () {
    ({bool sidebarVisible, MMSplitMode mode}) resolve(MMSplitMode mode, double width, {bool sidebar = true}) =>
        MMSplitView.resolveNarrow(mode: mode, sidebarVisible: sidebar, windowWidth: width, sidebarWidth: 244);

    test('keeps everything when it fits', () {
      expect(resolve(MMSplitMode.split, 1100), (sidebarVisible: true, mode: MMSplitMode.split));
    });

    test('collapses the sidebar before leaving split', () {
      expect(resolve(MMSplitMode.split, 900), (sidebarVisible: false, mode: MMSplitMode.split));
    });

    test('falls back to the reader once even the panes alone do not fit', () {
      expect(resolve(MMSplitMode.split, 700), (sidebarVisible: true, mode: MMSplitMode.primary));
      expect(resolve(MMSplitMode.split, 700, sidebar: false), (sidebarVisible: false, mode: MMSplitMode.primary));
    });

    test('single-pane layouts are left alone', () {
      expect(resolve(MMSplitMode.secondary, 500), (sidebarVisible: true, mode: MMSplitMode.secondary));
      expect(resolve(MMSplitMode.primary, 500), (sidebarVisible: true, mode: MMSplitMode.primary));
    });
  });

  test('primary width respects both minimums', () {
    expect(MMSplitView.primaryWidth(1000, 0.5, 420, 360), 500);
    expect(MMSplitView.primaryWidth(1000, 0.1, 420, 360), 420);
    expect(MMSplitView.primaryWidth(1000, 0.9, 420, 360), 1000 - 1 - 360);
  });

  testWidgets('dragging the divider reports a new fraction; double-click resets', (tester) async {
    double fraction = 0.5;
    await tester.pumpWidget(
      harness(
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 1000,
            height: 400,
            child: MMSplitView(
              fraction: fraction,
              onFractionChanged: (v) => setState(() => fraction = v),
              primary: const Text('A'),
              secondary: const Text('B'),
            ),
          ),
        ),
      ),
    );
    final divider = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
    expect(divider, findsOneWidget);
    await tester.drag(divider, const Offset(100, 0));
    await tester.pump();
    expect(fraction, greaterThan(0.53));
    expect(fraction, lessThanOrEqualTo(0.6));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(divider);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(divider);
    await tester.pumpAndSettle();
    expect(fraction, 0.5);
  });

  testWidgets('hidden panes stay mounted so their state survives', (tester) async {
    Widget build(MMSplitMode mode) => harness(
      SizedBox(
        width: 1000,
        height: 400,
        child: MMSplitView(
          mode: mode,
          primary: const _Counter(key: ValueKey('p')),
          secondary: const Text('B'),
        ),
      ),
    );
    await tester.pumpWidget(build(MMSplitMode.split));
    await tester.tap(find.byKey(const ValueKey('p')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(build(MMSplitMode.secondary));
    expect(find.text('1'), findsNothing); // offstage
    await tester.pumpWidget(build(MMSplitMode.split));
    expect(find.text('1'), findsOneWidget);
  });

  for (final axis in Axis.values) {
    testWidgets('hidden panes retain usable dimensions in $axis layouts', (tester) async {
      for (final mode in [MMSplitMode.split, MMSplitMode.secondary, MMSplitMode.primary, MMSplitMode.split]) {
        await tester.pumpWidget(
          harness(
            SizedBox(
              width: 700,
              height: 500,
              child: MMSplitView(
                mode: mode,
                axis: axis,
                minPrimaryWidth: 150,
                minSecondaryWidth: 150,
                primary: const SizedBox.expand(key: ValueKey('reader-viewport')),
                secondary: const SizedBox.expand(key: ValueKey('map-viewport')),
              ),
            ),
          ),
        );
        for (final key in ['reader-viewport', 'map-viewport']) {
          final size = tester.getSize(find.byKey(ValueKey(key), skipOffstage: false));
          expect(size.width, greaterThan(0), reason: '$mode $key');
          expect(size.height, greaterThan(0), reason: '$mode $key');
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(onTap: () => setState(() => n++), child: Text('$n'));
}
