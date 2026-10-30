import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:marginmind/features/workspace/reflow_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:marginmind/features/workspace/widgets/reading_settings.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/features/workspace/widgets/reader_zoom_control.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/reflow_reader.dart';
import 'package:marginmind/features/workspace/widgets/reflow_scroll_reader.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'reflow_fixtures.dart';

void main() {
  testWidgets('read, select, excerpt, resize, navigate and undo use source anchors', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.openDocument(doc.id);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ReflowReader), findsOneWidget);
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(session.ready, isTrue);
    final chapter = session.book!.chapters.first;
    final start = chapter.canonicalText.indexOf('Source anchors');
    final anchor = chapter.anchor(start, start + 'Source anchors'.length, revision: doc.revision!);
    final surface = find.byKey(const ValueKey('reflow-surface'));
    final box = session.layout!.boxes(anchor).first.rect;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getTopLeft(surface) + box.topLeft + const Offset(1, 5));
    await tester.pump();
    await mouse.down(tester.getTopLeft(surface) + box.topLeft + const Offset(1, 5));
    await mouse.moveBy(const Offset(20, 0));
    await tester.pump();
    await mouse.moveTo(tester.getTopLeft(surface) + box.topRight + const Offset(-1, 5));
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
    await tester.tap(find.byTooltip('Add to Map'));
    await tester.pumpAndSettle();
    expect(controller.content.annotations, isNotEmpty);
    final annotation = controller.content.annotations.last;
    expect(annotation.isText, isTrue);
    annotation.textAnchors.first.validate();
    final before = annotation.textAnchors.first.toJson();
    await container
        .read(settingsProvider.notifier)
        .setReading(doc.format, const ReadingSettings(size: 6, font: ReaderFont.serif, paged: false));
    await tester.pumpAndSettle();
    expect(controller.content.annotations.last.textAnchors.first.toJson(), before);
    expect(session.layout!.boxes(annotation.textAnchors.first), isNotEmpty);
    final card = controller.content.cardForAnnotation(annotation.id)!;
    controller.revealCard(card.id);
    await tester.pumpAndSettle();
    expect(session.position!.chapterId, anchor.chapterId);
    expect(session.position!.offset, annotation.textAnchors.first.start);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.annotations, isEmpty);
    await controller.redo();
    await tester.pumpAndSettle();
    expect(controller.content.annotations.single.isText, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(session.position!.offset, greaterThan(annotation.textAnchors.first.start));
    controller.setLayout(MMSplitMode.secondary);
    await tester.pumpAndSettle();
    controller.revealCard(card.id);
    await tester.pumpAndSettle();
    expect(
      container.read(reflowSessionProvider(('demo-1', doc.id))).position!.offset,
      annotation.textAnchors.first.start,
    );
    await controller.setReadingPosition(
      doc.id,
      TextReadingPosition(revision: doc.revision!, chapterId: 'main', offset: 100),
    );
    controller.closeDocument(doc.id);
    await tester.pumpAndSettle();
    controller.openDocument(doc.id);
    await tester.pumpAndSettle();
    expect(container.read(reflowSessionProvider(('demo-1', doc.id))).position!.offset, 100);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings, search and source sidebar stay usable on a book', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final chapter = const EpubParser().parseHtml('main', '<h1>First</h1><p>${'anchor text. ' * 100}</p>');
    final doc = await storeBook(
      repo,
      format: DocumentFormat.epub,
      book: Book('A book', [chapter], {}, [], toc: [BookTocEntry('first', 'First', 'main', 0)]),
    );
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    await tester.pumpAndSettle();
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(container.read(settingsProvider).bookReading.paged, isFalse);
    expect(find.byType(ReflowScrollReader), findsOneWidget);
    await tester.tap(find.byTooltip('Reading Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingSettingsPanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reading-larger')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).bookReading.size, 4);
    await tester.tap(find.byKey(const ValueKey('reading-smaller')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Loose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).bookReading.paged, isTrue);
    expect(find.byType(ReflowScrollReader), findsNothing);
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).bookReading.paged, isFalse);
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    workspace.showReaderPanel(ReaderPanelMode.outline);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Thumbnails'), findsNothing);
    await tester.tap(find.text('First').first);
    await tester.pumpAndSettle();
    workspace.setReaderPanelMode(ReaderPanelMode.bookmarks);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Bookmark'));
    await tester.pumpAndSettle();
    expect(workspace.content.bookmarks.single.position, isA<TextReadingPosition>());
    workspace.setReaderPanelMode(ReaderPanelMode.annotations);
    await tester.pumpAndSettle();
    expect(find.text('No Annotations'), findsOneWidget);
    workspace.openFind();
    await tester.pumpAndSettle();
    final field = find.descendant(of: find.byKey(const ValueKey('reflow-find')), matching: find.byType(TextField));
    await tester.enterText(field, 'anchor');
    await tester.pumpAndSettle();
    expect(session.matches.length, 100);
    await tester.tap(find.byTooltip('Find Next'));
    await tester.pumpAndSettle();
    expect(session.matchIndex, 1);
    await tester.tap(find.byTooltip('Find Previous'));
    await tester.pumpAndSettle();
    expect(session.matchIndex, 0);
    await tester.enterText(field, 'nothing');
    await tester.pumpAndSettle();
    expect(session.matches, isEmpty);
    workspace.closeFind();
    await tester.pumpAndSettle();
    expect(session.query, '');
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EPUB scrolls by default across chapters and restores a source position', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(
      repo,
      format: DocumentFormat.epub,
      book: Book(
        'Two chapters',
        [
          const EpubParser().parseHtml('first', '<p>First chapter.</p>'),
          const EpubParser().parseHtml('second', '<p>${'Second chapter original text. ' * 100}</p>'),
        ],
        {},
        [],
      ),
    );
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    await tester.pumpAndSettle();
    final view = find.descendant(of: find.byType(ReflowReader), matching: find.byType(CustomScrollView));
    await tester.drag(view, const Offset(0, -500));
    await tester.pumpAndSettle();
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(session.position!.chapterId, 'second');
    final before = session.position!.offset;
    await container
        .read(settingsProvider.notifier)
        .setReading(doc.format, const ReadingSettings(size: 6, paged: false));
    await tester.pumpAndSettle();
    expect(session.position!.chapterId, 'second');
    expect(session.position!.offset, before);
    expect((workspace.content.document(doc.id)!.readingPosition as TextReadingPosition).chapterId, 'second');
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fixed EPUB uses a Flutter viewport and can annotate', (tester) async {
    final original = const EpubParser().parseHtml('page', '<p>Fixed page text</p>');
    final chapter = BookChapter('page', original.blocks, viewportWidth: 600, viewportHeight: 800);
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(
      repo,
      format: DocumentFormat.epub,
      book: Book('Fixed', [chapter], {}, [], fixedLayout: true),
    );
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    container.read(workspaceProvider('demo-1').notifier).openDocument(doc.id);
    await tester.pumpAndSettle();
    expect(find.byType(ReflowReader), findsOneWidget);
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(session.layout!.pages.length, 1);
    expect(session.layout!.chapter.viewportWidth, 600);
    expect(session.layout!.boxes(chapter.anchor(0, 5, revision: doc.revision!)), isNotEmpty);
    session.zoomTo(2);
    await tester.pumpAndSettle();
    final fixed = find.descendant(of: find.byType(ReflowReader), matching: find.byType(InteractiveViewer));
    expect(tester.widget<InteractiveViewer>(fixed).transformationController!.value.getMaxScaleOnAxis(), 2);
    await tester.tap(find.byKey(const ValueKey('reader-page')));
    await tester.pumpAndSettle();
    final slider = find.descendant(of: find.byType(ReaderZoomSlider), matching: find.byType(Slider));
    final sourceSlider = tester.widget<Slider>(slider);
    sourceSlider.onChanged!(0);
    await tester.pumpAndSettle();
    expect(session.zoom, session.widthZoom);
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('reflow-surface'));
    final element = tester.element(surface);
    Actions.invoke(element, const ReaderZoomIntent(ReaderZoomCommand.actualSize));
    await tester.pumpAndSettle();
    expect(session.zoom, closeTo(1 / session.pageScale, .0001));
    Actions.invoke(element, const ReaderZoomIntent(ReaderZoomCommand.fitWidth));
    await tester.pumpAndSettle();
    expect(session.zoom, session.widthZoom);
    Actions.invoke(element, const ReaderZoomIntent(ReaderZoomCommand.fitPage));
    await tester.pumpAndSettle();
    expect(session.zoom, 1);
    Actions.invoke(element, const ReaderZoomIntent(ReaderZoomCommand.zoomIn));
    await tester.pumpAndSettle();
    expect(session.zoom, MMReaderLayout.zoomStep);
    Actions.invoke(element, const ReaderZoomIntent(ReaderZoomCommand.zoomOut));
    await tester.pumpAndSettle();
    expect(session.zoom, closeTo(1, .0001));
    expect(tester.takeException(), isNull);
  });
  testWidgets('image-only fixed EPUB pans when enlarged without claiming text selection', (tester) async {
    final original = const EpubParser().parseHtml('page', '<img src="page.svg">');
    final chapter = BookChapter('page', original.blocks, viewportWidth: 600, viewportHeight: 800);
    final repo = InMemoryStudySetContentRepository();
    final imported = await storeBook(
      repo,
      format: DocumentFormat.epub,
      book: Book(
        'Scanned',
        [chapter, BookChapter('page2', original.blocks, viewportWidth: 600, viewportHeight: 800)],
        {
          'page.svg': Uint8List.fromList(
            utf8.encode(
              '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="800"><rect width="600" height="800" fill="gray"/></svg>',
            ),
          ),
        },
        [],
        fixedLayout: true,
      ),
    );
    final doc = Document.fromJson({
      ...imported.toJson(),
      'features': const DocumentContentFeatures(text: false).toJson(),
    });
    await repo.update('demo-1', (c) => c.copyWith(documents: [doc]));
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    container.read(workspaceProvider('demo-1').notifier).openDocument(doc.id);
    await tester.pumpAndSettle();
    final s = container.read(reflowSessionProvider(('demo-1', doc.id)));
    container.read(workspaceProvider('demo-1').notifier).showReaderPanel(ReaderPanelMode.thumbnails);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reflow-thumbnail-page')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reflow-thumbnail-page2')));
    await tester.pumpAndSettle();
    expect(s.position!.chapterId, 'page2');
    s.zoomTo(2);
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.descendant(of: find.byType(ReflowReader), matching: find.byType(InteractiveViewer)),
    );
    final before = viewer.transformationController!.value.clone();
    await tester.drag(find.byKey(const ValueKey('reflow-surface')), const Offset(50, 40));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value, isNot(before));
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse selection spans visible chapters and auto-scrolls', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(
      repo,
      book: Book(
        'Two chapters',
        [
          const EpubParser().parseHtml('a', '<p>Alpha first paragraph.</p>'),
          const EpubParser().parseHtml('b', '<p>${'Beta original text. ' * 150}</p>'),
        ],
        {},
        [],
      ),
    );
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    await tester.pumpAndSettle();
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    final first = find.byKey(const ValueKey('reflow-surface')).first;
    final box = session.layout!.boxes(session.book!.chapters.first.anchor(0, 5)).first.rect;
    final begin = tester.getTopLeft(first) + box.topLeft + const Offset(1, 5);
    final viewport = find.descendant(of: find.byType(ReflowReader), matching: find.byType(CustomScrollView));
    final edge = tester.getRect(viewport).bottomCenter - const Offset(0, 8);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: begin);
    await tester.pump();
    await mouse.down(begin);
    await mouse.moveBy(const Offset(20, 0));
    await tester.pump();
    await mouse.moveTo(edge);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    final pending = container.read(workspaceProvider('demo-1')).pending as PendingSelection;
    expect(pending.selection.textAnchors.map((a) => a.chapterId), ['a', 'b']);
    for (final a in pending.selection.textAnchors) {
      a.validate();
      expect(a.revision, doc.revision);
    }
    await tester.tap(find.byTooltip('Add to Map'));
    await tester.pumpAndSettle();
    expect(workspace.content.annotations.single.textAnchors.length, 2);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone long press exposes selection handles and compact actions', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    final container = await pumpApp(
      tester,
      content: repo,
      size: const Size(390, 844),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    workspace.setLayout(MMSplitMode.primary);
    await tester.pumpAndSettle();
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(container.read(settingsProvider).articleReading.size, 4);
    final anchor = session.book!.chapters.first.anchor(0, 8, revision: doc.revision!);
    final box = session.layout!.boxes(anchor).first.rect;
    final surface = find.byKey(const ValueKey('reflow-surface'));
    await tester.longPressAt(tester.getTopLeft(surface) + box.topLeft + const Offset(4, 5));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
    expect(find.bySemanticsLabel('Selection start'), findsOneWidget);
    expect(find.bySemanticsLabel('Selection end'), findsOneWidget);
    final underline = find.byKey(const ValueKey('selection-underline'));
    expect(underline, findsOneWidget);
    await tester.tap(underline);
    await tester.pumpAndSettle();
    expect(workspace.content.annotations.single.kind, AnnotationKind.underline);
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    expect(find.byKey(const ValueKey('selection-underline')), findsNothing);
    expect(find.bySemanticsLabel('Selection start'), findsNothing);
    expect(find.bySemanticsLabel('Selection end'), findsNothing);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets('loading failures can be retried without a PDF fallback', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    final book = await ReflowDocument.load(repo, 'demo-1', doc);
    final provider = reflowSessionProvider(('demo-1', doc.id));
    var attempts = 0;
    final container = await pumpApp(
      tester,
      content: repo,
      overrides: [
        provider.overrideWith((ref) {
          final session = ReflowSession(() async {
            if (attempts++ == 0) throw const FormatException('temporary');
            return book;
          }, onPosition: (_) {});
          ref.onDispose(session.dispose);
          return session;
        }),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    container.read(workspaceProvider('demo-1').notifier).openDocument(doc.id);
    await tester.pumpAndSettle();
    expect(find.text('Unable to open document'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(container.read(provider).ready, isTrue);
    expect(find.byKey(const ValueKey('reflow-surface')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
