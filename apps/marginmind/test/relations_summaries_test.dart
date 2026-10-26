import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart' hide Card;
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'map_keyboard_test.dart' show focusMap, key;
import 'workspace_test.dart' show openFirstSet;

// Demo content: topics c3 "遗忘的规律" and c4 "对策一：间隔重复" at the root,
// the excerpt c6 under c3.

void main() {
  group('controller', () {
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

    MapRelation relation() => controller.content.relations.single;

    test('two selected nodes are related first to last; the label is one more step', () async {
      controller.selectCards(['c3', 'c4']);
      await controller.addRelation();
      expect((relation().fromId, relation().toId), ('c3', 'c4'));
      expect(state().selectedMarkId, relation().id);
      expect(state().selectedCardIds, isEmpty);
      expect(state().editingMarkId, relation().id);
      await controller.finishMarkEditing(' why ');
      expect(relation().label, 'why');
      expect(state().editingMarkId, isNull);
      await controller.undo();
      expect(relation().label, isEmpty);
      await controller.undo();
      expect(controller.content.relations, isEmpty);
      expect(state().selectedMarkId, isNull, reason: 'a mark that is gone is deselected');
      await controller.redo();
      controller.selectMark(relation().id);
      await controller.removeSelectedMark();
      expect(controller.content.relations, isEmpty);
      expect(state().selectedMarkId, isNull);
    });

    test('one selected node starts a line that the next node ends', () async {
      controller.selectCard('c3');
      await controller.addRelation();
      expect(state().connectingFromId, 'c3');
      expect(controller.content.relations, isEmpty);
      await controller.connectTo('c3');
      expect(state().connectingFromId, isNull, reason: 'a node cannot relate to itself');
      expect(controller.content.relations, isEmpty);
      await controller.addRelation();
      controller.cancelConnecting();
      expect(state().connectingFromId, isNull);
      await controller.connectTo('c4');
      expect(controller.content.relations, isEmpty, reason: 'nothing is being drawn');
      await controller.addRelation();
      await controller.connectTo('c6');
      expect((relation().fromId, relation().toId), ('c3', 'c6'));
      await controller.cancelMarkEditing();
      expect(relation().label, isEmpty);
      await controller.cancelMarkEditing();
      controller.selectCard(null);
      await controller.addRelation();
      expect(state().connectingFromId, isNull, reason: 'the root takes no relations');
    });

    test('a summary and its label are one undo step; Esc or an empty label leaves nothing', () async {
      controller.selectCards(['c4', 'c3']);
      await controller.addSummaryAndEdit('Summary');
      final summary = controller.content.summaries.single;
      expect((summary.fromId, summary.toId), ('c3', 'c4'));
      expect(summary.label, 'Summary');
      expect(state().editingMarkId, summary.id);
      expect(state().canUndo, isFalse, reason: 'inside the edit');
      await controller.addSummaryAndEdit('Again');
      expect(controller.content.summaries, hasLength(1), reason: 'one edit at a time');
      controller.beginEditing('c3');
      expect(state().editingCardId, isNull);
      await controller.finishMarkEditing('Both');
      expect(controller.content.summaries.single.label, 'Both');
      await controller.undo();
      expect(controller.content.summaries, isEmpty);
      expect(state().canUndo, isFalse);

      controller.selectCard('c3');
      await controller.addSummaryAndEdit('Summary');
      await controller.cancelMarkEditing();
      expect(controller.content.summaries, isEmpty);
      await controller.addSummaryAndEdit('Summary');
      await controller.finishMarkEditing('  ');
      expect(controller.content.summaries, isEmpty);
      expect(state().canUndo, isFalse);

      controller.selectCards(['c3', 'c6']);
      await controller.addSummaryAndEdit('Summary');
      expect(controller.content.summaries, isEmpty, reason: 'not siblings');
      expect(state().editingMarkId, isNull);
      controller.selectCard(null);
      await controller.addSummaryAndEdit('Summary');
      expect(controller.content.summaries, isEmpty);
    });

    test('editing an existing label, clearing it, and selection rules', () async {
      controller.selectCard('c3');
      await controller.addSummaryAndEdit('Summary');
      await controller.finishMarkEditing('Kept');
      final id = controller.content.summaries.single.id;
      controller.selectMark('missing');
      expect(state().selectedMarkId, id);
      controller.selectCard('c4');
      expect(state().selectedMarkId, isNull, reason: 'a node selection replaces the mark');
      controller.selectMark(id);
      expect(state().selectedCardIds, isEmpty);
      controller.beginMarkEditing(id);
      controller.beginMarkEditing('missing');
      await controller.finishMarkEditing('Kept');
      expect(state().canUndo, isTrue);
      controller.beginMarkEditing(id);
      await controller.finishMarkEditing('');
      expect(controller.content.summaries.single.label, isEmpty, reason: 'a kept summary may lose its label');
      await controller.finishMarkEditing('ignored');
      controller.selectMark(null);
      expect(state().selectedMarkId, isNull);
      await controller.removeSelectedMark();
      expect(controller.content.summaries, hasLength(1));
      // Switching maps drops a line being drawn.
      controller.selectCard('c3');
      await controller.addRelation();
      await controller.addMap('Second');
      expect(state().connectingFromId, isNull);
    });

    test('export uses the localized labels it is given', () async {
      controller.selectCards(['c3', 'c4']);
      await controller.addRelation();
      await controller.finishMarkEditing('link');
      controller.selectCards(['c3', 'c4']);
      await controller.addSummaryAndEdit('Summary');
      await controller.finishMarkEditing('pair');
      final md = controller.export(
        opml: false,
        rootTitle: 'set',
        source: (_, _) => 'source',
        summary: (label) => '概要：$label',
        relationsTitle: '关联',
      );
      expect(md, contains('- *概要：pair*'));
      expect(md, contains('## 关联'));
      expect(md, contains('遗忘的规律 → 对策一：间隔重复 — link'));
      final opml = controller.export(opml: true, rootTitle: 'set', source: (_, _) => 'source');
      expect(opml, contains('_mmRelations='));
      expect(opml, contains('_mmSummaries='));
    });
  });

  group('canvas', () {
    InteractiveViewer viewer(WidgetTester tester) => tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    RenderBox viewerBox(WidgetTester tester) => tester.renderObject<RenderBox>(find.byType(InteractiveViewer));
    Rect sceneRect(WidgetTester tester, String id) {
      final global = tester.getRect(find.byKey(ValueKey(id)));
      final box = viewerBox(tester);
      final controller = viewer(tester).transformationController!;
      return Rect.fromPoints(
        controller.toScene(box.globalToLocal(global.topLeft)),
        controller.toScene(box.globalToLocal(global.bottomRight)),
      );
    }

    Offset toGlobal(WidgetTester tester, Offset scene) =>
        viewerBox(tester)
            .localToGlobal(MatrixUtils.transformPoint(viewer(tester).transformationController!.value, scene));

    /// Empty canvas below the root node (branches leave it on both sides).
    Offset blank(WidgetTester tester) {
      final root = sceneRect(tester, rootNodeId);
      return toGlobal(tester, Offset(root.center.dx, root.bottom + 30));
    }

    /// Pans so [finder] is in the middle of the map pane.
    Future<void> reveal(WidgetTester tester, Finder finder) async {
      final controller = viewer(tester).transformationController!;
      final box = viewerBox(tester);
      final d = box.size.center(Offset.zero) - box.globalToLocal(tester.getCenter(finder));
      final m = controller.value;
      controller.value = m.clone()..setTranslationRaw(m.storage[12] + d.dx, m.storage[13] + d.dy, 0);
      await tester.pumpAndSettle();
    }

    /// A point on the drawn line from [from] to [to], away from its label;
    /// [others] are the nodes the line has to take into account.
    Offset onLine(WidgetTester tester, String from, String to, {List<String> others = const [], double t = 0.3}) =>
        toGlobal(
          tester,
          cubicPoint(
            relationCurve(sceneRect(tester, from), sceneRect(tester, to), [
              for (final id in others) sceneRect(tester, id),
            ]),
            t,
          ),
        );

    Future<WorkspaceController> open(WidgetTester tester) async {
      final container = await openFirstSet(tester);
      return container.read(workspaceProvider('demo-1').notifier);
    }

    WorkspaceState state(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(MindMapCanvas))).read(workspaceProvider('demo-1'));

    testWidgets('a relation is drawn between nodes, labeled in place, selected by its line and deleted', (
      tester,
    ) async {
      final controller = await open(tester);
      controller.selectCard('c3');
      await focusMap(tester);
      await key(tester, LogicalKeyboardKey.keyR, primary: true, alt: true);
      expect(state(tester).connectingFromId, 'c3');
      // A dashed line follows the pointer until a node is clicked.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byType(MindMapCanvas)) + const Offset(0, 200));
      await mouse.moveBy(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mind-map-marks')), findsOneWidget);
      await tester.tap(find.text('对策一：间隔重复'));
      // A node also takes double clicks: its tap waits out the double-click time.
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(state(tester).connectingFromId, isNull);
      final id = controller.content.relations.single.id;
      expect(find.byType(MMInlineTextField), findsOneWidget, reason: 'the label opens for typing');
      await tester.enterText(find.byType(MMInlineTextField), 'leads to');
      await key(tester, LogicalKeyboardKey.enter);
      expect(controller.content.relations.single.label, 'leads to');
      expect(find.text('leads to'), findsOneWidget);

      // The label follows the nodes when they move.
      final before = tester.getCenter(find.text('leads to'));
      await controller.moveCards(['c4'], 'c3');
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('leads to')), isNot(before));

      controller.selectCard(null);
      await tester.pumpAndSettle();
      // A short line: its label covers the middle.
      await tester.tapAt(onLine(tester, 'c3', 'c4', others: ['c6'], t: 0.1));
      await tester.pumpAndSettle();
      expect(state(tester).selectedMarkId, id);
      await focusMap(tester);
      await key(tester, LogicalKeyboardKey.f2);
      expect(state(tester).editingMarkId, id);
      await key(tester, LogicalKeyboardKey.escape);
      expect(state(tester).editingMarkId, isNull);
      expect(controller.content.relations.single.label, 'leads to');
      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.content.relations, isEmpty);
      expect(find.text('leads to'), findsNothing);
      await settleHud(tester);
    });

    testWidgets('Esc and clicking the root or empty canvas stop drawing a relation', (tester) async {
      final controller = await open(tester);
      for (final stop in ['esc', 'root', 'canvas']) {
        controller.selectCard('c3');
        await controller.addRelation();
        await tester.pumpAndSettle();
        await focusMap(tester);
        switch (stop) {
          case 'esc':
            await key(tester, LogicalKeyboardKey.escape);
          case 'root':
            await tester.tap(find.text('认知科学入门').last);
          default:
            await tester.tapAt(blank(tester));
        }
        await tester.pumpAndSettle();
        expect(state(tester).connectingFromId, isNull, reason: stop);
        expect(controller.content.relations, isEmpty, reason: stop);
      }
      await settleHud(tester);
    });

    testWidgets('a line between stacked nodes and its label stay inside the scene and the fitted view', (tester) async {
      final controller = await open(tester);
      const label = 'a rather long relationship label';
      // A column of leaves under c3, the tallest branch: right of the root.
      controller.selectCard('c3');
      final first = await controller.addTopic('First');
      controller.selectCard('c3');
      final middle = await controller.addTopic('A much wider topic in between');
      controller.selectCard('c3');
      final last = await controller.addTopic('Last');
      controller.selectCards([first.id, last.id]);
      await controller.addRelation();
      await controller.finishMarkEditing(label);
      await tester.pumpAndSettle();
      bool inside(Rect outer, Rect inner) =>
          inner.left >= outer.left &&
          inner.top >= outer.top &&
          inner.right <= outer.right &&
          inner.bottom <= outer.bottom;
      final text = find.text(label);
      // The canvas: the nearest stack holding both the label and the nodes.
      final around = find.ancestor(of: text, matching: find.byType(Stack)).evaluate().toSet();
      final canvas = find
          .ancestor(of: find.byKey(const ValueKey('c3')), matching: find.byType(Stack))
          .evaluate()
          .firstWhere(around.contains);
      final scene = tester.getRect(find.byElementPredicate((e) => e == canvas));
      final rect = tester.getRect(text);
      expect(inside(scene, rect), isTrue, reason: 'not clipped: $rect in $scene');
      expect(rect.left, greaterThan(tester.getRect(find.byKey(ValueKey(middle.id))).right), reason: 'past the column');

      // The map alone has room to fit it all at a readable zoom.
      controller.setLayout(MMSplitMode.secondary);
      await tester.pumpAndSettle();
      await focusMap(tester);
      await key(tester, LogicalKeyboardKey.digit0, primary: true);
      expect(mapScale(viewer(tester).transformationController!.value), greaterThanOrEqualTo(mapReadableScale));
      final view = viewerBox(tester).localToGlobal(Offset.zero) & viewerBox(tester).size;
      expect(inside(view, tester.getRect(text)), isTrue, reason: 'fit shows it: ${tester.getRect(text)} in $view');
      await settleHud(tester);
    });

    testWidgets('a summary is added from the menu, edited in place and removed from its bracket menu', (tester) async {
      final controller = await open(tester);
      controller.selectCards(['c3', 'c4']);
      await tester.pumpAndSettle();
      await focusMap(tester);
      await key(tester, LogicalKeyboardKey.bracketRight, primary: true);
      expect(find.byType(MMInlineTextField), findsOneWidget);
      await tester.enterText(find.byType(MMInlineTextField), 'Two ideas');
      await key(tester, LogicalKeyboardKey.enter);
      final summary = controller.content.summaries.single;
      expect(summary.label, 'Two ideas');
      await key(tester, LogicalKeyboardKey.digit0, primary: true);
      await reveal(tester, find.text('Two ideas'));
      final label = tester.getRect(find.text('Two ideas'));
      final width = tester.getRect(find.byKey(const ValueKey('c3'))).right;
      expect(label.left, greaterThan(width), reason: 'right of the covered nodes');
      final text = tester.renderObject<RenderParagraph>(find.text('Two ideas'));
      expect(
        text.size.width,
        greaterThan(text.getMaxIntrinsicWidth(double.infinity)),
        reason: 'room for glyphs a fraction wider than measured, so the label never wraps',
      );

      // Double click edits the label; Esc keeps the old text.
      await doubleTap(tester, find.text('Two ideas'));
      expect(state(tester).editingMarkId, summary.id);
      await tester.enterText(find.byType(MMInlineTextField), 'Changed');
      await key(tester, LogicalKeyboardKey.escape);
      expect(controller.content.summaries.single.label, 'Two ideas');

      // The bracket sits just left of the label.
      controller.selectCard(null);
      await tester.pumpAndSettle();
      final scale = mapScale(viewer(tester).transformationController!.value);
      final shown = tester.getRect(find.text('Two ideas'));
      final bracket = Offset(
        shown.left - (MMSpacing.s + MMSpacing.m / 2) * scale - MMSpacing.m * scale,
        shown.center.dy,
      );
      await tester.tapAt(bracket, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(state(tester).selectedMarkId, summary.id);
      expect(find.text('Delete Summary'), findsOneWidget);
      await tester.tap(find.text('Delete Summary'));
      await tester.pumpAndSettle();
      expect(controller.content.summaries, isEmpty);
      await settleHud(tester);
    });

    testWidgets('node menu adds relations and summaries; label menu edits and deletes', (tester) async {
      final controller = await open(tester);
      await tester.tap(find.text('遗忘的规律'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Summary'));
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.enter);
      expect(controller.content.summaries.single.label, 'Summary');

      await tester.tap(find.text('遗忘的规律'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Relationship'));
      await tester.pumpAndSettle();
      expect(state(tester).connectingFromId, 'c3');
      await tester.tap(find.text('对策一：间隔重复'));
      // A node also takes double clicks: its tap waits out the double-click time.
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(MMInlineTextField), 'link');
      await key(tester, LogicalKeyboardKey.enter);

      await tester.tap(find.text('link'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Label'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(MMInlineTextField), 'renamed');
      await tester.tapAt(blank(tester));
      await tester.pumpAndSettle();
      expect(controller.content.relations.single.label, 'renamed', reason: 'clicking elsewhere confirms');

      await tester.tap(find.text('renamed'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Relationship'));
      await tester.pumpAndSettle();
      expect(controller.content.relations, isEmpty);

      // The toolbar's trash removes a selected mark too. The label may end at
      // the window's right edge: tap its start.
      await reveal(tester, find.text('Summary'));
      await tester.tapAt(tester.getRect(find.text('Summary')).centerLeft + const Offset(MMSpacing.s, 0));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(state(tester).selectedMarkId, controller.content.summaries.single.id);
      await tester.tap(find.byTooltip('Remove from Map'));
      await tester.pumpAndSettle();
      expect(controller.content.summaries, isEmpty);
      expect(controller.content.card('c3'), isNotNull);
      await settleHud(tester);
    });

    testWidgets('marks of folded nodes are hidden and come back on expand', (tester) async {
      final controller = await open(tester);
      final topic = await controller.addTopic('Child');
      await controller.moveCards([topic.id], 'c3');
      controller.selectCards([topic.id, 'c6']);
      await controller.addSummaryAndEdit('Pair');
      await controller.finishMarkEditing('Pair');
      controller.selectCards(['c6', 'c4']);
      await controller.addRelation();
      await controller.finishMarkEditing('far');
      await tester.pumpAndSettle();
      expect(find.text('Pair'), findsOneWidget);
      expect(find.text('far'), findsOneWidget);
      await controller.toggleCollapsed('c3');
      await tester.pumpAndSettle();
      expect(find.text('Pair'), findsNothing);
      expect(find.text('far'), findsNothing);
      await controller.toggleCollapsed('c3');
      await tester.pumpAndSettle();
      expect(find.text('Pair'), findsOneWidget);
      expect(find.text('far'), findsOneWidget);
      await settleHud(tester);
    });
  });

  test('relation curves leave the facing borders and bow aside', () {
    const a = Rect.fromLTWH(0, 0, 100, 40), b = Rect.fromLTWH(300, 0, 100, 40);
    final c = relationCurve(a, b);
    expect(c.$1, const Offset(100, 20));
    expect(c.$4, const Offset(300, 20));
    expect(cubicPoint(c, 0.5).dy, isNot(20), reason: 'bowed');
    expect(cubicPoint(c, 0), c.$1);
    expect(cubicPoint(c, 1), c.$4);
    final same = relationCurve(a, a);
    expect(same.$1, a.center);
  });

  test('relation curves between stacked leaves run outside the column', () {
    const a = Rect.fromLTWH(0, 0, 100, 40), b = Rect.fromLTWH(10, 400, 120, 40);
    const between = Rect.fromLTWH(0, 200, 160, 40), parent = Rect.fromLTWH(-200, 200, 100, 40);
    final c = relationCurve(a, b, const [a, b, between, parent]);
    expect(c.$1, const Offset(100, 20));
    expect(c.$4, const Offset(130, 420));
    final middle = cubicPoint(c, 0.5);
    expect(middle.dx, greaterThanOrEqualTo(160 + 120 * 0.75), reason: 'apex clears the widest node in between');
    expect(relationGoesAround(c), isTrue);
    for (var t = 0.1; t < 1; t += 0.1) {
      expect(cubicPoint(c, t).dx, greaterThanOrEqualTo(100), reason: 'never crosses the column at $t');
    }
    expect(relationCurve(b, a).$4, const Offset(100, 20));
    final near = relationCurve(a, const Rect.fromLTWH(0, 50, 100, 40));
    expect(cubicPoint(near, 0.5).dx, greaterThan(100 + 30), reason: 'a minimum bow for neighbours');

    // A node with children to its right keeps the plain curve.
    const child = Rect.fromLTWH(160, 0, 80, 40);
    final plain = relationCurve(a, b, const [child]);
    expect(plain.$1.dy, 40, reason: 'leaves the facing (bottom) border');
    expect(plain.$4.dy, 400, reason: 'enters the facing (top) border');
    expect(relationGoesAround(plain), isFalse);
    expect(relationGoesAround(relationCurve(a, const Rect.fromLTWH(300, 0, 100, 40))), isFalse);
  });

  test('summary and relation commands have shortcuts', () {
    expect(mindMapShortcuts.values, containsAll([MindMapCommand.relation, MindMapCommand.summary]));
  });
}
