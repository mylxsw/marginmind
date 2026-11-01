import 'package:marginmind/features/workspace/document_translation_runtime.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:marginmind/features/workspace/widgets/full_translation_strip.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'full_translation_test.dart' show TestTranslator, testHost, MockReaderCompareSession;
import 'helpers.dart';
import 'reader_compare_test.dart' show compareFixture;

// Network behavior is supplied by the frozen task port, independent of the
// legacy assistant default used by older fixtures.
class LocalTranslator extends TestTranslator implements ScheduledParagraphTranslator {
  @override
  Future<void> prepareScope() async {}
  @override
  bool get localOnly => true;
  @override
  String get modelIdentity => 'local/fixture';
  @override
  Future<TranslationJob> bindJob(TranslationJob job, {ModelReference? modelOverride}) async => job;
  @override
  Future<void> saveJob(TranslationJob job) async {}
  @override
  Future<TranslationUsage> readUsage() async => TranslationUsage(requests: calls.length);
  @override
  void authorizeRecovery() {}
  @override
  void pauseDispatch({bool paused = true}) {}
  @override
  void newTranslation(TranslationParagraph paragraph) {}
  @override
  Future<void> cancelPending() async {}
  @override
  Future<PackedParagraphTranslation> translatePack(
    List<TranslationParagraph> paragraphs,
    String language,
    CancellationToken cancel,
    int maxTokens, {
    String? sourceLanguage,
    String note = '',
  }) async => PackedParagraphTranslation([
    for (final p in paragraphs) (await translate(p, language, cancel, maxTokens, sourceLanguage: sourceLanguage)).text,
  ]);
}

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
      documentTranslatorFactoryProvider.overrideWithValue(
        (_, _) async => translator ?? (ollama ? LocalTranslator() : TestTranslator()),
      ),
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

class DelayedJobStore extends InMemoryTranslationStore {
  final reading = Completer<void>();
  final release = Completer<void>();

  @override
  Future<TranslationJob?> loadJob(String documentId, String language) async {
    final snapshot = await super.loadJob(documentId, language);
    if (language == 'zh' && !reading.isCompleted) {
      reading.complete();
      await release.future;
    }
    return snapshot;
  }
}

class RetryStorage extends InMemoryTranslationStore {
  RetryStorage(this.ledger);
  final bool ledger;
  bool fail = true;
  @override
  Future<void> saveJob(TranslationJob job) async {
    if (fail && ledger) throw StateError('disk');
    await super.saveJob(job);
  }

  @override
  Future<void> append(String documentId, String targetLang, TranslationSegment segment) async {
    if (fail && !ledger) throw StateError('disk');
    await super.append(documentId, targetLang, segment);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final ledger in [false, true]) {
    testWidgets('${ledger ? 'initial ledger' : 'paragraph journal'} failures keep UI retry reachable', (tester) async {
      final store = RetryStorage(ledger);
      final translator = TestTranslator();
      final provider = fullTranslationProvider(('demo-1', 'c1', 'zh'));
      late ProviderContainer container;
      late ProviderSubscription<FullTranslationState> subscription;
      await tester.runAsync(() async {
        container = await containerFor(store: store, translator: translator, loading: Future.value([paragraphs.first]));
        subscription = container.listen(provider, (_, _) {});
        await flush();
      });
      final registry = container.read(translationSchedulersProvider('demo-1'));
      try {
        await tester.pump();
        await tester.runAsync(flush);
        await tester.pumpWidget(
          testHost(
            const FullTranslationStrip(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
            container: container,
          ),
        );
        await tester.runAsync(() async {
          await container
              .read(provider.notifier)
              .startJob(
                from: 1,
                to: 1,
                mode: TranslationMode.all,
                batchSize: 5,
                modelName: 'fixture',
                estimatedTokens: 1000,
              );
          await flush();
        });
        final calls = translator.calls.length;
        final usage = container.read(provider).job!.usage;
        final retry = find.byKey(const Key('full_translation_strip_retry'));
        for (var attempt = 0; attempt < 3; attempt++) {
          await tester.pump();
          expect(container.read(provider).job!.state, TranslationJobState.error);
          expect(container.read(provider).job!.errorKind, 'storage');
          expect(retry, findsOneWidget);
          await tester.runAsync(() async {
            await tester.tap(retry);
            await flush();
          });
          expect(translator.calls.length, calls);
        }
        store.fail = false;
        await tester.pump();
        expect(retry, findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(retry);
          await flush();
        });
        await tester.pump();
        expect(container.read(provider).job!.state, TranslationJobState.done);
        expect(retry, findsNothing);
        expect(translator.calls, [0]);
        expect(container.read(provider).values, isNotEmpty);
        if (!ledger) {
          expect(container.read(provider).job!.usage.requests, usage.requests);
          expect(container.read(provider).job!.usage.totalTokens, usage.totalTokens);
        }
        expect(tester.takeException(), isNull);
      } finally {
        store.fail = false;
        await tester.runAsync(registry.close);
        subscription.close();
        container.dispose();
      }
    });
  }
  for (final ollama in [false, true]) {
    test(
      'network events ${ollama ? 'leave Ollama running' : 'pause and resume cloud without overriding manual pause'}',
      () async {
        final translator = (ollama ? LocalTranslator() : TestTranslator())..delayMs = 150;
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

  test('removal during a pending summary read cannot restore the deleted task', () async {
    final storage = DelayedJobStore();
    await storage.saveJob(job(state: TranslationJobState.stopped));
    final container = await containerFor(store: storage);
    final provider = translationTaskSummaryProvider(('demo-1', 'c1'));
    final subscription = container.listen(provider, (_, _) {});
    await storage.reading.future;
    final registry = container.read(translationSchedulersProvider('demo-1'));
    await registry.removeTranslations('c1', 'zh');
    await flush();
    expect(container.read(provider).value, isNull);
    storage.release.complete();
    await flush();
    expect(container.read(provider).value, isNull);
    await registry.close();
    subscription.close();
    container.dispose();
  });

  test('removal can finish draining paid calls after the workspace is disposed', () async {
    final storage = InMemoryTranslationStore();
    final translator = TestTranslator()..delayMs = 150;
    final container = await containerFor(store: storage, translator: translator);
    final subscription = container.listen(translationSchedulersProvider('demo-1'), (_, _) {});
    final registry = container.read(translationSchedulersProvider('demo-1'));
    final scheduler = await registry.get('c1', 'zh', paragraphs, content: compareFixture());
    unawaited(scheduler.start(job()));
    await flush();
    expect(translator.calls, isNotEmpty);
    final removal = registry.removeTranslations('c1', 'zh');
    subscription.close();
    container.dispose();
    await removal;
    expect(await storage.loadJob('c1', 'zh'), isNull);
    expect((await storage.load('c1', 'zh')).segments, isEmpty);
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

  testWidgets('workspace emits network restored HUD and background system notification', (tester) async {
    const channel = MethodChannel('marginmind/system_notification');
    final notificationCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      notificationCalls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    var foreground = true;
    final events = StreamController<TranslationTaskSummary?>.broadcast();
    await tester.pumpWidget(
      testHost(
        Consumer(
          builder: (context, ref, _) {
            listenFullTranslationNotifications(
              context,
              ref,
              'demo-1',
              ['c1'],
              documentTitleOf: (_) => 'Learning and memory',
              isWindowForeground: () => foreground,
            );
            return const SizedBox.shrink();
          },
        ),
        overrides: [translationTaskSummaryProvider(('demo-1', 'c1')).overrideWith((ref) => events.stream)],
      ),
    );

    // 1. Offline -> Running emits network restored HUD
    events.add(TranslationTaskSummary(job(state: TranslationJobState.offline), 40));
    await tester.pump();
    await tester.pump();
    events.add(TranslationTaskSummary(job(state: TranslationJobState.running), 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('网络已恢复，继续翻译'), findsOneWidget);
    expect(notificationCalls, isEmpty);

    // 2. Foreground completion does NOT send system notification
    events.add(TranslationTaskSummary(job(state: TranslationJobState.done), 100));
    await tester.pump();
    await tester.pump();
    expect(find.text('全文翻译完成'), findsOneWidget);
    expect(notificationCalls, isEmpty);

    // 3. Background completion sends system notification (no failures)
    foreground = false;
    events.add(TranslationTaskSummary(job(state: TranslationJobState.running), 50));
    await tester.pump();
    await tester.pump();
    events.add(TranslationTaskSummary(job(state: TranslationJobState.done), 100));
    await tester.pump();
    await tester.pump();
    expect(notificationCalls.length, 1);
    expect(notificationCalls.last.method, 'notify');
    expect(notificationCalls.last.arguments, {'title': '全文翻译完成', 'body': 'Learning and memory'});

    // 4. Background completion with failures includes untranslated count in body
    events.add(TranslationTaskSummary(job(state: TranslationJobState.running), 50));
    await tester.pump();
    await tester.pump();
    events.add(
      TranslationTaskSummary(
        job(state: TranslationJobState.done).copyWith(
          failures: {
            'fp-1': TranslationFailure(kind: 'network', attempts: 1, at: testNow),
            'fp-2': TranslationFailure(kind: 'network', attempts: 1, at: testNow),
          },
        ),
        80,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(notificationCalls.length, 2);
    expect(notificationCalls.last.arguments, {'title': '全文翻译完成', 'body': 'Learning and memory · 2 段未译'});

    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
  });

  test('offline auto-resumes when network recovers, while manual pause stays paused', () async {
    final translator = TestTranslator()..delayMs = 80;
    final container = await containerFor(translator: translator);
    addTearDown(container.dispose);

    final sub = container.listen(fullTranslationProvider(('demo-1', 'c1', 'zh')), (_, _) {});
    addTearDown(sub.close);
    while (container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).loading) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final controller = container.read(fullTranslationProvider(('demo-1', 'c1', 'zh')).notifier);
    await controller.startJob(
      from: 1,
      to: 4,
      mode: TranslationMode.all,
      batchSize: 5,
      note: '',
      modelName: 'fixture',
      estimatedTokens: 10000,
    );
    await pumpEventQueue();
    expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job!.state, TranslationJobState.running);

    // Network drops -> job enters offline state
    container.read(translationOnlineProvider('demo-1').notifier).setOnline(false);
    await pumpEventQueue();
    expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job!.state, TranslationJobState.offline);

    // Network recovers -> job automatically resumes to running
    container.read(translationOnlineProvider('demo-1').notifier).setOnline(true);
    await pumpEventQueue();
    expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job!.state, TranslationJobState.running);

    // User manually pauses -> pauseReason is user
    await controller.pause();
    await pumpEventQueue();
    final pausedJob = container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job!;
    expect(pausedJob.state, TranslationJobState.paused);
    expect(pausedJob.pauseReason, TranslationPauseReason.user);

    // Network drops and recovers while manually paused -> must NOT auto-resume
    container.read(translationOnlineProvider('demo-1').notifier).setOnline(false);
    await pumpEventQueue();
    container.read(translationOnlineProvider('demo-1').notifier).setOnline(true);
    await pumpEventQueue();
    expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job!.state, TranslationJobState.paused);

    await controller.stop();
  });

  test('budget exceeded pauses once and does not pause again after resume', () async {
    final translator = TestTranslator();
    final container = await containerFor(translator: translator);
    addTearDown(container.dispose);

    final sub = container.listen(fullTranslationProvider(('demo-1', 'c1', 'zh')), (_, _) {});
    addTearDown(sub.close);
    while (container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).loading) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final controller = container.read(fullTranslationProvider(('demo-1', 'c1', 'zh')).notifier);
    // Each paragraph uses 5 tokens; estimateTokens = 4 means > 6 tokens (after 2 paragraphs = 10 tokens) triggers budget pause.
    await controller.startJob(
      from: 1,
      to: 4,
      mode: TranslationMode.all,
      batchSize: 5,
      note: '',
      modelName: 'fixture',
      estimatedTokens: 4,
    );
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job?.state == TranslationJobState.budget) {
        break;
      }
    }

    final budgetJob = container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job!;
    expect(budgetJob.state, TranslationJobState.budget);
    expect(budgetJob.budgetAcknowledged, isFalse);

    // Resuming acknowledges budget and completes remaining paragraphs without pausing for budget again
    await controller.resume();
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job?.state == TranslationJobState.done) {
        break;
      }
    }

    final doneJob = container.read(fullTranslationProvider(('demo-1', 'c1', 'zh'))).job!;
    expect(doneJob.state, TranslationJobState.done);
    expect(doneJob.budgetAcknowledged, isTrue);
  });
}
