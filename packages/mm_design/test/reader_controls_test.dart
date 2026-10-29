import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('line-spacing previews retain accessible labels and segment actions', (tester) async {
    final semantics = tester.ensureSemantics();
    var selected = 1;
    Widget panel(ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: MMReaderLayout.settingsWidth,
            child: MMSegmentedControl<int>(
              value: selected,
              expand: true,
              segments: const [
                MMSegment(value: 0, label: 'Tight', child: MMReaderLineSpacing(index: 0)),
                MMSegment(value: 1, label: 'Normal', child: MMReaderLineSpacing(index: 1)),
                MMSegment(value: 2, label: 'Loose', child: MMReaderLineSpacing(index: 2)),
              ],
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(panel(MMTheme.light()));
    expect(find.byType(MMReaderLineSpacing), findsNWidgets(3));
    expect(find.bySemanticsLabel(RegExp('Loose')), findsWidgets);
    await tester.tap(find.byType(MMReaderLineSpacing).last);
    await tester.pumpAndSettle();
    expect(selected, 2);
    await tester.pumpWidget(panel(MMTheme.dark()));
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
