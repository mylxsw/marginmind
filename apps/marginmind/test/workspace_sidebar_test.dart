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
Future<ProviderContainer> openSidebar(WidgetTester tester, {InMemoryStudySetContentRepository? content}) async {
  final c = await pumpApp(tester, size: const Size(1280, 1400), content: content);
  c.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return c;
}

Future<void> openTag(WidgetTester tester, String value) async {
  await tester.tap(find.byKey(const ValueKey('sidebar-tags')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('tag-filter-$value')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sidebar controls align with the titlebar and Home returns to the library', (tester) async {
    final c = await openSidebar(tester);
    final home = find.byKey(const ValueKey('workspace-home')).hitTestable();
    final hide = find.byKey(const ValueKey('workspace-hide-sidebar')).hitTestable();
    expect(inSidebar(find.text('认知科学入门')), findsNothing);
    expect(tester.getCenter(home).dy, 26);
    expect(tester.getCenter(hide).dy, 26);
    expect(tester.getCenter(home).dx, lessThan(tester.getCenter(hide).dx));
    await tester.tap(hide);
    await tester.pumpAndSettle();
    final show = find.byKey(const ValueKey('workspace-show-sidebar')).hitTestable();
    expect(tester.getCenter(show).dy, 26);
    expect(tester.getSize(find.byKey(const ValueKey('workspace-tab-row'))).height, 52);
    await tester.tap(show);
    await tester.pumpAndSettle();
    await tester.tap(home);
    await tester.pumpAndSettle();
    expect(c.read(navigationProvider), isA<LibraryRoute>());
    expect(tester.takeException(), isNull);
  });

  for (final phone in [false, true]) {
    testWidgets('tags close the ${phone ? 'phone' : 'tablet'} directory and display on the right', (tester) async {
      final c = await pumpApp(
        tester,
        size: phone ? const Size(402, 874) : const Size(834, 1194),
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(phone)],
      );
      c.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final owner = c.read(workspaceProvider('demo-1').notifier);
      await owner.setTags('c3', ['Science']);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show Sidebar').hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sidebar-tags')).hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar-tags')).hitTestable(), findsNothing);
      expect(find.byType(TagContentPane).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag-filter-Science')));
      await tester.pumpAndSettle();
      expect(c.read(workspaceProvider('demo-1')).tagFilter, 'Science');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('closing tags leaves the same map viewport and reader location', (tester) async {
    final c = await openSidebar(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    await owner.setTags('c3', ['Science']);
    await owner.setTags('c4', ['Science']);
    await tester.pumpAndSettle();
    final transform = tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).transformation;
    transform.value = Matrix4.identity()..translateByDouble(-120, -80, 0, 1);
    await tester.pumpAndSettle();
    final before = transform.value.clone();
    final document = c.read(workspaceProvider('demo-1')).activeDocumentId;
    for (final escape in [false, true]) {
      await openTag(tester, 'Science');
      expect(find.byType(MindMapCanvas), findsOneWidget);
      expect(find.text('2 matching topics'), findsOneWidget);
      if (escape) {
        // Give the right content region focus before its Escape command.
        await tester.tap(find.text('2 matching topics'));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        owner.closePanel();
      }
      await tester.pumpAndSettle();
      expect(find.byType(TagContentPane), findsNothing);
      expect(tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).transformation, same(transform));
      expect(transform.value.storage, orderedEquals(before.storage));
      expect(c.read(workspaceProvider('demo-1')).activeDocumentId, document);
    }
  });
  testWidgets('long tags and result titles fit and remain scrollable', (tester) async {
    var n = 0;
    final editor = StudySetEditor(newId: () => 'long-${n++}', now: () => testNow);
    var data = demoContent();
    const value = 'A long tag name that must wrap without hiding navigation or results';
    final ids = <String>[];
    for (var i = 0; i < 30; i++) {
      final (next, card) = editor.addTopic(data, title: 'Tagged result $i with a long title', parentId: 'c3');
      data = editor.setTags(next, card.id, [value]);
      ids.add(card.id);
    }
    final c = await openSidebar(tester, content: InMemoryStudySetContentRepository({'demo-1': data}));
    tester.view.physicalSize = const Size(800, 600);
    c.read(workspaceProvider('demo-1').notifier).filterTag(value);
    await tester.pumpAndSettle();
    final last = find.byKey(ValueKey('tag-result-main-${ids.last}'));
    await tester.scrollUntilVisible(
      last,
      240,
      scrollable: find.descendant(of: find.byType(TagContentPane), matching: find.byType(Scrollable)),
    );
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('tag result focuses summary descendants and expands collapsed ancestors', (tester) async {
    var n = 0;
    final editor = StudySetEditor(newId: () => 'tag-${n++}', now: () => testNow);
    final original = demoContent();
    final excerpt = original.cardForAnnotation(original.annotations.single.id)!;
    final made = editor.createSummary(original, [excerpt.id], label: 'Summary result');
    final summary = made.value!.cardId!;
    final (withChild, child) = editor.addTopic(made.content, title: 'Folded parent', parentId: summary);
    final (withResult, result) = editor.addTopic(withChild, title: 'Tagged result', parentId: child.id);
    var data = editor.setTags(withResult, result.id, ['test']);
    data = editor.setTags(data, summary, ['summary-tag']);
    data = editor.setCollapsed(data, 'c3', collapsed: true);
    data = editor.setCollapsed(data, child.id, collapsed: true);
    final c = await openSidebar(tester, content: InMemoryStudySetContentRepository({'demo-1': data}));
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.setLayout(MMSplitMode.primary);
    await tester.pumpAndSettle();
    await openTag(tester, 'test');
    expect(c.read(workspaceProvider('demo-1')).layout, MMSplitMode.primary);
    expect(find.text('Main Map › 遗忘的规律 › Summary result › Folded parent'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('tag-result-main-${result.id}')));
    await settleHud(tester);
    expect(c.read(workspaceProvider('demo-1')).selectedCardId, result.id);
    expect(c.read(workspaceProvider('demo-1')).layout, isNot(MMSplitMode.primary));
    expect(find.byType(TagContentPane), findsNothing);
    expect(owner.content.node('c3')!.collapsed, isFalse);
    expect(owner.content.node(child.id)!.collapsed, isFalse);
    await openTag(tester, 'summary-tag');
    await tester.tap(find.byKey(ValueKey('tag-result-main-$summary')));
    await settleHud(tester);
    expect(c.read(workspaceProvider('demo-1')).selectedCardId, summary);
    expect(tester.takeException(), isNull);
  });
  testWidgets('one tag entry remains in the directory and all filters live in its drawer', (tester) async {
    final c = await openSidebar(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final values = [for (var i = 0; i < 12; i++) 'Tag $i'];
    await owner.setTags('c3', values);
    await tester.pumpAndSettle();
    expect(inSidebar(find.text('Tags')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-tags-expand')), findsNothing);
    await openTag(tester, values.last);
    for (final value in values) {
      expect(find.byKey(ValueKey('tag-filter-$value')), findsOneWidget);
    }
    expect(c.read(workspaceProvider('demo-1')).tagFilter, values.last);
    await owner.addMap('Empty map');
    await tester.pumpAndSettle();
    owner.showTags();
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('tag-filter-${values.last}')),
      findsOneWidget,
      reason: 'tag drawer covers every map, including when current map has no tags',
    );
    await owner.setTags('c3', []);
    await tester.pumpAndSettle();
    expect(find.text('No nodes with this tag'), findsOneWidget);
    owner.closePanel();
    owner.setSidebarQuery('遗忘');
    await tester.pumpAndSettle();
    expect(inSidebar(find.text('遗忘的规律')), findsNothing, reason: 'search stays scoped to selected empty map');
    expect(tester.takeException(), isNull);
  });
}
