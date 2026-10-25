import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import 'map_keyboard_test.dart' show key, focusMap;
import 'workspace_test.dart' show openFirstSet;

void main() {
  String text = '';
  String? internal;
  String? fieldClipboard;
  bool failWrite = false;
  setUp(() {
    text = '';
    internal = null;
    failWrite = false;
    fieldClipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') fieldClipboard = (call.arguments as Map)['text'] as String;
        if (call.method == 'Clipboard.getData') return {'text': fieldClipboard};
        if (call.method == 'Clipboard.hasStrings') return {'value': fieldClipboard != null};
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MMMapClipboard.channel, (
      call,
    ) async {
      if (call.method == 'write') {
        if (failWrite) throw PlatformException(code: 'failed');
        final args = call.arguments as Map;
        text = args['text'] as String;
        internal = args['internal'] as String;
        return null;
      }
      return {'text': text, 'internal': ?internal};
    });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MMMapClipboard.channel,
      null,
    ),
  );

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  Finder node(String id) => find.byKey(ValueKey(id));
  testWidgets('modifier click toggles map and outline selections; delete is one undo step', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    WorkspaceState state() => container.read(workspaceProvider('demo-1'));
    controller.selectCard('c3');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(node('c4'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(state().selectedCardIds, {'c3', 'c4'});
    controller.selectCard('c6');
    await tester.pumpAndSettle();
    await tester.tap(node('c3'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(node('c4'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(state().selectedCardIds, {'c3', 'c4'});
    await key(tester, LogicalKeyboardKey.backspace);
    expect(controller.content.nodes, isEmpty);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.nodes, hasLength(3));
    expect(state().canUndo, isFalse);
    controller.setMapView(MapViewMode.outline);
    controller.selectCard('c3');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text('对策一：间隔重复'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(state().selectedCardIds, {'c3', 'c4'});
    await tester.tap(find.text('对策一：间隔重复'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(state().selectedCardIds, {'c3'});
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('marquee selects intersecting nodes and batch drag/color each undo once', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final bounds = tester
        .getRect(node('c3'))
        .expandToInclude(tester.getRect(node('c4')))
        .expandToInclude(tester.getRect(node('c6')));
    final gesture = await tester.startGesture(bounds.topLeft - const Offset(15, 15));
    await tester.pump();
    await gesture.moveTo(bounds.bottomRight + const Offset(15, 15));
    await tester.pump();
    expect(find.byKey(const ValueKey('map-selection-box')), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).selectedCardIds, {'c3', 'c4', 'c6'});
    // Use the same drop callback as the canvas; nested selections move once.
    final canvas = tester.widget<MindMapCanvas>(find.byType(MindMapCanvas));
    canvas.onMove('c3', null, 0);
    await tester.pumpAndSettle();
    expect(controller.content.node('c6')!.parentId, 'c3');
    await controller.recolorCards(['c6'], MMAnnotationColor.blue);
    expect(
      controller.content.annotation(controller.content.card('c6')!.annotationId!)!.colorIndex,
      MMAnnotationColor.blue.index,
    );
    await controller.undo();
    expect(controller.content.annotation(controller.content.card('c6')!.annotationId!)!.colorIndex, 0);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('copy/cut/paste keep subtrees and types, text fallback, and text editing keeps shortcuts', (
    tester,
  ) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCards(['c3', 'c6']);
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.keyC, primary: true);
    expect(text, contains('\t这条先陡后平'));
    expect(MapClipboard.decode(internal!)!.length, 2);
    controller.selectCard(null);
    await key(tester, LogicalKeyboardKey.keyV, primary: true);
    expect(controller.content.nodes, hasLength(5));
    final pasted = container.read(workspaceProvider('demo-1')).selectedCardId!;
    final child = controller.content.childrenOf(pasted).single.cardId;
    expect(controller.content.card(child)!.kind, CardKind.excerpt);
    await controller.undo();
    expect(controller.content.nodes, hasLength(3));
    controller.selectCard('c3');
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.keyX, primary: true);
    expect(controller.content.nodes, hasLength(1));
    await controller.undo();
    expect(controller.content.nodes, hasLength(3));
    internal = 'malformed';
    text = '- External\n  • Child\n\nOther';
    controller.selectCard(null);
    await key(tester, LogicalKeyboardKey.keyV, primary: true);
    expect(controller.content.nodes, hasLength(6));
    expect(controller.content.cards.where((c) => c.title == 'Child'), hasLength(1));
    await controller.undo();
    controller.selectCard('c3');
    controller.beginEditing('c3');
    await tester.pumpAndSettle();
    final before = controller.content.nodes.length;
    await controller.pasteSelection();
    await controller.copySelection(cut: true);
    expect(controller.content.nodes.length, before);
    expect(find.byType(MMInlineTextField), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('dragging one selected root moves the whole selection and rejects selected descendants', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard(null);
    final target = await controller.addTopic('Drop target');
    controller.selectCards(['c3', 'c4']);
    await tester.pumpAndSettle();
    Future<void> dragTo(String targetId) async {
      final gesture = await tester.startGesture(tester.getCenter(node('c3')));
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(node(targetId)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await dragTo('c6');
    expect(controller.content.node('c3')!.parentId, isNull);
    await dragTo(target.id);
    expect(controller.content.node('c3')!.parentId, target.id);
    expect(controller.content.node('c4')!.parentId, target.id);
    expect(controller.content.node('c6')!.parentId, 'c3');
    await controller.undo();
    expect(controller.content.node('c3')!.parentId, isNull);
    expect(controller.content.node('c4')!.parentId, isNull);
    expect(controller.content.card(target.id), isNotNull);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('native clipboard menu has one shortcut and routes text editing separately', (tester) async {
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

    PlatformMenuItem copyMenu() {
      final items = flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus);
      final copies = items
          .where(
            (item) =>
                item.shortcut is SingleActivator &&
                (item.shortcut! as SingleActivator).trigger == LogicalKeyboardKey.keyC,
          )
          .toList();
      expect(copies, hasLength(1));
      return copies.single;
    }

    copyMenu().onSelected!();
    await tester.pumpAndSettle();
    expect(text, contains('遗忘的规律'));
    controller.beginEditing('c3');
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.keyA, primary: true);
    copyMenu().onSelected!();
    await tester.pumpAndSettle();
    expect(fieldClipboard, '遗忘的规律');
    expect(controller.content.nodes, hasLength(3));
    await key(tester, LogicalKeyboardKey.escape);
    controller.setMapView(MapViewMode.outline);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.keyC, primary: true);
    expect(text, contains('遗忘的规律'));
    controller.selectCard(null);
    await tester.pumpAndSettle();
    expect(copyMenu().onSelected, isNull);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('failed cut retains content and empty paste adds no history', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard('c3');
    failWrite = true;
    await expectLater(controller.copySelection(cut: true), throwsA(isA<PlatformException>()));
    expect(controller.content.nodes, hasLength(3));
    expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
    failWrite = false;
    await controller.pasteSelection();
    expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
