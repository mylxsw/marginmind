import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('mixed checkbox paints a dash, exposes mixed semantics and selects all on tap', (tester) async {
    bool? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: Scaffold(
          body: MMCheckbox(value: true, mixed: true, semanticLabel: 'Document', onChanged: (value) => selected = value),
        ),
      ),
    );
    expect(find.byIcon(MMIcons.zoomOut), findsOneWidget);
    expect(find.byIcon(MMIcons.check), findsNothing);
    expect(tester.widgetList<Semantics>(find.byType(Semantics)).any((s) => s.properties.mixed == true), isTrue);
    await tester.tap(find.byType(MMCheckbox));
    expect(selected, isTrue);
  });
}
