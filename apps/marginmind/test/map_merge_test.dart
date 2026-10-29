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

void main() {
  testWidgets('toolbar merge, split, undo and cross-document segment navigation', (tester) async {
    final original = fixture();
    final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': original}));
    final controller = container.read(workspaceProvider('demo-1').notifier);
    WorkspaceState state() => container.read(workspaceProvider('demo-1'));
    final ids = original.cards.map((c) => c.id).toList();
    controller.selectCards(ids.reversed);
    await tester.pumpAndSettle();
    expect(find.byType(MapSelectionBar), findsOneWidget);
    // Enabled actions carry no tooltip; only a disabled one explains why.
    expect(find.ancestor(of: find.widgetWithText(MMButton, 'Merge'), matching: find.byType(Tooltip)), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.widgetWithText(MMButton, 'Merge')));
    await tester.pumpAndSettle();
    expect(tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).mergePreviewCardId, ids.first);
    await mouse.removePointer();
    await tester.tap(find.widgetWithText(MMButton, 'Merge'));
    await tester.pumpAndSettle();
    final merged = controller.content.card(ids.first)!;
    expect(merged.segments.map((s) => s.text), ['First passage', 'Second passage']);
    expect(state().selectedCardIds, {ids.first});
    expect(find.text('Second passage'), findsOneWidget);
    expect(find.textContaining('2 sources · Merged'), findsWidgets);
    await tester.tap(find.text('Second passage'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(state().activeDocumentId, original.documents.last.id);
    expect(state().reveal?.page, 7);
    expect(state().flashAnnotationId, merged.segments.last.annotationId);
    controller.revealCard(merged.id);
    await tester.pumpAndSettle();
    expect(state().activeDocumentId, original.documents.first.id);
    expect(state().reveal?.page, 2);
    controller.tapHighlight(merged.segments.last.annotationId!);
    expect(state().flashAnnotationId, merged.segments.last.annotationId);
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
    await tester.tap(find.widgetWithText(MMButton, 'Merge'));
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
