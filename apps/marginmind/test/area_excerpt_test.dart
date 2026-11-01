import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/review/review_screen.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/shared/card_image.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';

const _area = MMPdfArea(page: 24, rect: PageRect(50, 500, 250, 400), viewportRect: Rect.fromLTWH(100, 100, 200, 100));
final _png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);

Future<Uint8List?> _capture() async => _png;

/// demo-1 with one image excerpt (and nothing else to review).
StudySetContent _imageContent() {
  var n = 0;
  final editor = StudySetEditor(newId: () => 'i${++n}', now: () => testNow);
  final (withDoc, doc) = editor.addDocument(StudySetContent.empty, title: '图表集', fileName: 'a.pdf', pageCount: 30);
  return editor
      .createAreaExcerpt(
        withDoc,
        documentId: doc.id,
        page: 7,
        rect: const PageRect(10, 300, 210, 200),
        imageFileName: 'images/figure.png',
        colorIndex: 1,
      )
      .$1;
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets('shortcut and toolbar choose the area tool; colors keep it', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final shortcut = AppShortcuts.toggleAreaTool;
    expect(shortcut.shift, isTrue);
    expect(shortcut.trigger, LogicalKeyboardKey.keyR);
    Future<void> toggle() async {
      final modifier = shortcut.meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(shortcut.trigger);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    await toggle();
    expect(container.read(provider).tool, AnnotationTool.area);
    expect(container.read(sharedPreferencesProvider).getString('settings.annotationTool'), 'area');
    await tester.tap(find.byIcon(MMIcons.select));
    await tester.pumpAndSettle();
    expect(container.read(provider).tool, AnnotationTool.select);
    await tester.tap(find.byIcon(MMIcons.areaSelect));
    await tester.pumpAndSettle();
    expect(container.read(provider).tool, AnnotationTool.area);
    final l = AppLocalizations.of(tester.element(find.byIcon(MMIcons.areaSelect)));
    expect(find.byTooltip(AppShortcuts.tip(l.toolArea, shortcut)), findsOneWidget);
    await container.read(provider.notifier).setColor(MMAnnotationColor.green);
    expect(container.read(provider).tool, AnnotationTool.area);
    expect(container.read(provider).color, MMAnnotationColor.green);
    await toggle();
    expect(container.read(provider).tool, AnnotationTool.select);
    await container.read(provider.notifier).toggleAreaTool();
    await container.read(provider.notifier).toggleTool();
    expect(container.read(provider).tool, AnnotationTool.highlight);
  });

  test('a dragged area becomes one undoable image excerpt; failures change nothing', () async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final container = ProviderContainer(overrides: await testOverrides(content: repo));
    addTearDown(container.dispose);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);
    await controller.setColor(MMAnnotationColor.blue);
    controller.selectCard('c3');
    final before = controller.content;

    final notice = await controller.excerptArea('c1', _area, _capture);
    expect(notice, isA<ExcerptedNotice>());
    expect((notice as ExcerptedNotice).targetTitle, '遗忘的规律');
    final card = controller.content.cards.last;
    expect(card.kind, CardKind.image);
    expect(repo.images[card.imageFileName], _png);
    expect(controller.content.node(card.id)!.parentId, 'c3');
    final a = controller.content.annotation(card.annotationId!)!;
    expect(a.page, 24);
    expect(a.rects, [_area.rect]);
    expect(a.colorIndex, MMAnnotationColor.blue.index);
    expect(container.read(provider).flashCardId, card.id);
    expect(controller.imagePath(card.imageFileName!), card.imageFileName);

    controller.revealCard(card.id);
    final reveal = container.read(provider).reveal!;
    expect(reveal.documentId, 'c1');
    expect(reveal.page, 24);
    expect(reveal.rects, [_area.rect]);

    await controller.undo();
    expect(controller.content.cards, hasLength(before.cards.length));
    expect(controller.content.annotations, hasLength(before.annotations.length));

    expect(await controller.excerptArea('c1', _area, () async => null), isA<AreaFailedNotice>());
    expect(await controller.excerptArea('c1', _area, () async => throw StateError('render')), isA<AreaFailedNotice>());
    expect(
      await controller.excerptArea('c1', _area, () async => Uint8List.fromList([1])),
      isA<ExcerptedNotice>(),
      reason: 'the in-memory repository accepts any bytes',
    );
    expect(await controller.excerptArea('gone', _area, _capture), isA<AreaFailedNotice>());
  });

  testWidgets('map, outline and source show the image card and lead back to its area', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    await controller.excerptArea('c1', _area, _capture);
    await settleHud(tester);
    final card = controller.content.cards.last;
    final l = AppLocalizations.of(tester.element(find.byType(CardImage)));
    expect(find.byType(CardImage), findsOneWidget);
    // Untitled, the picture is the card: no title row, no source line.
    expect(find.text(l.imageExcerpt), findsNothing);
    // The image is sized from the area's aspect ratio (2:1) before decoding.
    expect(
      tester.getSize(find.byType(CardImage)).width / tester.getSize(find.byType(CardImage)).height,
      closeTo(2, 0.05),
    );

    await tester.tap(find.descendant(of: find.byKey(ValueKey(card.id)), matching: find.byIcon(MMIcons.revealSource)));
    // The node's double-click recognizer holds the arena briefly.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).reveal!.rects, [_area.rect]);
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, 'c1');
    await settleHud(tester);

    // Clicking the framed area offers recolor, locate and delete, not copy.
    controller.tapHighlight(card.annotationId!);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionToolbar), findsOneWidget);
    expect(find.descendant(of: find.byType(SelectionToolbar), matching: find.byIcon(MMIcons.copy)), findsNothing);
    await tester.tap(find.descendant(of: find.byType(SelectionToolbar), matching: find.byIcon(MMIcons.trash)));
    await tester.pumpAndSettle();
    expect(controller.content.card(card.id), isNull);
    expect(controller.content.annotation(card.annotationId!), isNull);
    await settleHud(tester);

    await controller.undo();
    controller.setMapView(MapViewMode.outline);
    await tester.pumpAndSettle();
    expect(find.text(l.imageExcerpt), findsOneWidget);

    // A titled image is found by search and opens its area.
    await controller.rename(card.id, '光谱图');
    controller.setSidebarQuery('光谱');
    controller.openDocument('c2');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(MMSidebar), matching: find.text('光谱图')));
    await tester.pumpAndSettle();
    expect(container.read(provider).activeDocumentId, 'c1');
    expect(container.read(provider).selectedCardId, card.id);
    expect(container.read(provider).tabs.activeId, WorkspaceTab.documents.id);
    expect(container.read(provider).tabs.current.reference, isNull);
    await settleHud(tester);
  });

  testWidgets('the reader captures a dragged area and frames it on the page', (tester) async {
    installTestPdfBackend();
    TestPdfRender.produceImages = true;
    addTearDown(() => TestPdfRender.produceImages = false);
    final repo = InMemoryStudySetContentRepository({
      'demo-1': StudySetContent(documents: [demoContent().documents.first]),
    });
    final container = await pumpApp(tester, content: repo, renderPdf: true);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    await controller.setTool(AnnotationTool.area);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(MMPdfView).evaluate().isNotEmpty &&
          tester.widget<MMPdfView>(find.byType(MMPdfView)).controller.isReady) {
        break;
      }
    }
    var view = tester.widget<MMPdfView>(find.byType(MMPdfView));
    expect(view.areaSelecting, isTrue);
    const area = MMPdfArea(page: 1, rect: PageRect(100, 700, 300, 600), viewportRect: Rect.fromLTWH(50, 50, 200, 100));
    // Rendering and PNG encoding are real async work; edits settle on pump.
    view.onAreaSelected!(area);
    for (var i = 0; i < 100 && controller.content.cards.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final card = controller.content.cards.single;
    expect(card.kind, CardKind.image);
    expect(repo.images[card.imageFileName]!.sublist(0, 4), [137, 80, 78, 71]);
    view = tester.widget<MMPdfView>(find.byType(MMPdfView));
    expect(view.highlights.single.framed, isTrue);
    expect(view.highlights.single.rects, [area.rect]);

    // A page that cannot be rendered leaves the content unchanged.
    TestPdfRender.produceImages = false;
    view.onAreaSelected!(area);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(controller.content.cards, hasLength(1));
    final l = AppLocalizations.of(tester.element(find.byType(MMPdfView)));
    expect(find.text(l.somethingWentWrong), findsOneWidget);
    await settleHud(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('removing the image card from the map also removes its area', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.excerptArea('c1', _area, _capture);
    final card = controller.content.cards.last;
    controller.selectCard(card.id);
    await controller.removeSelected();
    await tester.pumpAndSettle();
    expect(controller.content.annotation(card.annotationId!), isNull);
    expect(find.byType(CardImage), findsNothing);
    await settleHud(tester);
  });

  testWidgets('review shows the image as the answer and can reveal its area', (tester) async {
    final container = await pumpApp(tester, content: InMemoryStudySetContentRepository({'demo-1': _imageContent()}));
    container.read(navigationProvider.notifier).startReview('demo-1');
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(ReviewScreen)));
    expect(find.byKey(const ValueKey('page-prompt')), findsOneWidget);
    expect(find.text('图表集 · ${l.pageNumber(7)}'), findsNothing);
    expect(find.byType(CardImage), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(CardImage), findsOneWidget);
    expect(find.text('图表集 · ${l.pageNumber(7)}'), findsOneWidget);
    final image = tester.widget<Image>(find.descendant(of: find.byType(CardImage), matching: find.byType(Image)));
    final provider = image.image as ResizeImage;
    expect((provider.imageProvider as FileImage).file.path, 'images/figure.png');
    expect(provider.width, lessThanOrEqualTo(640), reason: 'decoded at the shown width');
    await tester.tap(find.text(l.revealSource));
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<WorkspaceRoute>());
    expect(container.read(workspaceProvider('demo-1')).reveal!.page, 7);
    await settleHud(tester);
  });

  testWidgets('a missing image file shows a placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: CardImageScope(
          resolve: (name) => '/nonexistent/$name',
          child: const SizedBox(width: 120, height: 60, child: CardImage('images/x.png')),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byIcon(MMIcons.areaSelect), findsOneWidget);
    await tester.pumpWidget(MaterialApp(theme: MMTheme.light(), home: const CardImage('images/x.png')));
    expect(find.byIcon(MMIcons.areaSelect), findsOneWidget);
  });

  group('clipboard', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    String? internal;
    setUp(() {
      internal = null;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MMMapClipboard.channel,
        (call) async {
          if (call.method == 'write') {
            internal = (call.arguments as Map)['internal'] as String;
            return null;
          }
          return {'text': 'x', 'internal': ?internal};
        },
      );
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MMMapClipboard.channel,
        null,
      );
    });

    test('copy records the image location; another set imports it on paste', () async {
      final repo = InMemoryStudySetContentRepository({'demo-1': demoContent(), 'other': StudySetContent.empty});
      final container = ProviderContainer(overrides: await testOverrides(content: repo));
      addTearDown(container.dispose);
      for (final id in ['demo-1', 'other']) {
        container.listen(workspaceProvider(id), (_, _) {});
        await container.read(contentProvider(id).future);
      }
      final source = container.read(workspaceProvider('demo-1').notifier);
      await source.excerptArea('c1', _area, _capture);
      source.selectCards([source.content.cards.last.id]);
      await source.copySelection();
      final copied = MapClipboard.decode(internal!)!.single;
      expect(copied.imagePath, source.content.cards.last.imageFileName);

      // A file in another package, named by its content hash.
      final dir = await Directory.systemTemp.createTemp('mm-area');
      addTearDown(() => dir.delete(recursive: true));
      final name = 'images/${'a' * 64}.png';
      final file = File('${dir.path}/$name');
      await file.create(recursive: true);
      await file.writeAsBytes(_png);
      OutlineEntry entry(String path, [String fileName = '']) => OutlineEntry(
        0,
        'Figure',
        kind: CardKind.image,
        imageFileName: fileName.isEmpty ? name : fileName,
        imagePath: path,
        annotation: copied.annotation,
      );

      final target = container.read(workspaceProvider('other').notifier);
      internal = MapClipboard.encode([
        entry(file.path),
        entry('${dir.path}/elsewhere.png', 'images/${'c' * 64}.png'),
        entry(file.path, 'images/not-a-hash.png'),
        entry('${dir.path}/images/${'b' * 64}.png', 'images/${'b' * 64}.png'),
      ]);
      await target.pasteSelection();
      final cards = target.content.cards;
      expect(cards, hasLength(4));
      expect(cards[0].kind, CardKind.image);
      expect(cards[0].imageFileName, file.path, reason: 'in memory, the import keeps the source path');
      expect(cards[0].annotationId, isNull);
      expect(cards.skip(1).map((c) => c.kind), everyElement(CardKind.note));
      expect(jsonEncode(target.content.toJson()), isNot(contains('elsewhere')));
    });
  });
}
