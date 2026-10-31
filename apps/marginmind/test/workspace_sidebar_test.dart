import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

Finder inSidebar(Finder matching) => find.descendant(of: find.byType(MMSidebar), matching: matching);
Finder tag(String name) => find.byKey(ValueKey('sidebar-tag-$name'));
const allTagsKey = ValueKey('sidebar-all-tags');
const expandKey = ValueKey('sidebar-tags-expand');

Future<ProviderContainer> openSidebar(WidgetTester tester) async {
  final container = await pumpApp(tester, size: const Size(1280, 1400));
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return container;
}

List<String> sectionTitles(WidgetTester tester) => tester
    .widgetList<MMSidebarSection>(inSidebar(find.byType(MMSidebarSection)))
    .map((section) => section.title)
    .toList();

void main() {
  testWidgets('optional sections hide when empty and follow documents, maps, notes and learn', (tester) async {
    final container = await openSidebar(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    expect(sectionTitles(tester), ['Documents', 'Mind Maps', 'Notes', 'Learn']);

    await controller.setTags('c3', ['Science']);
    await tester.pumpAndSettle();
    expect(sectionTitles(tester), ['Documents', 'Mind Maps', 'Notes', 'Learn', 'Tags']);
    expect(tester.widget<MMSidebarItem>(find.byKey(allTagsKey)).selected, isTrue);
    expect(find.byKey(expandKey), findsNothing);

    await tester.tap(tag('Science'));
    await tester.pumpAndSettle();
    expect(sectionTitles(tester), ['Documents', 'Mind Maps', 'Notes', 'Learn', 'Cards', 'Tags']);
    expect(tester.widget<MMSidebarItem>(find.byKey(allTagsKey)).selected, isFalse);
    expect(tester.widget<MMSidebarItem>(tag('Science')).selected, isTrue);

    controller.setSidebarQuery('no such card');
    await tester.pumpAndSettle();
    expect(inSidebar(find.text('Cards')), findsNothing);
    expect(tag('Science'), findsOneWidget);
    controller.setSidebarQuery('');
    await tester.tap(find.byKey(allTagsKey));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).tagFilter, isNull);
    expect(inSidebar(find.text('Cards')), findsNothing);

    await controller.setTags('c3', []);
    await tester.pumpAndSettle();
    expect(sectionTitles(tester), ['Documents', 'Mind Maps', 'Notes', 'Learn']);
  });

  testWidgets('ten tags fit the preview; expand and collapse retain the active filter', (tester) async {
    final container = await openSidebar(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final names = [for (var i = 1; i <= 12; i++) 'Tag ${i.toString().padLeft(2, '0')}'];
    await controller.setTags('c3', names.take(10).toList());
    await tester.pumpAndSettle();
    expect(find.byKey(expandKey), findsNothing);
    await controller.setTags('c3', names);
    await tester.pumpAndSettle();
    expect(tag(names[9]), findsOneWidget);
    expect(tag(names[10]), findsNothing);
    expect(tag(names[11]), findsNothing);
    expect(find.descendant(of: find.byKey(expandKey), matching: find.text('2')), findsOneWidget);

    await tester.tap(find.byKey(expandKey));
    await tester.pumpAndSettle();
    expect(tag(names[11]), findsOneWidget);
    await tester.tap(tag(names[11]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(expandKey));
    await tester.pumpAndSettle();
    expect(tester.widget<MMSidebarItem>(tag(names[11])).selected, isTrue);
    expect(names.where((name) => tag(name).evaluate().isNotEmpty), hasLength(10));
    expect(container.read(workspaceProvider('demo-1')).tagFilter, names[11]);

    controller.setSidebarQuery('Tag 11');
    await tester.pumpAndSettle();
    expect(tag(names[10]), findsOneWidget);
    expect(tag(names[11]), findsOneWidget);
    expect(find.byKey(expandKey), findsNothing);

    controller.setSidebarQuery('');
    await controller.setTags('c3', []);
    await tester.pumpAndSettle();
    expect(inSidebar(find.text('Tags')), findsNothing);
    expect(inSidebar(find.text('Cards')), findsNothing);
    controller.setSidebarQuery('遗忘');
    await tester.pumpAndSettle();
    expect(inSidebar(find.text('遗忘的规律')), findsOneWidget, reason: 'deleted tags cannot trap card search');
  });

  testWidgets('changing maps hides empty optional sections and resets the tag preview', (tester) async {
    final container = await openSidebar(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final originalMap = container.read(workspaceProvider('demo-1')).activeMapId;
    await controller.setTags('c3', [for (var i = 0; i < 11; i++) 'Tag $i']);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(expandKey));
    await tester.pumpAndSettle();
    await controller.addMap('Empty map');
    await tester.pumpAndSettle();
    expect(inSidebar(find.text('Tags')), findsNothing);
    expect(inSidebar(find.text('Cards')), findsNothing);
    await controller.selectMap(originalMap);
    await tester.pumpAndSettle();
    expect(tester.widget<MMSidebarItem>(find.byKey(expandKey)).label, 'Expand');
  });
}
