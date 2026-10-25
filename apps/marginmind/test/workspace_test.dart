import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

Future<void> openFirstSet(WidgetTester tester) async {
  await pumpApp(tester);
  await tester.tap(find.text('Starred'));
  await tester.pumpAndSettle();
  await doubleTap(tester, find.text('认知科学入门'));
}

void main() {
  testWidgets('double-clicking a study set opens its workspace', (tester) async {
    await openFirstSet(tester);
    expect(find.text('Mind Maps'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('学习的底层逻辑'), findsWidgets);
    expect(find.text('Your excerpts will appear here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout buttons switch panes and keep them mounted', (tester) async {
    await openFirstSet(tester);
    expect(find.byType(ReaderPane), findsOneWidget);
    await tester.tap(find.byIcon(MMIcons.layoutMap));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPane), findsNothing);
    expect(find.byType(ReaderPane, skipOffstage: false), findsOneWidget);
    await tester.tap(find.byIcon(MMIcons.layoutSplit));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPane), findsOneWidget);
  });

  testWidgets('sidebar search filters sections and documents open as tabs', (tester) async {
    await openFirstSet(tester);
    final search = find.byType(TextField).first;
    await tester.enterText(search, '论文');
    await tester.pumpAndSettle();
    expect(find.text('Mind Maps'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(MMSidebar), matching: find.text('论文：检索练习效应')));
    await tester.pumpAndSettle();
    expect(find.text('论文：检索练习效应'), findsWidgets); // sidebar, tab and toolbar title

    await tester.enterText(search, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('sidebar hides and the library is one click away', (tester) async {
    await openFirstSet(tester);
    await tester.tap(find.byIcon(MMIcons.sidebar).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Mind Maps').hitTestable(), findsNothing);
    await tester.tap(find.byIcon(MMIcons.sidebar).hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(MMIcons.library));
    await tester.pumpAndSettle();
    expect(find.text('All Study Sets'), findsWidgets);
  });
}
