import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  testWidgets('gallery floating toolbar follows the dragged selection and picks colors', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).showGallery();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controls'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(MMFloatingToolbar), 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();

    final selection = find.byKey(const ValueKey('gallery-selection'));
    Rect toolbarRect() => tester.getRect(find.byType(MMFloatingToolbar));
    final before = toolbarRect();
    expect(before.bottom, lessThan(tester.getRect(selection).top));

    // Drag the selection to the top edge: the toolbar flips below it.
    await tester.drag(selection, const Offset(300, -200));
    await tester.pumpAndSettle();
    final after = toolbarRect();
    expect(after.top, greaterThan(tester.getRect(selection).bottom));
    expect(after.center.dx, greaterThan(before.center.dx));

    expect(tester.widget<MMFloatingToolbarColor>(find.byType(MMFloatingToolbarColor).at(1)).tooltip, 'Green');
    await tester.tap(find.byType(MMFloatingToolbarColor).at(1));
    await tester.pumpAndSettle();
    final ring = tester
        .widgetList<Container>(
          find.descendant(of: find.byType(MMFloatingToolbarColor).at(1), matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.shape == BoxShape.circle);
    expect(ring.boxShadow, isNotNull);
  });
}
