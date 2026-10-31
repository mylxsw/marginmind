import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/full_translation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/widgets/translation_paragraph.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_panel.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'full_translation_test.dart' show MockFullTranslationController, testHost;
import 'reader_translation_test.dart' show setup, frames, paragraphs, TestTranslator;

class Journal extends InMemoryTranslationStore {
  final entries = <TranslationSegment>[];
  @override
  Future<void> append(String id, String language, TranslationSegment segment) async {
    entries.add(segment);
    await super.append(id, language, segment);
  }
}

final now = DateTime.utc(2026, 10, 31);
TranslationJob task({Map<String, TranslationFailure> failures = const {}}) => TranslationJob(
  id: 'task',
  documentId: 'c1',
  targetLang: 'en',
  range: TranslationRange(1, 2),
  mode: TranslationMode.all,
  batchSize: 5,
  model: 'fixture',
  state: TranslationJobState.done,
  batch: TranslationBatch(index: 1, range: TranslationRange(1, 2)),
  estimateTokens: 1000,
  createdAt: now,
  updatedAt: now,
  failures: failures,
);
Future<Journal> seed({bool failed = false, TranslationOrigin origin = TranslationOrigin.edited}) async {
  final store = Journal();
  for (final p in paragraphs('c1')) {
    if (failed && p.index == 0) continue;
    await store.append(
      'c1',
      'en',
      TranslationSegment(
        key: textKey(p.text, 'en'),
        fingerprint: p.fingerprint,
        page: p.page,
        index: p.index,
        text: 'Manual translation ${p.index}.',
        model: 'fixture',
        profile: '',
        origin: origin,
        at: now,
      ),
    );
  }
  await store.saveJob(
    task(
      failures: failed ? {'c1-0': TranslationFailure(kind: 'protocol', attempts: 1, at: now)} : {},
    ),
  );
  return store;
}

Future<TestGesture> hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('translation-paragraph-0'))));
  await tester.pump();
  expect(find.byKey(const ValueKey('translation-tools-0')), findsOneWidget);
  return mouse;
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'packages/cupertino_icons/CupertinoIcons',
    )..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'))).load();
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
    final font = Platform.environment['TRANSLATION_EVIDENCE_FONT'];
    if (font != null) {
      final bytes = ByteData.sublistView(File(font).readAsBytesSync());
      for (final family in [
        'Ahem',
        'Roboto',
        '.AppleSystemUIFont',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'Songti SC',
        'Noto Sans CJK SC',
      ]) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });
  testWidgets('retranslate requests one paragraph and HUD undo appends the original edited value', (tester) async {
    final store = await seed(), translator = TestTranslator();
    final c = await setup(tester, translator, storage: store);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    final mouse = await hover(tester);
    await tester.tap(find.byTooltip('Retranslate'));
    await frames(tester, count: 3);
    expect(translator.calls, [0]);
    translator.pending[0]!.complete(const ParagraphTranslation('New translation.'));
    await frames(tester);
    expect(find.text('Retranslated'), findsOneWidget);
    expect(find.text('New translation.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await frames(tester);
    expect(store.entries.last.text, 'Manual translation 0.');
    expect(store.entries.last.origin, TranslationOrigin.edited);
    expect(find.byKey(const ValueKey('translation-edited-0')), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('translation-tools-0')), findsNothing);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('HUD undo remains safe after leaving the paragraph view', (tester) async {
    final store = await seed(), translator = TestTranslator();
    final c = await setup(tester, translator, storage: store);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    final mouse = await hover(tester);
    await tester.tap(find.byTooltip('Retranslate'));
    await frames(tester, count: 3);
    translator.pending[0]!.complete(const ParagraphTranslation('New translation.'));
    await frames(tester);
    c.read(readerCompareProvider('demo-1').notifier).exit();
    await frames(tester);
    await tester.tap(find.text('Undo'));
    await frames(tester);
    expect(store.entries.last.text, 'Manual translation 0.');
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  for (final input in ['Manual translation 0.', ' \nManual translation 0.\t ', '', ' \n\t ']) {
    testWidgets('Enter closes an unchanged or empty edit without saving: ${input.replaceAll('\n', r'\n')}', (
      tester,
    ) async {
      final store = await seed(origin: TranslationOrigin.ai), translator = TestTranslator();
      final initialEntries = List<TranslationSegment>.of(store.entries);
      final c = await setup(tester, translator, storage: store);
      await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
      await frames(tester);
      final mouse = await hover(tester);
      await tester.tap(find.byTooltip('Edit Translation'));
      await tester.pump();
      final editor = find.byKey(const ValueKey('translation-editor-0'));
      await tester.enterText(editor, input);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await frames(tester);
      expect(editor, findsNothing);
      expect(find.text('Manual translation 0.'), findsOneWidget);
      expect(store.entries, initialEntries);
      expect(
        (await store.load('c1', 'en')).segments[textKey(paragraphs('c1').first.text, 'en')]!.origin,
        TranslationOrigin.ai,
      );
      expect(find.byKey(const ValueKey('translation-edited-0')), findsNothing);
      expect(find.text('Changes Saved'), findsNothing);
      expect(translator.calls, isEmpty);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
    });
  }

  testWidgets('editor saves Enter and command Enter, keeps shift Enter, cancels Escape, and copies', (tester) async {
    final store = await seed(), translator = TestTranslator();
    final c = await setup(tester, translator, storage: store);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    final mouse = await hover(tester);
    await tester.tap(find.byTooltip('Edit Translation'));
    await tester.pump();
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final editor = find.byKey(const ValueKey('translation-editor-0'));
    await tester.enterText(editor, ' ');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(editor, findsNothing);
    expect(find.text('Manual translation 0.'), findsOneWidget);
    expect(store.entries.length, 3);
    await mouse.moveTo(Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('translation-paragraph-0'))));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit Translation'));
    await tester.pump();
    await tester.enterText(editor, 'User revision');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(editor, findsOneWidget);
    expect(tester.widget<TextField>(editor).controller!.text, 'User revision\n');
    await tester.enterText(editor, 'User revision\nsecond line');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await frames(tester);
    expect(editor, findsNothing);
    expect(store.entries.last.text, 'User revision\nsecond line');
    expect(find.text('Changes Saved'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('translation-paragraph-0'))));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit Translation'));
    await tester.pump();
    await tester.enterText(editor, 'discard');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editor, findsNothing);
    expect(store.entries.last.text, 'User revision\nsecond line');
    await mouse.moveTo(Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('translation-paragraph-0'))));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit Translation'));
    await tester.pump();
    await tester.enterText(editor, 'Saved with Enter');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await frames(tester);
    expect(editor, findsNothing);
    expect(store.entries.last.text, 'Saved with Enter');

    await mouse.moveTo(Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('translation-paragraph-0'))));
    await tester.pump();
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(copied, 'Saved with Enter');
    expect(find.text('Translation Copied'), findsOneWidget);
    expect(translator.calls, isEmpty);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('switching target language discards the open editor without saving into the new language', (
    tester,
  ) async {
    final store = await seed(), translator = TestTranslator();
    for (final p in paragraphs('c1')) {
      await store.append(
        'c1',
        'zh',
        TranslationSegment(
          key: textKey(p.text, 'zh'),
          fingerprint: p.fingerprint,
          page: p.page,
          index: p.index,
          text: 'Chinese ${p.index}',
          model: 'fixture',
          profile: '',
          origin: TranslationOrigin.ai,
          at: now,
        ),
      );
    }
    final c = await setup(tester, translator, storage: store);
    final compare = c.read(readerCompareProvider('demo-1').notifier);
    await compare.openAi('en');
    await frames(tester);
    final mouse = await hover(tester);
    await tester.tap(find.byTooltip('Edit Translation'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('translation-editor-0')), 'Unsaved English');
    await compare.openAi('zh');
    await frames(tester);
    expect(find.byKey(const ValueKey('translation-editor-0')), findsNothing);
    expect(find.text('Chinese 0'), findsOneWidget);
    expect(translator.calls, isEmpty);
    expect((await store.load('c1', 'en')).segments.values.first.text, 'Manual translation 0.');
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('continue and retry-all keep manual paragraphs intact in the reader', (tester) async {
    final store = Journal(), translator = TestTranslator();
    for (final p in paragraphs('c1').where((p) => p.page == 1)) {
      await store.append(
        'c1',
        'en',
        TranslationSegment(
          key: textKey(p.text, 'en'),
          fingerprint: p.fingerprint,
          page: p.page,
          index: p.index,
          text: 'Edited ${p.index}',
          model: 'fixture',
          profile: '',
          origin: TranslationOrigin.edited,
          at: now,
        ),
      );
    }
    await store.saveJob(
      task().copyWith(
        state: TranslationJobState.review,
        batch: TranslationBatch(index: 1, range: TranslationRange(1, 1)),
      ),
    );
    final c = await setup(tester, translator, storage: store);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    expect(translator.calls, isEmpty);
    final controller = c.read(fullTranslationProvider(('demo-1', 'c1', 'en')).notifier);
    await controller.continueBatch();
    await frames(tester);
    expect(translator.calls, [2]);
    translator.pending[2]!.complete(const ParagraphTranslation('Remaining paragraph'));
    await frames(tester);
    await controller.retry();
    await frames(tester);
    expect(translator.calls, [2]);
    expect(find.text('Edited 0'), findsOneWidget);
    expect(find.text('Edited 1'), findsOneWidget);
    expect(
      (await store.load('c1', 'en')).segments[textKey(paragraphs('c1').first.text, 'en')]!.origin,
      TranslationOrigin.edited,
    );
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('edited translation excerpts contain only translated text and anchor to the original PDF paragraph', (
    tester,
  ) async {
    final store = await seed(), translator = TestTranslator();
    final c = await setup(tester, translator, storage: store);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    final editable = tester.state<EditableTextState>(
      find.descendant(of: find.byKey(const ValueKey('translation-paragraph-0')), matching: find.byType(EditableText)),
    );
    expect(editable.textEditingValue.text, 'Manual translation 0.');
    editable.userUpdateTextEditingValue(
      const TextEditingValue(text: 'Manual translation 0.', selection: TextSelection(baseOffset: 0, extentOffset: 21)),
      SelectionChangedCause.longPress,
    );
    editable.showToolbar();
    await tester.pump();
    await tester.tap(find.text('Excerpt to Map'));
    await frames(tester);
    final workspace = c.read(workspaceProvider('demo-1').notifier);
    final annotation = workspace.content.annotations.last;
    expect(annotation.quote, 'Manual translation 0.');
    expect(annotation.documentId, 'c1');
    expect(annotation.pages.single.rects, paragraphs('c1').first.rects);
    expect(workspace.content.cards.last.annotationId, annotation.id);
    expect(translator.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('failed paragraph retries in place and remove confirmation deletes manual translations', (tester) async {
    final store = await seed(failed: true), translator = TestTranslator();
    final c = await setup(tester, translator, storage: store);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    final failed = find.byKey(const ValueKey('translation-failed-0'));
    expect(failed, findsOneWidget);
    expect(find.textContaining('Untranslated ·'), findsOneWidget);
    await tester.tap(find.descendant(of: failed, matching: find.text('Retry')));
    await frames(tester, count: 3);
    expect(translator.calls, [0]);
    translator.pending[0]!.complete(const ParagraphTranslation('Recovered.'));
    await frames(tester);
    expect(failed, findsNothing);
    expect(find.text('Recovered.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('full-translation-capsule')));
    await frames(tester);
    expect(find.byType(FullTranslationPanel), findsOneWidget);
    await tester.tap(find.text('Remove Translations…'));
    await frames(tester);
    expect(find.text('Remove all AI translations for this document?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await frames(tester);
    expect((await store.load('c1', 'en')).segments, hasLength(3));
    await tester.tap(find.text('Remove Translations…'));
    await frames(tester);
    await tester.tap(find.text('Remove'));
    await frames(tester);
    expect((await store.load('c1', 'en')).segments, isEmpty);
    expect(await store.loadJob('c1', 'en'), isNull);
    expect(find.text('Translations Removed'), findsOneWidget);
    expect(translator.calls, [0]);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('retrying a completed task with one failed paragraph keeps that paragraph visible in flight', (
    tester,
  ) async {
    final store = await seed(failed: true), translator = TestTranslator();
    final first = paragraphs('c1').first;
    final c = await setup(tester, translator, storage: store, pageContent: [first]);
    await c.read(readerCompareProvider('demo-1').notifier).openAi('en');
    await frames(tester);
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('translation-failed-0')), matching: find.text('Retry')),
    );
    await frames(tester, count: 3);
    expect(translator.calls, [0]);
    final state = c.read(fullTranslationProvider(('demo-1', 'c1', 'en')));
    expect(state.pageState(1), TranslationPageState.running);
    expect(find.byKey(const ValueKey('translation-paragraph-0')), findsOneWidget);
    translator.pending[0]!.complete(const ParagraphTranslation('Recovered only paragraph.'));
    await frames(tester);
    expect(find.text('Recovered only paragraph.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  });

  testWidgets('failure source and edited marker retain contrast on white paper in a dark app', (tester) async {
    final first = paragraphs('c1')[0], failed = paragraphs('c1')[1];
    final store = await seed();
    final state = FullTranslationState(
      studySetId: 'demo-1',
      documentId: 'c1',
      targetLang: 'en',
      loading: false,
      paragraphs: [first, failed],
      segments: {
        for (final entry in (await store.load('c1', 'en')).segments.entries)
          if (entry.value.fingerprint == first.fingerprint) entry.key: entry.value,
      },
      job: task(
        failures: {failed.fingerprint: TranslationFailure(kind: 'protocol', attempts: 1, at: now)},
      ),
      segmentStates: {failed.fingerprint: TranslationSegmentState.failed},
    );
    Widget paragraph(TranslationParagraph p, String? value) => TranslationParagraphView(
      studySetId: 'demo-1',
      language: 'en',
      paragraph: p,
      value: value,
      style: MMTypography.readingBody.copyWith(color: MMReaderStyle.white.inkColor),
      placeholder: const SizedBox(),
      contextMenuBuilder: (_, _) => const SizedBox(),
    );
    await tester.pumpWidget(
      testHost(
        Container(
          color: MMReaderStyle.white.paperColor,
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [paragraph(first, 'Edited text'), paragraph(failed, null)],
          ),
        ),
        dark: true,
        overrides: [
          fullTranslationProvider(('demo-1', 'c1', 'en'))
              .overrideWith(() => MockFullTranslationController('demo-1', 'c1', 'en', state)),
        ],
      ),
    );
    double contrast(Color foreground) {
      final ink = Color.alphaBlend(foreground, MMReaderStyle.white.paperColor).computeLuminance();
      return (MMReaderStyle.white.paperColor.computeLuminance() + .05) / (ink + .05);
    }

    expect(contrast(tester.widget<Text>(find.text(failed.text)).style!.color!), greaterThanOrEqualTo(4.5));
    expect(
      contrast(tester.widget<Icon>(find.byKey(const ValueKey('translation-edited-0'))).color!),
      greaterThanOrEqualTo(3),
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    testWidgets('paragraph failure and hover toolbar golden ${dark ? 'dark' : 'light'}', (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final first = paragraphs('c1').first;
      final failed = paragraphs('c1')[1];
      final state = FullTranslationState(
        studySetId: 'demo-1',
        documentId: 'c1',
        targetLang: 'en',
        loading: false,
        job: task(
          failures: {failed.fingerprint: TranslationFailure(kind: 'protocol', attempts: 1, at: now)},
        ),
        paragraphs: [first, failed],
        segments: {
          textKey(first.text, 'en'): TranslationSegment(
            key: textKey(first.text, 'en'),
            fingerprint: first.fingerprint,
            page: 1,
            index: 0,
            text: 'A translated paragraph ready for review.',
            model: 'fixture',
            profile: '',
            origin: TranslationOrigin.ai,
            at: now,
          ),
        },
        segmentStates: {failed.fingerprint: TranslationSegmentState.failed},
      );
      Widget paragraph(TranslationParagraph p, String? value) => TranslationParagraphView(
        key: ValueKey('translation-paragraph-${p.index}'),
        studySetId: 'demo-1',
        language: 'en',
        paragraph: p,
        value: value,
        style: MMTypography.readingBody,
        placeholder: const SizedBox(),
        contextMenuBuilder: (_, _) => const SizedBox(),
      );
      final capture = GlobalKey();
      final evidence = Platform.environment['TRANSLATION_EVIDENCE_DIR'];
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: ProviderScope(
            overrides: [
              fullTranslationProvider(('demo-1', 'c1', 'en'))
                  .overrideWith(() => MockFullTranslationController('demo-1', 'c1', 'en', state)),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? MMTheme.dark() : MMTheme.light(),
              locale: Locale(evidence == null ? 'en' : 'zh'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        paragraph(
                          first,
                          evidence == null ? 'A translated paragraph ready for review.' : '注意力机制让模型在处理序列时，专注于最相关的信息。',
                        ),
                        const SizedBox(height: 36),
                        paragraph(failed, null),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await hover(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final directory = Platform.isLinux ? 'goldens/linux/translation_paragraph' : 'goldens/translation_paragraph';
      if (evidence == null) {
        await expectLater(find.byKey(capture), matchesGoldenFile('$directory/${dark ? 'dark' : 'light'}.png'));
      } else {
        final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 2);
          try {
            final data = (await picture.toByteData(format: ui.ImageByteFormat.png))!;
            Directory(evidence).createSync(recursive: true);
            File('$evidence/paragraph-${dark ? 'dark' : 'light'}.png').writeAsBytesSync(data.buffer.asUint8List());
          } finally {
            picture.dispose();
          }
        });
      }
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      // Exact goldens pin the Linux renderer; interaction tests run on every host.
    }, skip: !Platform.isLinux && Platform.environment['TRANSLATION_EVIDENCE_DIR'] == null);
  }
}
