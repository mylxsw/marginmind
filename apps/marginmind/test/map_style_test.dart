import 'dart:ui';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/map_export_scene.dart';
import 'package:marginmind/features/workspace/widgets/map_style_popover.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

import 'helpers.dart';

final _now = DateTime(2026);

/// Topics a, b, c under the root; a has children a1, a2, a3.
StudySetContent _content({MapStructure structure = MapStructure.mind, MapPalette palette = MapPalette.system}) =>
    StudySetContent(
      maps: [MindMap(id: MindMap.defaultId, title: '', structure: structure, palette: palette)],
      cards: [
        for (final id in ['a', 'b', 'c', 'a1', 'a2', 'a3'])
          Card(id: id, kind: CardKind.topic, title: 'Topic $id', createdAt: _now),
      ],
      nodes: [
        for (final (i, id) in ['a', 'b', 'c'].indexed) MapNode(cardId: id, parentId: null, order: i.toDouble()),
        for (final (i, id) in ['a1', 'a2', 'a3'].indexed) MapNode(cardId: id, parentId: 'a', order: i.toDouble()),
      ],
    );

const _root = LayoutRect(0, 100, 80, 40);

TreeLayoutResult _layout(LayoutStructure structure, {Set<String> leftSide = const {}}) => TreeLayoutResult(
  structure: structure,
  rects: {
    'r': _root,
    'a': const LayoutRect(160, 40, 60, 20),
    'b': const LayoutRect(160, 110, 60, 20),
    'c': const LayoutRect(160, 180, 60, 20),
    'a1': const LayoutRect(300, 40, 60, 20),
  },
  edges: const [LayoutEdge('r', 'a'), LayoutEdge('r', 'b'), LayoutEdge('r', 'c'), LayoutEdge('a', 'a1')],
  leftSide: leftSide,
  width: 400,
  height: 300,
);

Rect Function(String) _at(TreeLayoutResult l) =>
    (id) => Rect.fromLTWH(l.rects[id]!.left, l.rects[id]!.top, l.rects[id]!.width, l.rects[id]!.height);

/// Every segment starts where the one before it ended.
void _expectContiguous(MapConnector c) {
  for (var i = 1; i < c.segments.length; i++) {
    expect(c.segments[i].$1.dx, closeTo(c.segments[i - 1].$4.dx, 1e-9));
    expect(c.segments[i].$1.dy, closeTo(c.segments[i - 1].$4.dy, 1e-9));
  }
}

void main() {
  group('style tokens for stored values', () {
    test('every structure and palette maps to its layout and tokens', () {
      for (final s in MapStructure.values) {
        expect(layoutStructureOf(s).name, s.name);
      }
      for (final p in MapPalette.values) {
        expect(mapPaletteOf(p).name, p.name);
      }
    });

    test('branches number the root children in order and pass down', () {
      final branches = mapBranches(_layout(LayoutStructure.mind), 'r');
      expect(branches, {'a': 0, 'b': 1, 'c': 2, 'a1': 0});
    });
  });

  group('connectors follow the structure', () {
    test('mind: one curve per edge, level at both ends, mirrored on the left', () {
      final layout = _layout(LayoutStructure.mind, leftSide: {'c'});
      final connectors = mapConnectors(layout, _at(layout), rootId: 'r');
      expect(connectors.map((c) => c.colorId), ['a', 'b', 'c', 'a1']);
      final a = connectors.first.segments.single;
      expect(a.$1, const Offset(80, 120));
      expect(a.$4, const Offset(160, 50));
      expect(a.$2.dy, a.$1.dy);
      expect(a.$3.dy, a.$4.dy);
      final left = connectors[2].segments.single;
      expect(left.$1, const Offset(0, 120), reason: 'leaves the root on its left');
      expect(left.$4, const Offset(220, 190), reason: "enters the child's right edge");
    });

    test('logic: an elbow with rounded corners on a shared vertical', () {
      final layout = _layout(LayoutStructure.logic);
      final connectors = mapConnectors(layout, _at(layout), rootId: 'r');
      final up = connectors.first;
      _expectContiguous(up);
      expect(up.segments, hasLength(5));
      expect(up.segments.first.$1, const Offset(80, 120));
      expect(up.segments.last.$4, const Offset(160, 50));
      // The vertical runs 18 past the parent, for every child.
      expect(up.segments[2].$1.dx, 98);
      expect(connectors[2].segments[2].$1.dx, 98);
      // A child level with its parent takes a straight line.
      final level = connectors[1].segments;
      expect(level.single.$1.dy, 120);
      expect(level.single.$4, const Offset(160, 120));
    });

    test('tree: down from the parent near its left edge, then into the child', () {
      final layout = TreeLayoutResult(
        structure: LayoutStructure.tree,
        rects: const {'r': LayoutRect(0, 0, 80, 40), 'a': LayoutRect(56, 54, 60, 20), 'b': LayoutRect(56, 88, 60, 20)},
        edges: const [LayoutEdge('r', 'a'), LayoutEdge('r', 'b')],
        width: 200,
        height: 200,
      );
      final connectors = mapConnectors(layout, _at(layout), rootId: 'r');
      for (final (c, y) in [(connectors[0], 64.0), (connectors[1], 98.0)]) {
        _expectContiguous(c);
        expect(c.segments.first.$1, const Offset(mapTreeTrunkInset, 40));
        expect(c.segments.first.$4.dx, mapTreeTrunkInset, reason: 'the trunk is vertical');
        expect(c.segments.last.$4, Offset(56, y));
      }
    });

    test('brace: one brace per parent from the first child to the last, a stem to its point', () {
      final layout = _layout(LayoutStructure.brace);
      final connectors = mapConnectors(layout, _at(layout), rootId: 'r');
      // The root's brace and stem, and a single child joined by a curve.
      expect(connectors, hasLength(3));
      final brace = connectors[0], stem = connectors[1], single = connectors[2];
      _expectContiguous(brace);
      expect(brace.colorId, isNull, reason: "the root's brace spans every branch");
      expect(brace.segments.first.$1, const Offset(154, 50));
      expect(brace.segments.last.$4, const Offset(154, 190));
      final tip = brace.segments[2].$4;
      expect(tip, const Offset(138, 120));
      expect(stem.segments.single.$1, const Offset(80, 120));
      expect(stem.segments.single.$4, tip);
      expect(single.colorId, 'a1');
      expect(single.segments.single.$4, const Offset(300, 50));
    });

    test('a brace below the root takes its branch color', () {
      final layout = TreeLayoutResult(
        structure: LayoutStructure.brace,
        rects: const {
          'r': LayoutRect(0, 0, 40, 40),
          'a': LayoutRect(120, 0, 40, 40),
          'x': LayoutRect(240, -40, 40, 20),
          'y': LayoutRect(240, 60, 40, 20),
        },
        edges: const [LayoutEdge('r', 'a'), LayoutEdge('a', 'x'), LayoutEdge('a', 'y')],
        width: 300,
        height: 120,
      );
      final connectors = mapConnectors(layout, _at(layout), rootId: 'r');
      expect(connectors.map((c) => c.colorId), ['a', 'a', 'a']);
      expect(connectors.last.segments.single.$1, const Offset(160, 20));
    });
  });

  group('canvas', () {
    Future<(TransformationController, List<String?>)> pump(
      WidgetTester tester,
      StudySetContent content, {
      (MapStructure, MapPalette)? preview,
      EdgeInsets? fitInsets,
      String? selected,
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final transform = TransformationController();
      final focus = FocusNode();
      addTearDown(transform.dispose);
      addTearDown(focus.dispose);
      final children = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MindMapCanvas(
              content: content,
              rootTitle: 'Root',
              selectedCardId: selected,
              flashCardId: null,
              transformation: transform,
              focusNode: focus,
              previewStyle: preview,
              fitInsets: fitInsets,
              onSelect: (_) {},
              onReveal: (_) {},
              onRename: (_) {},
              onDelete: () {},
              onMove: (_, _, _) {},
              onToggleCollapsed: (_) {},
              onNavigate: (_) {},
              onAddChild: () => children.add(selected),
              onShift: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (transform, children);
    }

    Rect node(WidgetTester tester, String id) => tester.getRect(find.byKey(ValueKey(id)));

    BoxDecoration decoration(WidgetTester tester, String id) =>
        tester
                .widgetList<AnimatedContainer>(
                  find.descendant(of: find.byKey(ValueKey(id)), matching: find.byType(AnimatedContainer)),
                )
                .first
                .decoration!
            as BoxDecoration;

    Color? textColor(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style?.color;

    testWidgets('a tree grows down from the root, its add-child button below the node', (tester) async {
      await pump(tester, _content(structure: MapStructure.tree), selected: 'a');
      final root = node(tester, rootNodeId);
      final a = node(tester, 'a'), b = node(tester, 'b'), a1 = node(tester, 'a1');
      expect(a.top, greaterThan(root.bottom));
      expect(a.left, closeTo(root.left + 56, .5), reason: 'indented under the root');
      expect(a1.top, greaterThan(a.bottom));
      expect(b.top, greaterThan(node(tester, 'a3').bottom), reason: 'after the whole branch above it');
      final add = tester.getRect(find.byKey(const ValueKey('node-add-child')));
      expect(add.center.dy, closeTo(a.bottom, .5));
      expect(add.center.dx, closeTo(a.left + mapTreeTrunkInset, .5));
    });

    testWidgets('logic and brace maps grow right only; mind maps on both sides', (tester) async {
      for (final structure in [MapStructure.logic, MapStructure.brace]) {
        await pump(tester, _content(structure: structure));
        final root = node(tester, rootNodeId);
        for (final id in ['a', 'b', 'c']) {
          expect(node(tester, id).left, greaterThan(root.right), reason: '$structure $id');
        }
      }
      await pump(tester, _content());
      expect(node(tester, 'c').right, lessThan(node(tester, rootNodeId).left));
    });

    testWidgets('summary topics and details render in all structures, palettes and appearances', (tester) async {
      var seq = 0;
      final editor = StudySetEditor(newId: () => 'summary-${seq++}', now: () => _now);
      for (final dark in [false, true]) {
        final colors = dark ? MMColors.dark : MMColors.light;
        for (final structure in MapStructure.values) {
          for (final palette in MapPalette.values) {
            final result = editor.createSummary(_content(structure: structure, palette: palette), [
              'a1',
              'a3',
            ], label: 'Summary topic');
            final (content, child) = editor.addTopic(
              result.content,
              parentId: result.value!.cardId,
              title: 'Detail topic',
            );
            await pump(tester, content, theme: dark ? MMTheme.dark() : MMTheme.light());
            expect(find.text('Summary topic'), findsOneWidget);
            expect(find.byKey(ValueKey(child.id)), findsOneWidget);
            final tokens = mapPaletteOf(palette).of(colors.brightness);
            final box = tester.widget<DecoratedBox>(
              find.ancestor(of: find.text('Summary topic'), matching: find.byType(DecoratedBox)).first,
            );
            expect(
              (box.decoration as BoxDecoration).color,
              tokens.summary ?? Color.alphaBlend(colors.fill, colors.canvas),
              reason: '$structure $palette dark=$dark',
            );
            if (tokens.onSummary != null) expect(textColor(tester, 'Summary topic'), tokens.onSummary);
            expect(tester.takeException(), isNull);
          }
        }
      }
    });

    testWidgets('the palette colors the root and first-level topics only', (tester) async {
      await pump(tester, _content(palette: MapPalette.rainbow));
      final palette = MMMapPalette.rainbow.light;
      expect(decoration(tester, rootNodeId).color, palette.root);
      expect(textColor(tester, 'Root'), palette.onRoot);
      for (final (i, id) in ['a', 'b', 'c'].indexed) {
        expect(decoration(tester, id).color, palette.branches[i]);
        expect(textColor(tester, 'Topic $id'), palette.topicText(i, MMColors.light));
      }
      // A deeper topic keeps the topic look.
      expect(decoration(tester, 'a1').color, Color.alphaBlend(MMColors.light.fill, MMColors.light.canvas));

      await pump(tester, _content(palette: MapPalette.ink), theme: MMTheme.dark());
      final border = decoration(tester, 'b').border! as Border;
      expect(border.top.color, MMMapPalette.ink.dark.branches.single);
      expect(decoration(tester, rootNodeId).color, MMMapPalette.ink.dark.root);
    });

    testWidgets('a preview draws another style without changing the content', (tester) async {
      final content = _content();
      await pump(tester, content, preview: (MapStructure.tree, MapPalette.warm));
      expect(node(tester, 'a').top, greaterThan(node(tester, rootNodeId).bottom));
      expect(decoration(tester, rootNodeId).color, MMMapPalette.warm.light.root);
      expect(content.map(MindMap.defaultId)!.structure, MapStructure.mind);
      await pump(tester, content);
      expect(node(tester, 'c').right, lessThan(node(tester, rootNodeId).left));
      expect(decoration(tester, rootNodeId).color, MMColors.light.rootNode);
    });

    testWidgets('fit insets keep the whole map clear of the covered area', (tester) async {
      const insets = EdgeInsets.only(top: 56, right: 324, bottom: 56);
      await pump(tester, _content(), fitInsets: insets);
      final area = insets.deflateRect(Offset.zero & const Size(1200, 800));
      for (final id in [rootNodeId, 'a', 'b', 'c', 'a1', 'a3']) {
        final r = node(tester, id);
        expect(area.contains(r.topLeft) && area.contains(r.bottomRight), isTrue, reason: id);
      }
    });
  });

  group('style popover in the map pane', () {
    Future<(ProviderContainer, WorkspaceController)> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      return (container, container.read(workspaceProvider('demo-1').notifier));
    }

    MindMapCanvas canvas(WidgetTester tester) => tester.widget<MindMapCanvas>(find.byType(MindMapCanvas));

    testWidgets('hover previews, leaving restores, a click applies one undo step', (tester) async {
      final (_, controller) = await open(tester);
      MindMap map() => controller.content.map(MindMap.defaultId)!;
      await tester.tap(find.byKey(const ValueKey('map-style-button')));
      await tester.pumpAndSettle();
      expect(find.byType(MapStylePopover), findsOneWidget);
      expect(canvas(tester).fitInsets, isNotNull, reason: 'the map makes way for the popover');
      // Thumbnails only: the names are tooltips.
      expect(find.descendant(of: find.byType(MapStylePopover), matching: find.byType(Text)), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('map-structure-tree'))));
      await tester.pumpAndSettle();
      expect(canvas(tester).previewStyle, (MapStructure.tree, MapPalette.system));
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('map-palette-fresh'))));
      await tester.pumpAndSettle();
      expect(canvas(tester).previewStyle, (MapStructure.mind, MapPalette.fresh));
      expect(map().palette, MapPalette.system, reason: 'nothing is saved while previewing');

      await mouse.moveTo(const Offset(5, 500));
      await tester.pumpAndSettle();
      expect(canvas(tester).previewStyle, isNull);

      await tester.tap(find.byKey(const ValueKey('map-structure-logic')));
      await tester.pumpAndSettle();
      expect(map().structure, MapStructure.logic);
      await tester.tap(find.byKey(const ValueKey('map-palette-morandi')));
      await tester.pumpAndSettle();
      expect(map().palette, MapPalette.morandi);
      expect(find.byType(MapStylePopover), findsOneWidget, reason: 'stays open to try more');
      // Choosing the current one again writes nothing.
      await controller.setMapPalette(MapPalette.morandi);
      await controller.setMapStructure(MapStructure.logic);

      await controller.undo();
      expect(map().palette, MapPalette.system);
      expect(map().structure, MapStructure.logic);
      await controller.undo();
      expect(map().structure, MapStructure.mind);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MapStylePopover), findsNothing);
      expect(canvas(tester).fitInsets, isNull);
      await settleHud(tester);
    });

    testWidgets('a click outside closes the popover and ends the preview', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('map-style-button')));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('map-palette-ink'))));
      await tester.pumpAndSettle();
      expect(canvas(tester).previewStyle, isNotNull);
      await tester.tapAt(tester.getBottomLeft(find.byType(MindMapCanvas)) + const Offset(400, -200));
      await tester.pumpAndSettle();
      expect(find.byType(MapStylePopover), findsNothing);
      expect(canvas(tester).previewStyle, isNull);
      // The button opens and closes it.
      await tester.tap(find.byKey(const ValueKey('map-style-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-style-button')));
      await tester.pumpAndSettle();
      expect(find.byType(MapStylePopover), findsNothing);
      await settleHud(tester);
    });
  });

  group('export', () {
    MapExportScene build(StudySetContent content, {MMColors colors = MMColors.light}) => MapExportScene.build(
      content: content,
      mapId: MindMap.defaultId,
      title: 'Root',
      colors: colors,
      researchLabel: 'Research',
      source: (d, p) => '${d.title} $p',
    );

    List<int> boxColors(MapExportScene s) => [
      for (final c in s.commands)
        if (c['type'] == 'box') c['color']! as int,
    ];
    Set<int> curveColors(MapExportScene s) => {
      for (final c in s.commands)
        if (c['type'] == 'curve') c['color']! as int,
    };

    test('is drawn in the map structure', () {
      final tree = build(_content(structure: MapStructure.tree)).layout;
      expect(tree.structure, LayoutStructure.tree);
      expect(tree.rects['a']!.top, greaterThan(tree.rects['__export_root__']!.bottom));
      final mind = build(_content()).layout;
      expect(mind.leftSide, contains('c'));
    });

    test('is drawn in the map palette, light or dark', () {
      for (final colors in [MMColors.light, MMColors.dark]) {
        final palette = MMMapPalette.rainbow.of(colors.brightness);
        final s = build(_content(palette: MapPalette.rainbow), colors: colors);
        final boxes = boxColors(s);
        expect(boxes, contains(palette.root.toARGB32()));
        for (var i = 0; i < 3; i++) {
          expect(boxes, contains(palette.branches[i].toARGB32()));
          expect(curveColors(s), contains(palette.branches[i].toARGB32()));
        }
      }
      final ink = build(_content(palette: MapPalette.ink));
      // An outlined topic: the outline color, then the canvas inside it.
      expect(boxColors(ink), containsAllInOrder([0xFF3A3A3C, MMColors.light.canvas.toARGB32()]));
    });

    test('the system palette keeps the export look', () {
      final s = build(_content());
      expect(boxColors(s), contains(MMColors.light.rootNode.toARGB32()));
      expect(curveColors(s), {MMColors.light.line.toARGB32()});
    });
  });
}
