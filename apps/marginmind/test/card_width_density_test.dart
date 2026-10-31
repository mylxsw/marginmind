import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/l10n/generated/app_localizations_en.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

import 'helpers.dart';
import 'map_generation_ui_test.dart' as generation_harness;

final _now = DateTime(2026);
final _english = AppLocalizationsEn();
final _theme = MMTheme.light();
const _longQuote = 'Memory fades unless it is used again soon.';

/// A topic with an excerpt (long quote), an image, a research note and a
/// note under it.
StudySetContent _content({
  double? width,
  double? topicWidth,
  bool sourceTopic = false,
  MapDensity density = MapDensity.full,
}) => StudySetContent(
  maps: [MindMap(id: MindMap.defaultId, title: '', density: density)],
  documents: [Document(id: 'd', title: 'Book', fileName: 'a.pdf', pageCount: 9, importedAt: _now)],
  annotations: [
    Annotation(id: 'a1', documentId: 'd', page: 2, rects: const [], quote: _longQuote, colorIndex: 0, createdAt: _now),
    Annotation(
      id: 'a2',
      documentId: 'd',
      page: 3,
      rects: const [PageRect(0, 100, 100, 0)],
      quote: '',
      colorIndex: 1,
      createdAt: _now,
    ),
  ],
  cards: [
    Card(
      id: 't',
      kind: CardKind.topic,
      title: sourceTopic ? 'Spacing practice strengthens memory and improves long term recall' : 'Topic',
      source: sourceTopic ? CardSource(documentId: 'd', page: 2) : null,
      createdAt: _now,
    ),
    Card(id: 'e', kind: CardKind.excerpt, annotationId: 'a1', createdAt: _now),
    Card(id: 'i', kind: CardKind.image, annotationId: 'a2', imageFileName: 'images/x.png', createdAt: _now),
    Card(
      id: 'r',
      kind: CardKind.research,
      title: 'A research note whose title runs well past one line of the card',
      createdAt: _now,
    ),
    Card(id: 'n', kind: CardKind.note, title: 'Note', createdAt: _now),
  ],
  nodes: [
    MapNode(cardId: 't', order: 0, width: topicWidth),
    MapNode(cardId: 'e', parentId: 't', order: 0, width: width),
    const MapNode(cardId: 'i', parentId: 't', order: 1),
    const MapNode(cardId: 'r', parentId: 't', order: 2),
    const MapNode(cardId: 'n', parentId: 't', order: 3),
  ],
);

TreeLayoutResult _update(MindMapRenderCache cache, StudySetContent content, {(String, double)? widthDraft}) =>
    cache.update(content: content, rootTitle: 'Root', localizations: _english, theme: _theme, widthDraft: widthDraft);

Size _size(TreeLayoutResult layout, String id) {
  final r = layout.rects[id]!;
  return Size(r.width, r.height);
}

void main() {
  group('measurement', () {
    test('generated topic widths wrap the title and respect widths with attached notes', () {
      final cache = MindMapRenderCache();
      final content = _content(sourceTopic: true);
      final original = _size(_update(cache, content), 't');
      final narrow = _size(_update(cache, _content(sourceTopic: true, topicWidth: 200)), 't');
      final wide = _size(_update(cache, _content(sourceTopic: true, topicWidth: 400)), 't');
      expect(narrow.width, 200);
      expect(wide.width, 400);
      expect(wide.height, lessThan(narrow.height));
      expect(_size(_update(cache, content, widthDraft: ('t', 360)), 't').width, 360);
      expect(_size(_update(cache, content), 't'), original);

      final withoutNote = content.copyWith(nodes: content.nodes.where((node) => node.cardId != 'n').toList());
      final resized = _update(cache, withoutNote, widthDraft: ('t', 200));
      expect(narrow.height, greaterThan(_size(resized, 't').height));
    });

    test('the stored width sizes the card and wraps its quote', () {
      final cache = MindMapRenderCache();
      final normal = _update(cache, _content());
      expect(_size(normal, 'e').width, 240);
      final wide = _update(cache, _content(width: 480));
      expect(_size(wide, 'e').width, 480);
      // The wider card needs fewer lines for the same quote.
      expect(_size(wide, 'e').height, lessThan(_size(normal, 'e').height));
      // Out-of-range widths are kept within the allowed range.
      expect(_size(_update(cache, _content(width: 50)), 'e').width, MapNode.minWidth);
      expect(_size(_update(cache, _content(width: 900)), 'e').width, MapNode.maxWidth);
    });

    test('dragging remeasures only the resized card; going back reads the cache', () {
      final cache = MindMapRenderCache();
      final content = _content();
      final first = _update(cache, content);
      final before = cache.measurementCount;
      final dragged = _update(cache, content, widthDraft: ('e', 360));
      expect(_size(dragged, 'e').width, 360);
      // Only the excerpt's quote is measured again at its new width.
      final added = cache.measurementCount - before;
      expect(added, greaterThan(0));
      expect(added, lessThanOrEqualTo(4));
      // Other cards keep their sizes, and the layout makes room.
      for (final id in ['i', 'r', 't']) {
        expect(_size(dragged, id), _size(first, id));
      }
      expect(dragged.rects['i']!.top, isNot(first.rects['i']!.top));
      final after = cache.measurementCount;
      _update(cache, content);
      expect(cache.measurementCount, after);
    });

    test('compact shows two quote lines, no picture and a research note on one line', () {
      final cache = MindMapRenderCache();
      final full = _update(cache, _content());
      final compact = _update(cache, _content(density: MapDensity.compact));
      expect(_size(compact, 'e').height, lessThan(_size(full, 'e').height));
      expect(_size(compact, 'i').height, lessThan(_size(full, 'i').height));
      expect(_size(compact, 'r').height, lessThan(_size(full, 'r').height));
      // Attached notes stay within the topic in both densities.
      expect(compact.rects.containsKey('n'), isFalse);
      expect(full.rects.containsKey('n'), isFalse);
      expect(_size(compact, 't'), _size(full, 't'));
      // Switching back reuses every earlier measurement.
      final count = cache.measurementCount;
      _update(cache, _content());
      expect(cache.measurementCount, count);
    });

    test('an attached note respects the resized excerpt width when folded and expanded', () {
      final original = _content(width: MapNode.minWidth);
      final content = original.copyWith(
        nodes: [for (final n in original.nodes) n.cardId == 'n' ? n.copyWith(parentId: 'e') : n],
      );
      final cache = MindMapRenderCache();
      final folded = _update(cache, content);
      expect(_size(folded, 'e').width, MapNode.minWidth);
      final expanded = cache.update(
        content: content,
        rootTitle: 'Root',
        localizations: _english,
        theme: _theme,
        expandedNotes: {'e'},
      );
      expect(_size(expanded, 'e').width, MapNode.minWidth);
      expect(_size(expanded, 'e').height, greaterThan(_size(folded, 'e').height));
      expect(expanded.rects.containsKey('n'), isFalse);
    });

    test('a research note with a width keeps it', () {
      final cache = MindMapRenderCache();
      final content = _content();
      final sized = content.copyWith(
        nodes: [for (final n in content.nodes) n.cardId == 'r' ? n.copyWith(width: 400) : n],
      );
      expect(_size(_update(cache, sized), 'r').width, 400);
    });
  });

  group('canvas', () {
    Future<List<(String, double?)>> pumpCanvas(
      WidgetTester tester, {
      required StudySetContent content,
      String? selected,
    }) async {
      final calls = <(String, double?)>[];
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final transform = TransformationController();
      final focus = FocusNode();
      addTearDown(transform.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
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
              onSelect: (_) {},
              onReveal: (_) {},
              onRename: (_) {},
              onDelete: () {},
              onMove: (_, _, _) {},
              onToggleCollapsed: (_) {},
              onNavigate: (_) {},
              onAddChild: () {},
              onShift: (_) {},
              onResize: (id, width) => calls.add((id, width)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return calls;
    }

    final handle = find.byKey(const ValueKey('card-width-handle'));

    testWidgets('the selected excerpt has a handle; dragging it resizes, a double click resets', (tester) async {
      final calls = await pumpCanvas(tester, content: _content(), selected: 'e');
      expect(handle, findsOneWidget);
      final start = tester.getCenter(handle);
      final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      // While dragging the card follows the pointer before anything is saved.
      expect(calls, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(calls.single.$1, 'e');
      expect(calls.single.$2, closeTo(240 + 90, 1));

      // Past the double-click window of the drag's own button press.
      await tester.pump(const Duration(milliseconds: 500));
      calls.clear();
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(calls.single, ('e', null));

      // Far past the limit: kept at the widest.
      calls.clear();
      final again = await tester.startGesture(tester.getCenter(handle), kind: PointerDeviceKind.mouse);
      await again.moveBy(const Offset(30, 0));
      await again.moveBy(const Offset(600, 0));
      await again.up();
      await tester.pump();
      expect(calls.single, ('e', MapNode.maxWidth));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('topics have a handle; notes and unselected cards have no handle', (tester) async {
      await pumpCanvas(tester, content: _content(), selected: 't');
      expect(handle, findsOneWidget);
      await pumpCanvas(tester, content: _content(), selected: 'n');
      expect(handle, findsNothing);
      await pumpCanvas(tester, content: _content());
      expect(handle, findsNothing);
      await pumpCanvas(tester, content: _content(), selected: 'i');
      expect(handle, findsOneWidget);
    });

    testWidgets('a generated topic follows a horizontal drag and resets on double click', (tester) async {
      final calls = await pumpCanvas(tester, content: _content(sourceTopic: true, topicWidth: 280), selected: 't');
      expect(handle, findsOneWidget);
      final before = tester.getRect(find.byKey(const ValueKey('t')));
      final gesture = await tester.startGesture(tester.getCenter(handle), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('t'))).width, closeTo(before.width + 90, 1));
      expect(calls, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(calls.single, ('t', 370));
      await tester.pump(const Duration(milliseconds: 500));
      calls.clear();
      await doubleTap(tester, handle);
      expect(calls.single, ('t', null));
    });

    testWidgets('a compact image card shows its label instead of the picture', (tester) async {
      await pumpCanvas(tester, content: _content(density: MapDensity.compact));
      expect(find.text(_english.imageExcerpt), findsOneWidget);
    });
  });

  group('workspace', () {
    testWidgets('a kept generated topic can be resized, persisted, undone and redone', (tester) async {
      final repository = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      final fake = FakeMapGenerator(
        chapters: {
          '*': ['{"k":"point","id":"p1","title":"Spacing"}'],
        },
        generation: ['{"ref":"t1","parent":"ROOT","title":"间隔重复利用遗忘规律","page":2}'],
      );
      final container = await generation_harness.openWorkspace(
        tester,
        content: repository,
        overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
      );
      final generator = container.read(mapGenerationControllerProvider('demo-1').notifier);
      await generation_harness.runGeneration(
        tester,
        () => generator.start(
          const MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: 'generated-map',
            title: 'Generated map',
            sources: [MapDocumentSelection(documentId: 'c1')],
          ),
        ),
      );
      expect(await generator.keep(), 1);
      await tester.pumpAndSettle();
      final workspace = container.read(workspaceProvider('demo-1').notifier);
      final card = workspace.content.cards.singleWhere((card) => card.title == '间隔重复利用遗忘规律');
      expect(card.source?.page, 2);
      workspace.selectCard(card.id);
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('card-width-handle'));
      expect(handle, findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(handle), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(60, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      final width = workspace.content.node(card.id, mapId: 'generated-map')!.width;
      expect(width, isNotNull);
      expect((await repository.load('demo-1')).node(card.id, mapId: 'generated-map')!.width, width);
      await workspace.undo();
      await tester.pumpAndSettle();
      expect(workspace.content.node(card.id, mapId: 'generated-map')!.width, isNull);
      expect(workspace.content.card(card.id), isNotNull);
      await workspace.redo();
      await tester.pumpAndSettle();
      expect(workspace.content.node(card.id, mapId: 'generated-map')!.width, width);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    });

    Future<(ProviderContainer, WorkspaceController)> open(WidgetTester tester) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      return (container, container.read(workspaceProvider('demo-1').notifier));
    }

    testWidgets('width is saved per map node, undoable, and reset from the menu', (tester) async {
      final (_, controller) = await open(tester);
      final excerpt = controller.content.cards.firstWhere((c) => c.kind == CardKind.excerpt);
      await controller.setCardWidth(excerpt.id, 333.4);
      expect(controller.content.node(excerpt.id)!.width, 333);
      // Clamped, and an unchanged width writes nothing.
      await controller.setCardWidth(excerpt.id, 1000);
      expect(controller.content.node(excerpt.id)!.width, MapNode.maxWidth);
      await controller.setCardWidth(excerpt.id, MapNode.maxWidth);
      await controller.undo();
      expect(controller.content.node(excerpt.id)!.width, 333);
      await tester.pumpAndSettle();

      controller.selectCard(excerpt.id);
      await tester.pumpAndSettle();
      final quote = find.textContaining('遗忘曲线');
      await tester.tap(quote.first, buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset Width'));
      await tester.pumpAndSettle();
      expect(controller.content.node(excerpt.id)!.width, isNull);
      // Without a width the menu has no reset.
      await tester.tap(quote.first, buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('Reset Width'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleHud(tester);
    });

    testWidgets('the density control switches the map without changing any text', (tester) async {
      final (_, controller) = await open(tester);
      final before = controller.content.cards;
      await toggleMapStyle(tester);
      await tester.pumpAndSettle();
      expect(controller.content.map(MindMap.defaultId)!.density, MapDensity.full);
      await tester.tap(find.text('Compact'));
      await tester.pumpAndSettle();
      expect(controller.content.map(MindMap.defaultId)!.density, MapDensity.compact);
      expect(controller.content.cards, before);
      // Picking the current density again writes nothing.
      await controller.setMapDensity(MapDensity.compact);
      await tester.tap(find.text('Full'));
      await tester.pumpAndSettle();
      expect(controller.content.map(MindMap.defaultId)!.density, MapDensity.full);
      await controller.undo();
      expect(controller.content.map(MindMap.defaultId)!.density, MapDensity.compact);
      await settleHud(tester);
    });
  });
}
