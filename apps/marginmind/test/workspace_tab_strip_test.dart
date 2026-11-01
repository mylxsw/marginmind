import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_design/mm_design.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

import 'workspace_tabs_test.dart' show openTabs;

Finder tab(String id) => find.byKey(ValueKey('workspace-tab-$id'));
Finder close(String id) => find.byKey(ValueKey('close-workspace-tab-$id'));
double closeOpacity(WidgetTester tester, String id) =>
    tester.widget<AnimatedOpacity>(find.ancestor(of: close(id), matching: find.byType(AnimatedOpacity))).opacity;

void main() {
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
