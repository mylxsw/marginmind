import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
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
  bool closed = false;
  @override
  Future<ParagraphTranslation> translate(
    TranslationParagraph p,
    String language,
    CancellationToken cancel,
    int maxTokens,
  ) async {
    calls.add(p.index);
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
}) async {
  final c = await pumpApp(
    tester,
    renderPdf: render,
    size: const Size(1600, 1000),
    prefs: prefs,
    content: InMemoryStudySetContentRepository({'demo-1': data ?? compareFixture()}),
    overrides: [
      assistantDefaultModelProvider.overrideWithValue(selected),
      assistantCredentialStateProvider.overrideWith(
        (ref) async => selected == null ? AssistantCredentialState.unconfigured : AssistantCredentialState.ready,
      ),
      paragraphTranslatorProvider.overrideWithValue((_) async => translator),
      for (final id in ['c1', 'c2', 'third']) ...[
        translationParagraphsProvider(('demo-1', id)).overrideWith((ref) async => paragraphs(id)),
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

void main() {
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
    final info = c.read(compareDocumentInfoProvider(('demo-1', 'c1'))).value;
    expect(info!.hasText, true);
    expect(info.language, 'en');
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
  testWidgets('AI menu enters, progress, complete, cache, hover on either side and exit', (tester) async {
    final t = TestTranslator();
    final c = await setup(tester, t, render: true);
    await tester.tap(find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    expect(find.text('AI Translate into English'), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
    await tester.tap(find.text('AI Translate into English'));
    await frames(tester);
    expect(find.byType(ReaderTranslationView), findsOneWidget);
    expect(find.text('Translating 0/3'), findsOneWidget);
    expect(find.byKey(const ValueKey('compare-align')), findsNothing);
    expect(find.byKey(const ValueKey('compare-swap')), findsNothing);
    t.pending[0]!.complete(const ParagraphTranslation('Translated paragraph 0.', tokens: 5));
    await frames(tester);
    expect(find.text('Translating 1/3'), findsOneWidget);
    await finish(tester, t);
    expect(find.text('Saved'), findsOneWidget);
    final workspace = c.read(workspaceProvider('demo-1').notifier);
    expect(workspace.content.translationCaches.single.paragraphs.length, 3);
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
    expect(t.closed, true);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    expect(find.text('Saved'), findsOneWidget);
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
    t.pending[0]!.completeError(StateError('offline'));
    await frames(tester);
    await finish(tester, t);
    expect(find.text('Translation failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await frames(tester);
    expect(find.text('Translating 2/3'), findsOneWidget);
    t.pending[0]!.complete(const ParagraphTranslation('Retry translated.', tokens: 5));
    await frames(tester);
    expect(find.text('Saved'), findsOneWidget);
    await compare.select('c2', left: true);
    await frames(tester);
    expect(t.closed, true);
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
    await tester.tap(find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Translate into English'));
    await frames(tester);
    expect(find.text('Saved'), findsOneWidget);
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
  testWidgets('missing model, offline cloud model, scan each disable with reason', (tester) async {
    final t = TestTranslator();
    await setup(tester, t, selected: null);
    await tester.tap(find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    expect(find.text('Configure a model first'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    await setup(
      tester,
      t,
      selected: const AssistantModel(
        provider: AssistantProvider.claude,
        model: 'cloud',
        endpoint: 'https://example.com',
      ),
      prefs: {'assistant.online': false},
    );
    await tester.tap(find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    await setup(tester, t, hasText: false);
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('reader-compare')));
    await tester.pumpAndSettle();
    expect(find.text('Recognize text first'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });
}
