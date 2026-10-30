import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'map_keyboard_test.dart' show focusMap, key;
import 'workspace_test.dart' show openFirstSet;

void main() {
  for (final parentId in ['c3', 'c6']) {
    testWidgets('node toolbar adds an editable note under $parentId in one undo step', (tester) async {
      final container = await openFirstSet(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      WorkspaceState state() => container.read(workspaceProvider('demo-1'));
      expect(find.byTooltip('Add Topic'), findsNothing);
      expect(find.byTooltip('Add Note'), findsNothing);
      expect(find.byTooltip('Insert Image…'), findsNothing);

      controller.selectCard(parentId);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('node-bar-note')));
      await tester.pumpAndSettle();
      final noteId = state().selectedCardId!;
      expect(controller.content.card(noteId)!.kind, CardKind.note);
      expect(controller.content.node(noteId)!.parentId, parentId);
      expect(state().editingCardId, noteId);
      await tester.enterText(find.byType(MMInlineTextField), 'My reading note');
      await key(tester, LogicalKeyboardKey.enter);
      expect(controller.content.card(noteId)!.title, 'My reading note');
      await controller.undo();
      await tester.pumpAndSettle();
      expect(controller.content.card(noteId), isNull);
      expect(controller.content.card(parentId), isNotNull);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    });
  }

  testWidgets('one selected node gets its own toolbar; several get the selection bar; no selection gets none', (
    tester,
  ) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    WorkspaceState state() => container.read(workspaceProvider('demo-1'));

    controller.selectCard('c3');
    await tester.pumpAndSettle();
    expect(find.byType(MapNodeBar), findsOneWidget);
    expect(find.byType(MapSelectionBar), findsNothing);

    final parent = controller.content.node('c3')!.parentId;
    await tester.tap(find.byKey(const ValueKey('node-bar-child')));
    await tester.pumpAndSettle();
    final child = state().selectedCardId!;
    expect(controller.content.node(child)!.parentId, 'c3');
    await controller.cancelEditing();
    await tester.pumpAndSettle();

    controller.selectCard('c3');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('node-bar-sibling')));
    await tester.pumpAndSettle();
    expect(controller.content.node(state().selectedCardId!)!.parentId, parent);
    await controller.cancelEditing();
    await tester.pumpAndSettle();

    controller.selectCard('c3');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('node-bar-relation')));
    await tester.pumpAndSettle();
    expect(state().connectingFromId, 'c3');
    expect(find.byType(MapNodeBar), findsNothing, reason: 'the toolbar steps aside while the line is drawn');
    controller.cancelConnecting();

    controller.selectCards(['c3', 'c4']);
    await tester.pumpAndSettle();
    expect(find.byType(MapSelectionBar), findsOneWidget);
    expect(find.byType(MapNodeBar), findsNothing);

    controller.selectCard(null);
    await tester.pumpAndSettle();
    expect(find.byType(MapNodeBar), findsNothing);
    await settleHud(tester);
  });

  for (final cardId in ['c3', 'c6', 'image']) {
    testWidgets('node menu removes $cardId and undo restores it without a global delete button', (tester) async {
      final demo = demoContent();
      final content = demo.copyWith(
        cards: [
          ...demo.cards,
          Card(id: 'image', kind: CardKind.image, title: 'Image', createdAt: testNow),
        ],
        nodes: [
          ...demo.nodes,
          const MapNode(cardId: 'image', parentId: null, order: 10),
        ],
      );
      final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': content}));
      final controller = container.read(workspaceProvider('demo-1').notifier);
      controller.selectCard(cardId);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove from Map'), findsNothing);
      expect(find.byKey(const ValueKey('node-add-child')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('node-bar-delete')));
      await tester.tap(find.byKey(const ValueKey('node-bar-delete')));
      await tester.pumpAndSettle();
      expect(controller.content.node(cardId), isNull);
      await controller.undo();
      await tester.pumpAndSettle();
      expect(controller.content.node(cardId), isNotNull);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    });
  }

  testWidgets('only an explicit root click shows its reduced menu; blank canvas clears it', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    WorkspaceState state() => container.read(workspaceProvider('demo-1'));
    final root = find.byKey(const ValueKey(rootNodeId));
    bool rootHighlighted() =>
        tester.widget<MMInteractive>(find.descendant(of: root, matching: find.byType(MMInteractive))).selected;
    expect(state().rootSelected, isFalse);
    expect(rootHighlighted(), isFalse);
    expect(find.byType(MapNodeBar), findsNothing);

    await tester.tap(root);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(state().rootSelected, isTrue);
    expect(state().selectedCardIds, isEmpty);
    expect(rootHighlighted(), isTrue);
    for (final action in ['child', 'sibling', 'image', 'assistant']) {
      expect(find.byKey(ValueKey('node-bar-$action')), findsOneWidget);
    }
    for (final action in ['note', 'relation', 'delete']) {
      expect(find.byKey(ValueKey('node-bar-$action')), findsNothing);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.tap(find.byKey(const ValueKey('node-bar-assistant')));
    await tester.pumpAndSettle();
    expect(find.text('Organize This Branch…'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);

    for (final action in ['child', 'sibling']) {
      final button = find.byKey(ValueKey('node-bar-$action'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.content.node(state().editingCardId!)!.parentId, isNull);
      expect(state().rootSelected, isFalse);
      await controller.cancelEditing();
      await tester.pumpAndSettle();
      expect(state().rootSelected, isTrue, reason: 'cancel returns to the explicit root selection');
    }

    final canvas = tester.getRect(find.byType(MindMapCanvas));
    final transform = tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).transformation;
    final before = transform.value.clone();
    await tester.tapAt(canvas.bottomRight - const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(state().rootSelected, isFalse);
    expect(state().selectedCardId, isNull);
    expect(rootHighlighted(), isFalse);
    expect(find.byType(MapNodeBar), findsNothing);
    expect(transform.value, before);

    // With nothing selected, new content still goes under the root.
    await key(tester, LogicalKeyboardKey.tab);
    expect(controller.content.node(state().editingCardId!)!.parentId, isNull);
    await controller.cancelEditing();
    await tester.pumpAndSettle();
    expect(state().rootSelected, isFalse);
    expect(rootHighlighted(), isFalse);
    await settleHud(tester);
  });

  testWidgets('deselecting leaves no node selected without moving the view', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard('c3');
    await tester.pumpAndSettle();
    await focusMap(tester);
    // Pan so the root is far out of view.
    final view = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
    view.value = view.value.clone()..translateByDouble(-2000, -1500, 0, 1);
    await tester.pumpAndSettle();
    final before = view.value.clone();
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).selectedCardId, isNull);
    expect(container.read(workspaceProvider('demo-1')).rootSelected, isFalse);
    expect(view.value, before);
    await settleHud(tester);
  });

  testWidgets('a long excerpt starts wider, one step at a time, unless a width was set', (tester) async {
    var n = 0;
    final editor = StudySetEditor(newId: () => 'w${++n}', now: () => testNow);
    final (withDoc, doc) = editor.addDocument(StudySetContent.empty, title: 'Book', fileName: 'a.pdf', pageCount: 9);
    var content = withDoc;
    for (final (i, length) in [20, 60, 400].indexed) {
      content = editor
          .createExcerpt(
            content,
            documentId: doc.id,
            page: i + 1,
            rects: const [],
            quote: List.filled(length, '记').join(),
            colorIndex: 0,
          )
          .$1;
    }
    final cards = content.cards.map((c) => c.id).toList();
    final container = await openFirstSet(tester, content: InMemoryStudySetContentRepository({'demo-1': content}));
    await tester.pumpAndSettle();
    double width(String id) => tester.getSize(find.byKey(ValueKey(id))).width;
    final short = width(cards[0]), medium = width(cards[1]), long = width(cards[2]);
    expect(medium, greaterThan(short));
    expect(long, greaterThan(medium));
    final controller = container.read(workspaceProvider('demo-1').notifier);
    // Merged parts count as separate paragraphs: two short parts widen the card.
    controller.selectCards([cards[0], cards[1]]);
    final merged = (await controller.mergeSelected())!.value!;
    await tester.pumpAndSettle();
    expect(width(merged.id), greaterThan(short));
    await controller.undo();
    await tester.pumpAndSettle();
    await controller.setCardWidth(cards[2], 240);
    await tester.pumpAndSettle();
    expect(width(cards[2]), closeTo(short, 1), reason: 'a width set by hand wins');
    await settleHud(tester);
  });
}
