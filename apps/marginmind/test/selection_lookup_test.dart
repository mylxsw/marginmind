import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/vocabulary/selection_vocabulary.dart';
import 'package:marginmind/features/vocabulary/vocabulary_screen.dart';
import 'package:marginmind/features/vocabulary/vocabulary_controller.dart';
import 'package:marginmind/features/vocabulary/vocabulary_source_flash.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/word_lookup.dart';
import 'package:marginmind/features/workspace/widgets/selection_lookup.dart';
import 'package:marginmind/features/workspace/widgets/selection_translation.dart';
import 'package:marginmind/features/workspace/widgets/vocabulary_add_button.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'assistant_quick_actions_test.dart' show screenshot;
import 'helpers.dart';
import 'vocabulary_test.dart' show FailingRepository;

import 'package:marginmind/features/assistant/widgets/assistant_quick_actions.dart';

import 'reader_translation_test.dart' show model;
import 'selection_translation_test.dart' show SelectionTestTranslator;

final lookupResult = WordLookupResult(
  lemma: 'meticulous',
  ukPhonetic: '/məˈtɪkjʊləs/',
  usPhonetic: '/məˈtɪkjələs/',
  senses: [const WordSense(pos: 'adj.', meaning: '细致的')],
  context: const WordContext(contextMeaning: '一丝不苟地', sentenceTranslation: '她一丝不苟地工作。'),
  gloss: '细致',
  forms: ['meticulous', 'meticulously'],
);

class LookupFixture extends WordLookup {
  LookupFixture() : super(connect: (_) => throw UnimplementedError());
  final pending = Completer<WordLookupResult>();
  int calls = 0, contextCalls = 0;
  String? sentence;
  @override
  Future<WordLookupResult> lookup({
    required String term,
    required String sentence,
    String? sourceLanguage,
    required String targetLanguage,
    required AssistantModel? model,
    required CancellationToken cancel,
    bool online = true,
    bool refresh = false,
  }) {
    calls++;
    this.sentence = sentence;
    return pending.future;
  }

  @override
  Future<WordContext> lookupContext({
    required String lemma,
    required String sentence,
    String? sourceLanguage,
    required String targetLanguage,
    required AssistantModel? model,
    required CancellationToken cancel,
    bool online = true,
  }) async {
    contextCalls++;
    this.sentence = sentence;
    return lookupResult.context;
  }
}

Future<ProviderContainer> openLookup(
  WidgetTester tester,
  LookupFixture fixture, {
  String selected = 'meticulously',
  String appearance = 'light',
  bool setup = false,
  bool offline = false,
  InMemoryVocabularyRepository? repository,
  SelectionTestTranslator? translator,
}) async {
  final container = await pumpApp(
    tester,
    prefs: {'settings.language': 'zh', 'settings.appearance': appearance, 'assistant.online': !offline},
    vocabulary: repository,
    overrides: [
      assistantDefaultModelProvider.overrideWithValue(
        setup
            ? null
            : offline
            ? const AssistantModel(
                provider: AssistantProvider.compatible,
                model: 'fixture',
                endpoint: 'https://example.invalid/v1',
              )
            : model,
      ),
      wordLookupProvider.overrideWithValue(fixture),
      if (translator != null) paragraphTranslatorProvider.overrideWithValue((_) async => translator),
      translationParagraphsProvider(('demo-1', 'c1')).overrideWith(
        (ref) async => [
          TranslationParagraph(
            documentId: 'c1',
            page: 1,
            index: 0,
            text: 'Earlier sentence. She works meticulously. Next sentence.',
            fingerprint: '',
          ),
        ],
      ),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  await container
      .read(workspaceProvider('demo-1').notifier)
      .onSelectionCommitted(
        'c1',
        MMPdfSelection(
          page: 1,
          rects: const [PageRect(10, 100, 200, 88)],
          text: selected,
          viewportRect: const Rect.fromLTWH(120, 200, 180, 20),
        ),
      );
  await tester.pumpAndSettle();
  expect(
    find.byTooltip(classifyVocabularySelection(selected) == VocabularySelectionKind.word ? '查词（T）' : '翻译（T）'),
    findsOneWidget,
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
  await tester.pumpAndSettle();
  return container;
}

void speechTest(String description, WidgetTesterCallback callback) {
  testWidgets(description, callback, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

void main() {
  testWidgets('unsupported hosts hide lookup pronunciation', (tester) async {
    await openLookup(tester, LookupFixture()..pending.complete(lookupResult));
    expect(find.byTooltip('朗读'), findsNothing);
    expect(find.textContaining('məˈtɪkj'), findsWidgets);
  });

  setUpAll(() async {
    final output = Platform.environment['MM_SCREENSHOTS'];
    if (output == null) return;
    Directory(output).createSync(recursive: true);
    final data = ByteData.sublistView(
      File(Platform.environment['MM_FONT'] ?? '/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync(),
    );
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Ahem',
      'PingFang SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    await (FontLoader('Songti SC')..addFont(
          Future.value(ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Songti.ttc').readAsBytesSync())),
        ))
        .load();
    final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final iconDir = Directory('$pub/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('cupertino_icons-'));
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          Future.value(ByteData.sublistView(File('${iconDir.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
        ))
        .load();
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
  });

  for (final appearance in ['light', 'dark']) {
    testWidgets('lookup skeleton, sentence, add, undo and screenshot in $appearance', (tester) async {
      final fixture = LookupFixture();
      final container = await openLookup(tester, fixture, appearance: appearance);
      expect(find.byKey(const ValueKey('lookup-skeleton-1.0')), findsOneWidget);
      expect(fixture.sentence, 'She works meticulously.');
      fixture.pending.complete(lookupResult);
      await tester.pumpAndSettle();
      expect(find.text('meticulous'), findsOneWidget);
      expect(find.text('一丝不苟地'), findsOneWidget);
      final star = find.descendant(of: find.byType(VocabularyAddButton), matching: find.byIcon(MMIcons.star));
      expect(star, findsOneWidget);
      expect(find.text('加入生词本'), findsNothing);
      final card = tester.getRect(find.byKey(const ValueKey('selection-lookup-result')));
      final close = find.byWidgetPredicate((w) => w is MMIconButton && w.icon == MMIcons.close);
      final closeRect = tester.getRect(close);
      expect(closeRect.top - card.top, MMSpacing.s);
      expect(card.right - closeRect.right, MMSpacing.s);
      expect(tester.getRect(star).right, lessThan(closeRect.left));
      await screenshot(tester, 'selection-lookup-$appearance', target: find.byType(SelectionLookup));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      final entries = container.read(vocabularyProvider).requireValue.entries;
      expect(entries.single.term, 'meticulous');
      expect(container.read(vocabularyAddedFlashProvider), entries.single.id);
      expect(entries.single.contexts.single.sentence, 'She works meticulously.');
      expect(entries.single.contexts.single.studySetTitle, '认知科学入门');
      expect(find.byTooltip('学习中'), findsOneWidget);
      final savedStar = find.descendant(of: find.byType(VocabularyAddButton), matching: find.byIcon(MMIcons.starFill));
      expect(tester.widget<Icon>(savedStar).color, MMInkColor.yellow.color);
      await screenshot(tester, 'selection-lookup-saved-$appearance', target: find.byType(SelectionLookup));
      expect(find.byTooltip('收录为例句'), findsNothing);
      expect(find.byKey(const ValueKey('selection-vocabulary-dot')), findsOneWidget);
      await tester.tap(find.text('撤销').last);
      await tester.pumpAndSettle();
      expect(container.read(vocabularyProvider).requireValue.entries, isEmpty);
      expect(star, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleHud(tester);
    });
  }

  for (final offline in [false, true]) {
    testWidgets('problem allows bare add: offline=$offline', (tester) async {
      final fixture = LookupFixture();
      final container = await openLookup(tester, fixture, setup: !offline, offline: offline);
      expect(find.text(offline ? '联网已关闭' : '未设置模型'), findsOneWidget);
      expect(find.text('打开设置'), findsOneWidget);
      await tester.tap(find.byTooltip('加入生词本（S）'));
      await tester.pumpAndSettle();
      expect(container.read(vocabularyProvider).requireValue.entries.single.senses, isEmpty);
      expect(fixture.calls, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleHud(tester);
    });
  }

  speechTest('saved menu, new example, speech, status, removal and undo', (tester) async {
    final source = VocabularyContext(
      id: 'before',
      studySetId: 'other',
      documentId: 'd',
      studySetTitle: '',
      documentTitle: '',
      sentence: 'Another sentence.',
      hit: 'meticulous',
      addedAt: testNow,
      page: 1,
    );
    final initial = saveSelectionVocabulary(
      [],
      selected: 'meticulously',
      language: 'en',
      context: source,
      lookup: lookupResult,
    );
    final repository = InMemoryVocabularyRepository(initial);
    final fixture = LookupFixture();
    final container = await openLookup(tester, fixture, repository: repository);
    expect(fixture.calls, 0);
    expect(fixture.contextCalls, 1);
    final speech = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('marginmind/speech'), (
      call,
    ) async {
      speech.add(call);
      return null;
    });
    await tester.tap(find.byTooltip('朗读').first);
    await tester.pumpAndSettle();
    expect(speech.single.arguments, {'text': 'meticulous', 'language': 'en-GB'});
    await tester.tap(find.byTooltip('收录为例句'));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyProvider).requireValue.entries.single.contexts.length, 2);
    await tester.tap(find.byTooltip('学习中'));
    await tester.pumpAndSettle();
    expect(find.text('在生词本中查看'), findsOneWidget);
    await tester.tap(find.text('标为已掌握'));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyProvider).requireValue.entries.single.status, VocabularyStatus.known);
    await tester.tap(find.byTooltip('已掌握'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出生词本'));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyProvider).requireValue.entries, isEmpty);
    await tester.tap(find.text('撤销').last);
    await tester.pumpAndSettle();
    expect(container.read(vocabularyProvider).requireValue.entries.single.status, VocabularyStatus.known);
    await tester.tap(find.text('详情 ›'));
    await tester.pumpAndSettle();
    final route = container.read(navigationProvider) as VocabularyRoute;
    expect(route.entryId, container.read(vocabularyProvider).requireValue.entries.single.id);
    expect(find.byType(VocabularyScreen), findsOneWidget);
    expect(find.byType(VocabularyDetail), findsOneWidget);
    expect(find.text('meticulous'), findsWidgets);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('marginmind/speech'), null);
    await settleHud(tester);
  });

  testWidgets('failure and late result after dismissal', (tester) async {
    final fixture = LookupFixture();
    await openLookup(tester, fixture);
    fixture.pending.completeError(const ResearchFailure(ResearchFailureKind.authentication));
    await tester.pumpAndSettle();
    expect(find.text('未设置模型'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final late = LookupFixture();
    await openLookup(tester, late);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    late.pending.complete(lookupResult);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLookup), findsNothing);
  });

  testWidgets('long sentence disables add; phrase translates and adds', (tester) async {
    final translator = SelectionTestTranslator()..pending.complete(const ParagraphTranslation('翻译'));
    // Override the factory after mounting, before opening the translation.
    final fixture = LookupFixture();
    final container = await pumpApp(
      tester,
      prefs: {'settings.language': 'zh'},
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async => translator),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Navigator).first);
    unawaited(
      showSelectionLookup(
        context,
        studySetId: 'demo-1',
        paragraph: TranslationParagraph(
          documentId: 'c1',
          page: 1,
          index: 0,
          text: 'one two three four five six seven eight nine',
          fingerprint: '',
        ),
        toolbar: const Rect.fromLTWH(100, 100, 200, 30),
        selection: Rect.zero,
        viewport: const Rect.fromLTWH(0, 0, 1280, 820),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SelectionTranslation), findsOneWidget);
    expect(find.byTooltip('生词本收录单词和 8 个词以内的短语'), findsOneWidget);
    final button = tester.widget<MMButton>(
      find.descendant(of: find.byType(VocabularyAddButton), matching: find.byType(MMButton)),
    );
    expect(button.onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(container.read(vocabularyProvider).requireValue.entries, isEmpty);
    expect(fixture.calls, 0);
  });

  testWidgets('phrase adds translated sense; full sentence and assistant actions remain reachable', (tester) async {
    final translator = SelectionTestTranslator()..pending.complete(const ParagraphTranslation('认真工作'));
    final container = await pumpApp(
      tester,
      prefs: {'settings.language': 'zh'},
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async => translator),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container
        .read(workspaceProvider('demo-1').notifier)
        .onSelectionCommitted(
          'c1',
          const MMPdfSelection(
            page: 1,
            rects: [PageRect(10, 100, 200, 88)],
            text: 'work carefully',
            viewportRect: Rect.fromLTWH(120, 200, 180, 20),
          ),
        );
    await tester.pumpAndSettle();
    expect(find.byTooltip('翻译（T）'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    final e = container.read(vocabularyProvider).requireValue.entries.single;
    expect(e.kind, VocabularyKind.phrase);
    expect(e.senses.single.meaning, '认真工作');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleHud(tester);
  });

  testWidgets('lookup opens sentence translation with the complete source sentence', (tester) async {
    final fixture = LookupFixture()..pending.complete(lookupResult);
    final translator = SelectionTestTranslator()..pending.complete(const ParagraphTranslation('整句翻译'));
    await openLookup(tester, fixture, translator: translator);
    await tester.tap(find.text('翻译整句'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionTranslation), findsOneWidget);
    expect(translator.source, 'She works meticulously.');
  });

  testWidgets('saved sentence works without a model and does not issue another request', (tester) async {
    final source = VocabularyContext(
      id: 'cached',
      studySetId: 'demo-1',
      documentId: 'c1',
      studySetTitle: 'set',
      documentTitle: 'doc',
      sentence: 'She works meticulously.',
      hit: 'meticulously',
      addedAt: testNow,
      page: 1,
      sentenceTranslation: lookupResult.context.sentenceTranslation,
    );
    final entries = saveSelectionVocabulary(
      [],
      selected: 'meticulously',
      language: 'en',
      context: source,
      lookup: lookupResult,
    );
    final fixture = LookupFixture();
    await openLookup(tester, fixture, setup: true, repository: InMemoryVocabularyRepository(entries));
    expect(fixture.calls, 0);
    expect(fixture.contextCalls, 0);
    expect(find.text(lookupResult.context.sentenceTranslation), findsOneWidget);
    expect(find.text('未设置模型'), findsNothing);
    await tester.tap(find.byTooltip('学习中'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('在生词本中查看'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLookup), findsNothing);
  });

  testWidgets('failed persistence keeps the entry absent and a retry succeeds', (tester) async {
    final fixture = LookupFixture()..pending.complete(lookupResult);
    final repository = FailingRepository();
    final container = await openLookup(tester, fixture, repository: repository);
    repository.fail = true;
    await tester.tap(find.byTooltip('加入生词本（S）'));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyProvider).requireValue.entries, isEmpty);
    expect(find.text('出了点问题，请重试'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.byTooltip('加入生词本（S）'));
    await tester.pumpAndSettle();
    expect(container.read(vocabularyProvider).requireValue.entries.length, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleHud(tester);
  });

  speechTest('settings retry, speech failure and assistant handoff keep the card usable', (tester) async {
    final fixture = LookupFixture();
    await openLookup(tester, fixture);
    fixture.pending.completeError(const ResearchFailure(ResearchFailureKind.timeout));
    await tester.pumpAndSettle();
    expect(find.text('打开设置'), findsOneWidget);
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    expect(fixture.calls, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final next = LookupFixture()..pending.complete(lookupResult);
    await openLookup(tester, next);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('marginmind/speech'), (
      call,
    ) async {
      if (call.method == 'speak') throw PlatformException(code: 'failed');
      return null;
    });
    await tester.tap(find.byTooltip('朗读').last);
    await tester.pumpAndSettle();
    expect(find.text('出了点问题，请重试'), findsOneWidget);
    await tester.tap(find.text('问助手'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLookup), findsNothing);
    expect(find.byType(AssistantQuickActions), findsOneWidget);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('marginmind/speech'), null);
    await settleHud(tester);
  });

  testWidgets('native Add to vocabulary menu dispatches to the focused lookup card', (tester) async {
    final fixture = LookupFixture()..pending.complete(lookupResult);
    final container = await openLookup(tester, fixture);
    Iterable<PlatformMenuItem> flatten(Iterable<PlatformMenuItem> items) sync* {
      for (final item in items) {
        yield item;
        if (item is PlatformMenu) yield* flatten(item.menus);
        if (item is PlatformMenuItemGroup) yield* flatten(item.members);
      }
    }

    final command = flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus)
        .singleWhere((item) => item.label == '加入生词本');
    expect((command.shortcut as SingleActivator).trigger, LogicalKeyboardKey.keyS);
    expect(command.onSelected, isNotNull);
    command.onSelected!();
    await tester.pumpAndSettle();
    expect(container.read(vocabularyProvider).requireValue.entries.single.term, 'meticulous');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('T obeys disabled document text capabilities even with a stale selection', (tester) async {
    final original = demoContent();
    final documents = [
      for (final d in original.documents)
        Document(
          id: d.id,
          title: d.title,
          fileName: d.fileName,
          pageCount: d.pageCount,
          importedAt: d.importedAt,
          features: const DocumentContentFeatures(text: false),
        ),
    ];
    final container = await pumpApp(
      tester,
      content: InMemoryStudySetContentRepository({'demo-1': original.copyWith(documents: documents)}),
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container
        .read(workspaceProvider('demo-1').notifier)
        .onSelectionCommitted(
          'c1',
          const MMPdfSelection(
            page: 1,
            rects: [PageRect(10, 100, 200, 88)],
            text: 'meticulously',
            viewportRect: Rect.fromLTWH(120, 200, 180, 20),
          ),
        );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionLookup), findsNothing);
    expect(find.byType(SelectionTranslation), findsNothing);
  });

  test('empty offline fields are enriched; populated user data survives duplicate add', () {
    final source = VocabularyContext(
      id: 'c',
      studySetId: 's',
      documentId: 'd',
      studySetTitle: 's',
      documentTitle: 'd',
      sentence: 'She works meticulously.',
      hit: 'meticulously',
      addedAt: testNow,
      page: 1,
    );
    final bare = VocabularyEntry(
      id: 'e',
      forms: ['meticulous'],
      term: 'meticulous',
      language: 'en',
      kind: VocabularyKind.word,
      createdAt: testNow,
      updatedAt: testNow,
    );
    final enriched = saveSelectionVocabulary(
      [bare],
      selected: 'meticulously',
      language: 'en',
      context: source,
      lookup: lookupResult,
    ).single;
    expect(enriched.senses.single.meaning, '细致的');
    expect(enriched.ukPhonetic, lookupResult.ukPhonetic);
    expect(enriched.gloss, '细致');
    expect(enriched.forms, contains('meticulously'));
    final edited = enriched.copyWith(gloss: '自定义', note: 'note', ukPhonetic: '/user/', forms: ['meticulous']);
    final again = saveSelectionVocabulary(
      [edited],
      selected: 'meticulously',
      language: 'en',
      context: source,
      lookup: lookupResult,
    ).single;
    expect(again.gloss, '自定义');
    expect(again.note, 'note');
    expect(again.forms, ['meticulous'], reason: 'Do not restore forms the user removed from a populated entry');
    expect(again.ukPhonetic, '/user/');
    expect(again.contexts.length, 1);
  });
}
