import 'package:marginmind/features/workspace/document_translation_runtime.dart';

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/translation_schedulers.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/widgets/reader_translation_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_compare_test.dart' show compareFixture;

List<TranslationParagraph> paragraphs(String id) => [
  for (var i = 0; i < 3; i++)
    TranslationParagraph(
      documentId: id,
      page: i == 2 ? 2 : 1,
      index: i,
      text: 'Source paragraph $i with enough words to read.',
      fingerprint: '$id-$i',
      rects: [PageRect(70, 650 - i % 2 * 220, 500, 550 - i % 2 * 220)],
    ),
];

class TestTranslator implements ParagraphTranslator {
  final pending = <int, Completer<ParagraphTranslation>>{};
  final calls = <int>[];
  final languages = <String>[];
  bool closed = false;
  @override
  Future<ParagraphTranslation> translate(
    TranslationParagraph p,
    String language,
    CancellationToken cancel,
    int maxTokens, {
    String? sourceLanguage,
  }) async {
    calls.add(p.index);
    languages.add(language);
    return (pending[p.index] = Completer<ParagraphTranslation>()).future;
  }

  @override
  void close() => closed = true;
}

const model = AssistantModel(
  provider: AssistantProvider.ollama,
  model: 'fixture',
  endpoint: 'http://localhost:11434',
  localEnabled: true,
);
Future<void> frames(WidgetTester tester, {int count = 12}) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<ProviderContainer> setup(
  WidgetTester tester,
  TestTranslator translator, {
  bool render = false,
  bool hasText = true,
  StudySetContent? data,
  AssistantModel? selected = model,
  Map<String, Object> prefs = const {},
  List<TranslationParagraph>? pageContent,
  TranslationStore? storage,
}) async {
  final c = await pumpApp(
    tester,
    renderPdf: render,
    size: const Size(1600, 1000),
    prefs: prefs,
    content: InMemoryStudySetContentRepository({'demo-1': data ?? compareFixture()}),
    overrides: [
      if (storage != null) translationStoreProvider('demo-1').overrideWith((ref) async => storage),
      assistantDefaultModelProvider.overrideWithValue(selected),
      assistantCredentialStateProvider.overrideWith(
        (ref) async => selected == null ? AssistantCredentialState.unconfigured : AssistantCredentialState.ready,
      ),
      documentTranslatorFactoryProvider.overrideWithValue((_, _) async => translator),
      for (final id in ['c1', 'c2', 'third']) ...[
        translationParagraphsProvider(('demo-1', id)).overrideWith((ref) async => pageContent ?? paragraphs(id)),
        compareDocumentInfoProvider(('demo-1', id))
            .overrideWith((ref) async => (language: id == 'c1' ? 'zh' : 'en', hasText: hasText)),
      ],
    ],
  );
  c.read(navigationProvider.notifier).openStudySet('demo-1');
  await frames(tester);
  return c;
}

Future<void> finish(WidgetTester tester, TestTranslator translator) async {
  for (var n = 0; n < 5; n++) {
    for (final e in translator.pending.entries.toList()) {
      if (!e.value.isCompleted) e.value.complete(ParagraphTranslation('Translated paragraph ${e.key}.', tokens: 5));
    }
    await frames(tester, count: 3);
  }
}

Future<Map<String, String>> saved(ProviderContainer c, {String document = 'c1', String language = 'en'}) async {
  final store = await c.read(translationStoreProvider('demo-1').future);
  return {for (final s in (await store.load(document, language)).segments.values) s.fingerprint: s.text};
}

void main() {
  testWidgets('unfinished full job suppresses on-demand and reuses the same scheduler', (tester) async {
    final storage = InMemoryTranslationStore(), translator = TestTranslator();
    final now = DateTime.utc(2026, 10, 31);
    await storage.saveJob(
      TranslationJob(
        id: 'full',
        documentId: 'c1',
        targetLang: 'en',
        range: TranslationRange(1, 2),
        mode: TranslationMode.batch,
        batchSize: 5,
        model: 'fixture',
        state: TranslationJobState.review,
        batch: TranslationBatch(index: 1, range: TranslationRange(1, 1)),
        estimateTokens: 1000,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final c = await setup(tester, translator, storage: storage);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    final controller = c.read(readerTranslationProvider('demo-1').notifier);
    controller.prioritize([2], 2);
    await frames(tester);
    await controller.retry();
    expect(translator.calls, isEmpty);
    final registry = c.read(translationSchedulersProvider('demo-1'));
    final content = c.read(workspaceProvider('demo-1').notifier).content;
    final owner = await registry.get('c1', 'en', paragraphs('c1'), content: content);
    expect(identical(owner, await registry.get('c1', 'en', paragraphs('c1'), content: content)), true);
    final retry = owner.retry(owner.paragraphs[2]);
    await frames(tester);
    expect(translator.calls, [2]);
    translator.pending[2]!.complete(const ParagraphTranslation('explicit'));
    await retry;
    expect(owner.job!.state, TranslationJobState.review);
    await owner.stop();
    controller.prioritize([0], 0);
    await frames(tester);
    expect(translator.calls.toSet(), {0, 1, 2});
    await finish(tester, translator);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
  setUp(() {
    installTestPdfBackend();
    TestPdfRender.produceImages = true;
    TestPdfText.pages = {
      for (var n = 1; n <= 3; n++)
        n: PdfPageRawText('Source text', List.generate(11, (i) => PdfRect(70 + i * 10, 650, 80 + i * 10, 630))),
    };
  });
  tearDown(() {
    TestPdfRender.produceImages = false;
    TestPdfRender.renders.clear();
    TestPdfText.pages = {};
  });
  testWidgets('image cover does not disable a text document', (tester) async {
    TestPdfText.pages[1] = PdfPageRawText('', []);
    final c = await pumpApp(
      tester,
      renderPdf: true,
      content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}),
    );
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('reader-more')));
    await frames(tester);
    final info = c.read(compareDocumentInfoProvider(('demo-1', 'c1'))).value;
    expect(info!.hasText, true);
    expect(info.language, 'en');
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
  testWidgets('AI reader progress, cache, hover on either side and exit', (tester) async {
    final t = TestTranslator();
    final c = await setup(tester, t, render: true);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    expect(find.byType(ReaderTranslationView), findsOneWidget);
    expect(find.text('Page 1 · Translating 0/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('compare-align')), findsNothing);
    expect(find.byKey(const ValueKey('compare-swap')), findsNothing);
    t.pending[0]!.complete(const ParagraphTranslation('Translated paragraph 0.', tokens: 5));
    await frames(tester);
    expect(find.text('Page 1 · Translating 1/2'), findsOneWidget);
    await finish(tester, t);
    expect(find.textContaining(RegExp(r'Page \d+ saved')), findsOneWidget);
    final workspace = c.read(workspaceProvider('demo-1').notifier);
    expect(await saved(c), hasLength(2));
    expect(workspace.content.translationCaches, isEmpty);
    expect(t.calls.toSet(), {0, 1});
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('translation-paragraph-0'))));
    await tester.pump();
    expect(c.read(readerTranslationProvider('demo-1')).hovered, 'c1-0');
    expect(tester.widget<MMPdfView>(find.byType(MMPdfView)).hoveredParagraph, 'c1-0');
    await mouse.moveTo(
      tester.getCenter(
        find
            .byWidgetPredicate(
              (w) =>
                  w is MouseRegion &&
                  !w.opaque &&
                  w.hitTestBehavior == HitTestBehavior.translucent &&
                  w.onEnter != null,
            )
            .first,
      ),
    );
    await tester.pump();
    expect(c.read(readerTranslationProvider('demo-1')).hovered, 'c1-0');
    final compare = c.read(readerCompareProvider('demo-1').notifier);
    final moving = compare.pdf('c1').jumpToReadingPosition(PdfReadingPosition(page: 2, y: 600));
    await frames(tester);
    await moving;
    expect(t.calls, contains(2));
    await finish(tester, t);
    expect(await saved(c), hasLength(3));
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ReaderTranslationView),
            matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down),
          )
          .first,
    );
    expect(scrollable.position.pixels, greaterThan(100));
    final old = compare.pdf('c1').readingPosition!;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ReaderTranslationView)),
        scrollDelta: const Offset(0, -350),
      ),
    );
    await frames(tester);
    final position = compare.pdf('c1').readingPosition!;
    expect(position.page != old.page || (position.y - old.y).abs() > 1, true);
    final stable = position.toJson();
    await frames(tester);
    expect(compare.pdf('c1').readingPosition!.toJson(), stable);
    await compare.toggleSync();
    await frames(tester);
    final stopped = compare.pdf('c1').readingPosition!.toJson();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ReaderTranslationView)),
        scrollDelta: const Offset(0, 200),
      ),
    );
    await frames(tester);
    expect(compare.pdf('c1').readingPosition!.toJson(), stopped);
    await compare.toggleSync();
    await frames(tester);
    await tester.tapAt(tester.getTopLeft(find.byType(MMPdfView)) + const Offset(10, 10));
    await frames(tester);
    tester.view.physicalSize = const Size(1500, 950);
    await frames(tester);
    await mouse.removePointer();
    await c.read(readerCompareProvider('demo-1').notifier).exit();
    await frames(tester);
    expect(t.closed, false);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    expect(find.textContaining(RegExp(r'Page \d+ saved')), findsOneWidget);
    expect(t.calls.length, 3);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failure keeps saved paragraphs, retry completes, source switch cancels late writes', (tester) async {
    final t = TestTranslator();
    final c = await setup(tester, t);
    final compare = c.read(readerCompareProvider('demo-1').notifier);
    await compare.openAi('en');
    await frames(tester);
    t.pending[0]!.completeError(const ResearchFailure(ResearchFailureKind.protocol));
    await frames(tester);
    await finish(tester, t);
    expect(find.text('Translation failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await frames(tester);
    expect(find.text('Page 1 · Translating 1/2'), findsOneWidget);
    t.pending[0]!.complete(const ParagraphTranslation('Retry translated.', tokens: 5));
    await frames(tester);
    expect(find.textContaining(RegExp(r'Page \d+ saved')), findsOneWidget);
    await compare.select('c2', left: true);
    await frames(tester);
    expect(t.closed, false);
    expect(c.read(readerCompareProvider('demo-1'))!.leftDocumentId, 'c2');
    await compare.exit();
    await frames(tester);
    await finish(tester, t);
    expect(
      c.read(workspaceProvider('demo-1').notifier).content.translationCaches.where((c) => c.documentId == 'c2'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
  testWidgets('cached translation opens offline without configured model', (tester) async {
    final cache = TranslationCache(
      documentId: 'c1',
      targetLang: 'en',
      model: 'previous/model',
      createdAt: testNow,
      paragraphs: {for (final p in paragraphs('c1')) p.fingerprint: 'Cached translation ${p.index}.'},
    );
    final t = TestTranslator();
    final c = await setup(
      tester,
      t,
      selected: null,
      prefs: {'assistant.online': false},
      data: compareFixture().copyWith(translationCaches: [cache]),
    );
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    expect(find.textContaining(RegExp(r'Page \d+ saved')), findsOneWidget);
    expect(t.calls, isEmpty);
    final selectable = tester.widget<SelectableText>(
      find.ancestor(of: find.text('Cached translation 0.'), matching: find.byType(SelectableText)).first,
    );
    expect(selectable.contextMenuBuilder, isNotNull);
    final editableFinder = find.descendant(
      of: find.byKey(const ValueKey('translation-paragraph-0')),
      matching: find.byType(EditableText),
    );
    final editable = tester.state<EditableTextState>(editableFinder);
    editable.userUpdateTextEditingValue(
      const TextEditingValue(text: 'Cached translation 0.', selection: TextSelection(baseOffset: 0, extentOffset: 21)),
      SelectionChangedCause.longPress,
    );
    editable.showToolbar();
    await tester.pump();
    expect(find.text('Comment'), findsNothing);
    await tester.tap(find.text('Excerpt to Map'));
    await frames(tester);
    final workspace = c.read(workspaceProvider('demo-1').notifier);
    final excerpt = workspace.content.annotations.last;
    expect(excerpt.documentId, 'c1');
    expect(excerpt.quote, 'Cached translation 0.');
    expect(excerpt.pages.single.rects, paragraphs('c1').first.rects);
    editable.userUpdateTextEditingValue(
      const TextEditingValue(text: 'Cached translation 0.', selection: TextSelection(baseOffset: 0, extentOffset: 21)),
      SelectionChangedCause.longPress,
    );
    editable.showToolbar();
    await tester.pump();
    await tester.tap(find.text('Highlight'));
    await frames(tester);
    expect(workspace.content.annotations.where((a) => a.quote == 'Cached translation 0.').length, 2);
    expect(
      (tester.widget<Container>(find.byKey(const ValueKey('translation-paragraph-0'))).decoration as BoxDecoration)
          .color,
      isNotNull,
    );
    await c.read(readerCompareProvider('demo-1').notifier).toggleSync();
    await frames(tester);
    expect(c.read(readerCompareProvider('demo-1'))!.sync, false);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
  testWidgets('only the viewed page is requested; revisit and reopen reuse partial document cache offline', (
    tester,
  ) async {
    final t = TestTranslator();
    final c = await setup(tester, t);
    final compare = c.read(readerCompareProvider('demo-1').notifier);
    await compare.openAi('en');
    await frames(tester);
    await finish(tester, t);
    expect(t.calls.toSet(), {0, 1});
    expect(c.read(readerTranslationProvider('demo-1')).complete, true);
    await frames(tester, count: 20);
    expect(t.calls.toSet(), {0, 1});
    final cache = c.read(workspaceProvider('demo-1').notifier).content;
    final storage = await c.read(translationStoreProvider('demo-1').future);
    expect(await saved(c), hasLength(2));
    final controller = c.read(readerTranslationProvider('demo-1').notifier);
    controller.prioritize([2], 2);
    await frames(tester);
    expect(t.calls, [0, 1, 2]);
    await finish(tester, t);
    controller.prioritize([0], 0);
    await frames(tester);
    expect(c.read(readerTranslationProvider('demo-1')).page, 1);
    expect(t.calls, [0, 1, 2]);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    final offline = TestTranslator();
    final reopened = await setup(tester, offline, data: cache, selected: null, storage: storage);
    await reopened.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    expect(reopened.read(readerTranslationProvider('demo-1')).complete, true);
    expect(reopened.read(readerTranslationProvider('demo-1')).failed, false);
    expect(offline.calls, isEmpty);
    final restored = reopened.read(readerTranslationProvider('demo-1').notifier);
    restored.prioritize([2], 2);
    await frames(tester);
    expect(reopened.read(readerTranslationProvider('demo-1')).complete, true);
    restored.prioritize([0], 0);
    await frames(tester);
    expect(reopened.read(readerTranslationProvider('demo-1')).complete, true);
    expect(reopened.read(readerTranslationProvider('demo-1')).failed, false);
    expect(offline.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('turning a page drains paid results before dispatching the visible page', (tester) async {
    final t = TestTranslator();
    final c = await setup(tester, t);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    final pending = t.pending.values.toList();
    c.read(readerTranslationProvider('demo-1').notifier).prioritize([2], 2);
    await frames(tester);
    expect(t.closed, false);
    expect(t.calls, [0, 1]);
    for (final future in pending) {
      future.complete(const ParagraphTranslation('Late previous-page text', tokens: 5));
    }
    await frames(tester);
    t.pending[2]!.complete(const ParagraphTranslation('Current-page text', tokens: 5));
    await frames(tester);
    expect(await saved(c), {
      'c1-0': 'Late previous-page text',
      'c1-1': 'Late previous-page text',
      'c1-2': 'Current-page text',
    });
    expect(c.read(readerTranslationProvider('demo-1')).page, 2);
    expect(c.read(readerTranslationProvider('demo-1')).complete, true);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('a text-run-heavy page can finish with reasoning token usage, without starting the next page', (
    tester,
  ) async {
    final t = TestTranslator();
    final content = [
      for (var i = 0; i < 27; i++)
        TranslationParagraph(
          documentId: 'c1',
          page: i == 26 ? 2 : 1,
          index: i,
          text: 'Ordinary source fragment $i, extracted PDF text.',
          fingerprint: 'c1-heavy-$i',
          rects: [PageRect(70, 650, 500, 630)],
        ),
    ];
    final c = await setup(tester, t, pageContent: content);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    for (var n = 0; n < 14; n++) {
      for (final e in t.pending.entries.toList()) {
        if (!e.value.isCompleted) e.value.complete(ParagraphTranslation('Translated run ${e.key}', tokens: 400));
      }
      await frames(tester, count: 2);
    }
    expect(c.read(readerTranslationProvider('demo-1')).complete, true);
    expect(t.calls.toSet(), {for (var i = 0; i < 26; i++) i});
    expect(await saved(c), hasLength(26));
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('opening before the PDF is ready uses the saved reading page', (tester) async {
    final t = TestTranslator();
    final fixture = compareFixture();
    final c = await setup(
      tester,
      t,
      data: fixture.copyWith(
        documents: [for (final doc in fixture.documents) doc.id == 'c1' ? doc.copyWith(lastPage: 2) : doc],
      ),
    );
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    expect(t.calls, [2]);
    expect(c.read(readerTranslationProvider('demo-1')).page, 2);
    await finish(tester, t);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('English source on-demand reader requests only its current page', (tester) async {
    final t = TestTranslator();
    final c = await setup(tester, t);
    c.read(workspaceProvider('demo-1').notifier).openDocument('c2');
    await frames(tester);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('zh');
    await frames(tester);
    expect((c.read(readerCompareProvider('demo-1'))!.right as AiCompareTarget).targetLang, 'zh');
    expect(t.languages, ['zh', 'zh']);
    await finish(tester, t);
    expect(await saved(c, document: 'c2', language: 'zh'), hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('comparison menu contains no immediate translation entry, even without a model', (tester) async {
    final t = TestTranslator();
    await setup(tester, t, selected: null);
    await tapReaderCommand(tester, find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    expect(find.textContaining('AI Translate into'), findsNothing);
    expect(t.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
}
