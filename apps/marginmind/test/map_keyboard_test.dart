import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/outline_view.dart';

import 'dart:convert';
import 'dart:math' as math;

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

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool primary = false,
  bool shift = false,
  bool alt = false,
}) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  if (primary) await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
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

void keyRepeatTests({bool native = false}) {
  testWidgets(
    'holding outline arrows keeps navigating and never focuses the toolbar',
    (tester) async {
      final container = await openFirstSet(tester);
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      controller.setMapView(MapViewMode.outline);
      await tester.pumpAndSettle();
      final focus = tester.widget<OutlineView>(find.byType(OutlineView)).focusNode;
      final layout = container.read(provider).layout;
      final cases = <(LogicalKeyboardKey, String?, List<String?>)>[
        (LogicalKeyboardKey.arrowUp, 'c4', ['c6', 'c3', null, null]),
        (LogicalKeyboardKey.arrowDown, null, ['c3', 'c6', 'c4', 'c4']),
        (LogicalKeyboardKey.arrowRight, null, ['c3', 'c6', 'c6', 'c6']),
        (LogicalKeyboardKey.arrowLeft, 'c6', ['c3', null, null, null]),
      ];
      for (final (arrow, start, expected) in cases) {
        // Profile builds omit debug key names; pass physical keys explicitly.
        final physical = switch (arrow) {
          LogicalKeyboardKey.arrowUp => PhysicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown => PhysicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowRight => PhysicalKeyboardKey.arrowRight,
          _ => PhysicalKeyboardKey.arrowLeft,
        };
        controller.selectCard(start);
        focus.requestFocus();
        await tester.pumpAndSettle();
        for (var i = 0; i < expected.length; i++) {
          if (i == 0) {
            await tester.sendKeyDownEvent(arrow, physicalKey: physical);
          } else {
            await tester.sendKeyRepeatEvent(arrow, physicalKey: physical);
          }
          await tester.pump(const Duration(milliseconds: 40));
          String? focusedButton;
          FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
            if (element.widget case final MMToolbarButton button) focusedButton = button.tooltip;
            return true;
          });
          expect(
            FocusManager.instance.primaryFocus,
            same(focus),
            reason: '$arrow repeat $i must stay in the outline; focused toolbar: $focusedButton',
          );
          expect(container.read(provider).selectedCardId, expected[i], reason: '$arrow repeat $i');
          expect(container.read(provider).layout, layout);
        }
        await tester.sendKeyUpEvent(arrow, physicalKey: physical);
      }
      await settleHud(tester);
    },
    semanticsEnabled: !native,
    variant: native ? const DefaultTestVariant() : TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'holding canvas arrows keeps navigating through children and at boundaries',
    (tester) async {
      final container = await openFirstSet(tester);
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      controller.selectCard(null);
      await focusMap(tester);
      final focus = canvas(tester).focusNode;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight, physicalKey: PhysicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(container.read(provider).selectedCardId, 'c3');
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight, physicalKey: PhysicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(container.read(provider).selectedCardId, 'c6');
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight, physicalKey: PhysicalKeyboardKey.arrowRight);
      await settleHud(tester);
    },
    semanticsEnabled: !native,
    variant: native ? const DefaultTestVariant() : TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'repeats keep folding single-shot and leave editing arrows with the text field',
    (tester) async {
      final container = await openFirstSet(tester);
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      for (final view in MapViewMode.values) {
        controller.setMapView(view);
        controller.selectCard('c3');
        await tester.pumpAndSettle();
        final focus = view == MapViewMode.outline
            ? tester.widget<OutlineView>(find.byType(OutlineView)).focusNode
            : canvas(tester).focusNode;
        focus.requestFocus();
        await tester.pumpAndSettle();
        final initiallyCollapsed = controller.content.node('c3')!.collapsed;
        final expectedCollapsed = view == MapViewMode.map ? !initiallyCollapsed : initiallyCollapsed;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, physicalKey: PhysicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, physicalKey: PhysicalKeyboardKey.slash);
        await tester.pumpAndSettle();
        expect(controller.content.node('c3')!.collapsed, expectedCollapsed);
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.slash, physicalKey: PhysicalKeyboardKey.slash);
          await tester.pumpAndSettle();
          expect(controller.content.node('c3')!.collapsed, expectedCollapsed);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.slash, physicalKey: PhysicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, physicalKey: PhysicalKeyboardKey.metaLeft);
        controller.beginEditing('c3');
        await tester.pumpAndSettle();
        final editor = tester.widget<MMInlineTextField>(find.byType(MMInlineTextField));
        editor.controller.selection = TextSelection.collapsed(offset: editor.controller.text.length);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft, physicalKey: PhysicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft, physicalKey: PhysicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(editor.focusNode));
        expect(container.read(provider).selectedCardId, 'c3');
        expect(container.read(provider).editingCardId, 'c3');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft, physicalKey: PhysicalKeyboardKey.arrowLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape, physicalKey: PhysicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      await settleHud(tester);
    },
    semanticsEnabled: !native,
    variant: native ? const DefaultTestVariant() : TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

void main() {
  keyRepeatTests();

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
    command('Locate Selected Node').onSelected!();
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
    expect(command('Locate Selected Node').onSelected, isNull);
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
    // Too deep to fit readably: "fit" stops at the readable zoom, centered on
    // the selection.
    await key(tester, LogicalKeyboardKey.digit0, primary: true);
    expect(mapScale(transform.value), lessThan(mapReadableScale));
    Actions.invoke(canvas(tester).focusNode.context!, const MindMapIntent(MindMapCommand.center));
    await tester.pumpAndSettle();
    expect(mapScale(transform.value), mapLocateScale);
    visible(tester, find.byKey(const ValueKey('c3')));
    final viewport = tester.getRect(find.byType(MindMapCanvas));
    expect(tester.getCenter(find.byKey(const ValueKey('c3'))).dx, closeTo(viewport.center.dx, 1));
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
  testWidgets('zoom label follows fit and gestures; zooming out after fit keeps going out', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard('c4');
    await focusMap(tester);
    for (var i = 0; i < 12; i++) {
      await key(tester, LogicalKeyboardKey.tab);
      tester.testTextInput.enterText('Deep topic $i');
      await tester.pump();
      await key(tester, LogicalKeyboardKey.enter);
    }
    final transform = canvas(tester).transformation;
    String label() => '${(mapScale(transform.value) * 100).round()}%';
    await key(tester, LogicalKeyboardKey.digit0, primary: true);
    final fitted = mapScale(transform.value);
    expect(fitted, lessThan(mapReadableScale));
    expect(find.text(label()), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(MapPane), matching: find.byTooltip('Zoom Out')));
    await tester.pumpAndSettle();
    expect(mapScale(transform.value), closeTo(math.max(fitted / 1.25, mapMinScale), 1e-9));
    expect(find.text(label()), findsOneWidget);
    // A pan or pinch changes the transform without rebuilding the pane.
    transform.value = Matrix4.identity()..scaleByDouble(1.5, 1.5, 1, 1);
    await tester.pump();
    expect(find.text('150%'), findsOneWidget);
    await settleHud(tester);
  });
}
