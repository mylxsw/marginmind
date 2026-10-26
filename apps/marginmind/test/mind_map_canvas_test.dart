import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'mind_map_cache_test.dart' show fixture;

void main() {
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
      expect((located.center.dx - viewport.center.dx).abs(), lessThan(1));
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
    final gesture = await tester.startGesture(tester.getCenter(find.text('Node 0 中文')));
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
