import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

final _now = DateTime(2026);

/// [count] topics t0, t1, … directly under the root; t1 has a child t1a.
StudySetContent _topics(int count) => StudySetContent(
  cards: [
    for (var i = 0; i < count; i++) Card(id: 't$i', kind: CardKind.topic, title: 'Topic $i', createdAt: _now),
    Card(id: 't1a', kind: CardKind.topic, title: 'Child', createdAt: _now),
  ],
  nodes: [
    for (var i = 0; i < count; i++) MapNode(cardId: 't$i', parentId: null, order: i.toDouble()),
    const MapNode(cardId: 't1a', parentId: 't1', order: 0),
  ],
);

class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final transform = TransformationController();
  final focus = FocusNode();
  final moves = <String>[];
  String? selection;
  Set<String> selected = {};
  late StudySetContent content;
  late StateSetter rebuild;

  Future<void> pump(StudySetContent initial, {Size size = const Size(700, 500)}) async {
    content = initial;
    addTearDown(transform.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            theme: MMTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: MindMapCanvas(
                    content: content,
                    rootTitle: 'Root',
                    selectedCardId: selection,
                    selectedCardIds: selected,
                    flashCardId: null,
                    transformation: transform,
                    focusNode: focus,
                    onSelect: (id) => setState(() {
                      selection = id;
                      selected = {?id};
                    }),
                    onReveal: (_) {},
                    onRename: (_) {},
                    onDelete: () {},
                    onMove: (id, parent, index) => moves.add('$id:$parent:$index'),
                    onToggleCollapsed: (_) {},
                    onNavigate: (_) {},
                    onAddChild: () {},
                    onShift: (_) {},
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect node(String id) => tester.getRect(find.byKey(ValueKey(id)));

  Finder get preview => find.byKey(const ValueKey('map-drop-preview'));

  /// Starts dragging [id] with enough small steps for `Draggable` to start.
  Future<TestGesture> grab(String id) async {
    final gesture = await tester.startGesture(node(id).center);
    await gesture.moveBy(const Offset(8, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    return gesture;
  }

  Future<void> moveTo(TestGesture gesture, Offset to) async {
    await gesture.moveTo(to);
    await tester.pump();
  }
}

void main() {
  testWidgets('the preview line or ring shows exactly where the node lands', (tester) async {
    final h = _Harness(tester);
    await h.pump(_topics(4));
    final scale = mapScale(h.transform.value);

    Future<Rect?> dropAt(Offset Function(Rect target) point, String target) async {
      final gesture = await h.grab('t0');
      final to = point(h.node(target));
      await h.moveTo(gesture, to);
      final shown = h.preview.evaluate().isEmpty ? null : tester.getRect(h.preview);
      await gesture.up();
      await tester.pumpAndSettle();
      return shown;
    }

    // Bottom quarter of t2: a line in the gap below it; t0 lands after t2.
    final t2 = h.node('t2');
    final after = await dropAt((r) => Offset(r.center.dx, r.bottom - 2), 't2');
    expect(h.moves.removeLast(), 't0:null:2');
    expect(after!.height, lessThan(4));
    expect(after.center.dy, closeTo(t2.bottom + 7 * scale, 1));
    expect(after.left, closeTo(t2.left, 0.5));

    // The gap above t3 (below t2) is the same slot and the same line.
    final gap = await dropAt((r) => Offset(r.center.dx, r.top - 2 * scale), 't3');
    expect(h.moves.removeLast(), 't0:null:2');
    expect(gap!.center.dy, closeTo(after.center.dy, 1));

    // Top quarter of t1: before it.
    final before = await dropAt((r) => Offset(r.center.dx, r.top + 2), 't1');
    expect(h.moves.removeLast(), 't0:null:0');
    expect(before!.center.dy, closeTo(h.node('t1').top - 7 * scale, 1));

    // Middle of t3: a ring around it; t0 becomes its last child.
    final ring = await dropAt((r) => r.center, 't3');
    expect(h.moves.removeLast(), 't0:t3:null');
    expect(ring, h.node('t3'));

    // The root takes children anywhere on it.
    await dropAt((r) => Offset(r.center.dx, r.top + 2), '__root__');
    expect(h.moves.removeLast(), 't0:null:null');

    // A drag that starts on the very move that reaches the target still
    // previews and drops there (Draggable's first update reports the press).
    final quick = await tester.startGesture(h.node('t0').center);
    await h.moveTo(quick, h.node('t3').center);
    expect(tester.getRect(h.preview), h.node('t3'));
    await quick.up();
    await tester.pumpAndSettle();
    expect(h.moves.removeLast(), 't0:t3:null');

    // Onto itself or empty canvas: no preview, no move.
    expect(await dropAt((r) => r.center, 't0'), isNull);
    expect(await dropAt((r) => Offset(r.right + 200, r.center.dy), 't3'), isNull);
    expect(h.moves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a multi-selection shows a count and moves the selection; descendants refuse', (tester) async {
    final h = _Harness(tester);
    h.selection = 't1';
    h.selected = {'t0', 't1'};
    await h.pump(_topics(4));
    final gesture = await h.grab('t1');
    expect(find.text('2'), findsOneWidget);
    // t1's own child cannot take the selection.
    await h.moveTo(gesture, h.node('t1a').center);
    expect(h.preview, findsNothing);
    await h.moveTo(gesture, Offset(h.node('t3').center.dx, h.node('t3').bottom - 2));
    expect(h.preview, findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    // Remaining siblings are t2, t3: after t3 is index 2.
    expect(h.moves, ['t1:null:2']);
    expect(h.selected, {'t0', 't1'});
    expect(find.text('2'), findsNothing);
  });

  testWidgets('holding a drag at the edge scrolls the canvas until the map ends; drop matches the preview', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump(_topics(40), size: const Size(500, 400));
    double ty() => h.transform.value.storage[13];
    final canvas = tester.getRect(find.byType(MindMapCanvas));
    // The tree is centered on the root, so the middle topic is on screen.
    final gesture = await h.grab('t20');
    final start = ty();

    // Near the bottom edge: the map moves up and keeps moving.
    final edge = Offset(h.node('t20').left + 10, canvas.bottom - 6);
    await h.moveTo(gesture, edge);
    await tester.pump(const Duration(milliseconds: 100));
    final early = ty();
    expect(early, lessThan(start));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ty(), lessThan(early));

    // Beyond the canvas it scrolls at full speed but offers no drop.
    await h.moveTo(gesture, edge + const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.preview, findsNothing);
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // It stopped with the last topic in view.
    final settled = ty();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ty(), settled);
    expect(h.node('t39').bottom, lessThanOrEqualTo(canvas.bottom));

    // Back up toward the top edge; when the pointer rests the preview
    // follows the nodes scrolling under it.
    final top = Offset(edge.dx, canvas.top + 20);
    await h.moveTo(gesture, top);
    await tester.pump(const Duration(milliseconds: 16));
    final previews = <Rect>{};
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (h.preview.evaluate().isNotEmpty) previews.add(tester.getRect(h.preview));
    }
    expect(previews.length, greaterThan(1));
    final shown = tester.getRect(h.preview);
    // Which slot the last preview stands for, read from the nodes around it.
    String? expected;
    for (var i = 0; i < 40; i++) {
      if (i == 20) continue;
      final r = h.node('t$i');
      if (shown.height < 4 && (shown.center.dy - (r.top - 7 * mapScale(h.transform.value))).abs() < 1) {
        expected = 't20:null:${i < 20 ? i : i - 1}';
      } else if (shown == r) {
        expected = 't20:t$i:null';
      }
    }
    expect(expected, isNotNull);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.moves, [expected]);
    // Scrolling stops with the drag.
    final after = ty();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ty(), after);
  });

  testWidgets('a dragged node removed mid-drag ends the drag without a move', (tester) async {
    final h = _Harness(tester);
    await h.pump(_topics(4));
    final gesture = await h.grab('t3');
    await h.moveTo(gesture, h.node('t1').center);
    expect(h.preview, findsOneWidget);
    final editor = StudySetEditor(newId: () => 'x', now: () => _now);
    // Undo, a fold or another window removes the target: no preview, no crash.
    h.rebuild(() => h.content = editor.removeMany(h.content, {'t1'}));
    await tester.pump();
    await tester.pump();
    expect(h.preview, findsNothing);
    await h.moveTo(gesture, h.node('t2').center);
    expect(h.preview, findsOneWidget);
    // Then the node being dragged.
    h.rebuild(() => h.content = editor.removeMany(h.content, {'t3'}));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.moves, isEmpty);
    expect(h.preview, findsNothing);
    // The canvas is usable again: the next drag moves as usual.
    final next = await h.grab('t0');
    await h.moveTo(next, h.node('t2').center);
    await next.up();
    await tester.pumpAndSettle();
    expect(h.moves, ['t0:t2:null']);
  });
}
