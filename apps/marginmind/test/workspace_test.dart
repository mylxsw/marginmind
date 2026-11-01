import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/tag_content_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'helpers.dart';
import 'map_keyboard_test.dart' show focusMap;

Future<ProviderContainer> openFirstSet(
  WidgetTester tester, {
  InMemoryStudySetContentRepository? content,
  bool showMapCommandBar = false,
  Map<String, Object> prefs = const {},
}) async {
  final container = await pumpApp(
    tester,
    prefs: prefs,
    content: content,
    overrides: [if (showMapCommandBar) mapCommandBarVisibleProvider.overrideWithValue(true)],
  );
  await tester.tap(find.text('Starred'));
  await tester.pumpAndSettle();
  await doubleTap(tester, find.text('认知科学入门'));
  return container;
}

void main() {
  testWidgets('tag sheet adds, deduplicates, removes, cancels and supports undo', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.selectCard('c3');
    await tester.pumpAndSettle();
    Future<void> openTags() async {
      await tester.tap(find.text('遗忘的规律'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags…'));
      await tester.pumpAndSettle();
    }

    await openTags();
    await tester.enterText(find.descendant(of: find.byType(MMSheet), matching: find.byType(TextField)), ' Science ');
    await tester.tap(find.byTooltip('Add Tag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(MMSheet), matching: find.byType(TextField)), 'science');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MMButton, 'Save'));
    await tester.pumpAndSettle();
    expect(controller.content.card('c3')!.tags, ['Science']);
    await openTags();
    await tester.tap(find.byTooltip('Remove Tag'));
    await tester.tap(find.widgetWithText(MMButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(controller.content.card('c3')!.tags, ['Science']);
    await openTags();
    await tester.tap(find.byTooltip('Remove Tag'));
    await tester.tap(find.widgetWithText(MMButton, 'Save'));
    await tester.pumpAndSettle();
    expect(controller.content.card('c3')!.tags, isEmpty);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.card('c3')!.tags, ['Science']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tags open a content view independently of sidebar search', (tester) async {
    final container = await openFirstSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.setTags('c3', ['Science']);
    await controller.setTags('c4', ['Practice']);
    await tester.pumpAndSettle();
    final sidebar = find.byType(MMSidebar);
    Finder inSidebar(String text) => find.descendant(of: sidebar, matching: find.text(text));
    controller.filterTag('Science');
    await tester.pumpAndSettle();
    expect(inSidebar('遗忘的规律'), findsNothing);
    expect(inSidebar('对策一：间隔重复'), findsNothing);
    expect(find.descendant(of: find.byType(TagContentPane), matching: find.text('遗忘的规律')), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'science');
    await tester.pumpAndSettle();
    expect(inSidebar('遗忘的规律'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();
    expect(inSidebar('遗忘的规律'), findsNothing);
    expect(inSidebar('Cards'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    controller.closePanel();
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).tagFilter, isNull);
    await tester.enterText(find.byType(TextField).first, 'practice');
    await tester.pumpAndSettle();
    expect(inSidebar('对策一：间隔重复'), findsOneWidget);
    expect(inSidebar('遗忘的规律'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a study set shows its documents and mind map', (tester) async {
    await openFirstSet(tester);
    expect(find.text('Mind Maps'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('论文：检索练习效应'), findsWidgets);
    expect(find.text('遗忘的规律'), findsOneWidget); // topic node
    expect(find.text('这条先陡后平的曲线，被称为遗忘曲线。'), findsOneWidget); // excerpt card
    expect(find.byKey(const ValueKey('pdf-placeholder-c1')), findsOneWidget); // last-read doc opened
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout buttons switch panes and keep them mounted', (tester) async {
    await openFirstSet(tester);
    expect(find.byType(ReaderPane), findsOneWidget);
    await tester.tap(find.byIcon(MMIcons.layoutMap));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPane), findsNothing);
    expect(find.byType(ReaderPane, skipOffstage: false), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(MMToolbar), matching: find.byIcon(MMIcons.layoutSplit)));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPane), findsOneWidget);
  });

  testWidgets('sidebar search filters sections and documents open as tabs', (tester) async {
    final container = await openFirstSet(tester);
    final search = find.byType(TextField).first;
    await tester.enterText(search, '论文');
    await tester.pumpAndSettle();
    expect(find.text('Mind Maps'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(MMSidebar), matching: find.text('论文：检索练习效应')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c2');
    expect(container.read(workspaceProvider('demo-1')).openDocumentIds, ['c1', 'c2']);

    await tester.enterText(search, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('adding a topic opens it for naming in place and saves it', (tester) async {
    final content = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    await openFirstSet(tester, content: content);
    await focusMap(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.byType(MMSheet), findsNothing);
    await tester.enterText(find.byType(MMInlineTextField), '提取练习');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('提取练习'), findsOneWidget);
    final saved = await content.load('demo-1');
    expect(saved.cards.where((c) => c.title == '提取练习'), hasLength(1));
  });

  testWidgets('outline lists the map and selecting a row selects the node', (tester) async {
    final container = await openFirstSet(tester);
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect(find.text('对策一：间隔重复'), findsOneWidget);
    await tester.tap(find.text('对策一：间隔重复'));
    await tester.pump(const Duration(milliseconds: 400));
    final selected = container.read(workspaceProvider('demo-1')).selectedCardId;
    expect(container.read(workspaceProvider('demo-1').notifier).content.card(selected!)!.title, '对策一：间隔重复');
    await settleHud(tester);
  });

  testWidgets('sidebar hides and the library is one click away', (tester) async {
    await openFirstSet(tester);
    await tester.tap(find.byIcon(MMIcons.sidebarClose).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Mind Maps').hitTestable(), findsNothing);
    await tester.tap(find.byIcon(MMIcons.sidebar).hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-home')));
    await tester.pumpAndSettle();
    expect(find.text('All Study Sets'), findsWidgets);
  });

  group('controller', () {
    late ProviderContainer container;
    late InMemoryStudySetContentRepository repo;
    late WorkspaceController controller;

    setUp(() async {
      repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
      container = ProviderContainer(overrides: await testOverrides(content: repo));
      // Keep the providers alive and let the content stream deliver.
      container.listen(workspaceProvider('demo-1'), (_, _) {});
      await container.read(contentProvider('demo-1').future);
      controller = container.read(workspaceProvider('demo-1').notifier);
    });
    tearDown(() => container.dispose());

    const selection = MMPdfSelection(page: 30, rects: [PageRect(1, 20, 50, 10)], text: '主动提取');

    test('highlight tool + sync excerpts under the selected topic', () async {
      await controller.setTool(AnnotationTool.highlight);
      final topic = controller.content.cards.firstWhere((c) => c.title == '对策一：间隔重复');
      controller.selectCard(topic.id);
      final notice = await controller.onSelectionCommitted('c1', selection);
      expect(notice, isA<ExcerptedNotice>());
      expect((notice as ExcerptedNotice).targetTitle, '对策一：间隔重复');
      final c = await repo.load('demo-1');
      final card = c.cardForAnnotation(c.annotations.last.id)!;
      expect(c.node(card.id)!.parentId, topic.id);
      expect(container.read(workspaceProvider('demo-1')).flashCardId, card.id);
    });

    test('sync off only highlights; select tool asks first', () async {
      await controller.setTool(AnnotationTool.highlight);
      controller.toggleSyncToMap();
      expect(await controller.onSelectionCommitted('c1', selection), isA<HighlightedNotice>());
      var c = await repo.load('demo-1');
      expect(c.annotations, hasLength(2));
      expect(c.excerptCount, 1);

      controller.setTool(AnnotationTool.select);
      expect(await controller.onSelectionCommitted('c1', selection), isNull);
      expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
      controller.dismissPending();
      expect(container.read(workspaceProvider('demo-1')).pending, isNull);

      // Clicking the plain highlight offers "add to map".
      final plain = c.annotations.last.id;
      controller.tapHighlight(plain);
      expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingHighlight>());
      await controller.addHighlightToMap(plain);
      c = await repo.load('demo-1');
      expect(c.cardForAnnotation(plain), isNotNull);
    });

    test('revealing a card opens an owned reference without switching the main document', () async {
      controller.openDocument('c2');
      final excerpt = controller.content.cards.firstWhere((c) => c.kind == CardKind.excerpt);
      controller.setLayout(MMSplitMode.secondary);
      controller.revealCard(excerpt.id);
      final state = container.read(workspaceProvider('demo-1'));
      expect(state.activeDocumentId, 'c2');
      expect(state.layout, MMSplitMode.secondary);
      expect(state.tabs.current.reference!.id, 'c1');
      expect((state.tabs.current.reference!.anchor!.target as PdfTarget).pages.first.page, 24);
    });

    test('removing a card keeps its highlight; deleting the highlight removes both', () async {
      final excerpt = controller.content.cards.firstWhere((c) => c.kind == CardKind.excerpt);
      final annotationId = excerpt.annotationId!;
      controller.selectCard(excerpt.id);
      expect(await controller.removeSelected(), isA<RemovedNotice>());
      var c = await repo.load('demo-1');
      expect(c.card(excerpt.id), isNull);
      expect(c.annotation(annotationId), isNotNull);
      await controller.deleteHighlight(annotationId);
      c = await repo.load('demo-1');
      expect(c.annotations, isEmpty);
    });

    test('page changes are saved after a pause', () async {
      controller.recordPage('c1', 42);
      expect(container.read(readingPagesProvider('demo-1'))['c1'], 42);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect((await repo.load('demo-1')).document('c1')!.lastPage, 42);
    });
  });

  testWidgets('dragging a node onto a topic makes it a child', (tester) async {
    final container = await openFirstSet(tester);
    await showWholeMap(tester);
    final from = tester.getCenter(find.text('这条先陡后平的曲线，被称为遗忘曲线。'));
    final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(-20, 0));
    // Grabbing selects the node, which may pan it into view: aim afterwards.
    await tester.pumpAndSettle();
    final start = from + const Offset(-20, 0);
    final to = tester.getCenter(find.text('对策一：间隔重复'));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(start, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final c = container.read(contentProvider('demo-1')).value!;
    final card = c.cards.firstWhere((x) => x.kind == CardKind.excerpt);
    expect(c.card(c.node(card.id)!.parentId!)!.title, '对策一：间隔重复');
    await settleHud(tester);
  });

  testWidgets('folding a topic hides its children and keeps the root in place', (tester) async {
    final container = await openFirstSet(tester);
    final root = find.text('认知科学入门').last;
    final before = tester.getTopLeft(root);
    await tester.tap(find.byTooltip('Collapse').first);
    await tester.pumpAndSettle();
    expect(find.text('这条先陡后平的曲线，被称为遗忘曲线。'), findsNothing);
    expect(find.text('1'), findsWidgets); // hidden-children badge
    expect(tester.getTopLeft(root), before);
    final c = container.read(contentProvider('demo-1')).value!;
    expect(c.nodes.where((n) => n.collapsed), hasLength(1));
    await settleHud(tester);
  });
}
