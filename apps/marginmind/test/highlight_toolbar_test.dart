import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/highlight_color_button.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'selection_toolbar_test.dart' show selection;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  bool failClipboard = false;
  setUp(() {
    clipboard = null;
    failClipboard = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (failClipboard) throw PlatformException(code: 'unavailable');
          clipboard = (call.arguments as Map)['text'] as String;
        }
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
  for (final linked in [false, true]) {
    for (final action in ['color', 'map', 'copy', 'delete']) {
      testWidgets('$action on linked=$linked highlight', (tester) async {
        final container = await pumpApp(tester);
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await tester.pumpAndSettle();
        final provider = workspaceProvider('demo-1');
        final controller = container.read(provider.notifier);
        if (!linked) await controller.highlight('c1', selection, MMAnnotationColor.yellow);
        final parent = controller.content.nodes.first.cardId;
        if (action == 'map') {
          await controller.toggleCollapsed(parent);
          controller.selectCard(parent);
          controller.setMapView(MapViewMode.outline);
        }
        final before = controller.content;
        final annotation = before.annotations.last;
        final card = before.cardForAnnotation(annotation.id);
        controller.tapHighlight(annotation.id, selection.viewportRect!);
        await tester.pumpAndSettle();
        expect(find.byType(SelectionToolbar), findsOneWidget);
        expect(
          tester.widget<MMFloatingToolbarLayout>(find.byType(MMFloatingToolbarLayout)).anchor,
          selection.viewportRect,
        );
        expect(find.byTooltip(linked ? 'Locate Card' : 'Add to Map'), findsOneWidget);
        expect(
          tester.widget<HighlightColorButton>(find.byKey(const ValueKey('selection-more-colors'))).color.index,
          annotation.colorIndex,
        );
        switch (action) {
          case 'color':
            await tester.tap(
              find.byWidgetPredicate((w) => w is MMFloatingToolbarColor && w.color == MMAnnotationColor.blue),
            );
          case 'map':
            controller.setLayout(MMSplitMode.primary);
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip(linked ? 'Locate Card' : 'Add to Map'));
          case 'copy':
            await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          case 'delete':
            await tester.tap(find.byTooltip('Delete Highlight'));
        }
        await tester.pumpAndSettle();
        expect(container.read(provider).pending, isNull);
        expect(find.byType(SelectionToolbar), findsNothing);
        switch (action) {
          case 'color':
            expect(controller.content.annotation(annotation.id)!.colorIndex, MMAnnotationColor.blue.index);
            expect(controller.content.cards.length, before.cards.length);
          case 'map':
            final target = controller.content.cardForAnnotation(annotation.id)!;
            expect(container.read(provider).selectedCardId, target.id);
            expect(container.read(provider).flashCardId, target.id);
            expect(container.read(provider).layout, MMSplitMode.split);
            expect(container.read(provider).mapView, MapViewMode.map);
            expect(controller.content.node(parent)!.collapsed, isFalse);
            expect(controller.content.cards.length, before.cards.length + (linked ? 0 : 1));
            if (linked) expect(target.id, card!.id);
          case 'copy':
            expect(clipboard, annotation.quote);
            expect(controller.content, same(before));
          case 'delete':
            expect(controller.content.annotation(annotation.id), isNull);
            expect(controller.content.cardForAnnotation(annotation.id), isNull);
            expect(controller.content.cards.length, before.cards.length - (linked ? 1 : 0));
        }
        if (action == 'color' || action == 'delete' || (action == 'map' && !linked)) {
          await controller.undo();
          expect(controller.content.annotation(annotation.id)!.colorIndex, annotation.colorIndex);
          expect(controller.content.cards.length, before.cards.length);
        }
        await settleHud(tester);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }
  for (final linked in [false, true]) {
    testWidgets('highlight menu map and delete linked=$linked', (tester) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      if (!linked) await controller.highlight('c1', selection, MMAnnotationColor.yellow);
      final annotation = controller.content.annotations.last;
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
      controller.tapHighlight(annotation.id);
      await tester.pumpAndSettle();
      expect(command('Highlight').onSelected, isNull);
      expect(command('Excerpt with Note').onSelected, isNull);
      expect(command('Locate Card').onSelected == null, !linked);
      command(linked ? 'Locate Card' : 'Add to Map').onSelected!();
      await tester.pumpAndSettle();
      expect(controller.content.cardForAnnotation(annotation.id), isNotNull);
      controller.tapHighlight(annotation.id);
      await tester.pumpAndSettle();
      command('Delete Highlight').onSelected!();
      await tester.pumpAndSettle();
      expect(controller.content.annotation(annotation.id), isNull);
      expect(find.byType(SelectionToolbar), findsNothing);
      await settleHud(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
  testWidgets('clipboard failure retains highlight for retry by button', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    final annotation = controller.content.annotations.last;
    controller.tapHighlight(annotation.id);
    await tester.pumpAndSettle();
    final copy = find.descendant(of: find.byType(SelectionToolbar), matching: find.byIcon(MMIcons.copy));
    failClipboard = true;
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(container.read(provider).pending, isA<PendingHighlight>());
    failClipboard = false;
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboard, annotation.quote);
    expect(container.read(provider).pending, isNull);
    await settleHud(tester);
  });
  for (final dismiss in ['escape', 'outside', 'scroll', 'pan', 'next', 'document']) {
    testWidgets('highlight dismiss by $dismiss', (tester) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      final before = controller.content;
      controller.tapHighlight(before.annotations.last.id, selection.viewportRect!);
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
        case 'document':
          controller.openDocument('c2');
      }
      await tester.pumpAndSettle();
      expect(container.read(provider).pending, isNull);
      expect(find.byType(SelectionToolbar), findsNothing);
      expect(controller.content.annotations, before.annotations);
      expect(controller.content.cards, before.cards);
      await settleHud(tester);
    });
  }
}
