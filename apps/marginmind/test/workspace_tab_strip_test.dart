import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_design/mm_design.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

import 'workspace_tabs_test.dart' show openTabs;

Finder tab(String id) => find.byKey(ValueKey('workspace-tab-$id'));
Finder close(String id) => find.byKey(ValueKey('close-workspace-tab-$id'));
double closeOpacity(WidgetTester tester, String id) =>
    tester.widget<AnimatedOpacity>(find.ancestor(of: close(id), matching: find.byType(AnimatedOpacity))).opacity;

void main() {
  testWidgets('tabs start at the leading edge for one or multiple open tabs', (tester) async {
    final c = await openTabs(tester);
    final strip = find.byKey(const ValueKey('workspace-main-tabs'));
    final left = tester.getTopLeft(strip).dx;
    expect(left, tester.getTopLeft(find.byKey(const ValueKey('workspace-tab-row'))).dx);
    expect(tester.getTopLeft(tab('documentMap')).dx, closeTo(left + 12, 0.01));
    c.read(workspaceProvider('demo-1').notifier).openStudyNote('written');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(strip).dx, left);
    expect(tester.getTopLeft(tab('documentMap')).dx, closeTo(left + 12, 0.01));
    expect(find.byKey(const ValueKey('workspace-tab-drag-area')).hitTestable(), findsOneWidget);
  });

  for (final touch in [false, true]) {
    testWidgets('dragging a tab changes order while retaining selection and references; touch=$touch', (tester) async {
      const channel = MethodChannel('window_manager');
      final windowCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        windowCalls.add(call);
        return call.method == 'isMaximized' ? false : null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      final c = await openTabs(tester, touch: touch);
      final owner = c.read(workspaceProvider('demo-1').notifier);
      owner.openReference(const WorkspaceReference.note('second'));
      owner.openStudyNote('written');
      owner.openReference(const WorkspaceReference.document('c1'));
      owner.activateTab(WorkspaceTab.vocabulary);
      owner.activateTab(WorkspaceTab.review);
      owner.openStudyNote('written');
      await tester.pumpAndSettle();
      final contexts = owner.state.tabs.contexts;
      final panel = owner.state.panel;
      final title = find.descendant(of: tab('documentMap'), matching: find.byType(Text)).first;
      final end = tester.getRect(tab('review')).centerRight + Offset(tester.getSize(tab('documentMap')).width, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(title),
        kind: touch ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
      );
      if (touch) await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveTo(end);
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(owner.state.tabs.open.map((t) => t.id), ['note:written', 'vocabulary', 'review', 'documentMap']);
      expect(owner.state.tabs.activeId, 'note:written');
      expect(owner.state.panel, panel);
      expect(owner.state.tabs.contexts, same(contexts));
      expect(owner.state.tabs.current.reference?.id, 'c1');
      owner.activateTab(WorkspaceTab.documents);
      await tester.pumpAndSettle();
      expect(owner.state.tabs.current.reference?.id, 'second');
      await tester.tap(close('documentMap'));
      await tester.pumpAndSettle();
      expect(owner.state.tabs.open.map((t) => t.id), ['note:written', 'vocabulary', 'review']);
      expect(owner.state.tabs.activeId, 'review');
      expect(windowCalls.where((call) => call.method == 'startDragging' || call.method == 'maximize'), isEmpty);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('tabs fit their titles and resize on rename without shifting on selection', (tester) async {
    final c = await openTabs(tester);
    await c.read(settingsProvider.notifier).setLanguage(LanguagePreference.zh);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    await owner.saveStudyNote(owner.content.studyNote('written')!.copyWith(title: '短记'));
    owner.openStudyNote('written');
    owner.activateTab(WorkspaceTab.vocabulary);
    owner.activateTab(WorkspaceTab.review);
    owner.activateTab(WorkspaceTab.documents);
    await tester.pumpAndSettle();
    double width(String id) => tester.getSize(tab(id)).width;
    final shortWidth = width('note:written');
    final documentWidth = width('documentMap');
    expect(documentWidth, lessThan(180));
    expect(width('review'), lessThan(width('vocabulary')));
    expect(width('vocabulary'), lessThan(documentWidth));
    expect(shortWidth, lessThan(documentWidth));
    for (final id in ['documentMap', 'note:written', 'vocabulary', 'review']) {
      final label = find.descendant(of: tab(id), matching: find.byType(Text)).first;
      expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse, reason: '$id must fit its title');
    }
    owner.openStudyNote('written');
    await tester.pumpAndSettle();
    expect(width('note:written'), shortWidth);
    expect(width('documentMap'), documentWidth);

    const longTitle = '这是一篇标题很长的阅读笔记，用来整理注意力、阅读方法和知识管理的实践';
    await owner.saveStudyNote(owner.content.studyNote('written')!.copyWith(title: longTitle));
    await tester.pumpAndSettle();
    expect(width('note:written'), greaterThan(shortWidth));
    expect(width('note:written'), lessThan(300));
    expect(find.descendant(of: tab('note:written'), matching: find.byTooltip(longTitle)), findsOneWidget);
    expect(width('documentMap'), documentWidth);
    expect(find.byKey(const ValueKey('workspace-tab-overflow')), findsNothing);
    expect(find.byKey(const ValueKey('workspace-tab-drag-area')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover reveals an inactive close without shifting or selecting the tab', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openStudyNote('written');
    owner.activateTab(WorkspaceTab.documents);
    await tester.pumpAndSettle();
    expect(closeOpacity(tester, 'note:written'), 0);
    final before = tester.getRect(tab('note:written'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tab('note:written')));
    await tester.pumpAndSettle();
    expect(closeOpacity(tester, 'note:written'), 1);
    expect(tester.getRect(tab('note:written')), before);
    await tester.tap(close('note:written'));
    await tester.pumpAndSettle();
    expect(owner.state.tabs.activeId, WorkspaceTab.documents.id);
    expect(tab('note:written'), findsNothing);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard focus exposes an inactive close as a separate control', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openStudyNote('written');
    owner.activateTab(WorkspaceTab.documents);
    await tester.pumpAndSettle();
    final icon = find.descendant(of: close('note:written'), matching: find.byType(Icon));
    Focus.of(tester.element(icon)).requestFocus();
    await tester.pumpAndSettle();
    expect(closeOpacity(tester, 'note:written'), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tab('note:written'), findsNothing);
    expect(owner.state.tabs.activeId, WorkspaceTab.documents.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short label has no duplicate title tooltip', (tester) async {
    final c = await openTabs(tester);
    await c.read(settingsProvider.notifier).setLanguage(LanguagePreference.zh);
    await tester.pumpAndSettle();
    expect(find.descendant(of: tab('documentMap'), matching: find.byTooltip('文档与脑图')), findsNothing);
    expect(close('documentMap'), findsOneWidget);
  });

  testWidgets('overflow menu selects a tab and brings it into view', (tester) async {
    final c = await openTabs(tester, size: const Size(900, 820));
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openStudyNote('written');
    owner.openStudyNote('second');
    owner.activateTab(WorkspaceTab.vocabulary);
    owner.activateTab(WorkspaceTab.review);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-tab-overflow')));
    await tester.pumpAndSettle();
    final choice = find.byWidgetPredicate(
      (w) => w is MMDropdownItem<WorkspaceTab> && w.value?.id == WorkspaceTab.documents.id,
    );
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(owner.state.tabs.activeId, WorkspaceTab.documents.id);
    expect(tab('documentMap').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [500.0, 834.0]) {
    testWidgets('touch close controls stay visible and reachable at $width', (tester) async {
      final c = await openTabs(tester, size: Size(width, 1000), touch: true);
      final owner = c.read(workspaceProvider('demo-1').notifier);
      owner.openStudyNote('written');
      await tester.pumpAndSettle();
      expect(closeOpacity(tester, 'documentMap'), 1);
      expect(tester.getSize(close('note:written')), const Size.square(44));
      await tester.tap(close('note:written'));
      await tester.pumpAndSettle();
      expect(owner.state.tabs.activeId, WorkspaceTab.documents.id);
      expect(tester.takeException(), isNull);
    });
  }
}
