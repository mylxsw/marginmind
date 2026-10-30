import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/vocabulary/vocabulary_screen.dart';
import 'package:marginmind/features/vocabulary/vocabulary_source_flash.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/word_lookup.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import 'vocabulary_test.dart' show FailingRepository, UnreadableRepository;
import 'assistant_quick_actions_test.dart' show screenshot;
import 'reader_translation_test.dart' show model;

VocabularyContext source(String id, {String set = 'demo-1', String doc = 'c1', bool text = false}) => VocabularyContext(
  id: id,
  studySetId: set,
  documentId: doc,
  studySetTitle: 'Learning',
  documentTitle: 'A book',
  sentence: 'Cats sleep.',
  hit: 'Cats',
  addedAt: testNow,
  sentenceTranslation: '猫睡觉。',
  page: text ? null : 3,
  rects: text ? [] : [const PageRect(10, 100, 200, 88)],
  textAnchor: text ? const TextAnchor('chapter', 0, 11, 'Cats sleep.', revision: 'r1') : null,
);
VocabularyEntry word(
  String id, {
  bool old = false,
  String phonetic = '/kæt/',
  VocabularyStatus status = VocabularyStatus.learning,
  List<VocabularyContext>? contexts,
}) => VocabularyEntry(
  id: id,
  term: id,
  language: 'en',
  kind: VocabularyKind.word,
  createdAt: old ? testNow.subtract(const Duration(days: 2)) : testNow,
  updatedAt: testNow,
  forms: [id, '${id}s'],
  gloss: '猫',
  ukPhonetic: phonetic,
  usPhonetic: phonetic,
  status: status,
  senses: [const VocabularySense(partOfSpeech: 'n.', meaning: 'a small animal')],
  contexts: contexts ?? [source('same')],
);

class Speech extends SystemSpeech {
  final calls = <String>[];
  @override
  Future<void> speak(String text, String locale) async {
    calls.add('$text:$locale');
  }

  @override
  Future<void> stop() async {}
}

class Lookup extends WordLookup {
  Lookup() : super(connect: (_) => throw UnimplementedError());
  bool refreshed = false, fail = false;
  Completer<WordLookupResult>? pending;
  CancellationToken? token;
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
  }) async {
    refreshed = refresh;
    token = cancel;
    if (fail) throw StateError('failed');
    if (pending != null) return pending!.future;
    return WordLookupResult(
      lemma: term,
      ukPhonetic: '',
      usPhonetic: '',
      senses: [const WordSense(pos: 'n.', meaning: 'regenerated')],
      context: const WordContext(contextMeaning: '猫', sentenceTranslation: '猫睡觉。'),
      gloss: '猫',
      forms: [term],
    );
  }
}

Future<(ProviderContainer, InMemoryVocabularyRepository)> open(
  WidgetTester tester, {
  List<VocabularyEntry>? entries,
  InMemoryVocabularyRepository? repository,
  bool scoped = false,
  bool compact = false,
  String? entryId,
  bool dark = false,
  bool chinese = false,
  Lookup? lookup,
  Speech? speech,
  InMemoryStudySetContentRepository? content,
}) async {
  final repo =
      repository ??
      InMemoryVocabularyRepository(
        entries ??
            [
              word('cat'),
              word(
                'dog',
                old: true,
                status: VocabularyStatus.known,
                contexts: [source('other', set: 'demo-2')],
              ),
            ],
      );
  addTearDown(repo.dispose);
  final c = await pumpApp(
    tester,
    size: compact ? const Size(430, 900) : const Size(1280, 900),
    content: content,
    vocabulary: repo,
    prefs: {'settings.appearance': dark ? 'dark' : 'light', 'settings.language': chinese ? 'zh' : 'en'},
    overrides: [
      if (compact) touchPlatformProvider.overrideWithValue(true),
      assistantDefaultModelProvider.overrideWithValue(lookup == null ? null : model),
      if (lookup != null) wordLookupProvider.overrideWithValue(lookup),
      systemSpeechProvider.overrideWithValue(speech ?? Speech()),
      translationParagraphsProvider(('demo-1', 'c1')).overrideWith(
        (ref) async => [
          TranslationParagraph(documentId: 'c1', page: 1, index: 0, text: 'Cats and cats.', fingerprint: 'f'),
        ],
      ),
    ],
  );
  c.read(navigationProvider.notifier).showVocabulary(studySetId: scoped ? 'demo-1' : null, entryId: entryId);
  await tester.pumpAndSettle();
  return (c, repo);
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> button(WidgetTester tester, String text) => tap(tester, find.widgetWithText(MMButton, text));
void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final bytes = ByteData.sublistView(
      File(Platform.environment['MM_FONT'] ?? '/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync(),
    );
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
      'Songti SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    final cache = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final icons = Directory('$cache/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('cupertino_icons-'));
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
        ))
        .load();
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
  });
  testWidgets('filters, search, grouping, scope and real document counts', (tester) async {
    final (c, _) = await open(
      tester,
      scoped: true,
      entries: [
        word('cat'),
        word('bird', old: true, contexts: [source('other', set: 'demo-2')]),
        word('dog', old: true, status: VocabularyStatus.known),
      ],
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.byKey(const ValueKey('vocabulary-row-bird')), findsNothing);
    expect(find.byTooltip('Occurrences in this document'), findsOneWidget);
    await tap(tester, find.text('All').first);
    expect(find.text('Earlier'), findsOneWidget);
    final search = find.descendant(of: find.byType(MMSearchField), matching: find.byType(TextField));
    await tester.enterText(search, 'birds');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vocabulary-row-bird')), findsOneWidget);
    await tester.enterText(search, 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching words'), findsOneWidget);
    await tester.enterText(search, 'animal');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vocabulary-row-cat')), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    await tap(tester, find.text('Known'));
    expect(find.byKey(const ValueKey('vocabulary-row-dog')), findsOneWidget);
    await tap(tester, find.text('All').last);
    expect(find.byKey(const ValueKey('vocabulary-row-cat')), findsOneWidget);
    c.read(navigationProvider.notifier).back();
    await tester.pumpAndSettle();
    expect(c.read(navigationProvider), isA<LibraryRoute>());
  });
  testWidgets('persistent edits, Unicode limit, forms, speech and destructive undo', (tester) async {
    final speech = Speech();
    final (_, repo) = await open(tester, speech: speech, entries: [word('cat')]);
    await tester.enterText(find.byKey(const ValueKey('vocabulary-gloss')), '😀😀😀😀😀😀😀😀😀');
    await tester.enterText(find.byKey(const ValueKey('vocabulary-note')), 'My note');
    await tester.pumpAndSettle();
    expect((await repo.load()).single.gloss.runes.length, 8);
    expect((await repo.load()).single.note, 'My note');
    await tester.enterText(find.byKey(const ValueKey('vocabulary-add-form')), 'Feline');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect((await repo.load()).single.forms, contains('feline'));
    await tap(tester, find.byKey(const ValueKey('remove-form-feline')));
    expect((await repo.load()).single.forms, isNot(contains('feline')));
    expect(find.byKey(const ValueKey('remove-form-cat')), findsNothing);
    await tap(tester, find.byTooltip('Read aloud').first);
    expect(speech.calls, ['cat:en-GB']);
    await tap(tester, find.byKey(const ValueKey('delete-example-same')));
    expect((await repo.load()).single.contexts, isEmpty);
    await tap(tester, find.text('Undo'));
    expect((await repo.load()).single.contexts, hasLength(1));
    await button(tester, 'Mark as known');
    expect((await repo.load()).single.status, VocabularyStatus.known);
    await tap(tester, find.text('Undo'));
    expect((await repo.load()).single.status, VocabularyStatus.learning);
    await button(tester, 'Delete from vocabulary');
    expect(await repo.load(), isEmpty);
    await tap(tester, find.text('Undo'));
    expect(await repo.load(), hasLength(1));
    await settleHud(tester);
  });
  testWidgets('compact direct known entry pushes and returns to origin', (tester) async {
    final (c, _) = await open(tester, compact: true, entryId: 'dog');
    expect(find.byType(VocabularyDetail), findsOneWidget);
    await tap(tester, find.byTooltip('Back'));
    expect(find.byType(VocabularyDetail), findsNothing);
    await tap(tester, find.byKey(const ValueKey('vocabulary-row-cat')));
    expect(find.byType(VocabularyDetail), findsOneWidget);
    await tap(tester, find.byTooltip('Back'));
    await tap(tester, find.byTooltip('Back'));
    expect(c.read(navigationProvider), isA<LibraryRoute>());
  });
  for (final text in [false, true]) {
    testWidgets('same/cross set navigation, deleted sources, text=$text', (tester) async {
      final content = InMemoryStudySetContentRepository({'demo-1': demoContent(), 'demo-2': demoContent()});
      final (c, _) = await open(
        tester,
        scoped: true,
        content: content,
        entries: [
          word(
            'cat',
            contexts: [
              source('same', text: text),
              source('other', set: 'demo-2', text: text),
              source('deleted', doc: 'deleted'),
            ],
          ),
        ],
      );
      expect(find.widgetWithText(MMButton, 'Back to source'), findsOneWidget);
      expect(find.widgetWithText(MMButton, 'Open study set ›'), findsOneWidget);
      c.read(workspaceBrowserProvider('demo-1').notifier).show();
      await button(tester, 'Back to source');
      expect(c.read(workspaceBrowserProvider('demo-1')).visible, isFalse);
      final r = c.read(workspaceProvider('demo-1')).reveal!;
      expect(r.documentId, 'c1');
      expect(text ? r.textAnchors.single.quote : r.page, text ? 'Cats sleep.' : 3);
      expect(c.read(vocabularySourceFlashProvider)?.id, 'same');
      c.read(navigationProvider.notifier).showVocabulary(studySetId: 'demo-1');
      await tester.pumpAndSettle();
      await button(tester, 'Open study set ›');
      expect((c.read(navigationProvider) as WorkspaceRoute).studySetId, 'demo-2');
      expect(c.read(workspaceProvider('demo-2')).reveal!.documentId, 'c1');
      await settleHud(tester);
      expect(c.read(vocabularySourceFlashProvider), isNull);
    });
  }
  testWidgets('regenerate refreshes, handles errors and cancels on leaving', (tester) async {
    final lookup = Lookup();
    final (c, repo) = await open(tester, lookup: lookup);
    await tap(tester, find.byTooltip('Regenerate'));
    expect(lookup.refreshed, isTrue);
    expect((await repo.load()).first.senses.single.meaning, 'regenerated');
    lookup.fail = true;
    await tap(tester, find.byTooltip('Regenerate'));
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    lookup.fail = false;
    lookup.pending = Completer();
    await tester.tap(find.byTooltip('Regenerate'));
    await tester.pump();
    c.read(navigationProvider.notifier).back();
    await tester.pumpAndSettle();
    expect(lookup.token!.isCancelled, isTrue);
    lookup.pending!.completeError(StateError('cancelled'));
    await tester.pumpAndSettle();
    await settleHud(tester);
  });
  testWidgets('library and workspace sidebar entries share the global learning count and retain origin', (
    tester,
  ) async {
    final repo = InMemoryVocabularyRepository([word('cat'), word('dog', status: VocabularyStatus.known)]);
    addTearDown(repo.dispose);
    final c = await pumpApp(tester, vocabulary: repo);
    final row = find.widgetWithText(MMSidebarItem, 'Vocabulary');
    expect(tester.widget<MMCount>(find.descendant(of: row, matching: find.byType(MMCount))).value, 1);
    await tap(tester, row);
    expect((c.read(navigationProvider) as VocabularyRoute).studySetId, isNull);
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await repo.save([
      word('cat').copyWith(status: VocabularyStatus.known),
      word('dog', status: VocabularyStatus.known),
    ]);
    await tester.pumpAndSettle();
    expect(tester.widget<MMCount>(find.descendant(of: row, matching: find.byType(MMCount))).value, 0);
    await tap(tester, row);
    expect((c.read(navigationProvider) as VocabularyRoute).studySetId, 'demo-1');
    await tap(tester, find.byTooltip('Back'));
    expect(c.read(navigationProvider), isA<WorkspaceRoute>());
  });
  testWidgets('failed saves and stale undo never overwrite newer user data', (tester) async {
    final repo = FailingRepository();
    await repo.save([word('cat')]);
    await open(tester, repository: repo);
    repo.fail = true;
    await tester.enterText(find.byKey(const ValueKey('vocabulary-note')), 'unsaved');
    await tester.pumpAndSettle();
    expect((await repo.load()).single.note, '');
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    repo.fail = false;
    await tester.enterText(find.byKey(const ValueKey('vocabulary-note')), 'saved');
    await tester.pumpAndSettle();
    expect((await repo.load()).single.note, 'saved');
    await button(tester, 'Mark as known');
    await repo.save([(await repo.load()).single.copyWith(note: 'later')]);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Undo'));
    expect((await repo.load()).single.note, 'later');
    expect((await repo.load()).single.status, VocabularyStatus.known);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    await settleHud(tester);
  });
  testWidgets('narrow desktop pushes details, empty values and form cap remain usable', (tester) async {
    await open(
      tester,
      entries: [
        word('cat').copyWith(senses: [], contexts: [], forms: ['cat', ...List.generate(15, (i) => 'form$i')]),
      ],
    );
    expect(find.text('No examples.'), findsOneWidget);
    expect(tester.widget<MMTextField>(find.byKey(const ValueKey('vocabulary-add-form'))).enabled, isFalse);
    tester.view.physicalSize = const Size(430, 900);
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyDetail), findsNothing);
    await tap(tester, find.byKey(const ValueKey('vocabulary-row-cat')));
    expect(find.byType(VocabularyDetail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('long valid phonetics and forms stay bounded in compact and narrow split layouts', (tester) async {
    final term = 'a' * 64;
    await open(tester, compact: true, entries: [word(term, phonetic: '/${'a' * 126}/')]);
    await tap(tester, find.byKey(ValueKey('vocabulary-row-$term')));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('unreadable vocabulary reports a load failure without presenting an empty book', (tester) async {
    final repo = UnreadableRepository();
    final c = await pumpApp(tester, vocabulary: repo);
    addTearDown(repo.dispose);
    c.read(navigationProvider.notifier).showVocabulary();
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('No words yet'), findsNothing);
  });
  for (final dark in [false, true]) {
    testWidgets('screenshot ${dark ? 'dark' : 'light'}', (tester) async {
      await open(tester, dark: dark, chinese: true, scoped: true);
      expect(
        tester
            .widget<MMIconButton>(find.ancestor(of: find.byTooltip('未设置模型'), matching: find.byType(MMIconButton)))
            .onPressed,
        isNull,
      );
      if (Platform.environment['MM_SCREENSHOTS'] != null) {
        await screenshot(tester, 'vocabulary-${dark ? 'dark' : 'light'}', target: find.byType(VocabularyScreen));
        tester.view.physicalSize = const Size(430, 900);
        await tester.pumpAndSettle();
        await screenshot(
          tester,
          'vocabulary-list-compact-${dark ? 'dark' : 'light'}',
          target: find.byType(VocabularyScreen),
        );
        await tap(tester, find.byKey(const ValueKey('vocabulary-row-cat')));
        await screenshot(
          tester,
          'vocabulary-detail-compact-${dark ? 'dark' : 'light'}',
          target: find.byType(VocabularyScreen),
        );
        return;
      }
      await expectLater(
        find.byType(VocabularyScreen),
        matchesGoldenFile('goldens/vocabulary-${dark ? 'dark' : 'light'}.png'),
      );
    });
  }
}
