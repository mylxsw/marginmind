import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'workspace_test.dart' show openFirstSet;

final _now = DateTime(2026);

/// [count] topics t0, t1, … under the root; t2 has two children.
StudySetContent _topics(int count) => StudySetContent(
  cards: [
    for (var i = 0; i < count; i++) Card(id: 't$i', kind: CardKind.topic, title: 'Topic $i', createdAt: _now),
    Card(id: 't2a', kind: CardKind.topic, title: 'Child a', createdAt: _now),
    Card(id: 't2b', kind: CardKind.topic, title: 'Child b', createdAt: _now),
  ],
  nodes: [
    for (var i = 0; i < count; i++) MapNode(cardId: 't$i', parentId: null, order: i.toDouble()),
    const MapNode(cardId: 't2a', parentId: 't2', order: 0),
    const MapNode(cardId: 't2b', parentId: 't2', order: 1),
  ],
);

const _longQuote =
    'Desirable difficulties slow down initial learning but improve long-term retention and transfer to new '
    'situations, which is why spacing and retrieval practice feel harder than rereading.';

/// One untitled excerpt with a long quote and one titled excerpt, under a
/// topic, from a document.
StudySetContent _excerpts() => StudySetContent(
  documents: [Document(id: 'd', title: 'Book', fileName: 'a.pdf', pageCount: 10, importedAt: _now)],
  annotations: [
    Annotation(id: 'a1', documentId: 'd', page: 3, rects: const [], quote: _longQuote, colorIndex: 0, createdAt: _now),
    Annotation(id: 'a2', documentId: 'd', page: 5, rects: const [], quote: 'Short.', colorIndex: 1, createdAt: _now),
  ],
  cards: [
    Card(id: 'topic', kind: CardKind.topic, title: 'Topic', createdAt: _now),
    Card(id: 'e1', kind: CardKind.excerpt, annotationId: 'a1', createdAt: _now),
    Card(id: 'e2', kind: CardKind.excerpt, title: 'Titled', annotationId: 'a2', createdAt: _now),
  ],
  nodes: const [
    MapNode(cardId: 'topic', parentId: null, order: 0),
    MapNode(cardId: 'e1', parentId: 'topic', order: 0),
    MapNode(cardId: 'e2', parentId: 'topic', order: 1),
  ],
);

class _Harness {
  _Harness(this.tester) {
    addTearDown(transform.dispose);
    addTearDown(focus.dispose);
  }

  final WidgetTester tester;
  final transform = TransformationController();
  final focus = FocusNode();
  final navigated = <AxisDirection>[];
  String? selection;
  String? excerptTarget;
  late StudySetContent content;

  Future<void> pump(StudySetContent initial, {Size size = const Size(800, 600)}) async {
    content = initial;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
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
                  flashCardId: null,
                  transformation: transform,
                  focusNode: focus,
                  excerptTargetId: excerptTarget,
                  onSelect: (id) => setState(() => selection = id),
                  onReveal: (_) {},
                  onRename: (_) {},
                  onDelete: () {},
                  onMove: (_, _, _) {},
                  onToggleCollapsed: (_) {},
                  onNavigate: navigated.add,
                  onAddChild: () {},
                  onShift: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect node(String id) => tester.getRect(find.byKey(ValueKey(id)));

  double get scale => mapScale(transform.value);
  Offset get translation => Offset(transform.value.storage[12], transform.value.storage[13]);

  Offset get center => tester.getCenter(find.byType(MindMapCanvas));

  Future<void> wheel(Offset delta, {Offset? at}) async {
    await tester.sendEventToBinding(PointerScrollEvent(position: at ?? center, scrollDelta: delta));
    await tester.pump();
  }

  Future<void> key(LogicalKeyboardKey key, {bool primary = false}) async {
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    if (primary) await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    if (primary) await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('U-M1 wheel and trackpad', () {
    testWidgets('the mouse wheel pans; Shift + wheel pans sideways; neither zooms', (tester) async {
      final h = _Harness(tester);
      await h.pump(_topics(30), size: const Size(500, 400));
      final scale = h.scale, start = h.translation;

      await h.wheel(const Offset(0, 40));
      expect(h.scale, scale);
      expect(h.translation, start + const Offset(0, -40));

      await h.wheel(const Offset(0, -40));
      expect(h.translation, start);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await h.wheel(const Offset(0, 30));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(h.translation, start + const Offset(-30, 0));
      expect(h.scale, scale);
    });

    testWidgets('wheel panning stops once the far side of the map is in view', (tester) async {
      final h = _Harness(tester);
      await h.pump(_topics(30), size: const Size(500, 400));
      for (var i = 0; i < 200; i++) {
        await h.wheel(const Offset(0, 100));
      }
      final viewport = tester.getRect(find.byType(MindMapCanvas));
      final bottom = [for (var i = 0; i < 30; i++) h.node('t$i').bottom].reduce(math.max);
      expect(bottom, lessThanOrEqualTo(viewport.bottom));
      expect(bottom, greaterThan(viewport.top), reason: 'the map is not scrolled away');
      final settled = h.translation;
      await h.wheel(const Offset(0, 100));
      expect(h.translation, settled);
    });

    testWidgets('⌘ / Ctrl + wheel zooms at the pointer', (tester) async {
      final h = _Harness(tester);
      await h.pump(_topics(4));
      final scale = h.scale;
      final at = h.node('t0').center;
      final scene = h.transform.toScene(at - tester.getTopLeft(find.byType(MindMapCanvas)));
      for (final modifier in [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.controlLeft]) {
        await tester.sendKeyDownEvent(modifier);
        await h.wheel(const Offset(0, -40), at: at);
        await tester.sendKeyUpEvent(modifier);
      }
      expect(h.scale, closeTo(scale * math.exp(80 / 200), 1e-9));
      // The point under the pointer stays put.
      final after = h.transform.toScene(at - tester.getTopLeft(find.byType(MindMapCanvas)));
      expect(after.dx, closeTo(scene.dx, 1e-6));
      expect(after.dy, closeTo(scene.dy, 1e-6));

      // Zooming is bounded.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      for (var i = 0; i < 40; i++) {
        await h.wheel(const Offset(0, -100), at: at);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(h.scale, mapMaxScale);
    });

    testWidgets('pinching zooms at the pointer; two-finger scrolling pans', (tester) async {
      final h = _Harness(tester);
      await h.pump(_topics(4));
      final scale = h.scale;
      final trackpad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await trackpad.panZoomStart(h.center);
      await tester.pump();
      for (final s in [1.1, 1.3, 1.5]) {
        await trackpad.panZoomUpdate(h.center, scale: s);
        await tester.pump();
      }
      await trackpad.panZoomEnd();
      await tester.pumpAndSettle();
      expect(h.scale, closeTo(scale * 1.5, 1e-9));

      final start = h.translation;
      await trackpad.panZoomStart(h.center);
      await tester.pump();
      for (var i = 1; i <= 5; i++) {
        await trackpad.panZoomUpdate(h.center, pan: Offset(0, -10.0 * i));
        await tester.pump();
      }
      await trackpad.panZoomEnd();
      await tester.pumpAndSettle();
      expect(h.scale, closeTo(scale * 1.5, 1e-9));
      expect(h.translation.dy, lessThan(start.dy));

      // A scale signal (another platform's pinch) zooms too.
      await tester.sendEventToBinding(PointerScaleEvent(position: h.center, scale: 0.5));
      await tester.pump();
      expect(h.scale, closeTo(scale * 0.75, 1e-9));
    });
  });

  group('U-M2 balanced map and fit', () {
    testWidgets('branches grow on both sides of the root, connectors and fold buttons facing it', (tester) async {
      final h = _Harness(tester);
      await h.pump(_topics(4));
      final root = h.node(rootNodeId);
      for (final id in ['t0', 't1']) {
        expect(h.node(id).left, greaterThan(root.right));
      }
      for (final id in ['t2', 't3']) {
        expect(h.node(id).right, lessThan(root.left));
      }
      expect(h.node('t2a').right, lessThan(h.node('t2').left), reason: 'grows outward');
      // t2's fold button is on its outer (left) side.
      final fold = tester.getRect(find.byTooltip('Collapse'));
      expect(fold.right, lessThanOrEqualTo(h.node('t2').left));
      expect(fold.center.dy, closeTo(h.node('t2').center.dy, 1));
    });

    testWidgets('arrow keys follow the drawing on the left side', (tester) async {
      final h = _Harness(tester);
      await h.pump(_topics(4));
      h.focus.requestFocus();
      await tester.pump();

      // From the root, ← goes to the first branch on the left.
      await h.key(LogicalKeyboardKey.arrowLeft);
      expect(h.selection, 't2');
      expect(h.navigated, isEmpty);
      // On the left, ← goes outward (children) and → back to the parent.
      await h.key(LogicalKeyboardKey.arrowLeft);
      await h.key(LogicalKeyboardKey.arrowRight);
      await h.key(LogicalKeyboardKey.arrowUp);
      expect(h.navigated, [AxisDirection.right, AxisDirection.left, AxisDirection.up]);

      // On the right nothing is swapped.
      h.navigated.clear();
      h.selection = 't0';
      await h.pump(_topics(4));
      h.focus.requestFocus();
      await h.key(LogicalKeyboardKey.arrowLeft);
      await h.key(LogicalKeyboardKey.arrowRight);
      expect(h.navigated, [AxisDirection.left, AxisDirection.right]);
    });

    testWidgets('a single branch keeps ← from the root doing nothing', (tester) async {
      final h = _Harness(tester);
      await h.pump(_topics(1));
      h.focus.requestFocus();
      await h.key(LogicalKeyboardKey.arrowLeft);
      expect(h.selection, isNull);
      expect(h.navigated, isEmpty);
    });

    testWidgets('fit shows a small map whole and a large one readable around the selection', (tester) async {
      final h = _Harness(tester);
      await h.pump(_topics(4));
      h.focus.requestFocus();
      h.transform.value = Matrix4.identity()..scaleByDouble(2, 2, 1, 1);
      await h.key(LogicalKeyboardKey.digit0, primary: true);
      final viewport = tester.getRect(find.byType(MindMapCanvas));
      expect(h.scale, lessThanOrEqualTo(1));
      for (final id in [rootNodeId, 't0', 't3', 't2a']) {
        final r = h.node(id);
        expect(viewport.contains(r.topLeft) && viewport.contains(r.bottomRight), isTrue, reason: id);
      }

      h.selection = 't40';
      await h.pump(_topics(80), size: const Size(500, 400));
      h.focus.requestFocus();
      await h.key(LogicalKeyboardKey.digit0, primary: true);
      expect(h.scale, mapReadableScale);
      final small = tester.getRect(find.byType(MindMapCanvas));
      expect(h.node('t40').center.dx, closeTo(small.center.dx, 0.5));
      expect(h.node('t40').center.dy, closeTo(small.center.dy, 0.5));

      // Without a selection, around the root.
      h.selection = null;
      await h.pump(_topics(80), size: const Size(500, 400));
      h.focus.requestFocus();
      await h.key(LogicalKeyboardKey.digit0, primary: true);
      expect(h.node(rootNodeId).center.dx, closeTo(small.center.dx, 0.5));
    });

    testWidgets('the first view of a wide balanced map is centered on the root', (tester) async {
      final h = _Harness(tester);
      final wide = _topics(4).copyWith(
        cards: [
          ..._topics(4).cards.where((c) => c.id != 't0'),
          Card(id: 't0', kind: CardKind.topic, title: 'A very long title ' * 3, createdAt: _now),
        ],
      );
      await h.pump(wide, size: const Size(400, 400));
      expect(h.scale, mapReadableScale);
      expect(h.node(rootNodeId).center.dx, closeTo(200, 0.5));
    });
  });

  group('U-M3 / U-M4 excerpt cards', () {
    testWidgets('the quote is the card: no placeholder title, source on hover or selection only', (tester) async {
      final h = _Harness(tester);
      await h.pump(_excerpts());
      expect(find.text('Untitled excerpt'), findsNothing);
      expect(find.text('Titled'), findsOneWidget);
      expect(find.text('Book · Page 3'), findsNothing);
      expect(find.text('Book · Page 5'), findsNothing);
      // Padding, title row (titled only), quote lines in their box; no source row.
      expect(h.node('e1').height / h.scale, 11 + (4 * 20 + 12) + 11 + 2);
      expect(h.node('e2').height / h.scale, 11 + (17 + 6) + (1 * 20 + 12) + 11 + 2);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(h.node('e1').center);
      await tester.pumpAndSettle();
      final source = find.text('Book · Page 3');
      expect(source, findsOneWidget);
      expect(tester.getRect(source).top, greaterThan(h.node('e1').bottom), reason: 'below the card');
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(source, findsNothing);

      h.selection = 'e2';
      await h.pump(_excerpts());
      expect(find.text('Book · Page 5'), findsOneWidget);
      // Topics have no source.
      await mouse.moveTo(h.node('topic').center);
      await tester.pumpAndSettle();
      expect(find.text('Book · Page 3'), findsNothing);
    });

    testWidgets('a quote longer than four lines ends with an ellipsis', (tester) async {
      final h = _Harness(tester);
      await h.pump(_excerpts());
      final quote = find.textContaining('Desirable difficulties');
      final text = tester.widget<Text>(quote).data!;
      expect(text, endsWith('…'));
      expect(_longQuote.startsWith(text.substring(0, text.length - 1).trimRight()), isTrue);
      final paragraph = tester.renderObject<RenderParagraph>(quote);
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'the shown text fits in four lines');
      expect(find.text('Short.'), findsOneWidget, reason: 'short quotes are shown whole');
    });

    testWidgets('cutting a quote never splits a character', (tester) async {
      final h = _Harness(tester);
      final emoji = _excerpts().copyWith(
        annotations: [
          Annotation(
            id: 'a1',
            documentId: 'd',
            page: 3,
            rects: const [],
            quote: '😀' * 120,
            colorIndex: 0,
            createdAt: _now,
          ),
        ],
      );
      await h.pump(emoji);
      final text = tester.widget<Text>(find.textContaining('😀')).data!;
      expect(text, endsWith('…'));
      expect(text.substring(0, text.length - 1), matches(RegExp(r'^(😀)+$')));
    });
  });

  group('U-M5 excerpt target', () {
    testWidgets('the node new excerpts go under is marked on its corner', (tester) async {
      final h = _Harness(tester);
      h.excerptTarget = 'topic';
      await h.pump(_excerpts());
      final mark = tester.getRect(find.byKey(const ValueKey('excerpt-target')));
      expect(mark.center.dx, closeTo(h.node('topic').right, 0.5));
      expect(mark.center.dy, closeTo(h.node('topic').top, 0.5));

      h.excerptTarget = rootNodeId;
      await h.pump(_excerpts());
      expect(
        tester.getRect(find.byKey(const ValueKey('excerpt-target'))).center.dx,
        closeTo(h.node(rootNodeId).right, 0.5),
      );

      h.excerptTarget = null;
      await h.pump(_excerpts());
      expect(find.byKey(const ValueKey('excerpt-target')), findsNothing);
    });

    testWidgets('the pane marks the target on the map instead of describing it', (tester) async {
      final container = await openFirstSet(tester);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final l = AppLocalizations.of(tester.element(find.byType(MindMapCanvas)));
      expect(find.text(l.newExcerptTarget('认知科学入门')), findsNothing);
      Rect mark() => tester.getRect(find.byKey(const ValueKey('excerpt-target')));
      Rect node(String title) =>
          tester.getRect(find.ancestor(of: find.text(title), matching: find.byType(Positioned)).first);
      // Nothing selected: the root.
      expect(mark().center.dx, closeTo(node('认知科学入门').right, 0.5));
      // A topic takes new excerpts itself; an excerpt sends them to its parent.
      final topic = controller.content.cards.firstWhere((c) => c.title == '对策一：间隔重复');
      controller.selectCard(topic.id);
      await tester.pumpAndSettle();
      final target = tester.getRect(find.byKey(ValueKey(topic.id)));
      expect(mark().center, isNot(Offset.zero));
      expect((mark().center.dx - target.left).abs() < 0.5 || (mark().center.dx - target.right).abs() < 0.5, isTrue);
      expect(mark().center.dy, closeTo(target.top, 0.5));
      final excerpt = controller.content.cards.firstWhere((c) => c.kind == CardKind.excerpt);
      final parent = controller.content.node(excerpt.id)!.parentId!;
      controller.selectCard(excerpt.id);
      await tester.pumpAndSettle();
      expect(mark().center.dy, closeTo(tester.getRect(find.byKey(ValueKey(parent))).top, 0.5));
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel(l.newExcerptTarget(controller.content.card(parent)!.title)), findsOneWidget);
      semantics.dispose();
      await settleHud(tester);
    });

    testWidgets('on the left side the mark sits on the outer corner', (tester) async {
      final h = _Harness(tester);
      h.excerptTarget = 't2';
      await h.pump(_topics(4));
      final mark = tester.getRect(find.byKey(const ValueKey('excerpt-target')));
      expect(mark.center.dx, closeTo(h.node('t2').left, 0.5));
    });
  });

  group('marks on the left side', () {
    testWidgets('a relation between stacked left nodes goes around their left, its label on the canvas', (
      tester,
    ) async {
      final h = _Harness(tester);
      await h.pump(
        _topics(4).copyWith(
          relations: const [MapRelation(id: 'r', mapId: MindMap.defaultId, fromId: 't2a', toId: 't2b', label: 'link')],
        ),
      );
      final label = tester.getRect(find.text('link'));
      expect(label.right, lessThan(h.node('t2a').left), reason: 'outward, past the column');
      final canvas = tester.getRect(find.byType(MindMapCanvas));
      // The scene's left edge, at this zoom and pan.
      expect(label.left, greaterThanOrEqualTo(h.translation.dx + canvas.left));

      // A summary of the column opens to the left as well.
      await h.pump(
        _topics(4).copyWith(
          summaries: const [
            MapSummary(id: 's', mapId: MindMap.defaultId, parentId: 't2', fromId: 't2a', toId: 't2b', label: 'both'),
          ],
        ),
      );
      final summary = tester.getRect(find.text('both'));
      expect(summary.right, lessThan(h.node('t2a').left));
      expect(summary.center.dy, closeTo((h.node('t2a').top + h.node('t2b').bottom) / 2, 1));
      expect(tester.takeException(), isNull);
    });

    test('mirrored relation curves stay on the canvas', () {
      const a = Rect.fromLTWH(10, 0, 100, 40), b = Rect.fromLTWH(10, 200, 100, 40);
      final c = relationCurveOnSide(a, b, const [a, b], left: true);
      expect(c.$1, const Offset(10, 20));
      expect(c.$4, const Offset(10, 220));
      expect(c.$2.dx, 0, reason: 'clamped at the canvas edge');
      expect(relationGoesAround(c), isTrue);
      final right = relationCurveOnSide(a, b, const [a, b], left: false);
      expect(right, relationCurve(a, b, const [a, b]));
      final far = relationCurveOnSide(
        const Rect.fromLTWH(400, 0, 100, 40),
        const Rect.fromLTWH(400, 200, 100, 40),
        const [],
        left: true,
      );
      expect(far.$2.dx, lessThan(400));
      expect(far.$2.dx, greaterThan(0));
    });
  });

  test('zoomMapAt keeps the focal point and the zoom limits', () {
    final m = Matrix4.identity()
      ..translateByDouble(30, 40, 0, 1)
      ..scaleByDouble(0.5, 0.5, 1, 1);
    const focal = Offset(100, 80);
    final zoomed = zoomMapAt(m, focal, 2);
    expect(mapScale(zoomed), 1);
    expect(
      MatrixUtils.transformPoint(Matrix4.inverted(zoomed), focal),
      MatrixUtils.transformPoint(Matrix4.inverted(m), focal),
    );
    expect(mapScale(zoomMapAt(m, focal, 100)), mapMaxScale);
    expect(mapScale(zoomMapAt(m, focal, 0.0001)), mapMinScale);
  });
}
