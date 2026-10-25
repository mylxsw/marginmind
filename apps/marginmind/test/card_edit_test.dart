import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/features/workspace/widgets/outline_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

final _field = find.byType(MMInlineTextField);
const _quote = '这条先陡后平的曲线，被称为遗忘曲线。';

TextEditingController _text(WidgetTester tester) => tester.widget<MMInlineTextField>(_field).controller;

String _json(StudySetContent c) => jsonEncode(c.toJson());

Future<void> _select(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// Types [text] into the open field as one input-method update.
Future<void> _type(WidgetTester tester, String text) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
  await tester.pump();
}

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
  final held = [if (primary) modifier, if (shift) LogicalKeyboardKey.shiftLeft, if (alt) LogicalKeyboardKey.altLeft];
  for (final k in held) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(key);
  for (final k in held.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pumpAndSettle();
}

Future<void> _shiftEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  group('E-06 excerpts and notes on the map', () {
    testWidgets('an excerpt title is edited in place and can be cleared again', (tester) async {
      final container = await openFirstSet(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final excerpt = controller.content.cards.singleWhere((c) => c.kind == CardKind.excerpt);
      await doubleTap(tester, find.text('Untitled excerpt'));
      expect(find.byType(MMSheet), findsNothing);
      expect(container.read(workspaceProvider('demo-1')).editingCardId, excerpt.id);
      // The title starts empty (the placeholder is not text to edit).
      expect(_text(tester).text, '');
      final height = tester.getSize(find.ancestor(of: _field, matching: find.byType(Positioned)).first).height;
      await _type(tester, '遗忘曲线：一条很长很长的标题，不会把卡片撑高');
      await tester.pumpAndSettle();
      expect(tester.getSize(find.ancestor(of: _field, matching: find.byType(Positioned)).first).height, height);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      expect(controller.content.card(excerpt.id)!.title, '遗忘曲线：一条很长很长的标题，不会把卡片撑高');
      expect(find.text(_quote), findsOneWidget);

      // F2 on the selected excerpt; clearing the title is saved as such.
      await key(tester, LogicalKeyboardKey.f2);
      expect(_text(tester).text, '遗忘曲线：一条很长很长的标题，不会把卡片撑高');
      await _type(tester, '');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.content.card(excerpt.id)!.title, '');
      expect(find.text('Untitled excerpt'), findsOneWidget);

      // Two edits, two undo steps.
      await controller.undo();
      expect(controller.content.card(excerpt.id)!.title, '遗忘曲线：一条很长很长的标题，不会把卡片撑高');
      await controller.undo();
      expect(controller.content.card(excerpt.id)!.title, '');
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
      await settleHud(tester);
    });

    testWidgets('a new note opens in place; ⇧Enter breaks lines, Enter saves', (tester) async {
      final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      final container = await openFirstSet(tester, content: repo);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      await _select(tester, find.text('遗忘的规律'));
      await tester.tap(find.byIcon(MMIcons.addNote));
      await tester.pumpAndSettle();
      expect(find.byType(MMSheet), findsNothing);
      expect(_text(tester).text, 'New note');
      expect(_text(tester).selection, const TextSelection(baseOffset: 0, extentOffset: 8));
      final height = tester.getSize(_field).height;

      await _type(tester, '第一行');
      await _shiftEnter(tester);
      expect(_field, findsOneWidget);
      expect(_text(tester).text, '第一行\n');
      expect(_text(tester).selection, const TextSelection.collapsed(offset: 4));
      await _type(tester, '第一行\n第二行');
      await tester.pumpAndSettle();
      // The node grows with the new line; the map lays out around it.
      expect(tester.getSize(_field).height, greaterThan(height * 1.5));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      final note = controller.content.cards.singleWhere((c) => c.kind == CardKind.note);
      expect(note.title, '第一行\n第二行');
      expect(controller.content.node(note.id)!.parentId, 'c3');

      // Creation and text are one undo step.
      final before = _json(demoContent());
      await controller.undo();
      await tester.pumpAndSettle();
      expect(_json(await repo.load('demo-1')), before);
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
      await settleHud(tester);
    });

    testWidgets('Esc on a new note leaves nothing behind', (tester) async {
      final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      final container = await openFirstSet(tester, content: repo);
      final before = _json(await repo.load('demo-1'));
      await tester.tap(find.byIcon(MMIcons.addNote));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      expect(find.text('New note'), findsNothing);
      expect(_json(await repo.load('demo-1')), before);
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
      await settleHud(tester);
    });

    testWidgets('notes: typing replaces, the context menu edits in place, blank keeps the text', (tester) async {
      final container = await openFirstSet(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final note = await controller.addNote('笔记');
      await tester.pumpAndSettle();
      await _select(tester, find.text('笔记'));
      await key(tester, LogicalKeyboardKey.keyX);
      expect(_text(tester).text, 'x');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.content.card(note.id)!.title, 'x');

      await tester.tap(find.text('x'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Note'));
      await tester.pumpAndSettle();
      expect(find.byType(MMSheet), findsNothing);
      expect(_text(tester).text, 'x');
      await _type(tester, '   ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.content.card(note.id)!.title, 'x');

      // The menu bar's Add Note opens the field too.
      await key(tester, LogicalKeyboardKey.keyN, primary: true, alt: true);
      expect(_text(tester).text, 'New note');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await settleHud(tester);
    });

    testWidgets('the node menu adds a note in place', (tester) async {
      await openFirstSet(tester);
      await tester.tap(find.text('遗忘的规律'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Note'));
      await tester.pumpAndSettle();
      expect(find.byType(MMSheet), findsNothing);
      expect(_text(tester).text, 'New note');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await settleHud(tester);
    });
  });

  group('E-13 outline', () {
    Future<ProviderContainer> openOutline(WidgetTester tester, {InMemoryStudySetContentRepository? content}) async {
      final container = await openFirstSet(tester, content: content);
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();
      await _select(tester, find.text('认知科学入门').last);
      return container;
    }

    testWidgets('a multi-level tree is written with the keyboard alone', (tester) async {
      final container = await openOutline(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      Future<void> write(String text) async {
        expect(_field, findsOneWidget, reason: text);
        await _type(tester, text);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }

      // Tab on the root: a child at the root's end.
      await key(tester, LogicalKeyboardKey.tab);
      expect(_text(tester).text, 'New Topic');
      await write('A');
      await key(tester, LogicalKeyboardKey.enter);
      await write('B');
      await key(tester, LogicalKeyboardKey.tab);
      await write('B1');
      await key(tester, LogicalKeyboardKey.tab);
      await write('B1a');
      await key(tester, LogicalKeyboardKey.enter, shift: true);
      await write('B1-first');
      await key(tester, LogicalKeyboardKey.tab, shift: true);
      await key(tester, LogicalKeyboardKey.enter, primary: true);
      await write('B-parent');
      expect(find.byType(MMSheet), findsNothing);

      final c = controller.content;
      String id(String title) => c.cards.singleWhere((card) => card.title == title).id;
      String? parent(String title) => c.node(id(title))!.parentId;
      expect(parent('A'), isNull);
      expect(parent('B'), isNull);
      expect(parent('B1'), id('B'));
      expect(parent('B1a'), id('B1'));
      // ⇧Tab moved the new sibling up next to B1; ⌘Enter wrapped it.
      expect(parent('B-parent'), id('B'));
      expect(parent('B1-first'), id('B-parent'));
      expect([for (final n in c.childrenOf(id('B'))) c.card(n.cardId)!.title], ['B1', 'B-parent']);
      // Rows follow the tree, indented by level.
      double indent(String title) => tester.getTopLeft(find.text(title)).dx;
      expect(indent('B1'), greaterThan(indent('B')));
      expect(indent('B-parent'), indent('B1'));
      expect(indent('B1-first'), greaterThan(indent('B-parent')));
      await settleHud(tester);
    });

    testWidgets('arrows, F2, Space, typing, Esc, ⌘↑ and ⌫ act on rows', (tester) async {
      final container = await openOutline(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      String? selected() => container.read(workspaceProvider('demo-1')).selectedCardId;
      String? title() => selected() == null ? null : controller.content.card(selected()!)!.title;

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(title(), '遗忘的规律');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(title(), '');
      expect(controller.content.card(selected()!)!.kind, CardKind.excerpt);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(title(), '遗忘的规律');
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.content.card(selected()!)!.kind, CardKind.excerpt);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(title(), '对策一：间隔重复');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(title(), '对策一：间隔重复');
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(title(), '对策一：间隔重复');

      // F2 / Space open the field; Esc keeps the text and the focus.
      for (final k in [LogicalKeyboardKey.f2, LogicalKeyboardKey.space]) {
        await key(tester, k);
        expect(_text(tester).text, '对策一：间隔重复');
        await _type(tester, '临时');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_field, findsNothing);
      }
      expect(controller.content.card(selected()!)!.title, '对策一：间隔重复');
      await key(tester, LogicalKeyboardKey.keyQ);
      expect(_text(tester).text, 'q');
      await _type(tester, 'quick');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(title(), 'quick');

      await key(tester, LogicalKeyboardKey.arrowUp, primary: true);
      expect(controller.content.childrenOf(null).first.cardId, selected());
      // Shortcuts that only make sense on the map do nothing here.
      await key(tester, LogicalKeyboardKey.slash, primary: true);
      await key(tester, LogicalKeyboardKey.digit0, primary: true);
      expect(_field, findsNothing);

      final id = selected()!;
      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.content.card(id), isNull);
      await key(tester, LogicalKeyboardKey.escape);
      expect(selected(), isNull);
      await key(tester, LogicalKeyboardKey.arrowUp);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(selected(), isNull);
      // Typing on the root does not edit it.
      await key(tester, LogicalKeyboardKey.keyQ);
      expect(_field, findsNothing);
      await settleHud(tester);
    });

    testWidgets('excerpts and notes edit in place; double-click reveals an excerpt', (tester) async {
      final container = await openOutline(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final excerpt = controller.content.cards.singleWhere((c) => c.kind == CardKind.excerpt);
      await _select(tester, find.text(_quote));
      await key(tester, LogicalKeyboardKey.f2);
      expect(_text(tester).text, '');
      // The quote stays visible below the field while the title is typed.
      expect(find.text(_quote), findsOneWidget);
      await _type(tester, '曲线');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.content.card(excerpt.id)!.title, '曲线');
      await doubleTap(tester, find.text('曲线'));
      expect(_field, findsNothing);
      expect(container.read(workspaceProvider('demo-1')).reveal, isNotNull);

      // ⌥⌘N: a note under the selection, multi-line with ⇧Enter.
      await key(tester, LogicalKeyboardKey.keyN, primary: true, alt: true);
      expect(_text(tester).text, 'New note');
      await _type(tester, '一');
      await _shiftEnter(tester);
      await _type(tester, '一\n二');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final note = controller.content.cards.singleWhere((c) => c.kind == CardKind.note);
      expect(note.title, '一\n二');
      expect(controller.content.node(note.id)!.parentId, excerpt.id);

      // Double-click a note or topic row to edit it; clicking another row confirms.
      await doubleTap(tester, find.text('遗忘的规律'));
      expect(_text(tester).text, '遗忘的规律');
      await _type(tester, '遗忘');
      await tester.tap(find.text('对策一：间隔重复'));
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
      expect(controller.content.cards.where((c) => c.title == '遗忘'), hasLength(1));
      await settleHud(tester);
    });

    testWidgets('the toolbar and menu add topics in place; Esc leaves nothing', (tester) async {
      final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      final container = await openOutline(tester, content: repo);
      final before = _json(await repo.load('demo-1'));
      await tester.tap(find.byIcon(MMIcons.addTopic));
      await tester.pumpAndSettle();
      expect(find.byType(MMSheet), findsNothing);
      expect(_text(tester).text, 'New Topic');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.keyN, primary: true, shift: true);
      expect(_text(tester).text, 'New Topic');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_json(await repo.load('demo-1')), before);
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
      await settleHud(tester);
    });

    testWidgets('with the map pane hidden, a new card brings it back to edit', (tester) async {
      final container = await openFirstSet(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      for (final view in MapViewMode.values) {
        controller.setMapView(view);
        controller.setLayout(MMSplitMode.primary);
        await tester.pumpAndSettle();
        await key(tester, LogicalKeyboardKey.keyN, primary: true, alt: true);
        final state = container.read(workspaceProvider('demo-1'));
        expect(state.layout, MMSplitMode.split, reason: '$view');
        expect(_field.hitTestable(), findsOneWidget, reason: '$view');
        // The field has the keyboard: Esc reaches it and leaves nothing behind.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(container.read(workspaceProvider('demo-1')).editingCardId, isNull, reason: '$view');
        expect(controller.content.cards.where((c) => c.kind == CardKind.note), isEmpty, reason: '$view');
      }
      // Editing an existing card does the same.
      controller.setLayout(MMSplitMode.primary);
      await tester.pumpAndSettle();
      controller.beginEditing('c3');
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.split);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).editingCardId, isNull);
      await settleHud(tester);
    });

    testWidgets('menu bar: map-only commands are off in the outline', (tester) async {
      final container = await openOutline(tester);
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
      expect(command('Add Child Topic').onSelected, isNotNull);
      expect(command('Fit Map to Window').onSelected, isNull);
      expect(command('Center on Current Node').onSelected, isNull);
      container.read(workspaceProvider('demo-1').notifier).setMapView(MapViewMode.map);
      await tester.pumpAndSettle();
      await tester.tap(find.text('遗忘的规律'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(command('Center on Current Node').onSelected, isNotNull);
      await settleHud(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('switching to the outline hands it the keyboard', (tester) async {
      final container = await openFirstSet(tester);
      await tester.tap(find.text('Outline'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(container.read(workspaceProvider('demo-1')).selectedCardId, 'c3');
      // Menu bar commands reach the focused outline like they reach the map.
      Actions.invoke(FocusManager.instance.primaryFocus!.context!, const MindMapIntent(MindMapCommand.child));
      await tester.pumpAndSettle();
      expect(_text(tester).text, 'New Topic');
      // Ignored while a row is being edited.
      Actions.invoke(FocusManager.instance.primaryFocus!.context!, const MindMapIntent(MindMapCommand.child));
      await tester.pumpAndSettle();
      expect(_field, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await settleHud(tester);
    });

    testWidgets('the row being written stays in view', (tester) async {
      await openOutline(tester);
      for (var i = 0; i < 40; i++) {
        await key(tester, i == 0 ? LogicalKeyboardKey.tab : LogicalKeyboardKey.enter);
        await _type(tester, 'Row $i');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }
      final view = tester.getRect(find.byType(OutlineView));
      final row = tester.getRect(find.text('Row 39'));
      // Clear of the floating controls at the bottom (the list's padding).
      expect(row.bottom, lessThanOrEqualTo(view.bottom - 72));
      expect(row.top, greaterThanOrEqualTo(view.top + 76));
      // Up one row at a time: each selected row stays clear of the top controls.
      for (var i = 0; i < 30; i++) {
        await key(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(tester.getRect(find.text('Row 9')).top, greaterThanOrEqualTo(view.top + 76));
      // Back to the top: the first row comes out from under the controls.
      await key(tester, LogicalKeyboardKey.escape);
      expect(tester.getRect(find.text('遗忘的规律')).top, greaterThan(view.top + 60));
      await settleHud(tester);
    });
  });
}
