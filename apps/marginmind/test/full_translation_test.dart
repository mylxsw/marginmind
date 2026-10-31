import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/full_translation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/translation_schedulers.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_capsule.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_checkpoint.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_panel.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_sheet.dart';
import 'package:marginmind/features/workspace/widgets/reader_translation_view.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reader_compare_test.dart' show compareFixture;

Directory _evidenceDir() {
  var dir = Directory('docs/evidence/gul-618');
  if (!dir.existsSync()) {
    dir = Directory('../../docs/evidence/gul-618');
  }
  dir.createSync(recursive: true);
  return dir;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() async {
    final dir = _evidenceDir();
    File('${dir.path}/$name.png').writeAsBytesSync(png.buffer.asUint8List());
  });
  image.dispose();
}

Widget testHost(
  Widget child, {
  Key? key,
  bool dark = false,
  Locale locale = const Locale('zh'),
  ProviderContainer? container,
  List<Override> overrides = const [],
}) {
  final app = MaterialApp(
    locale: locale,
    theme: dark ? MMTheme.dark() : MMTheme.light(),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      backgroundColor: dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F7),
      body: MMHudHost(child: Center(child: child)),
    ),
  );
  if (container != null) {
    return UncontrolledProviderScope(key: key, container: container, child: app);
  }
  if (overrides.isNotEmpty) {
    return ProviderScope(key: key ?? UniqueKey(), overrides: overrides, child: app);
  }
  return app;
}

List<TranslationParagraph> _sampleParagraphs([String docId = 'c1']) => [
  for (var p = 1; p <= 5; p++)
    for (var i = 0; i < 4; i++)
      TranslationParagraph(
        documentId: docId,
        page: p,
        index: (p - 1) * 4 + i,
        text: 'Page $p paragraph $i: Deep learning systems utilize multi-layer neural architectures.',
        fingerprint: '$docId-$p-$i',
        rects: [const PageRect(50, 50, 400, 100)],
      ),
];

class MockTranslationOnlineNotifier extends TranslationOnlineNotifier {
  MockTranslationOnlineNotifier(super.studySetId, this.initialOnline);
  final bool initialOnline;
  @override
  bool build() => initialOnline;
}

class MockReaderCompareSession extends ReaderCompareSession {
  MockReaderCompareSession(super.studySetId, this.presetPair);
  final ComparePair? presetPair;
  @override
  ComparePair? build() => presetPair;
}

class MockFullTranslationController extends FullTranslationController {
  MockFullTranslationController(
    super.studySetId,
    super.documentId,
    super.targetLang,
    this.presetState,
  );

  final FullTranslationState presetState;
  bool paused = false;
  bool resumed = false;
  bool stopped = false;
  bool continued = false;
  bool retryCalled = false;
  bool removed = false;

  @override
  FullTranslationState build() => presetState;

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    resumed = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> continueBatch({bool all = false, String? note, int? batchSize}) async {
    continued = true;
  }

  @override
  Future<void> retry([TranslationParagraph? paragraph]) async {
    retryCalled = true;
  }

  @override
  Future<void> removeTranslations() async {
    removed = true;
  }
}

class TestTranslator implements ParagraphTranslator {
  final calls = <int>[];
  int delayMs = 0;
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
    if (delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
    return ParagraphTranslation('Translated ${p.index}', tokens: 5);
  }

  @override
  void close() => closed = true;
}

void main() {
  group('FullTranslation Estimation & Formatting Unit Tests', () {
    test('formatTokens formats numbers correctly', () {
      expect(formatTokens(0), '0');
      expect(formatTokens(450), '450');
      expect(formatTokens(999), '999');
      expect(formatTokens(1500), '1,500');
      expect(formatTokens(9999), '9,999');
      expect(formatTokens(10000), '1 万');
      expect(formatTokens(15000), '1.5 万');
      expect(formatTokens(24500), '2.5 万');
      expect(formatTokens(1000000), '100 万');
    });

    test('estimateFullTranslation calculates counts, tokens, and minutes correctly', () {
      final emptyEst = estimateFullTranslation(
        paragraphs: const [],
        from: 1,
        to: 5,
        targetLang: 'zh',
        values: const {},
      );
      expect(emptyEst.paras, 0);
      expect(emptyEst.chars, 0);
      expect(emptyEst.tokens, 0);
      expect(emptyEst.minutes, 1);

      final paras = _sampleParagraphs();
      final estAll = estimateFullTranslation(
        paragraphs: paras,
        from: 1,
        to: 5,
        targetLang: 'zh',
        values: const {},
      );
      expect(estAll.paras, 20);
      expect(estAll.chars > 0, true);
      expect(estAll.reused, 0);
      expect(estAll.tokens > 0, true);
      expect(estAll.minutes >= 1, true);

      // Custom range: pages 2 to 3
      final estSub = estimateFullTranslation(
        paragraphs: paras,
        from: 2,
        to: 3,
        targetLang: 'zh',
        values: const {},
      );
      expect(estSub.paras, 8);
      expect(estSub.chars < estAll.chars, true);

      // Reused segment
      final existingValues = {
        paras.first.fingerprint: '已翻译第一段',
      };
      final estReused = estimateFullTranslation(
        paragraphs: paras,
        from: 1,
        to: 5,
        targetLang: 'zh',
        values: existingValues,
      );
      expect(estReused.reused, 1);
      expect(estReused.paras, 19);
    });

    test('FullTranslationCounts holds correct values', () {
      const counts = FullTranslationCounts(
        total: 20,
        done: 10,
        fail: 1,
        run: 2,
        reused: 3,
        pagesDone: 2,
        pagesTotal: 5,
        pct: 50,
      );
      expect(counts.total, 20);
      expect(counts.done, 10);
      expect(counts.fail, 1);
      expect(counts.run, 2);
      expect(counts.reused, 3);
      expect(counts.pagesDone, 2);
      expect(counts.pagesTotal, 5);
      expect(counts.pct, 50);
    });

    test('FullTranslationState computes ranges and page states correctly', () {
      final now = DateTime.utc(2026, 10, 31);
      final job = TranslationJob(
        id: 'full1',
        documentId: 'c1',
        targetLang: 'en',
        range: TranslationRange(1, 4),
        mode: TranslationMode.batch,
        batchSize: 5,
        model: 'fixture',
        state: TranslationJobState.running,
        batch: TranslationBatch(index: 1, range: TranslationRange(1, 2)),
        estimateTokens: 5000,
        createdAt: now,
        updatedAt: now,
      );

      final paras = _sampleParagraphs().where((p) => p.page <= 5).toList();
      final values = {
        for (final p in paras.where((p) => p.page == 1)) textKey(p.text, 'en'): 'done',
      };

      final state = FullTranslationState(
        studySetId: 'demo-1',
        documentId: 'c1',
        targetLang: 'en',
        job: job,
        paragraphs: paras,
        values: values,
        runningKeys: {textKey(paras[4].text, 'en')},
        loading: false,
      );

      expect(state.hasJob, true);
      expect(state.isActive, true);
      expect(state.isRunning, true);
      expect(state.pageCount, 5);
      expect(state.from, 1);
      expect(state.to, 4);
      expect(state.inRange(1), true);
      expect(state.inRange(5), false);
      expect(state.batchOf(1), 1);
      expect(state.batchOf(3), 1);

      // Page 1 has all 4 segments done
      expect(state.pageState(1), TranslationPageState.done);
      // Page 2 has a running segment
      expect(state.pageState(2), TranslationPageState.running);

      final c = state.counts();
      expect(c.total, 16); // pages 1-4
      expect(c.done, 4);
      expect(c.run, 1);
      expect(c.pagesDone, 1);
      expect(c.pct, 25);
    });

    test('FullTranslationController manages reading page, collapsed checkpoint, and lifecycle', () async {
      final baseOverrides = await testOverrides(
        content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}),
      );
      final storage = InMemoryTranslationStore();
      final translator = TestTranslator()..delayMs = 100;
      final container = ProviderContainer(
        overrides: [
          ...baseOverrides,
          translationStoreProvider('demo-1').overrideWith((ref) async => storage),
          paragraphTranslatorProvider.overrideWithValue((_) async => translator),
          translationParagraphsProvider(('demo-1', 'c1')).overrideWith((ref) async => _sampleParagraphs('c1')),
          compareDocumentInfoProvider(('demo-1', 'c1')).overrideWith((ref) async => (language: 'zh', hasText: true)),
          assistantDefaultModelProvider.overrideWithValue(const AssistantModel(
            provider: AssistantProvider.ollama,
            model: 'fixture',
            endpoint: 'http://localhost:11434',
            localEnabled: true,
          )),
          assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(fullTranslationProvider(('demo-1', 'c1', 'en')), (_, _) {});
      addTearDown(sub.close);
      final controller = container.read(fullTranslationProvider(('demo-1', 'c1', 'en')).notifier);
      while (container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).loading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      controller.setCurrentReadingPage(3);
      expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).currentReadingPage, 3);

      expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).checkpointCollapsed, false);
      controller.setCheckpointCollapsed(true);
      expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).checkpointCollapsed, true);
      controller.toggleCheckpointCollapsed();
      expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).checkpointCollapsed, false);

      await controller.startJob(
        from: 1,
        to: 5,
        mode: TranslationMode.batch,
        batchSize: 5,
        note: 'glossary terms',
        modelName: 'fixture',
        estimatedTokens: 100000,
      );
      for (var i = 0; i < 5; i++) {
        await pumpEventQueue();
      }

      final active = container.read(fullTranslationProvider(('demo-1', 'c1', 'en')));
      expect(active.hasJob, true);
      expect(active.job!.range.from, 1);
      expect(active.job!.range.to, 5);
      expect(active.job!.mode, TranslationMode.batch);
      expect(active.job!.note, 'glossary terms');

      await controller.pause();
      await pumpEventQueue();
      expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).job!.state, TranslationJobState.paused);

      await controller.resume();
      await pumpEventQueue();
      expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).job!.state, TranslationJobState.running);

      await controller.stop();
      await pumpEventQueue();
      expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).job!.state, TranslationJobState.stopped);

      await controller.removeTranslations();
      await pumpEventQueue();
      expect(container.read(fullTranslationProvider(('demo-1', 'c1', 'en'))).hasJob, false);
    });
  });

  group('FullTranslation Widgets & Visual Evidence', () {
    testWidgets('FullTranslationSheet renders light, dark, and blocked states and captures screenshots', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      final baseOverrides = await testOverrides(
        content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}),
      );

      Widget buildSheet({
        bool dark = false,
        bool hasText = true,
        bool isOnline = true,
        AssistantCredentialState cred = AssistantCredentialState.ready,
      }) {
        return testHost(
          dark: dark,
          overrides: [
            ...baseOverrides,
            translationParagraphsProvider(('demo-1', 'c1')).overrideWith(
              (ref) async => hasText ? _sampleParagraphs('c1') : const <TranslationParagraph>[],
            ),
            compareDocumentInfoProvider(('demo-1', 'c1')).overrideWith(
              (ref) async => (language: 'zh', hasText: hasText),
            ),
            translationOnlineProvider('demo-1').overrideWith(
              () => MockTranslationOnlineNotifier('demo-1', isOnline),
            ),
            assistantDefaultModelProvider.overrideWithValue(const AssistantModel(
              provider: AssistantProvider.claude,
              model: 'claude-3-5-sonnet',
              endpoint: 'https://api.anthropic.com',
            )),
            assistantCredentialStateProvider.overrideWith((ref) async => cred),
            fullTranslationProvider(('demo-1', 'c1', 'en')).overrideWith(
              () => MockFullTranslationController(
                'demo-1',
                'c1',
                'en',
                const FullTranslationState(
                  studySetId: 'demo-1',
                  documentId: 'c1',
                  targetLang: 'en',
                  loading: false,
                ),
              ),
            ),
          ],
          RepaintBoundary(
            key: key,
            child: const FullTranslationSheet(
              studySetId: 'demo-1',
              documentId: 'c1',
              initialTargetLang: 'en',
            ),
          ),
        );
      }

      // 1. Light Mode
      await tester.pumpWidget(buildSheet(dark: false));
      await tester.pumpAndSettle();

      expect(find.text('翻译全文'), findsOneWidget);
      expect(find.text('分批确认'), findsOneWidget);
      expect(find.text('一次完成'), findsOneWidget);
      expect(find.textContaining('开始 · 第'), findsOneWidget);
      await _capture(tester, key, 'sheet-light');

      // 2. Dark Mode
      await tester.pumpWidget(buildSheet(dark: true));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'sheet-dark');

      // 3. Blocked State: Offline Cloud Model
      await tester.pumpWidget(buildSheet(dark: false, isOnline: false));
      await tester.pumpAndSettle();
      expect(find.text('网络不可用'), findsOneWidget);
      await _capture(tester, key, 'sheet-blocked');

      // 4. Custom range toggle and input interaction
      await tester.pumpWidget(buildSheet(dark: false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('页码'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsWidgets);
      expect(find.text('–'), findsOneWidget);
    });

    testWidgets('FullTranslationCapsule renders multiple states and captures screenshot', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      final now = DateTime.utc(2026, 10, 31);
      final baseOverrides = await testOverrides(
        content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}),
      );

      FullTranslationState makeState(TranslationJobState jState) {
        return FullTranslationState(
          studySetId: 'demo-1',
          documentId: 'c1',
          targetLang: 'en',
          job: TranslationJob(
            id: 'j',
            documentId: 'c1',
            targetLang: 'en',
            range: TranslationRange(1, 10),
            mode: TranslationMode.batch,
            batchSize: 5,
            model: 'fixture',
            state: jState,
            batch: TranslationBatch(index: 1, range: TranslationRange(1, 5)),
            estimateTokens: 2000,
            createdAt: now,
            updatedAt: now,
          ),
          paragraphs: _sampleParagraphs(),
          values: {'c1-1-0': 'done'},
          loading: false,
        );
      }

      final mockRunning = MockFullTranslationController('demo-1', 'c1', 'en', makeState(TranslationJobState.running));
      final mockReview = MockFullTranslationController('demo-1', 'c1', 'zh', makeState(TranslationJobState.review));

      await tester.pumpWidget(
        testHost(
          overrides: [
            ...baseOverrides,
            fullTranslationProvider(('demo-1', 'c1', 'en')).overrideWith(() => mockRunning),
            fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(() => mockReview),
          ],
          RepaintBoundary(
            key: key,
            child: Container(
              padding: const EdgeInsets.all(24),
              color: const Color(0xFFF8F9FA),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  FullTranslationCapsule(studySetId: 'demo-1', documentId: 'c1', targetLang: 'en'),
                  SizedBox(height: 12),
                  FullTranslationCapsule(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('第 1 批待确认'), findsOneWidget);
      await _capture(tester, key, 'capsule-states');
    });

    testWidgets('FullTranslationPanel renders running and review states and captures screenshots', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key1 = GlobalKey();
      final key2 = GlobalKey();
      final key3 = GlobalKey();
      final now = DateTime.utc(2026, 10, 31);
      final baseOverrides = await testOverrides(
        content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}),
      );

      FullTranslationState makePanelState(TranslationJobState jState) {
        return FullTranslationState(
          studySetId: 'demo-1',
          documentId: 'c1',
          targetLang: 'en',
          job: TranslationJob(
            id: 'job1',
            documentId: 'c1',
            targetLang: 'en',
            range: TranslationRange(1, 16),
            mode: TranslationMode.batch,
            batchSize: 5,
            model: 'Qwen 2.5 72B',
            state: jState,
            batch: TranslationBatch(index: 2, range: TranslationRange(6, 10)),
            estimateTokens: 8500,
            usage: TranslationUsage(inputTokens: 3200, outputTokens: 1800, requests: 12),
            createdAt: now,
            updatedAt: now,
          ),
          paragraphs: _sampleParagraphs(),
          values: {for (var i = 0; i < 4; i++) 'c1-1-$i': 'translated'},
          runningKeys: jState == TranslationJobState.running ? {'c1-2-0'} : const {},
          loading: false,
        );
      }

      Widget buildPanel(TranslationJobState state, GlobalKey boundaryKey, {bool dark = false}) {
        final mock = MockFullTranslationController('demo-1', 'c1', 'en', makePanelState(state));
        return testHost(
          dark: dark,
          overrides: [
            ...baseOverrides,
            fullTranslationProvider(('demo-1', 'c1', 'en')).overrideWith(() => mock),
          ],
          RepaintBoundary(
            key: boundaryKey,
            child: const SizedBox(
              width: 372,
              child: FullTranslationPanel(
                studySetId: 'demo-1',
                documentId: 'c1',
                targetLang: 'en',
              ),
            ),
          ),
        );
      }

      // 1. Panel Running - Light
      await tester.pumpWidget(buildPanel(TranslationJobState.running, key1, dark: false));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('全文翻译'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      await _capture(tester, key1, 'panel-running-light');

      // 2. Panel Running - Dark
      await tester.pumpWidget(buildPanel(TranslationJobState.running, key2, dark: true));
      await tester.pump(const Duration(milliseconds: 50));
      await _capture(tester, key2, 'panel-running-dark');

      // 3. Panel Review
      await tester.pumpWidget(buildPanel(TranslationJobState.review, key3, dark: false));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('第 2 批待确认'), findsOneWidget);
      expect(find.text('继续下一批'), findsOneWidget);
      await _capture(tester, key3, 'panel-review');
    });

    testWidgets('FullTranslationCheckpoint renders expanded and collapsed and captures screenshots', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key1 = GlobalKey();
      final key2 = GlobalKey();
      final key3 = GlobalKey();
      final now = DateTime.utc(2026, 10, 31);
      final baseOverrides = await testOverrides(
        content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}),
      );

      FullTranslationState makeCkptState({bool collapsed = false}) {
        return FullTranslationState(
          studySetId: 'demo-1',
          documentId: 'c1',
          targetLang: 'en',
          job: TranslationJob(
            id: 'job-ckpt',
            documentId: 'c1',
            targetLang: 'en',
            range: TranslationRange(1, 20),
            mode: TranslationMode.batch,
            batchSize: 5,
            model: 'Qwen 2.5 72B',
            state: TranslationJobState.review,
            batch: TranslationBatch(index: 1, range: TranslationRange(1, 5)),
            estimateTokens: 10000,
            usage: TranslationUsage(inputTokens: 1400, outputTokens: 1200, requests: 6),
            createdAt: now,
            updatedAt: now,
          ),
          paragraphs: _sampleParagraphs(),
          values: {for (var i = 0; i < 4; i++) 'c1-1-$i': 'done'},
          loading: false,
          checkpointCollapsed: collapsed,
        );
      }

      Widget buildCheckpoint(GlobalKey boundaryKey, {bool dark = false, bool collapsed = false}) {
        final mock = MockFullTranslationController('demo-1', 'c1', 'en', makeCkptState(collapsed: collapsed));
        return testHost(
          dark: dark,
          overrides: [
            ...baseOverrides,
            fullTranslationProvider(('demo-1', 'c1', 'en')).overrideWith(() => mock),
          ],
          RepaintBoundary(
            key: boundaryKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const FullTranslationCheckpoint(
                studySetId: 'demo-1',
                documentId: 'c1',
                targetLang: 'en',
              ),
            ),
          ),
        );
      }

      // 1. Expanded - Light
      await tester.pumpWidget(buildCheckpoint(key1, dark: false, collapsed: false));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('第 1 批已完成'), findsOneWidget);
      expect(find.text('从第 1 页开始检查'), findsOneWidget);
      expect(find.text('翻译剩余全部'), findsOneWidget);
      await _capture(tester, key1, 'checkpoint-expanded-light');

      // 2. Expanded - Dark
      await tester.pumpWidget(buildCheckpoint(key2, dark: true, collapsed: false));
      await tester.pump(const Duration(milliseconds: 50));
      await _capture(tester, key2, 'checkpoint-expanded-dark');

      // 3. Collapsed State
      await tester.pumpWidget(buildCheckpoint(key3, dark: false, collapsed: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('第 1 批待确认'), findsOneWidget);
      await _capture(tester, key3, 'checkpoint-collapsed');
    });

    testWidgets('ReaderTranslationView displays page placeholders and quit HUD', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      final baseOverrides = await testOverrides(
        content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}),
      );
      final now = DateTime.utc(2026, 10, 31);

      final job = TranslationJob(
        id: 'job-running',
        documentId: 'c1',
        targetLang: 'en',
        range: TranslationRange(1, 2),
        mode: TranslationMode.batch,
        batchSize: 5,
        model: 'fixture',
        state: TranslationJobState.running,
        batch: TranslationBatch(index: 1, range: TranslationRange(1, 1)),
        estimateTokens: 1000,
        createdAt: now,
        updatedAt: now,
      );

      final state = FullTranslationState(
        studySetId: 'demo-1',
        documentId: 'c1',
        targetLang: 'en',
        job: job,
        paragraphs: _sampleParagraphs('c1'),
        values: const {},
        recoveredQuit: true,
        loading: false,
      );

      final mock = MockFullTranslationController('demo-1', 'c1', 'en', state);

      await tester.pumpWidget(
        testHost(
          overrides: [
            ...baseOverrides,
            readerCompareProvider('demo-1').overrideWith(
              () => MockReaderCompareSession(
                'demo-1',
                ComparePair(
                  id: 'pair1',
                  leftDocumentId: 'c1',
                  right: AiCompareTarget('en'),
                ),
              ),
            ),
            fullTranslationProvider(('demo-1', 'c1', 'en')).overrideWith(() => mock),
          ],
          RepaintBoundary(
            key: key,
            child: const ReaderTranslationView(studySetId: 'demo-1'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Quit recovery notification banner
      expect(find.textContaining('全文翻译已暂停在第'), findsOneWidget);
      expect(find.text('继续'), findsOneWidget);

      await _capture(tester, key, 'translation-placeholders');
    });
  });
}
