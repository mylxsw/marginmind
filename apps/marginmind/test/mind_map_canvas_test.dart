import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'mind_map_cache_test.dart' show fixture;

void main() {
  testWidgets('marquee paints beyond every scene edge after pan and zoom', (tester) async {
    final transform = TransformationController();
    final focus = FocusNode();
    addTearDown(transform.dispose);
    addTearDown(focus.dispose);
    const captureKey = ValueKey('canvas-capture');
    Set<String> selected = {};
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RepaintBoundary(
            key: captureKey,
            child: SizedBox(
              width: 700,
              height: 500,
              child: MindMapCanvas(
                content: fixture(1),
                rootTitle: 'Root',
                selectedCardId: null,
                flashCardId: null,
                transformation: transform,
                focusNode: focus,
                onSelect: (_) {},
                onSelectMany: (ids) => selected = ids,
                onReveal: (_) {},
                onRename: (_) {},
                onDelete: () {},
                onMove: (_, _, _) {},
                onToggleCollapsed: (_) {},
                onNavigate: (_) {},
                onAddChild: () {},
                onShift: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
    Future<List<int>> pixelsAt(List<Offset> points) async {
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final pixels = [
          for (final point in points) data.getUint32((point.dy.toInt() * image.width + point.dx.toInt()) * 4),
        ];
        image.dispose();
        return pixels;
      }))!;
    }

    final scene = tester.getSize(find.byKey(const ValueKey('mind-map-edges')));
    for (final scale in [0.5, 0.8]) {
      transform.value = Matrix4.identity()
        ..translateByDouble((700 - scene.width * scale) / 2, (500 - scene.height * scale) / 2, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
      await tester.pump();
      const start = Offset(10, 10);
      const end = Offset(690, 490);
      // Each sample lies beyond a different edge of the finite map scene.
      const samples = [Offset(11, 250), Offset(688, 250), Offset(350, 11), Offset(350, 488)];
      final before = await pixelsAt(samples);
      for (final reverse in [false, true]) {
        final gesture = await tester.startGesture(reverse ? end : start, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await gesture.moveTo(reverse ? start : end);
        await tester.pump();
        final box = tester.getRect(find.byKey(const ValueKey('map-selection-box')));
        expect(box.left, closeTo(start.dx, 0.001));
        expect(box.top, closeTo(start.dy, 0.001));
        expect(box.right, closeTo(end.dx, 0.001));
        expect(box.bottom, closeTo(end.dy, 0.001));
        final after = await pixelsAt(samples);
        for (var i = 0; i < samples.length; i++) {
          expect(after[i], isNot(before[i]), reason: 'The marquee must paint at ${samples[i]} at zoom $scale');
        }
        expect(selected, {'c0'});
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('map-selection-box')), findsNothing);
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selection, flash, pan, zoom, drag and resize reuse edges; text and theme invalidate', (tester) async {
    final transform = TransformationController();
    final focus = FocusNode();
    addTearDown(transform.dispose);
    addTearDown(focus.dispose);
    var content = fixture(3);
    String? selection;
    String? flash;
    var locateTick = 0;
    var dark = false;
    // Wide enough that the first fit stays at 100% (nodes are kept per zoom).
    var width = 840.0;
    final moves = <String>[];
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            theme: dark ? MMTheme.dark() : MMTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: width,
                height: 580,
                child: MindMapCanvas(
                  content: content,
                  rootTitle: 'Root',
                  selectedCardId: selection,
                  flashCardId: flash,
                  locateCardTick: locateTick,
                  transformation: transform,
                  focusNode: focus,
                  onSelect: (id) => rebuild(() => selection = id),
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
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    CustomPainter edges() => tester.widget<CustomPaint>(find.byKey(const ValueKey('mind-map-edges'))).painter!;
    final original = edges();
    Widget nodeChild(String id) => tester.widget<Positioned>(find.byKey(ValueKey(id))).child;
    final unchanged = nodeChild('c2');

    await tester.tap(find.text('Node 0 中文'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(selection, 'c0');
    expect(nodeChild('c2'), same(unchanged), reason: 'Selecting another node must retain unchanged node subtrees');
    expect(edges().shouldRepaint(original), isFalse);
    for (final zoom in [0.1, 1.5]) {
      transform.value = Matrix4.identity()
        ..translateByDouble(-2000, -2000, 0, 1)
        ..scaleByDouble(zoom, zoom, 1, 1);
      rebuild(() {
        flash = selection = 'c1';
        locateTick++;
      });
      await tester.pumpAndSettle();
      expect(mapScale(transform.value), closeTo(zoom < 1 ? mapLocateScale : zoom, .001));
      final viewport = tester.getRect(find.byType(InteractiveViewer));
      final card = tester.getRect(find.byKey(const ValueKey('c1')));
      // The source label beside the card counts as part of what is located.
      final label = tester.getRect(find.textContaining('Source ·')).inflate(MMSpacing.xs);
      final located = card.expandToInclude(label);
      expect(
        (located.center.dx - viewport.center.dx).abs(),
        lessThan(4),
        reason: 'label width is measured, not laid out',
      );
      expect((card.center.dy - viewport.center.dy).abs(), lessThan(1));
      expect(viewport.contains(located.topLeft), isTrue);
      expect(viewport.contains(located.bottomRight), isTrue);
    }
    expect(edges().shouldRepaint(original), isFalse);
    transform.value = Matrix4.identity()
      ..translateByDouble(10, 20, 0, 1)
      ..scaleByDouble(0.8, 0.8, 1, 1);
    rebuild(() => width = 700);
    await tester.pumpAndSettle();
    expect(edges().shouldRepaint(original), isFalse);
    // Drag feedback and hover live inside each node's repaint boundary.
    final gesture = await tester.startGesture(tester.getCenter(find.text('Node 0 中文')), kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Node 2 中文')));
    await tester.pump();
    expect(edges().shouldRepaint(original), isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moves, isNotEmpty);
    rebuild(
      () => content = content.copyWith(
        cards: [
          content.cards.first.copyWith(title: 'Long title that forces a larger node and new layout'),
          ...content.cards.skip(1),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(edges().shouldRepaint(original), isTrue);
    final edited = edges();
    final stable = nodeChild('c2');
    rebuild(
      () => content = content.copyWith(
        cards: [
          content.cards.first.copyWith(title: 'Another title'),
          ...content.cards.skip(1),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(nodeChild('c2'), same(stable), reason: 'Typing into one node must not rebuild every other node');

    rebuild(() => dark = true);
    await tester.pumpAndSettle();
    expect(edges().shouldRepaint(edited), isTrue);
    expect(tester.takeException(), isNull);
    // One boundary for each visible node, and a separate boundary for edges.
    expect(find.descendant(of: find.byType(MindMapCanvas), matching: find.byType(RepaintBoundary)), findsAtLeast(5));
    await tester.pumpWidget(const SizedBox());
  });
}
