import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/library/widgets/study_set_cover.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  testWidgets('library shows continue learning and all study sets', (tester) async {
    await pumpApp(tester);
    expect(find.text('All Study Sets'), findsNWidgets(2)); // toolbar title + sidebar
    expect(find.text('Continue Learning'), findsOneWidget);
    expect(find.text('产品设计方法论'), findsWidgets);
    expect(find.textContaining('6 study sets'), findsOneWidget);
    // Grid covers fill their cell (regression: covers collapsed to 0 width).
    final covers = find.byType(StudySetCover);
    expect(tester.getSize(covers.last).width, greaterThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar filters and search narrow the grid', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 study sets'), findsOneWidget);
    expect(find.text('Continue Learning'), findsNothing);
    expect(find.text('注意力与专注'), findsNothing);

    await tester.tap(find.text('All Study Sets').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '投资');
    await tester.pumpAndSettle();
    expect(find.textContaining('1 study set'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching study sets'), findsOneWidget);
  });

  testWidgets('list view shows a sortable table', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(MMIcons.list));
    await tester.pumpAndSettle();
    expect(find.text('Folder'), findsOneWidget);
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(find.text('论文文献综述')).dy;
    final second = tester.getTopLeft(find.text('产品设计方法论')).dy;
    expect(first, lessThan(second)); // 214 cards before 128
  });

  testWidgets('new study set sheet creates and selects a set', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(MMIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('New Study Set'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, '认知心理学');
    await tester.tap(find.text('Import PDFs after creating…'));
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Created “认知心理学”'), findsOneWidget);
    expect(find.text('认知心理学'), findsWidgets);
    await settleHud(tester);
  });

  testWidgets('clicking a study set selects it and Return opens it', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('交互设计原则笔记'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Mind Maps'), findsOneWidget);
  });

  testWidgets('first run shows the drop zone', (tester) async {
    await pumpApp(tester, sets: const []);
    expect(find.text('Start your first study set'), findsOneWidget);
    expect(find.text('Open Sample Study Set'), findsOneWidget);
  });

  testWidgets('language and appearance settings apply to the whole app', (tester) async {
    await pumpApp(tester, prefs: {'settings.language': 'zh', 'settings.appearance': 'dark'});
    expect(find.text('全部学习集'), findsWidgets);
    expect(find.text('继续学习'), findsOneWidget);
    final context = tester.element(find.text('继续学习'));
    expect(context.mmColors.brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
