import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart' show touchPlatformProvider, phoneProvider;
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/tag_content_pane.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

Finder inSidebar(Finder matching) => find.descendant(of: find.byType(MMSidebar), matching: matching);
Finder tag(String name) => find.byKey(ValueKey('sidebar-tag-$name'));
const expandKey = ValueKey('sidebar-tags-expand');

Future<ProviderContainer> openSidebar(WidgetTester tester, {InMemoryStudySetContentRepository? content}) async {
  final container = await pumpApp(tester, size: const Size(1280, 1400), content: content);
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return container;
}

List<String> sectionTitles(WidgetTester tester) => tester
    .widgetList<MMSidebarSection>(inSidebar(find.byType(MMSidebarSection)))
    .map((section) => section.title)
    .toList();

void main() {
  for (final phone in [false, true]) {
    testWidgets('a tag closes the ${phone ? 'phone' : 'tablet'} drawer and opens its content', (tester) async {
      final container = await pumpApp(
        tester,
        size: phone ? const Size(402, 874) : const Size(834, 1194),
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(phone)],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      await controller.setTags('c3', ['Science']);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show Sidebar').hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(tag('Science').hitTestable());
      await tester.pumpAndSettle();
      expect(tag('Science').hitTestable(), findsNothing);
      expect(find.byType(TagContentPane).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-back-to-map')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Back and Escape restore the same map viewport without moving the reader', (tester) async {
    final container = await openSidebar(tester);
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    await controller.setTags('c3', ['Science']);
    await controller.setTags('c4', ['Science']);
    await tester.pumpAndSettle();
    final transform = tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).transformation;
    transform.value = Matrix4.identity()..translateByDouble(-120, -80, 0, 1);
    await tester.pumpAndSettle();
    final before = transform.value.clone();
    final document = container.read(provider).activeDocumentId;
    final page = controller.content.document(document!)!.lastPage;
    for (final escape in [false, true]) {
      await tester.tap(tag('Science'));
      await tester.pumpAndSettle();
      expect(find.byType(MindMapCanvas), findsNothing);
      expect(find.text('2 related nodes · Current map'), findsOneWidget);
      expect(tester.widget<MMSidebarItem>(find.byKey(const ValueKey('sidebar-map-main'))).selected, isFalse);
      if (escape) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tap(find.byKey(const ValueKey('tag-back-to-map')));
      }
      await tester.pumpAndSettle();
      expect(find.byType(TagContentPane), findsNothing);
      expect(tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).transformation, same(transform));
      expect(transform.value.storage, orderedEquals(before.storage));
      expect(container.read(provider).activeDocumentId, document);
      expect(controller.content.document(document)!.lastPage, page);
    }
  });

  testWidgets('long tags and node paths fit a small window and results remain scrollable', (tester) async {
    var id = 0;
    final editor = StudySetEditor(newId: () => 'long-${id++}', now: () => testNow);
    var content = demoContent();
    const name = 'A long tag name that must wrap without hiding navigation or results';
    final ids = <String>[];
    for (var i = 0; i < 30; i++) {
      final (next, card) = editor.addTopic(content, title: 'Tagged result $i with a long title', parentId: 'c3');
      content = editor.setTags(next, card.id, [name]);
      ids.add(card.id);
    }
    final container = await openSidebar(tester, content: InMemoryStudySetContentRepository({'demo-1': content}));
    tester.view.physicalSize = const Size(800, 600);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.setLayout(MMSplitMode.secondary);
    controller.filterTag(name);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-back-to-map')).hitTestable(), findsOneWidget);
    final last = find.byKey(ValueKey('tag-result-${ids.last}'));
    await tester.scrollUntilVisible(
      last,
      240,
      scrollable: find.descendant(of: find.byType(TagContentPane), matching: find.byType(Scrollable)),
    );
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tag finds summary descendants and result clicks reveal collapsed map branches', (tester) async {
    var nextId = 0;
    final editor = StudySetEditor(newId: () => 'tag-fixture-${nextId++}', now: () => testNow);
    final original = demoContent();
    final excerpt = original.cardForAnnotation(original.annotations.single.id)!;
    final made = editor.createSummary(original, [excerpt.id], label: 'Summary result');
    final summaryId = made.value!.cardId!;
    final (withChild, child) = editor.addTopic(made.content, title: 'Folded parent', parentId: summaryId);
    final (withResult, result) = editor.addTopic(withChild, title: 'Tagged result', parentId: child.id);
    var content = editor.setTags(withResult, result.id, ['test']);
    content = editor.setTags(content, summaryId, ['summary-tag']);
    content = editor.setCollapsed(content, 'c3', collapsed: true);
    content = editor.setCollapsed(content, child.id, collapsed: true);
    final container = await openSidebar(tester, content: InMemoryStudySetContentRepository({'demo-1': content}));
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    controller.setLayout(MMSplitMode.primary);
    await tester.pumpAndSettle();
    await tester.tap(tag('test'));
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('tag-result-${result.id}'));
    expect(row, findsOneWidget);
    expect(inSidebar(find.text('Cards')), findsNothing);
    expect(find.text('Main Map › 遗忘的规律 › Summary result › Folded parent'), findsOneWidget);
    expect(container.read(provider).layout, isNot(MMSplitMode.primary));
    final tick = container.read(provider).locateCardTick;
    await tester.tap(row);
    await settleHud(tester);
    expect(container.read(provider).selectedCardId, result.id);
    expect(container.read(provider).tagFilter, isNull);
    expect(find.byType(TagContentPane), findsNothing);
    expect(container.read(provider).locateCardTick, greaterThan(tick));
    expect(container.read(provider).layout, isNot(MMSplitMode.primary));
    expect(controller.content.node('c3')!.collapsed, isFalse);
    expect(controller.content.node(child.id)!.collapsed, isFalse);

    await tester.tap(tag('summary-tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('tag-result-$summaryId')));
    await settleHud(tester);
    expect(container.read(provider).selectedCardId, summaryId);
    expect(container.read(provider).locateCardTick, greaterThan(tick + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional sections hide when empty and follow documents, maps, notes and learn', (tester) async {
    final container = await openSidebar(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    expect(sectionTitles(tester), ['Documents', 'Mind Maps', 'Notes', 'Learn']);

    await controller.setTags('c3', ['Science']);
    await tester.pumpAndSettle();
    expect(sectionTitles(tester), ['Documents', 'Mind Maps', 'Notes', 'Learn', 'Tags']);
    expect(inSidebar(find.text('All Tags')), findsNothing);
    expect(find.byKey(expandKey), findsNothing);

    await tester.tap(tag('Science'));
    await tester.pumpAndSettle();
    expect(sectionTitles(tester), ['Documents', 'Mind Maps', 'Notes', 'Learn', 'Tags']);
    expect(find.text('1 related node · Current map'), findsOneWidget);
    expect(tester.widget<MMSidebarItem>(tag('Science')).selected, isTrue);

    controller.setSidebarQuery('no such card');
    await tester.pumpAndSettle();
    expect(inSidebar(find.text('Cards')), findsNothing);
    expect(tag('Science'), findsOneWidget);
    controller.setSidebarQuery('');
    await tester.tap(find.byKey(const ValueKey('tag-back-to-map')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).tagFilter, isNull);
    expect(inSidebar(find.text('Cards')), findsNothing);
    expect(find.byType(TagContentPane), findsNothing);

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
    expect(find.text('No nodes with this tag'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-back-to-map')));
    await tester.pumpAndSettle();
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
    await tester.tap(tag('Tag 0'));
    await tester.pumpAndSettle();
    await controller.addMap('Empty map');
    await tester.pumpAndSettle();
    expect(inSidebar(find.text('Tags')), findsNothing);
    expect(inSidebar(find.text('Cards')), findsNothing);
    expect(container.read(workspaceProvider('demo-1')).tagFilter, isNull);
    await controller.selectMap(originalMap);
    await tester.pumpAndSettle();
    expect(tester.widget<MMSidebarItem>(find.byKey(expandKey)).label, 'Expand');
  });
}
