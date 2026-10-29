import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'map_keyboard_test.dart' show focusMap, key;
import 'workspace_test.dart' show openFirstSet;

void main() {
  testWidgets('one selected node gets its own toolbar; several get the selection bar; the root none', (tester) async {
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

  testWidgets('deselecting returns focus to the root without moving the view', (tester) async {
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
    await controller.setCardWidth(cards[2], 240);
    await tester.pumpAndSettle();
    expect(width(cards[2]), closeTo(short, 1), reason: 'a width set by hand wins');
    await settleHud(tester);
  });
}
