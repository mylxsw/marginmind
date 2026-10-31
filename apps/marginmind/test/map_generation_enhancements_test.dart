import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/map_generation_cache.dart';
import 'package:marginmind/features/assistant/map_generation_context.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/map_quote.dart';
import 'package:marginmind/features/map_generation/widgets/map_source_range.dart';
import 'package:marginmind/features/map_generation/widgets/generate_map_sheet.dart';
import 'package:marginmind/features/map_generation/widgets/map_generation_bar.dart';
import 'package:marginmind/features/workspace/reader_ocr.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';

import 'helpers.dart';
import 'map_generation_context_test.dart' show DigestReader, pdf, digest;
import 'map_generation_ui_test.dart' as harness;
import 'reader_ocr_test.dart' show FakeOcr;
import 'reflow_fixtures.dart';

import 'package:marginmind/features/workspace/reflow_document.dart';

void main() {
  test('footer counts valid pages once, including nested chapter ranges', () {
    final entries = OutlineTree.flatten(const [
      PdfOutlineEntry(
        id: 'part',
        title: 'Part',
        page: 0,
        children: [
          PdfOutlineEntry(id: 'a', title: 'A', page: 1),
          PdfOutlineEntry(id: 'b', title: 'B', page: 3),
        ],
      ),
      PdfOutlineEntry(id: 'page-summary', title: 'Summary', page: 4),
    ]).toList();
    expect(mapSelectedPages(pdf(), entries, null), isEmpty);
    expect(mapSelectedPages(pdf(), entries, []), {1, 2, 3, 4});
    expect(mapSelectedPages(pdf(), entries, ['part', 'a']), {1, 2, 3});
    expect(mapSelectedPages(pdf(), entries, ['page-summary']), {4});
    expect(mapSelectedPages(pdf(), [], ['page-2', 'page-2', 'page-9']), {2});
  });

  test('page range restricts inputs and persists range, rejects invalid page', () async {
    final builder = DocumentDigestBuilder(DigestReader({1: 'one', 2: 'two', 3: 'three', 4: 'four'}));
    final content = StudySetContent(documents: [pdf()]);
    final result = await digest(builder, content, chapters: ['page-2', 'page-3']);
    expect(result.source.chapters, ['page-2', 'page-3']);
    expect(result.chapters.expand((c) => c.input.textByPage.keys), [2, 3]);
    expect(result.chapters.expand((c) => c.input.textByPage.values), ['two', 'three']);
    await expectLater(digest(builder, content, chapters: ['page-5']), throwsA(isA<ResearchFailure>()));
  });

  test('outline containers without a destination select their descendants', () async {
    final builder = DocumentDigestBuilder(DigestReader({1: 'one', 2: 'two', 3: 'three', 4: 'four'}));
    final content = StudySetContent(
      documents: [pdf()],
      documentOutlines: [
        DocumentOutline(
          documentId: 'private-doc',
          items: const [
            PdfOutlineEntry(
              id: 'container',
              title: 'Part',
              page: 0,
              children: [
                PdfOutlineEntry(id: 'a', title: 'A', page: 1),
                PdfOutlineEntry(id: 'b', title: 'B', page: 3),
              ],
            ),
          ],
        ),
      ],
    );
    final all = await digest(builder, content, chapters: ['container']);
    expect(all.chapters.expand((c) => c.input.textByPage.keys), [1, 2, 3, 4]);
    final selected = await digest(builder, content, chapters: ['a']);
    expect(selected.chapters.expand((c) => c.input.textByPage.keys), [1, 2]);
    await expectLater(
      digest(
        DocumentDigestBuilder(DigestReader({1: 'one'})),
        StudySetContent(documents: [pdf()]),
        chapters: ['page-3'],
      ),
      throwsA(isA<MapDigestNeedsText>()),
    );
  });

  test('exact quotes only; geometry rejects mismatches, unavailable boxes and empty text', () {
    MapLine point(String? quote) => MapLine(
      id: 'p',
      kind: MapLineKind.point,
      quote: quote,
      source: CardSource(documentId: 'doc', page: 1),
    );
    final page = TranslationPage(1, 'A quote.', [for (var i = 0; i < 8; i++) PageRect(i * 5, 20, i * 5 + 5, 10)]);
    final mark = mapQuoteAnnotation(page, point('quote'), 'mark', DateTime.utc(2026))!;
    expect(mark.kind, AnnotationKind.underline);
    expect(mark.lineStyle, AnnotationLineStyle.dashed);
    expect(mark.quote, 'quote');
    expect(mark.rects.single, const PageRect(10, 20, 35, 10));
    for (final quote in [null, '', 'invented']) {
      expect(mapQuoteAnnotation(page, point(quote), 'mark', DateTime.utc(2026)), isNull);
    }
    expect(
      mapQuoteAnnotation(TranslationPage(2, page.text, page.boxes), point('quote'), 'm', DateTime.utc(2026)),
      isNull,
    );
    expect(mapQuoteAnnotation(TranslationPage(1, page.text, []), point('quote'), 'm', DateTime.utc(2026)), isNull);
  });

  test('canonical text quotes become stable dashed anchors without PDF pages', () async {
    final repository = InMemoryStudySetContentRepository({'demo-1': StudySetContent.empty});
    final doc = await storeBook(repository);
    final content = await repository.load('demo-1');
    final book = await ReflowDocument.load(repository, 'demo-1', doc);
    final digest = await DocumentDigestBuilder(
      DigestReader({}),
      repository: repository,
    ).build(content, studySetId: 'demo-1', documentId: doc.id, mapId: 'map', draftPrefix: 'run-', extractQuotes: true);
    final context = digest.chapters.first.input.context;
    final point = parseMapLine('{"k":"point","id":"p","title":"Source","page":1,"quote":"Source anchors"}', context)!;
    expect(point.source, isNull);
    expect(point.quoteSource!.page, 1);
    final mark = mapTextQuoteAnnotation(book, point, 'm', DateTime.utc(2026))!;
    expect(mark.isText, isTrue);
    expect(mark.textAnchors.single.quote, 'Source anchors');
    expect(mark.lineStyle, AnnotationLineStyle.dashed);
    expect(mapTextQuoteAnnotation(book, MapLine(id: 'bad', kind: MapLineKind.point), 'm', DateTime.utc(2026)), isNull);
  });

  test('cache size includes old schemas and clear is isolated', () async {
    final directory = await Directory.systemTemp.createTemp('gul628-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = MapDigestCache(directory);
    expect(await cache.sizeBytes(), 0);
    await cache.write('a' * 64, ['{"k":"point","id":"p","title":"中文"}']);
    final size = await cache.sizeBytes();
    expect(size, greaterThan(0));
    final old = File('${cache.directory!.parent.path}/v0/old.json');
    await old.parent.create(recursive: true);
    await old.writeAsString('123');
    expect(await cache.sizeBytes(), size + 3);
    await cache.clear();
    expect(await cache.sizeBytes(), 0);
    final memory = MapDigestCache(null);
    await memory.write('b' * 64, ['{"k":"point","id":"p","title":"中文"}']);
    expect(await memory.sizeBytes(), greaterThan(0));
    await memory.clear();
    expect(await memory.sizeBytes(), 0);
  });

  testWidgets('range contents select all/none and validate fixed-width page fields', (tester) async {
    List<String>? selected = [];
    Future<void> show(List<PdfOutlineEntry> entries) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => MapSourceRange(
                document: pdf(),
                entries: entries,
                selection: selected,
                onChanged: (value) => update(() => selected = value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(const [PdfOutlineEntry(id: 'c1', title: 'One', page: 1)]);
    expect(tester.widget<MMCheckbox>(find.byType(MMCheckbox)).value, isTrue);
    await tester.tap(find.byType(MMCheckbox));
    await tester.pump();
    expect(selected, isNull);
    await tester.tap(find.byType(MMCheckbox));
    await tester.pump();
    expect(selected, isEmpty);
    await tester.pumpWidget(const SizedBox());
    selected = [];
    await show([]);
    expect(tester.getSize(find.byType(MMTextField).first).width, MMSizes.mapGeneratePageFieldWidth);
    await tester.enterText(find.byType(TextField).first, '0');
    expect(selected, isNull);
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.enterText(find.byType(TextField).last, '3');
    expect(selected, ['page-2', 'page-3']);
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.enterText(find.byType(TextField).last, '4');
    expect(selected, isEmpty);
  });

  for (final withOutline in [true, false]) {
    testWidgets('settings forwards selected ${withOutline ? 'chapters' : 'pages'} and quote toggle', (tester) async {
      final base = demoContent();
      final original = base.documents.first;
      final doc = Document(
        id: original.id,
        title: original.title,
        fileName: original.fileName,
        pageCount: 4,
        importedAt: original.importedAt,
      );
      final repository = InMemoryStudySetContentRepository({
        'demo-1': base.copyWith(
          documents: [doc],
          documentOutlines: [
            if (withOutline)
              DocumentOutline(
                documentId: doc.id,
                items: const [
                  PdfOutlineEntry(id: 'first', title: 'First chapter', page: 1),
                  PdfOutlineEntry(id: 'second', title: 'Second chapter', page: 3),
                ],
              ),
          ],
        ),
      });
      final fake = FakeMapGenerator(
        chapters: {
          '*': ['{"k":"point","id":"p","title":"Point","page":3,"quote":"Exact quote"}'],
        },
        generation: ['{"ref":"t","parent":"ROOT","title":"Selected topic"}'],
      );
      final container = await harness.openWorkspace(
        tester,
        content: repository,
        pageText: (_, _) async => 'Exact quote',
        overrides: [
          mapGeneratorProvider.overrideWithValue(() async => fake),
          mapQuotePageProvider.overrideWithValue((_, _) async => throw StateError('Unavailable geometry')),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('map-generate-header-button')));
      await tester.pumpAndSettle();
      expect(find.byType(MapSourceRange), findsNothing);
      await tester.tap(find.byKey(ValueKey('map-range-toggle-${doc.id}')));
      final range = find.byType(MapSourceRange);
      await tester.pumpAndSettle();
      if (withOutline) {
        await tester.tap(find.descendant(of: range, matching: find.byType(MMCheckbox)).first);
      } else {
        final fields = find.descendant(of: range, matching: find.byType(TextField));
        await tester.enterText(fields.first, '0');
        await tester.pump();
        expect(
          tester.widget<MMButton>(find.byKey(const ValueKey('map-generate-sheet-start-button'))).onPressed,
          isNull,
        );
        await tester.enterText(fields.first, '3');
      }
      await tester.pump();
      final check = tester.widget<MMCheckbox>(find.byKey(ValueKey('map-document-check-${doc.id}')));
      expect(check.mixed, isTrue);
      expect(tester.widget<Text>(find.byKey(const ValueKey('map-range-page-count'))).data, '2 页');
      await tester.tap(find.byKey(ValueKey('map-range-toggle-${doc.id}')));
      await tester.pump();
      expect(find.byType(MapSourceRange), findsNothing);
      final sheet = find.byType(GenerateMapSheet);
      await tester.tap(find.descendant(of: sheet, matching: find.byType(MMSwitch)).last);
      await tester.tap(find.byKey(const ValueKey('map-generate-sheet-start-button')));
      await tester.pumpAndSettle();
      final preview = container.read(mapGenerationControllerProvider('demo-1'))!;
      expect(preview.request.extractQuotes, isTrue);
      expect(preview.request.sources.single.chapters, withOutline ? ['second'] : ['page-3', 'page-4']);
      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      expect(controller.chapterInputs.values.expand((i) => i.textByPage.keys), [3, 4]);
      expect(preview.phase, MapGenerationPhase.review);
      expect(container.read(workspaceProvider('demo-1').notifier).content.annotations, base.annotations);
    });
  }

  testWidgets('range toggle belongs to the single document row and multi-selection hides it', (tester) async {
    await harness.openWorkspace(tester);
    await tester.tap(find.byKey(const ValueKey('map-generate-header-button')));
    await tester.pumpAndSettle();
    final sheet = find.byType(GenerateMapSheet);
    expect(
      find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is Text && w.data == '学习的底层逻辑')),
      findsOneWidget,
    );
    expect(
      tester.widget<Material>(find.descendant(of: sheet, matching: find.byType(Material)).first).color,
      tester.element(sheet).mmColors.windowBackground,
    );
    await tester.tap(find.byKey(const ValueKey('map-range-toggle-c1')));
    await tester.pump();
    expect(find.byType(MapSourceRange), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.byType(MMSwitch)), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('map-document-check-c2')));
    await tester.pumpAndSettle();
    expect(find.byType(MapSourceRange), findsNothing);
    expect(find.byKey(const ValueKey('map-range-toggle-c1')), findsNothing);
    expect(find.byKey(const ValueKey('map-range-toggle-c2')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('map-range-page-count'))).data, '42 页');
  });

  testWidgets('scanned source has the specified independent banner and disables the sheet before generation', (
    tester,
  ) async {
    final ocr = FakeOcr()..document = const PdfOcrDocument(path: '/scan.pdf', pageCount: 30, textPages: {});
    final container = await harness.openWorkspace(
      tester,
      pageText: (_, _) async => '',
      overrides: [pdfOcrServiceProvider.overrideWithValue(ocr)],
    );
    final banner = find.byKey(const ValueKey('map-ocr-banner'));
    expect(banner, findsOneWidget);
    expect(tester.getSize(banner).height, MMSizes.mapDocumentBanner);
    expect(find.descendant(of: banner, matching: find.byIcon(MMReaderIcons.area)), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.text('先识别文字才能生成')), findsOneWidget);
    final recognize = tester.widget<MMButton>(find.byKey(const ValueKey('map-ocr-recognize')));
    expect(recognize.label, '识别文字');
    expect(recognize.variant, MMButtonVariant.primary);
    expect(find.descendant(of: banner, matching: find.text('取消')), findsNothing);
    final border = (tester.widget<Container>(banner).decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, MMSizes.hairline);
    await tester.tap(find.byKey(const ValueKey('map-generate-header-button')));
    await tester.pumpAndSettle();
    final sheet = find.byType(GenerateMapSheet);
    expect(find.descendant(of: sheet, matching: find.byIcon(MMReaderIcons.area)), findsNWidgets(2));
    expect(find.descendant(of: sheet, matching: find.text('需先识别文字')), findsNWidgets(2));
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('map-generate-sheet-start-button'))).onPressed, isNull);
    expect(find.descendant(of: sheet, matching: find.byTooltip('先识别文字才能生成')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('map-range-page-count'))).data, '0 页');
    expect(find.byKey(const ValueKey('map-range-toggle-c1')), findsNothing);
    expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
    await harness.key(tester, LogicalKeyboardKey.escape);
    await container.read(workspaceProvider('demo-1').notifier).addMap('Scan');
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('map-empty-state-start-button'))).onPressed, isNull);
    await harness.key(tester, LogicalKeyboardKey.enter, primary: true);
    expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
    await tester.tap(find.byKey(const ValueKey('map-ocr-recognize')));
    await tester.pumpAndSettle();
    expect(find.text('范围'), findsOneWidget);
    await harness.key(tester, LogicalKeyboardKey.escape);
    await tester.tap(find.byKey(const ValueKey('map-ocr-close')));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    // A fresh request must surface OCR again after a previously dismissed notice.
    await harness.runGeneration(
      tester,
      () => container
          .read(mapGenerationControllerProvider('demo-1').notifier)
          .start(
            const MapGenerationRequest(
              studySetId: 'demo-1',
              mapId: 'scan',
              title: 'Scan',
              sources: [MapDocumentSelection(documentId: 'c1')],
            ),
          ),
    );
    expect(banner, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-ocr-close')));
    await tester.pumpAndSettle();
    expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
    expect(banner, findsNothing);
  });

  testWidgets('cache settings shows bytes and clears all study set caches', (tester) async {
    final cache = MapDigestCache(null);
    await cache.write('a' * 64, ['{"k":"point","id":"p","title":"Point"}']);
    await pumpApp(
      tester,
      overrides: [
        mapDigestCachesProvider.overrideWith((ref) async => [cache]),
      ],
    );
    // Use the existing app's settings route, preserving its ProviderScope.
    final context = tester.element(find.byType(Navigator).first);
    showSettings(context, tab: SettingsTab.maps);
    await tester.pumpAndSettle();
    expect(find.textContaining(' B'), findsOneWidget);
    expect(
      find.ancestor(of: find.byKey(const ValueKey('map-cache-clear')), matching: find.byType(MMSettingsRow)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('map-cache-clear')));
    await tester.pumpAndSettle();
    expect(await cache.sizeBytes(), 0);
    expect(find.text('0 B'), findsOneWidget);
  });

  testWidgets('quotes are staged for review, discarded cleanly, retained and undone together', (tester) async {
    FakeMapGenerator fake() => FakeMapGenerator(
      chapters: {
        '*': ['{"k":"point","id":"p","title":"Memory","page":1,"quote":"Exact quote"}'],
      },
      generation: ['{"ref":"t","parent":"ROOT","title":"Memory"}', '{"mark":"A1","parent":"t"}'],
    );
    final container = await harness.openWorkspace(
      tester,
      pageText: (_, _) async => 'Exact quote',
      overrides: [
        mapGeneratorProvider.overrideWithValue(() async => fake()),
        mapQuotePageProvider.overrideWithValue(
          (_, page) async =>
              TranslationPage(page, 'Exact quote', [for (var i = 0; i < 11; i++) PageRect(i * 5, 20, i * 5 + 5, 10)]),
        ),
      ],
    );
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final before = workspace.content.annotations.length;
    final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
    const request = MapGenerationRequest(
      studySetId: 'demo-1',
      mapId: 'quote-map',
      title: 'Quote map',
      sources: [
        MapDocumentSelection(documentId: 'c1', chapters: ['page-1']),
      ],
      includeAnnotations: false,
      extractQuotes: true,
    );
    await harness.runGeneration(tester, () => controller.start(request));
    expect(container.read(mapGenerationControllerProvider('demo-1'))!.lines, hasLength(2));
    expect(workspace.content.annotations, hasLength(before));
    controller.discard();
    expect(workspace.content.annotations, hasLength(before));
    await harness.runGeneration(tester, () => controller.start(request));
    var kept = 0;
    await harness.runGeneration(tester, () async {
      kept = await controller.keep();
    });
    expect(kept, 2);
    expect(workspace.content.annotations, hasLength(before + 1));
    expect(workspace.content.annotations.last.lineStyle, AnnotationLineStyle.dashed);
    expect(workspace.content.map('quote-map')!.generation!.sources.single.chapters, ['page-1']);
    await workspace.undo();
    expect(workspace.content.annotations, hasLength(before));
    expect(workspace.content.map('quote-map'), isNull);
  });

  testWidgets('text document quotes use the same review and transaction', (tester) async {
    final repository = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final chapter = const EpubParser().parseHtml('main', '<h1>Text</h1><p>Source anchors keep annotations stable.</p>');
    await storeBook(
      repository,
      book: Book('Text', [chapter], {}, [], toc: [BookTocEntry('main-toc', 'Text', 'main', 0)]),
    );
    final fake = FakeMapGenerator(
      chapters: {
        '*': ['{"k":"point","id":"p","title":"Source","page":1,"quote":"Source anchors"}'],
      },
      generation: ['{"ref":"t","parent":"ROOT","title":"Source"}', '{"mark":"A1","parent":"t"}'],
    );
    final container = await harness.openWorkspace(
      tester,
      content: repository,
      overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
    );
    final outline = await container.read(mapDocumentOutlineProvider(('demo-1', 'book')).future);
    expect(outline, isNotEmpty);
    final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
    await harness.runGeneration(
      tester,
      () => controller.start(
        const MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: 'text-map',
          title: 'Text map',
          sources: [MapDocumentSelection(documentId: 'book')],
          includeAnnotations: false,
          extractQuotes: true,
        ),
      ),
    );
    var kept = 0;
    await harness.runGeneration(tester, () async {
      kept = await controller.keep();
    });
    expect(kept, 2);
    final content = container.read(workspaceProvider('demo-1').notifier).content;
    expect(content.annotations.last.isText, isTrue);
    expect(content.annotations.last.quote, 'Source anchors');
  });

  testWidgets('scanned PDF offers OCR and resumes using recognized copy', (tester) async {
    final ocr = FakeOcr();
    ocr.document = const PdfOcrDocument(path: '/scan.pdf', pageCount: 30, textPages: {});
    final fake = FakeMapGenerator(
      chapters: {
        '*': ['{"k":"point","id":"p","title":"Scanned point","page":1}'],
      },
      generation: ['{"ref":"t","parent":"ROOT","title":"Scanned topic"}'],
    );
    final container = await harness.openWorkspace(
      tester,
      pageText: (path, _) async => path == '/recognized.pdf' ? 'Recognized text' : '',
      overrides: [
        pdfOcrServiceProvider.overrideWithValue(ocr),

        mapGeneratorProvider.overrideWithValue(() async => fake),
      ],
    );
    final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
    await harness.runGeneration(
      tester,
      () => controller.start(
        const MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: 'scan-map',
          title: 'Scan',
          sources: [MapDocumentSelection(documentId: 'c1')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(mapGenerationControllerProvider('demo-1'))!.needsTextDocumentId, 'c1');
    expect(find.byKey(const ValueKey('map-ocr-recognize')), findsOneWidget);
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('map-ocr-recognize'))).label, '识别文字');
    expect(find.descendant(of: find.byType(MapGenerationBar), matching: find.text('先识别文字才能生成')), findsNothing);
    expect(fake.calls, isEmpty);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final source = workspace.filePath(workspace.content.document('c1')!);
    for (final cancelled in [true, false]) {
      final unsuccessful = container
          .read(readerOcrProvider(source).notifier)
          .recognize(1, 30, PdfOcrLanguage.chineseEnglish);
      await tester.pump();
      if (cancelled) {
        ocr.result.complete((document: ocr.document, cancelled: true));
      } else {
        ocr.result.completeError(StateError('OCR failed'));
      }
      await harness.runGeneration(tester, () => unsuccessful);
      expect(container.read(mapGenerationControllerProvider('demo-1'))!.phase, MapGenerationPhase.failed);
      expect(fake.calls, isEmpty);
      ocr.result = Completer();
    }
    final job = container.read(readerOcrProvider(source).notifier).recognize(1, 30, PdfOcrLanguage.chineseEnglish);
    await tester.pump();
    ocr.result.complete((
      document: const PdfOcrDocument(path: '/recognized.pdf', pageCount: 30, textPages: {1}, hasCopy: true),
      cancelled: false,
    ));
    await harness.runGeneration(tester, () => job);
    await tester.pumpAndSettle();
    expect(container.read(mapGenerationControllerProvider('demo-1'))!.phase, MapGenerationPhase.review);
    expect(find.text('Scanned topic'), findsOneWidget);
  });
}
