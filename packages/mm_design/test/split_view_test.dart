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
