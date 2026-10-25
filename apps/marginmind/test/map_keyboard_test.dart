import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

Future<void> key(WidgetTester tester, LogicalKeyboardKey key, {bool primary = false, bool shift = false}) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  if (primary) await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (primary) await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

MindMapCanvas canvas(WidgetTester tester) => tester.widget<MindMapCanvas>(find.byType(MindMapCanvas));
Future<void> focusMap(WidgetTester tester) async {
  canvas(tester).focusNode.requestFocus();
  await tester.pumpAndSettle();
}

void visible(WidgetTester tester, Finder node) {
  final viewport = tester.getRect(find.byType(MindMapCanvas));
  final rect = tester.getRect(node);
  expect(rect.left, greaterThanOrEqualTo(viewport.left));
  expect(rect.right, lessThanOrEqualTo(viewport.right));
  expect(rect.top, greaterThanOrEqualTo(viewport.top));
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
}

void main() {
  testWidgets('macOS menu lists shortcuts, dispatches commands and protects text focus', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard('c3');
    await focusMap(tester);
    Iterable<PlatformMenuItem> flatten(Iterable<PlatformMenuItem> items) sync* {
      for (final item in items) {
        yield item;
        if (item is PlatformMenu) yield* flatten(item.menus);
        if (item is PlatformMenuItemGroup) yield* flatten(item.members);
      }
    }

    PlatformMenuItem command(String label) =>
        flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus)
            .singleWhere((item) => item.label == label);
    for (final shortcut in mindMapShortcuts.entries) {
      if (shortcut.key.trigger == LogicalKeyboardKey.f2 || shortcut.key.trigger == LogicalKeyboardKey.delete) continue;
      final items = flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus);
      expect(
        items.any((item) {
          final key = item.shortcut;
          return key is SingleActivator &&
              key.trigger == shortcut.key.trigger &&
              key.meta == shortcut.key.meta &&
              key.control == shortcut.key.control &&
              key.shift == shortcut.key.shift;
        }),
        isTrue,
        reason: '${shortcut.value}',
      );
    }
    command('Center on Current Node').onSelected!();
    await tester.pumpAndSettle();
    command('Add Sibling After').onSelected!();
    await tester.pumpAndSettle();
    expect(find.byType(MMInlineTextField), findsOneWidget);
    expect(command('Add Sibling After').onSelected, isNull);
    tester.testTextInput.enterText('Menu');
    await key(tester, LogicalKeyboardKey.enter);
    await key(tester, LogicalKeyboardKey.enter, primary: true);
    expect(find.byType(MMInlineTextField), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    await key(tester, LogicalKeyboardKey.arrowDown, primary: true);
    await key(tester, LogicalKeyboardKey.arrowUp, primary: true);
    controller.selectCard('c3');
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.slash, primary: true);
    expect(controller.content.node('c3')!.collapsed, isTrue);
    await key(tester, LogicalKeyboardKey.digit0, primary: true);
    // A reader/search field keeps map commands disabled.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(command('Add Child Topic').onSelected, isNull);
    expect(command('Center on Current Node').onSelected, isNull);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Enter, Shift Enter, Tab, Shift Tab and primary Enter restructure in place', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final provider = workspaceProvider('demo-1');
    controller.selectCard('c3');
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.enter);
    final after = container.read(provider).editingCardId!;
    expect(controller.content.childrenOf(null).map((n) => n.cardId), ['c3', after, 'c4']);
    tester.testTextInput.enterText('After');
    await key(tester, LogicalKeyboardKey.enter);
    await key(tester, LogicalKeyboardKey.enter, shift: true);
    final before = container.read(provider).editingCardId!;
    expect(controller.content.childrenOf(null).map((n) => n.cardId), ['c3', before, after, 'c4']);
    tester.testTextInput.enterText('Before');
    await key(tester, LogicalKeyboardKey.enter);
    await key(tester, LogicalKeyboardKey.tab);
    final child = container.read(provider).editingCardId!;
    expect(controller.content.node(child)!.parentId, before);
    tester.testTextInput.enterText('Child');
    await key(tester, LogicalKeyboardKey.enter);
    await key(tester, LogicalKeyboardKey.tab, shift: true);
    expect(controller.content.node(child)!.parentId, isNull);
    await key(tester, LogicalKeyboardKey.enter, primary: true);
    expect(controller.content.node(child)!.parentId, container.read(provider).editingCardId);
    await key(tester, LogicalKeyboardKey.escape);
    expect(controller.content.node(child)!.parentId, isNull);
    expect(container.read(provider).selectedCardId, child);
    await key(tester, LogicalKeyboardKey.enter, primary: true);
    tester.testTextInput.enterText('Parent');
    await key(tester, LogicalKeyboardKey.enter);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.node(child)!.parentId, isNull);
    await settleHud(tester);
  });
  testWidgets('fold, order, Space, delete, fit and center use shared menu actions', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard('c3');
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.slash, primary: true);
    expect(controller.content.node('c3')!.collapsed, isTrue);
    await key(tester, LogicalKeyboardKey.tab);
    expect(controller.content.node('c3')!.collapsed, isFalse);
    visible(tester, find.byType(MMInlineTextField));
    await key(tester, LogicalKeyboardKey.escape);
    expect(controller.content.node('c3')!.collapsed, isTrue);
    await key(tester, LogicalKeyboardKey.slash, primary: true);
    await key(tester, LogicalKeyboardKey.arrowDown, primary: true);
    expect(controller.content.childrenOf(null).first.cardId, 'c4');
    await key(tester, LogicalKeyboardKey.arrowUp, primary: true);
    expect(controller.content.childrenOf(null).first.cardId, 'c3');
    await key(tester, LogicalKeyboardKey.space);
    expect(find.byType(MMInlineTextField), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    final map = canvas(tester);
    map.transformation.value = Matrix4.identity()..translateByDouble(-2000, -2000, 0, 1);
    Actions.invoke(map.focusNode.context!, const MindMapIntent(MindMapCommand.center));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(MindMapCanvas));
    final node = tester.getRect(find.byKey(const ValueKey('c3')));
    expect(node.center.dx, closeTo(viewport.center.dx, 1));
    expect(node.center.dy, closeTo(viewport.center.dy, 1));
    await key(tester, LogicalKeyboardKey.digit0, primary: true);
    visible(tester, find.byKey(const ValueKey(rootNodeId)));
    visible(tester, find.byKey(const ValueKey('c3')));
    await key(tester, LogicalKeyboardKey.backspace);
    expect(controller.content.node('c3'), isNull);
    await settleHud(tester);
  });
  testWidgets('root commands safely ignore illegal mutations, Tab creates child', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard(null);
    await focusMap(tester);
    final before = jsonEncode(controller.content.toJson());
    for (final command in [
      MindMapCommand.siblingAfter,
      MindMapCommand.siblingBefore,
      MindMapCommand.parent,
      MindMapCommand.promote,
      MindMapCommand.delete,
      MindMapCommand.fold,
      MindMapCommand.up,
      MindMapCommand.down,
      MindMapCommand.edit,
    ]) {
      final activator = mindMapShortcuts.entries.firstWhere((e) => e.value == command).key;
      await key(tester, activator.trigger, primary: activator.control, shift: activator.shift);
    }
    expect(jsonEncode(controller.content.toJson()), before);
    expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
    await key(tester, LogicalKeyboardKey.tab);
    final id = container.read(workspaceProvider('demo-1')).editingCardId!;
    expect(controller.content.node(id)!.parentId, isNull);
    await key(tester, LogicalKeyboardKey.escape);
    await settleHud(tester);
  });
  testWidgets('keyboard deep creation, growing drafts and selection remain visible at user zoom', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard('c4');
    await focusMap(tester);
    final transform = canvas(tester).transformation;
    transform.value = Matrix4.identity();
    for (var i = 0; i < 12; i++) {
      await key(tester, LogicalKeyboardKey.tab);
      visible(tester, find.byType(MMInlineTextField));
      tester.testTextInput.enterText('Keyboard topic $i grows across several words');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      visible(tester, find.byType(MMInlineTextField));
      await tester.pumpAndSettle();
      visible(tester, find.byType(MMInlineTextField));
      await key(tester, LogicalKeyboardKey.enter);
    }
    expect(mapScale(transform.value), 1);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    final id = container.read(workspaceProvider('demo-1')).selectedCardId!;
    visible(tester, find.byKey(ValueKey(id)));
    controller.selectCard('c3');
    await tester.pumpAndSettle();
    visible(tester, find.byKey(const ValueKey('c3')));
    await key(tester, LogicalKeyboardKey.digit0, primary: true);
    expect(mapScale(transform.value), lessThan(0.3));
    visible(tester, find.byKey(const ValueKey(rootNodeId)));
    visible(tester, find.byKey(ValueKey(id)));
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
}
