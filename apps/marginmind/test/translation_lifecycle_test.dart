import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/full_translation.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/translation_schedulers.dart';
import 'package:marginmind/features/workspace/translation_task_summary.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_notifications.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_sheet.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'full_translation_test.dart' show TestTranslator, testHost, MockReaderCompareSession;
import 'helpers.dart';
import 'reader_compare_test.dart' show compareFixture;

final paragraphs = [
  for (var i = 0; i < 8; i++)
    TranslationParagraph(
      documentId: 'c1',
      page: i ~/ 2 + 1,
      index: i,
      text: 'This paragraph contains sufficient English words for translation number $i.',
      fingerprint: 'fp-$i',
      rects: [PageRect(50, 600 - (i % 2) * 120, 400, 540 - (i % 2) * 120)],
    ),
];
TranslationJob job({TranslationJobState state = TranslationJobState.running, String lang = 'zh'}) => TranslationJob(
  id: 'job',
  documentId: 'c1',
  targetLang: lang,
  range: TranslationRange(1, 4),
  mode: TranslationMode.batch,
  batchSize: 5,
  model: 'fixture',
  state: state,
  batch: TranslationBatch(index: 1, range: TranslationRange(1, 4)),
  estimateTokens: 1000,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
Future<ProviderContainer> containerFor({
  bool ollama = false,
  bool compare = false,
  TranslationStore? store,
  TestTranslator? translator,
  Future<List<TranslationParagraph>>? loading,
}) async {
  final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
  return ProviderContainer(
    overrides: [
      ...overrides,
      if (compare)
        readerCompareProvider('demo-1').overrideWith(
          () => MockReaderCompareSession(
            'demo-1',
            ComparePair(id: 'pair', leftDocumentId: 'c1', right: AiCompareTarget('zh')),
          ),
        ),
      translationConnectivityProvider.overrideWith((ref) => Stream.value(true)),
      translationStoreProvider('demo-1').overrideWith((ref) async => store ?? InMemoryTranslationStore()),
      paragraphTranslatorProvider.overrideWithValue((_) async => translator ?? TestTranslator()),
      assistantDefaultModelProvider.overrideWithValue(
        AssistantModel(
          provider: ollama ? AssistantProvider.ollama : AssistantProvider.claude,
          model: 'fixture',
          endpoint: ollama ? 'http://localhost:11434' : 'https://api.anthropic.com',
          localEnabled: ollama,
        ),
      ),
      translationParagraphsProvider(('demo-1', 'c1')).overrideWith((ref) => loading ?? Future.value(paragraphs)),
    ],
  );
}

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await pumpEventQueue();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final ollama in [false, true]) {
    test(
      'network events ${ollama ? 'leave Ollama running' : 'pause and resume cloud without overriding manual pause'}',
      () async {
        final translator = TestTranslator()..delayMs = 150;
        final container = await containerFor(ollama: ollama, translator: translator);
        final subscription = container.listen(translationSchedulersProvider('demo-1'), (_, _) {});
        final registry = container.read(translationSchedulersProvider('demo-1'));
        try {
          final scheduler = await registry.get('c1', 'zh', paragraphs, content: compareFixture());
          unawaited(scheduler.start(job()));
          await flush();
          container.read(translationOnlineProvider('demo-1').notifier).setOnline(false);
          await flush();
          expect(scheduler.job!.state, ollama ? TranslationJobState.running : TranslationJobState.offline);
          container.read(translationOnlineProvider('demo-1').notifier).setOnline(true);
          await flush();
          expect(scheduler.job!.state, TranslationJobState.running);
          await scheduler.pause();
          container.read(translationOnlineProvider('demo-1').notifier).setOnline(false);
          await flush();
          container.read(translationOnlineProvider('demo-1').notifier).setOnline(true);
          await flush();
          expect(scheduler.job!.state, TranslationJobState.paused);
          expect(scheduler.job!.pauseReason, TranslationPauseReason.user);
        } finally {
          await registry.close();
          subscription.close();
          container.dispose();
        }
      },
    );
  }
  test('OS event stream feeds the online notifier', () async {
    final events = StreamController<bool>();
    final overrides = await testOverrides();
    final container = ProviderContainer(
      overrides: [...overrides, translationConnectivityProvider.overrideWith((ref) => events.stream)],
    );
    final subscription = container.listen(translationOnlineProvider('demo-1'), (_, _) {});
    events.add(false);
    await flush();
    expect(container.read(translationOnlineProvider('demo-1')), false);
    events.add(true);
    await flush();
    expect(container.read(translationOnlineProvider('demo-1')), true);
    subscription.close();
    container.dispose();
    await events.close();
  });
  test('summary finds persisted user-selected language without extracting paragraphs', () async {
    final storage = InMemoryTranslationStore();
    await storage.saveJob(job(state: TranslationJobState.review, lang: 'en'));
    final never = Completer<List<TranslationParagraph>>();
    final container = await containerFor(store: storage, loading: never.future);
    final provider = translationTaskSummaryProvider(('demo-1', 'c1'));
    final sub = container.listen(provider, (_, _) {});
    final summary = await container.read(provider.future);
    expect(summary!.targetLang, 'en');
    expect(summary.isActive, true);
    expect(container.read(translationSchedulersProvider('demo-1')).peek('c1', 'en'), isNull);
    expect(container.exists(translationParagraphsProvider(('demo-1', 'c1'))), false);
    sub.close();
    container.dispose();
  });
  test('start waits for slow extraction and reports failed loading', () async {
    final slow = Completer<List<TranslationParagraph>>();
    final container = await containerFor(loading: slow.future);
    final provider = fullTranslationProvider(('demo-1', 'c1', 'zh'));
    final sub = container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier);
    var started = false;
    final pending = controller
        .startJob(
          from: 1,
          to: 4,
          mode: TranslationMode.batch,
          batchSize: 5,
          modelName: 'fixture',
          estimatedTokens: 1000,
        )
        .then((_) => started = true);
    await flush();
    expect(started, false);
    slow.complete(paragraphs);
    await pending;
    expect(container.read(provider).hasJob, true);
    await container.read(translationSchedulersProvider('demo-1')).close();
    sub.close();
    container.dispose();
    final broken = Completer<List<TranslationParagraph>>();
    final failed = await containerFor(loading: broken.future);
    final failedSub = failed.listen(provider, (_, _) {});
    final failure = failed
        .read(provider.notifier)
        .startJob(from: 1, to: 4, mode: TranslationMode.all, batchSize: 5, modelName: 'fixture', estimatedTokens: 1000);
    final check = expectLater(failure, throwsStateError);
    broken.completeError(StateError('Extraction failed'));
    await check;
    expect(failed.read(provider).loadError, isNotNull);
    expect(failed.read(provider).loading, false);
    failedSub.close();
    failed.dispose();
  });
  test('summary follows live progress and clearing cannot resurrect a persisted job', () async {
    final storage = InMemoryTranslationStore();
    await storage.saveJob(job(state: TranslationJobState.stopped));
    final container = await containerFor(store: storage);
    final provider = translationTaskSummaryProvider(('demo-1', 'c1'));
    final subscription = container.listen(provider, (_, _) {});
    expect((await container.read(provider.future))!.job.state, TranslationJobState.stopped);
    final registry = container.read(translationSchedulersProvider('demo-1'));
    final scheduler = await registry.get('c1', 'zh', paragraphs, content: compareFixture());
    expect(await registry.get('c1', 'zh', paragraphs, content: compareFixture()), same(scheduler));
    await scheduler.start(job().copyWith(estimateTokens: 100000));
    await flush();
    expect(container.read(provider).value!.percent, 100);
    expect(container.read(provider).value!.job.state, TranslationJobState.done);
    await registry.removeTranslations('c1', 'zh');
    await flush();
    expect(container.read(provider).value, isNull);
    await registry.close();
    subscription.close();
    container.dispose();
  });

  test('removing translations clears the visible reader without buying new translations', () async {
    final storage = InMemoryTranslationStore();
    for (final p in paragraphs) {
      await storage.append(
        'c1',
        'zh',
        TranslationSegment(
          key: textKey(p.text, 'zh'),
          fingerprint: p.fingerprint,
          page: p.page,
          index: p.index,
          text: 'Saved translation',
          model: 'fixture',
          profile: 'default',
          origin: TranslationOrigin.ai,
          at: testNow,
        ),
      );
    }
    final translator = TestTranslator();
    final container = await containerFor(ollama: true, compare: true, store: storage, translator: translator);
    final reader = readerTranslationProvider('demo-1');
    final task = fullTranslationProvider(('demo-1', 'c1', 'zh'));
    final readerSub = container.listen(reader, (_, _) {});
    final taskSub = container.listen(task, (_, _) {});
    for (var i = 0; i < 50 && (container.read(reader).loading || container.read(task).loading); i++) {
      await flush();
    }
    expect(container.read(reader).values, isNotEmpty);
    await container.read(task.notifier).removeTranslations();
    expect(container.read(reader).values, isEmpty);
    expect(container.read(reader).loading, false);
    expect(translator.calls, isEmpty);
    await container.read(translationSchedulersProvider('demo-1')).close();
    readerSub.close();
    taskSub.close();
    container.dispose();
  });

  test('recovered page is the first incomplete page in the selected range', () {
    final state = FullTranslationState(
      studySetId: 'demo-1',
      documentId: 'c1',
      targetLang: 'zh',
      job: job(),
      paragraphs: paragraphs,
      values: {for (final p in paragraphs.where((p) => p.page == 1)) textKey(p.text, 'zh'): 'translated'},
    );
    expect(state.firstUnfinishedPage, 2);
    expect(
      state.copyWith(loadError: StateError('unavailable')).copyWith(checkpointCollapsed: true).loadError,
      isNotNull,
    );
    expect(state.copyWith(loadError: StateError('unavailable')).copyWith(clearLoadError: true).loadError, isNull);
  });

  test('target language uses source content language', () {
    expect(fullTranslationTargetLanguage('zh'), 'en');
    expect(fullTranslationTargetLanguage('en'), 'zh');
    expect(fullTranslationTargetLanguage(null), 'zh');
  });
  for (final target in [TranslationJobState.done, TranslationJobState.stopped]) {
    testWidgets('workspace emits $target HUD with view action', (tester) async {
      final events = StreamController<TranslationTaskSummary?>.broadcast();
      await tester.pumpWidget(
        testHost(
          Consumer(
            builder: (context, ref, _) {
              listenFullTranslationNotifications(context, ref, 'demo-1', ['c1']);
              return const SizedBox.shrink();
            },
          ),
          overrides: [translationTaskSummaryProvider(('demo-1', 'c1')).overrideWith((ref) => events.stream)],
        ),
      );
      events.add(TranslationTaskSummary(job(), 0));
      await tester.pump();
      await tester.pump();
      events.add(TranslationTaskSummary(job(state: target), 100));
      await tester.pump();
      await tester.pump();
      expect(find.text(target == TranslationJobState.done ? '全文翻译完成' : '已停止 · 已译内容已保存'), findsOneWidget);
      expect(find.text('查看'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await events.close();
    });
  }
  testWidgets('workspace emits failure completion and translate-rest HUDs', (tester) async {
    final events = StreamController<TranslationTaskSummary?>.broadcast();
    await tester.pumpWidget(
      testHost(
        Consumer(
          builder: (context, ref, _) {
            listenFullTranslationNotifications(context, ref, 'demo-1', ['c1']);
            return const SizedBox.shrink();
          },
        ),
        overrides: [translationTaskSummaryProvider(('demo-1', 'c1')).overrideWith((ref) => events.stream)],
      ),
    );
    events.add(TranslationTaskSummary(job(state: TranslationJobState.review), 0));
    await tester.pump();
    await tester.pump();
    events.add(TranslationTaskSummary(job().copyWith(mode: TranslationMode.all), 0));
    await tester.pump();
    await tester.pump();
    expect(find.text('剩余页面将一次翻译完成'), findsOneWidget);
    events.add(
      TranslationTaskSummary(
        job(state: TranslationJobState.done).copyWith(
          mode: TranslationMode.all,
          failures: {'fp-1': TranslationFailure(kind: 'network', attempts: 1, at: testNow)},
        ),
        80,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('全文翻译完成 · 1 段未译'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
  });
}
