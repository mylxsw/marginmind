import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/widgets/outline_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;
import 'map_keyboard_test.dart' show key, focusMap;
import 'map_export_test.dart' show scene;

StudySetContent fixture({bool long = false}) {
  var n = 0;
  final e = StudySetEditor(newId: () => 'm${++n}', now: () => testNow);
  final (one, doc) = e.addDocument(StudySetContent.empty, title: 'First book', fileName: 'a.pdf', pageCount: 20);
  final (two, other) = e.addDocument(one, title: 'Second book', fileName: 'b.pdf', pageCount: 20);
  final (three, _) = e.createExcerpt(
    two,
    documentId: doc.id,
    page: 2,
    rects: const [],
    quote: long ? List.filled(40, 'First passage').join(' ') : 'First passage',
    colorIndex: 0,
  );
  return e
      .createExcerpt(three, documentId: other.id, page: 7, rects: const [], quote: 'Second passage', colorIndex: 2)
      .$1;
}

void mergeViewportTests({bool native = false}) {
  for (final structure in MapStructure.values) {
    for (final zoom in [0.75, 1.5]) {
      testWidgets('$structure long excerpt merge and history keep the reading position at $zoom zoom', (tester) async {
        var seq = 0;
        final editor = StudySetEditor(newId: () => 'balance${seq++}', now: () => testNow);
        final (initial, doc) = editor.addDocument(
          StudySetContent.empty,
          title: 'Book',
          fileName: 'a.pdf',
          pageCount: 20,
        );
        var content = initial;
        final ids = <String>[];
        for (var i = 0; i < 6; i++) {
          final (next, card) = editor.createExcerpt(
            content,
            documentId: doc.id,
            page: i + 1,
            rects: const [],
            quote: List.filled(30, 'Passage $i').join(' '),
            colorIndex: i,
          );
          content = next;
          ids.add(card.id);
        }
        final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': content}));
        final provider = workspaceProvider('demo-1');
        final controller = container.read(provider.notifier);
        await controller.setMapStructure(structure);
        controller.selectCards([ids[2], ids[3]]);
        await tester.pumpAndSettle();
        final viewer = find.byType(InteractiveViewer);
        final transform = tester.widget<InteractiveViewer>(viewer).transformationController!;
        final survivor = find.byKey(ValueKey(ids[2]));
        transform.value = zoomMapAt(transform.value, Offset.zero, zoom / mapScale(transform.value));
        await tester.pumpAndSettle();
        final delta = tester.getCenter(viewer) - tester.getCenter(survivor);
        final matrix = transform.value;
        transform.value = matrix.clone()
          ..setTranslationRaw(matrix.storage[12] + delta.dx, matrix.storage[13] + delta.dy, 0);
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(survivor);
        Future<void> expectAnchored() async {
          // Check painted frames too: anchoring only the final layout still
          // lets the node fly away and return during the transition.
          for (var frame = 0; frame < 20; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect((tester.getTopLeft(survivor) - before).distance, lessThan(0.01));
            expect(mapScale(transform.value), closeTo(zoom, 0.001));
          }
          await tester.pumpAndSettle();
          expect(container.read(provider).selectedCardId, ids[2]);
          expect((tester.getTopLeft(survivor) - before).distance, lessThan(0.01));
        }

        await controller.mergeSelected();
        await expectAnchored();
        await settleHud(tester);
        expect(
          (tester.getTopLeft(survivor) - before).distance,
          lessThan(0.01),
          reason: 'ending the merge highlight must not pan',
        );
        await controller.undo();
        await expectAnchored();
        await controller.redo();
        await expectAnchored();
        await settleHud(tester);
      }, semanticsEnabled: !native);
    }
  }

  for (final structure in MapStructure.values) {
    for (final reverse in [false, true]) {
      testWidgets('$structure merge preserves deep selection and viewport (reversed: $reverse)', (tester) async {
        final container = await openFirstSet(tester);
        final provider = workspaceProvider('demo-1');
        final controller = container.read(provider.notifier);
        await controller.setMapStructure(structure);
        controller.selectCard('c3');
        for (var i = 0; i < 8; i++) {
          await controller.addTopic('Deep branch $i');
        }
        final parent = container.read(provider).selectedCardId!;
        final first = await controller.addTopic('First');
        controller.selectCard(parent);
        final second = await controller.addTopic('Second');
        final ids = [first.id, second.id];
        controller.selectCards(reverse ? ids.reversed : ids);
        await tester.pumpAndSettle();
        final viewer = find.byType(InteractiveViewer);
        final transform = tester.widget<InteractiveViewer>(viewer).transformationController!;
        final delta = tester.getCenter(viewer) - tester.getCenter(find.byKey(ValueKey(first.id)));
        final matrix = transform.value;
        transform.value = matrix.clone()
          ..setTranslationRaw(matrix.storage[12] + delta.dx, matrix.storage[13] + delta.dy, 0);
        await tester.pumpAndSettle();
        final root = find.byKey(const ValueKey(rootNodeId));
        expect(tester.getRect(viewer).overlaps(tester.getRect(root)), isFalse);
        final survivor = find.byKey(ValueKey(first.id));
        final before = tester.getTopLeft(survivor);
        final scale = mapScale(transform.value);
        final selections = <String?>[];
        final subscription = container.listen(provider, (_, next) => selections.add(next.selectedCardId));
        addTearDown(subscription.close);

        await tester.tap(find.byKey(const ValueKey('node-bar-merge')));
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect((tester.getTopLeft(survivor) - before).distance, lessThan(0.01));
          expect(tester.getRect(viewer).overlaps(tester.getRect(root)), isFalse);
        }
        await tester.pumpAndSettle();
        expect(controller.content.card(first.id)!.segments, hasLength(2));
        expect(container.read(provider).selectedCardIds, {first.id});
        expect(selections, isNot(contains(null)), reason: 'no intermediate root selection');
        expect(mapScale(transform.value), scale);
        expect((tester.getTopLeft(survivor) - before).distance, lessThan(0.01));
        expect(tester.getRect(viewer).overlaps(tester.getRect(survivor)), isTrue);
        await settleHud(tester);
        expect(
          (tester.getTopLeft(survivor) - before).distance,
          lessThan(0.01),
          reason: 'the highlight expiry must not move the viewport',
        );
      }, semanticsEnabled: !native);
    }
  }
}

void main() {
  mergeViewportTests();

  testWidgets('toolbar merge, split, undo and cross-document segment navigation', (tester) async {
    final original = fixture();
    final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': original}));
    final controller = container.read(workspaceProvider('demo-1').notifier);
    WorkspaceState state() => container.read(workspaceProvider('demo-1'));
    final ids = original.cards.map((c) => c.id).toList();
    controller.selectCards(ids.reversed);
    await tester.pumpAndSettle();
    expect(find.byType(MapSelectionBar), findsOneWidget);
    // Icon-only actions describe their name and shortcut on hover.
    expect(
      tester.widget<MMToolbarPreviewButton>(find.byKey(const ValueKey('node-bar-merge'))).tooltip,
      contains('Merge'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('node-bar-merge'))));
    await tester.pumpAndSettle();
    expect(tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).mergePreviewCardId, ids.first);
    await mouse.removePointer();
    await tester.tap(find.byKey(const ValueKey('node-bar-merge')));
    await tester.pumpAndSettle();
    final merged = controller.content.card(ids.first)!;
    expect(merged.segments.map((s) => s.text), ['First passage', 'Second passage']);
    expect(state().selectedCardIds, {ids.first});
    expect(find.text('Second passage'), findsOneWidget);
    expect(find.textContaining('2 sources · Merged'), findsWidgets);
    await tester.tap(find.text('Second passage'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(referenceState(tester).activeDocumentId, original.documents.last.id);
    expect(referenceState(tester).reveal?.page, 7);
    expect(
      referenceState(tester).reveal!.rects,
      controller.content.annotation(merged.segments.last.annotationId!)!.rects,
    );
    controller.revealCard(merged.id);
    await tester.pumpAndSettle();
    expect(referenceState(tester).activeDocumentId, original.documents.first.id);
    expect(referenceState(tester).reveal?.page, 2);
    controller.tapHighlight(merged.segments.last.annotationId!);
    expect(
      referenceState(tester).reveal!.rects,
      controller.content.annotation(merged.segments.last.annotationId!)!.rects,
    );
    expect(state().flashCardId, merged.id);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.cards.map((c) => c.id), ids);
    expect(state().canUndo, isFalse);
    await controller.redo();
    await controller.splitCard(merged.id);
    await tester.pumpAndSettle();
    expect(controller.content.cards, hasLength(2));
    expect(state().selectedCardIds, hasLength(2));
    expect(controller.content.cards.map((c) => controller.content.segmentsOf(c).single.text), [
      'First passage',
      'Second passage',
    ]);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.card(merged.id)!.segments, hasLength(2));
    controller.revealSegment(merged.id, -1);
    controller.revealSegment(merged.id, 20);
    controller.revealSegment('missing', 0);
    controller.setMapView(MapViewMode.outline);
    await tester.pumpAndSettle();
    expect(find.textContaining('Second passage'), findsWidgets);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('context menu merge and split, visual export includes both document sources', (tester) async {
    final original = fixture();
    final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': original}));
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCards(original.cards.map((c) => c.id));
    await tester.pumpAndSettle();
    await showWholeMap(tester);
    await tester.tap(find.text('First passage'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge 2 nodes'));
    await tester.pumpAndSettle();
    final text = scene(controller.content).commands.where((c) => c['type'] == 'text').map((c) => c['text']).join('\n');
    expect(text, contains('First passage'));
    expect(text, contains('Second passage'));
    expect(text, contains('Second book'));
    await showWholeMap(tester);
    await tester.tap(find.text('First passage'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split into 2 nodes'));
    await tester.pumpAndSettle();
    expect(controller.content.cards, hasLength(2));
    await settleHud(tester);
  });

  testWidgets('a merged card shows every part in full; compact clips each part and can expand', (tester) async {
    final original = fixture(long: true);
    final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': original}));
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCards(original.cards.map((c) => c.id));
    final result = await controller.mergeSelected();
    await tester.pumpAndSettle();
    expect(find.text('Show Full Text'), findsNothing);
    expect(find.text('Second passage'), findsOneWidget);
    await controller.setMapDensity(MapDensity.compact);
    await tester.pumpAndSettle();
    expect(find.text('Show Full Text'), findsOneWidget);
    expect(find.text('Second passage'), findsOneWidget, reason: 'every part keeps its own lines');
    controller.tapHighlight(result!.value!.segments.first.annotationId!);
    await tester.pumpAndSettle();
    expect(find.text('Show Less'), findsOneWidget);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unavailable action says why when clicked', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard('c3');
    await controller.addSummaryAndEdit('Summary');
    await controller.finishMarkEditing('Summary');
    final topic = controller.content.summaries.single.cardId!;
    controller.selectCards(['c3', topic]);
    await tester.pumpAndSettle();
    expect(controller.mergeReason, MapEditReason.summaryTopic);
    await tester.tap(find.byKey(const ValueKey('node-bar-merge')));
    await tester.pump();
    final reason = mapEditReasonText(tester.element(find.byType(MapSelectionBar)), MapEditReason.summaryTopic);
    expect(find.text(reason), findsWidgets);
    expect(controller.content.card('c3')!.segments, isEmpty);
    await settleHud(tester);
  });

  testWidgets('own-words paragraphs have no source colour dot', (tester) async {
    final excerpts = fixture();
    final (original, topic) = StudySetEditor(
      newId: () => 'own',
      now: () => testNow,
    ).addTopic(excerpts, title: 'My own words');
    final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': original}));
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCards([excerpts.cards.first.id, topic.id]);
    final result = await controller.mergeSelected();
    await tester.pumpAndSettle();
    expect(result!.reason, isNull);
    expect(result.value!.segments.map((s) => s.text), ['First passage', 'My own words']);
    // Each paragraph row is a 6 pt dot followed by its text.
    Decoration? dotOf(String text) => tester
        .widgetList<Row>(find.byType(Row))
        .map((row) => row.children)
        .where(
          (c) =>
              c.length == 2 &&
              c.last is Expanded &&
              switch ((c.last as Expanded).child) {
                Text(:final data) => data == text,
                _ => false,
              },
        )
        .map((c) => (c.first as Container).decoration)
        .single;
    expect(dotOf('First passage'), isNotNull);
    expect(dotOf('My own words'), isNull);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcut and invalid merge selection', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCards(['c3']);
    expect(controller.mergeReason, MapEditReason.tooFewCards);
    expect((await controller.mergeSelected())!.reason, MapEditReason.tooFewCards);
    expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
    controller.selectCards(['c4', 'c3']);
    await tester.pumpAndSettle();
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.keyJ, primary: true, alt: true);
    expect(controller.content.card('c3')!.segments, hasLength(2));
    expect(controller.content.card('c4'), isNull);
    await controller.undo();
    controller.setMapView(MapViewMode.outline);
    controller.selectCards(['c3', 'c4']);
    await tester.pumpAndSettle();
    tester.widget<OutlineView>(find.byType(OutlineView)).focusNode.requestFocus();
    await key(tester, LogicalKeyboardKey.keyJ, primary: true, alt: true);
    expect(controller.content.card('c3')!.segments, hasLength(2));
    await settleHud(tester);
  });
}
