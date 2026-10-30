import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/annotation_color_button.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'helpers.dart';

import 'package:marginmind/shared/l10n.dart';

const selection = MMPdfSelection(
  page: 1,
  rects: [PageRect(10, 100, 200, 88)],
  text: 'A selected passage',
  viewportRect: Rect.fromLTWH(120, 200, 180, 20),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      },
    );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  for (final target in ['root', 'topic', 'excerpt', 'note']) {
    for (final fromHighlight in [false, true]) {
      testWidgets('add to map makes a child of selected $target, existing highlight=$fromHighlight', (tester) async {
        final container = await pumpApp(tester);
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await tester.pumpAndSettle();
        final provider = workspaceProvider('demo-1');
        final controller = container.read(provider.notifier);
        final String? parentId = switch (target) {
          'topic' => controller.content.cards.firstWhere((c) => c.kind == CardKind.topic).id,
          'excerpt' => controller.content.cards.firstWhere((c) => c.kind == CardKind.excerpt).id,
          'note' => (await controller.addNote('Selected note')).id,
          _ => null,
        };
        if (parentId != null) await controller.toggleCollapsed(parentId);
        controller.selectCard(parentId);
        if (fromHighlight) {
          await controller.highlight('c1', selection, MMAnnotationColor.yellow);
          controller.tapHighlight(controller.content.annotations.last.id, selection.viewportRect!);
        } else {
          await controller.onSelectionCommitted('c1', selection);
        }
        await tester.pumpAndSettle();
        expect(container.read(provider).selectedCardId, parentId);
        final before = controller.content;
        await tester.tap(find.byTooltip('Add to Map'));
        await tester.pumpAndSettle();
        final card = controller.content.cardForAnnotation(controller.content.annotations.last.id)!;
        expect(controller.content.node(card.id)!.parentId, parentId);
        expect(controller.content.cards.length, before.cards.length + 1);
        expect(controller.content.annotations.length, before.annotations.length + (fromHighlight ? 0 : 1));
        if (parentId != null) expect(controller.content.node(parentId)!.collapsed, isFalse);
        expect(find.byType(SelectionToolbar), findsNothing);
        await controller.undo();
        expect(controller.content.card(card.id), isNull);
        expect(controller.content.annotations.length, before.annotations.length);
        await controller.redo();
        expect(controller.content.node(card.id)!.parentId, parentId);
        await settleHud(tester);
      });
    }
  }
  for (final color in MMAnnotationColor.values) {
    testWidgets('color ${color.name} only changes settings until the highlighter is applied', (tester) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final before = controller.content;
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before.annotations.length);
      expect(
        tester.widget<MMFloatingToolbarLayout>(find.byType(MMFloatingToolbarLayout)).anchor,
        selection.viewportRect,
      );
      expect(find.byType(MMFloatingToolbarColor), findsNothing);
      expect(
        find.descendant(of: find.byType(SelectionToolbar), matching: find.byIcon(MMIcons.highlight)),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: find.byType(SelectionToolbar), matching: find.byType(AnnotationColorButton)),
      );
      await tester.pumpAndSettle();
      if (![MMAnnotationColor.yellow, MMAnnotationColor.green, MMAnnotationColor.blue].contains(color)) {
        await tester.tap(find.byTooltip('More Colors'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byWidgetPredicate((w) => w is MMFloatingToolbarColor && w.color == color));
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before.annotations.length);
      expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('selection-highlight')));
      await tester.pumpAndSettle();
      final annotation = controller.content.annotations.last;
      expect(controller.content.cardForAnnotation(annotation.id), isNull);
      expect(controller.content.cards.length, before.cards.length);
      expect(annotation.colorIndex, color.index);
      expect(annotation.quote, selection.text);
      expect(container.read(workspaceProvider('demo-1')).color, color);
      expect(find.byType(SelectionToolbar), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await controller.undo();
      expect(controller.content.annotations.length, before.annotations.length);
      expect(controller.content.cards.length, before.cards.length);
      await settleHud(tester);
    });
  }
  for (final command in [
    ReaderSelectionCommand.excerpt,
    ReaderSelectionCommand.highlight,
    ReaderSelectionCommand.copy,
  ]) {
    for (final keyboard in [false, true]) {
      if (command == ReaderSelectionCommand.excerpt && !keyboard) continue;
      testWidgets('$command keyboard=$keyboard', (tester) async {
        final container = await pumpApp(tester);
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await tester.pumpAndSettle();
        final controller = container.read(workspaceProvider('demo-1').notifier);
        final before = controller.content;
        await controller.onSelectionCommitted('c1', selection);
        await tester.pumpAndSettle();
        if (keyboard) {
          final shortcut =
              readerSelectionShortcuts.entries.firstWhere((e) => e.value.command == command).key as SingleActivator;
          final modifier = shortcut.meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
          if (shortcut.meta || shortcut.control) await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(shortcut.trigger);
          if (shortcut.meta || shortcut.control) await tester.sendKeyUpEvent(modifier);
        } else {
          await tester.tap(
            find.descendant(
              of: find.byType(SelectionToolbar),
              matching: command == ReaderSelectionCommand.copy
                  ? find.byIcon(MMIcons.copy)
                  : find.byIcon(MMIcons.highlight),
            ),
          );
        }
        await tester.pumpAndSettle();
        if (!keyboard && command == ReaderSelectionCommand.highlight) {
          expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingHighlight>());
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        expect(find.byType(SelectionToolbar), findsNothing);
        expect(container.read(workspaceProvider('demo-1')).pending, isNull);
        expect(
          controller.content.annotations.length,
          before.annotations.length + (command == ReaderSelectionCommand.copy ? 0 : 1),
        );
        expect(
          controller.content.cards.length,
          before.cards.length + (command == ReaderSelectionCommand.excerpt ? 1 : 0),
        );
        if (command == ReaderSelectionCommand.copy) {
          expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, selection.text);
        }
        await settleHud(tester);
      });
    }
  }
  for (final outcome in ['save', 'cancel', 'empty']) {
    testWidgets('note $outcome edits on the card, preserves quote and atomic undo', (tester) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final before = controller.content;
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(SelectionToolbar), matching: find.byIcon(MMIcons.addNote)));
      await tester.pumpAndSettle();
      // No dialog: the empty note card is already on the map, open for typing.
      expect(find.byType(MMSheet), findsNothing);
      expect(find.byType(SelectionToolbar), findsNothing);
      final state = container.read(workspaceProvider('demo-1'));
      expect(state.pending, isNull);
      expect(state.editingCardId, isNotNull);
      expect(controller.content.card(state.editingCardId!)!.kind, CardKind.note);
      if (outcome == 'save') {
        tester.testTextInput.enterText('My own words');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else if (outcome == 'cancel') {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        tester.testTextInput.enterText('  ');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).editingCardId, isNull);
      if (outcome == 'save') {
        expect(controller.content.annotations.last.quote, selection.text);
        expect(controller.content.cards.last.title, 'My own words');
        expect(controller.content.cards.last.kind, CardKind.note);
        final excerpt = controller.content.cardForAnnotation(controller.content.annotations.last.id)!;
        expect(controller.content.node(controller.content.cards.last.id)!.parentId, excerpt.id);
        await controller.undo();
      }
      expect(controller.content.cards.length, before.cards.length);
      expect(controller.content.annotations.length, before.annotations.length);
      await settleHud(tester);
    });
  }
  testWidgets('adding a note with the reader alone brings the map back to type on', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.setLayout(MMSplitMode.primary);
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(SelectionToolbar), matching: find.byIcon(MMIcons.addNote)));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.split);
    expect(container.read(workspaceProvider('demo-1')).editingCardId, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
  testWidgets('the toolbar steps aside for the page pill', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    final layout = tester.widget<MMFloatingToolbarLayout>(find.byType(MMFloatingToolbarLayout));
    final area = layout.avoid!(const Size(800, 600));
    expect(area.bottom, 600 - 16);
    expect(area.center.dx, 400);
    final toolbar = tester.getRect(find.byType(MMFloatingToolbar));
    final pill = tester.getRect(find.byTooltip('Next Page')).inflate(2);
    expect(toolbar.overlaps(pill), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
  testWidgets('native menu invokes actions and disables selection keys in a text field', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
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
    final l = tester.element(find.byType(SelectionToolbar)).l10n;
    // Moving between toolbar controls must not rebuild/serialize the menu bar.
    final menu = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final controls = FocusManager.instance.rootScope.descendants
        .where(
          (node) => node.canRequestFocus && node.context?.findAncestorWidgetOfExactType<SelectionToolbar>() != null,
        )
        .toList();
    expect(controls.length, greaterThan(1));
    for (final node in controls.take(2)) {
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)), same(menu));
    }
    final noteShortcut = command(l.addNote).shortcut! as SingleActivator;
    expect(noteShortcut.trigger, AppShortcuts.addNote.trigger);
    expect(noteShortcut.alt, isTrue);
    command(l.excerptWithNote).onSelected!();
    await tester.pumpAndSettle();
    // The note is typed on its card in the map, where selection keys stay out of the way.
    expect(container.read(workspaceProvider('demo-1')).editingCardId, isNotNull);
    expect(find.byType(SelectionToolbar), findsNothing);
    expect(command(l.excerptAction).onSelected, isNull);
    expect(command(l.highlightAction).onSelected, isNull);
    tester.testTextInput.enterText('EH');
    expect(controller.content.annotations.length, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.content.annotations.length, 1);
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    command(l.excerptAction).onSelected!();
    await tester.pumpAndSettle();
    expect(controller.content.annotations.length, 2);
    expect(find.byType(SelectionToolbar), findsNothing);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('clipboard failure keeps selection and retry succeeds', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.onSelectionCommitted('c1', selection);
    await tester.pumpAndSettle();
    var fail = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData' && fail) throw PlatformException(code: 'unavailable');
        return null;
      },
    );
    final copy = find.descendant(of: find.byType(SelectionToolbar), matching: find.byIcon(MMIcons.copy));
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
    fail = false;
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionToolbar), findsNothing);
    await settleHud(tester);
  });

  for (final dismiss in ['escape', 'outside', 'scroll', 'pan', 'next', 'previous', 'document']) {
    testWidgets('dismiss by $dismiss makes no edits', (tester) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final before = controller.content;
      controller.recordPage('c1', 5);
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      final point = tester.getCenter(find.byKey(const ValueKey('pdf-placeholder-c1')));
      switch (dismiss) {
        case 'escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case 'outside':
          await tester.tapAt(point);
        case 'scroll':
          await tester.sendEventToBinding(PointerScrollEvent(position: point, scrollDelta: const Offset(0, 30)));
        case 'pan':
          await tester.sendEventToBinding(PointerPanZoomStartEvent(position: point));
        case 'next':
          await tester.tap(find.byTooltip('Next Page'));
        case 'previous':
          await tester.tap(find.byTooltip('Previous Page'));
        case 'document':
          controller.openDocument('c2');
      }
      await tester.pumpAndSettle();
      expect(find.byType(SelectionToolbar), findsNothing);
      expect(container.read(workspaceProvider('demo-1')).pending, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before.annotations.length);
      expect(controller.content.cards.length, before.cards.length);
      await settleHud(tester);
    });
  }
}
