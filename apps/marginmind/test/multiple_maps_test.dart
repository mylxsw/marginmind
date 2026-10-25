import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/review/review_controller.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart' hide Card;
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

void main() {
  group('map lifecycle controller', () {
    late ProviderContainer container;
    late WorkspaceController controller;
    WorkspaceState state() => container.read(workspaceProvider('demo-1'));
    setUp(() async {
      container = ProviderContainer(overrides: await testOverrides());
      container.listen(workspaceProvider('demo-1'), (_, _) {});
      await container.read(contentProvider('demo-1').future);
      controller = container.read(workspaceProvider('demo-1').notifier);
    });
    tearDown(() => container.dispose());

    test('create rename delete switch and undo keep a valid map and selection', () async {
      controller.selectCard('c3');
      await controller.addMap(' Second ');
      final id = state().activeMapId;
      expect(id, isNot(MindMap.defaultId));
      expect(controller.content.map(id)!.title, 'Second');
      expect(state().selectedCardIds, isEmpty);
      await controller.renameMap(id, ' Renamed ');
      expect(controller.content.map(id)!.title, 'Renamed');
      await controller.undo();
      expect(controller.content.map(id)!.title, 'Second');
      await controller.redo();
      await controller.placeCardInMap('c3', id);
      await controller.selectMap(MindMap.defaultId);
      controller.selectCard('c3');
      await controller.removeMap(MindMap.defaultId);
      expect(state().activeMapId, id);
      expect(controller.content.card('c3'), isNotNull);
      await controller.removeMap(id);
      expect(controller.content.maps.single.id, id);
      await controller.undo();
      expect(controller.content.maps.length, 2);
      await controller.selectMap(MindMap.defaultId);
      await controller.redo();
      expect(state().activeMapId, id);
      await controller.selectMap('missing');
      expect(state().activeMapId, id);
      await controller.addMap(' ');
      await controller.renameMap(id, ' ');
      expect(controller.content.map(id)!.title, 'Renamed');
    });

    test('shared cards use local tree navigation and scoped exports', () async {
      final annotation = controller.content.annotations.single.id;
      final card = controller.content.cardForAnnotation(annotation)!;
      await controller.addMap('Second');
      final id = state().activeMapId;
      await controller.addHighlightToMap(annotation);
      expect(controller.content.cards.where((c) => c.id == card.id), hasLength(1));
      expect(controller.content.node(card.id, mapId: id), isNotNull);
      final topic = await controller.addTopic('Local topic');
      await controller.moveCard(card.id, topic.id);
      controller.selectCards([card.id, 'c3']);
      expect(state().selectedCardIds, {card.id});
      controller.selectNeighbor(AxisDirection.left);
      expect(state().selectedCardId, topic.id);
      await controller.toggleCollapsed(topic.id);
      await controller.locateHighlightCard(annotation);
      expect(controller.content.node(topic.id, mapId: id)!.collapsed, isFalse);
      expect(controller.content.node(card.id)!.parentId, 'c3');
      final md = controller.export(opml: false, rootTitle: 'set', source: (_, _) => 'source');
      expect(md, startsWith('# Second'));
      expect(md, contains('Local topic'));
      expect(md, isNot(contains('遗忘的规律')));
      expect(controller.export(opml: true, rootTitle: 'set', source: (_, _) => 'source'), contains('Local topic'));
      await controller.rename(card.id, 'Shared title');
      await controller.removeSelected();
      expect(controller.content.card(card.id)!.title, 'Shared title');
      expect(controller.content.node(card.id), isNotNull);
      await controller.undo();
      expect(controller.content.node(card.id, mapId: id), isNotNull);
      await controller.selectMap(MindMap.defaultId);
      expect(controller.content.card(card.id)!.title, 'Shared title');
      expect(controller.export(opml: false, rootTitle: 'set', source: (_, _) => 'source'), startsWith('# set'));
    });

    test('inline edits protect lifecycle and switching does not add history', () async {
      await controller.addMap('Second');
      final id = state().activeMapId;
      await controller.selectMap(MindMap.defaultId);
      controller.beginEditing('c3');
      await controller.selectMap(id);
      await controller.addMap('Blocked');
      await controller.removeMap(id);
      await controller.renameMap(id, 'Blocked');
      await controller.placeCardInMap('c3', id);
      expect(state().activeMapId, MindMap.defaultId);
      expect(controller.content.maps.length, 2);
      expect(controller.content.map(id)!.title, 'Second');
      expect(controller.content.node('c3', mapId: id), isNull);
      await controller.cancelEditing();
      await controller.selectMap(id);
      await controller.undo();
      expect(controller.content.maps, [MindMap.main]);
      expect(state().activeMapId, MindMap.defaultId);
      await controller.redo();
      expect(controller.content.map(id), isNotNull);
    });

    test('review route snapshots map scope and shares its schedule', () async {
      await controller.addMap('Second');
      final id = state().activeMapId;
      final note = await controller.addNote('Only here');
      await container.pump();
      final nav = container.read(navigationProvider.notifier);
      nav.startReview('demo-1', mapId: id);
      final sub = container.listen(reviewSessionProvider('demo-1'), (_, _) {});
      expect(container.read(reviewSessionProvider('demo-1')).queue, [note.id]);
      final review = container.read(reviewSessionProvider('demo-1').notifier);
      review.reveal();
      await review.rate(Rating.good);
      await container.pump();
      sub.close();
      container.invalidate(reviewSessionProvider('demo-1'));
      nav.startReview('demo-1');
      container.listen(reviewSessionProvider('demo-1'), (_, _) {});
      expect(container.read(reviewSessionProvider('demo-1')).queue, isNot(contains(note.id)));
      expect(
        container.read(reviewSessionProvider('demo-1')).queue,
        contains(controller.content.cardForAnnotation(controller.content.annotations.single.id)!.id),
      );
    });
  });

  testWidgets('sidebar creates renames switches deletes and undoes maps', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await tester.tap(find.byTooltip('New Mind Map…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Second');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final id = container.read(workspaceProvider('demo-1')).activeMapId;
    expect(controller.content.map(id)!.title, 'Second');
    expect(find.text('遗忘的规律'), findsNothing);
    await tester.tap(find.byKey(ValueKey('sidebar-map-$id')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename Mind Map…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Renamed');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(controller.content.map(id)!.title, 'Renamed');
    await tester.tap(find.byKey(const ValueKey('sidebar-map-main')));
    await tester.pumpAndSettle();
    expect(find.text('遗忘的规律'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('sidebar-map-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('sidebar-map-$id')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Mind Map'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeMapId, MindMap.defaultId);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.map(id), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared card renders in each canvas and outline', (tester) async {
    final content = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final container = await openFirstSet(tester, content: content);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.addMap('Second');
    final id = container.read(workspaceProvider('demo-1')).activeMapId;
    await controller.placeCardInMap('c3', id);
    await controller.selectMap(id);
    await tester.pumpAndSettle();
    expect(find.text('遗忘的规律'), findsOneWidget);
    expect(find.text('对策一：间隔重复'), findsNothing);
    expect(tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).mapId, id);
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect(find.text('遗忘的规律'), findsOneWidget);
    await controller.rename('c3', 'Shared rename');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-map-main')));
    await tester.pumpAndSettle();
    expect(find.text('Shared rename'), findsOneWidget);
    expect(find.text('对策一：间隔重复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('node menu shares a card and existing highlights attach to the current map', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.addMap('Second');
    final id = container.read(workspaceProvider('demo-1')).activeMapId;
    await controller.selectMap(MindMap.defaultId);
    await tester.pumpAndSettle();
    await tester.tap(find.text('遗忘的规律'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to “Second”'));
    await tester.pumpAndSettle();
    expect(controller.content.node('c3', mapId: id), isNotNull);
    await controller.selectMap(id);
    controller.setLayout(MMSplitMode.split);
    final annotation = controller.content.annotations.single;
    controller.tapHighlight(annotation.id, const Rect.fromLTWH(360, 180, 160, 30));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to Map'));
    await tester.pumpAndSettle();
    final card = controller.content.cardForAnnotation(annotation.id)!;
    expect(controller.content.node(card.id, mapId: id), isNotNull);
    expect(controller.content.cards.where((c) => c.annotationId == annotation.id), hasLength(1));
    await controller.renameMap(id, List.filled(50, 'Very long map title').join(' '));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
  testWidgets('a pending cut cannot switch maps and remove the shared placement there', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.addMap('Second');
    final id = container.read(workspaceProvider('demo-1')).activeMapId;
    await controller.placeCardInMap('c3', id);
    await controller.selectMap(MindMap.defaultId);
    controller.selectCard('c3');
    final write = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MMMapClipboard.channel,
      (_) => write.future,
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MMMapClipboard.channel,
        null,
      ),
    );
    final cut = controller.copySelection(cut: true);
    await tester.pump();
    await controller.selectMap(id);
    await controller.removeMap(MindMap.defaultId);
    await controller.addMap('Blocked');
    expect(container.read(workspaceProvider('demo-1')).activeMapId, MindMap.defaultId);
    expect(controller.content.maps.length, 2);
    write.complete();
    await cut;
    expect(controller.content.node('c3'), isNull);
    expect(controller.content.node('c3', mapId: id), isNotNull);
    await controller.selectMap(id);
    expect(container.read(workspaceProvider('demo-1')).activeMapId, id);
    await controller.undo();
    expect(controller.content.node('c3'), isNotNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
}
