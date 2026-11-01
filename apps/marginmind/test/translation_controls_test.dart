import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/full_translation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_capsule.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_checkpoint.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_panel.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_sheet.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'full_translation_test.dart' show MockFullTranslationController, testHost;
import 'helpers.dart';
import 'reader_compare_test.dart' show compareFixture;
import 'translation_lifecycle_test.dart' show paragraphs, job;

class StartingController extends MockFullTranslationController {
  StartingController(super.studySetId, super.documentId, super.targetLang, super.presetState);
  final gate = Completer<void>();
  bool started = false;
  bool requested = false;
  String? sourceLang;
  @override
  Future<void> startJob({
    required int from,
    required int to,
    required TranslationMode mode,
    required int batchSize,
    String? note,
    String? sourceLang,
    required String modelName,
    required int estimatedTokens,
  }) async {
    requested = true;
    this.sourceLang = sourceLang;
    await gate.future;
    started = true;
  }
}

class RecordingCompare extends ReaderCompareSession {
  RecordingCompare() : super('demo-1');
  String? opened;
  @override
  ComparePair? build() => null;
  @override
  Future<bool> openAi(String language, {String? documentId, double readerWidth = 0}) async {
    opened = documentId;
    return false;
  }
}

void main() {
  testWidgets('sheet starts the selected non-current document after slow startup, then closes', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
    final compare = RecordingCompare();
    final controller = StartingController(
      'demo-1',
      'c2',
      'en',
      FullTranslationState(
        studySetId: 'demo-1',
        documentId: 'c2',
        targetLang: 'en',
        loading: false,
        paragraphs: paragraphs,
      ),
    );
    await tester.pumpWidget(
      testHost(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showMMSheet<void>(
              context: context,
              width: MMSizes.fullTranslationSheetWidth,
              builder: (_) =>
                  const FullTranslationSheet(studySetId: 'demo-1', documentId: 'c2', initialTargetLang: 'en'),
            ),
            child: const Text('Open'),
          ),
        ),
        overrides: [
          ...overrides,
          readerCompareProvider('demo-1').overrideWith(() => compare),
          fullTranslationProvider(('demo-1', 'c2', 'en')).overrideWith(() => controller),
          translationParagraphsProvider(('demo-1', 'c2')).overrideWith(
            (ref) async => [
              TranslationParagraph(
                documentId: 'c2',
                page: 1,
                index: 0,
                text: '这是用于学习与记忆的中文翻译测试段落。',
                fingerprint: 'c2-p1',
              ),
            ],
          ),
          compareDocumentInfoProvider(('demo-1', 'c2')).overrideWith((ref) async => (language: 'zh', hasText: true)),
          assistantDefaultModelProvider.overrideWithValue(
            const AssistantModel(
              provider: AssistantProvider.ollama,
              model: 'fixture',
              endpoint: 'http://localhost:11434',
              localEnabled: true,
            ),
          ),
          assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready),
        ],
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(compare.opened, isNull);
    expect(controller.requested, true);
    expect(controller.started, false);
    expect(find.byType(FullTranslationSheet), findsOneWidget);
    controller.gate.complete();
    await tester.pumpAndSettle();
    expect(controller.started, true);
    expect(compare.opened, 'c2');
    expect(find.byType(FullTranslationSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet header, language pop-ups, estimate and footer follow the prototype', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
    final controller = StartingController(
      'demo-1',
      'c1',
      'zh',
      FullTranslationState(
        studySetId: 'demo-1',
        documentId: 'c1',
        targetLang: 'zh',
        loading: false,
        paragraphs: paragraphs,
      ),
    );
    controller.gate.complete();
    await tester.pumpWidget(
      testHost(
        const SizedBox(
          width: 560,
          child: FullTranslationSheet(studySetId: 'demo-1', documentId: 'c1', initialTargetLang: 'zh'),
        ),
        overrides: [
          ...overrides,
          readerCompareProvider('demo-1').overrideWith(RecordingCompare.new),
          fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(() => controller),
          translationParagraphsProvider(('demo-1', 'c1')).overrideWith((ref) async => paragraphs),
          compareDocumentInfoProvider(('demo-1', 'c1')).overrideWith((ref) async => (language: 'en', hasText: true)),
          assistantDefaultModelProvider.overrideWithValue(
            const AssistantModel(
              provider: AssistantProvider.ollama,
              model: 'fixture',
              endpoint: 'http://localhost:11434',
              localEnabled: true,
            ),
          ),
          assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(MMIcons.layers), findsOneWidget);
    expect(find.textContaining(' · 4 页'), findsOneWidget);
    expect(find.text('英文（检测）'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('不发送：页眉页码 0 处'), findsOneWidget);
    expect(find.text('译文保存在学习集内，不修改原文'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('full-translation-source-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日语').last);
    await tester.pumpAndSettle();
    expect(find.text('日语'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('full-translation-target-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('英文').last);
    await tester.pumpAndSettle();
    expect(find.text('英文'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet sends the chosen source language and detected language by default', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
    for (final explicit in [false, true]) {
      final controller = StartingController(
        'demo-1',
        'c1',
        'zh',
        FullTranslationState(
          studySetId: 'demo-1',
          documentId: 'c1',
          targetLang: 'zh',
          loading: false,
          paragraphs: paragraphs,
        ),
      );
      controller.gate.complete();
      await tester.pumpWidget(
        testHost(
          key: UniqueKey(),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showMMSheet<void>(
                context: context,
                width: MMSizes.fullTranslationSheetWidth,
                builder: (_) =>
                    const FullTranslationSheet(studySetId: 'demo-1', documentId: 'c1', initialTargetLang: 'zh'),
              ),
              child: const Text('Open'),
            ),
          ),
          overrides: [
            ...overrides,
            readerCompareProvider('demo-1').overrideWith(RecordingCompare.new),
            fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(() => controller),
            translationParagraphsProvider(('demo-1', 'c1')).overrideWith((ref) async => paragraphs),
            compareDocumentInfoProvider(('demo-1', 'c1')).overrideWith((ref) async => (language: 'en', hasText: true)),
            assistantDefaultModelProvider.overrideWithValue(
              const AssistantModel(
                provider: AssistantProvider.ollama,
                model: 'fixture',
                endpoint: 'http://localhost:11434',
                localEnabled: true,
              ),
            ),
            assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready),
          ],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      if (explicit) {
        await tester.tap(find.byKey(const ValueKey('full-translation-source-language')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('法语').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.textContaining('开始 · 第'));
      await tester.pumpAndSettle();
      expect(controller.started, true);
      expect(controller.sourceLang, explicit ? 'fr' : 'en');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet rejects empty, nonnumeric, reversed and out-of-bounds page ranges', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
    final controller = StartingController(
      'demo-1',
      'c1',
      'zh',
      FullTranslationState(
        studySetId: 'demo-1',
        documentId: 'c1',
        targetLang: 'zh',
        loading: false,
        paragraphs: paragraphs,
      ),
    );
    await tester.pumpWidget(
      testHost(
        const SizedBox(
          width: 560,
          child: FullTranslationSheet(studySetId: 'demo-1', documentId: 'c1', initialTargetLang: 'zh'),
        ),
        overrides: [
          ...overrides,
          fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(() => controller),
          translationParagraphsProvider(('demo-1', 'c1')).overrideWith((ref) async => paragraphs),
          compareDocumentInfoProvider(('demo-1', 'c1')).overrideWith((ref) async => (language: 'en', hasText: true)),
          assistantDefaultModelProvider.overrideWithValue(
            const AssistantModel(
              provider: AssistantProvider.ollama,
              model: 'fixture',
              endpoint: 'http://localhost:11434',
              localEnabled: true,
            ),
          ),
          assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('页码'));
    await tester.pumpAndSettle();
    final from = find.byType(TextField).at(0), to = find.byType(TextField).at(1);
    MMButton start() =>
        tester.widget<MMButton>(find.byWidgetPredicate((w) => w is MMButton && w.label.startsWith('开始')));
    for (final (f, t) in [('', '4'), ('abc', '4'), ('0', '4'), ('3', '2'), ('1', '5'), ('1', '')]) {
      await tester.enterText(from, f);
      await tester.enterText(to, t);
      await tester.pump();
      expect(start().onPressed, isNull, reason: '$f–$t must be invalid');
      expect(find.text('1–4'), findsOneWidget);
    }
    await tester.enterText(from, '2');
    await tester.enterText(to, '3');
    await tester.pump();
    expect(start().onPressed, isNotNull);
    await tester.tap(find.text('一次完成'));
    await tester.pump();
    expect(find.text('开始翻译'), findsOneWidget);
    final note = find.byType(TextField).last;
    await tester.enterText(note, 'Keep names unchanged');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.requested, false, reason: 'Enter in the glossary must not start paid work');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final kind in ['idle', 'done', 'all']) {
    testWidgets('capsule $kind opens its appropriate control surface', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
      final task = kind == 'idle'
          ? null
          : job(state: kind == 'done' ? TranslationJobState.done : TranslationJobState.running)
                .copyWith(mode: TranslationMode.all);
      final controller = MockFullTranslationController(
        'demo-1',
        'c1',
        'zh',
        FullTranslationState(
          studySetId: 'demo-1',
          documentId: 'c1',
          targetLang: 'zh',
          job: task,
          paragraphs: paragraphs,
          loading: false,
        ),
      );
      await tester.pumpWidget(
        testHost(
          const FullTranslationCapsule(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
          overrides: [
            ...overrides,
            fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(() => controller),
            translationParagraphsProvider(('demo-1', 'c1')).overrideWith((ref) async => paragraphs),
            compareDocumentInfoProvider(('demo-1', 'c1')).overrideWith((ref) async => (language: 'en', hasText: true)),
            assistantDefaultModelProvider.overrideWithValue(
              const AssistantModel(
                provider: AssistantProvider.ollama,
                model: 'fixture',
                endpoint: 'http://localhost:11434',
                localEnabled: true,
              ),
            ),
            assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready),
          ],
        ),
      );
      await tester.pump();
      if (kind == 'done') expect(find.text('全文已译'), findsOneWidget);
      await tester.tap(find.byType(FullTranslationCapsule));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      if (kind == 'idle') {
        expect(find.byType(FullTranslationSheet), findsOneWidget);
      } else {
        expect(find.byType(FullTranslationPanel), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final status in TranslationJobState.values) {
    testWidgets('panel and capsule expose $status controls', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
      final state = FullTranslationState(
        studySetId: 'demo-1',
        documentId: 'c1',
        targetLang: 'zh',
        loading: false,
        job: job(state: status),
        paragraphs: paragraphs,
        segmentStates: {
          paragraphs[0].fingerprint: TranslationSegmentState.reused,
          paragraphs[1].fingerprint: TranslationSegmentState.reused,
          paragraphs[2].fingerprint: TranslationSegmentState.failed,
          paragraphs[3].fingerprint: TranslationSegmentState.failed,
          paragraphs[4].fingerprint: TranslationSegmentState.done,
          paragraphs[5].fingerprint: TranslationSegmentState.failed,
        },
      );
      final controller = MockFullTranslationController('demo-1', 'c1', 'zh', state);
      await tester.pumpWidget(
        testHost(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              FullTranslationCapsule(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
              SizedBox(
                width: 372,
                child: FullTranslationPanel(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
              ),
            ],
          ),
          overrides: [...overrides, fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(() => controller)],
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final label = switch (status) {
        TranslationJobState.running || TranslationJobState.offline => '暂停',
        TranslationJobState.paused || TranslationJobState.error || TranslationJobState.budget => '继续',
        TranslationJobState.review => '继续下一批',
        _ => null,
      };
      if (label != null) {
        await tester.tap(find.text(label));
        await tester.pump();
        expect(
          status == TranslationJobState.review
              ? controller.continued
              : (status == TranslationJobState.running || status == TranslationJobState.offline)
              ? controller.paused
              : controller.resumed,
          true,
        );
      }
      if (status == TranslationJobState.running ||
          status == TranslationJobState.offline ||
          status == TranslationJobState.paused ||
          status == TranslationJobState.error ||
          status == TranslationJobState.budget) {
        await tester.tap(find.text('停止'));
        await tester.pump();
        expect(controller.stopped, true);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('checkpoint edits next batch, glossary, collapse and review actions', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
    final state = FullTranslationState(
      studySetId: 'demo-1',
      documentId: 'c1',
      targetLang: 'zh',
      loading: false,
      job: TranslationJob(
        id: 'j',
        documentId: 'c1',
        targetLang: 'zh',
        range: TranslationRange(1, 10),
        mode: TranslationMode.batch,
        batchSize: 5,
        model: 'fixture',
        state: TranslationJobState.review,
        batch: TranslationBatch(index: 1, range: TranslationRange(1, 5)),
        estimateTokens: 1000,
        createdAt: testNow,
        updatedAt: testNow,
      ),
      paragraphs: paragraphs,
    );
    final controller = MockFullTranslationController('demo-1', 'c1', 'zh', state);
    await tester.pumpWidget(
      testHost(
        const SizedBox(
          width: 420,
          child: FullTranslationCheckpoint(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
        ),
        overrides: [...overrides, fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(() => controller)],
      ),
    );
    await tester.pump();
    await tester.tap(find.text('术语与要求'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Use consistent terminology');
    await tester.tap(find.text('20 页'));
    await tester.pump();
    await tester.tap(find.text('翻译剩余全部'));
    await tester.pump();
    expect(controller.continued, true);
    await tester.tap(find.text('结束'));
    await tester.pump();
    expect(controller.stopped, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkpoint reports failed paragraphs with an in-line retry; panel names languages', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': compareFixture()}));
    final review = TranslationJob(
      id: 'job',
      documentId: 'c1',
      sourceLang: 'en',
      targetLang: 'zh',
      range: TranslationRange(1, 4),
      mode: TranslationMode.batch,
      batchSize: 5,
      model: 'fixture',
      state: TranslationJobState.review,
      batch: TranslationBatch(index: 1, range: TranslationRange(1, 4)),
      estimateTokens: 1000,
      createdAt: testNow,
      updatedAt: testNow,
    );
    final state = FullTranslationState(
      studySetId: 'demo-1',
      documentId: 'c1',
      targetLang: 'zh',
      loading: false,
      job: review,
      paragraphs: paragraphs,
      segmentStates: {
        for (final p in paragraphs) p.fingerprint: TranslationSegmentState.done,
        'fp-1': TranslationSegmentState.failed,
      },
    );
    final controller = MockFullTranslationController('demo-1', 'c1', 'zh', state);
    await tester.pumpWidget(
      testHost(
        const SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FullTranslationCheckpoint(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
              SizedBox(
                width: 372,
                child: FullTranslationPanel(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
              ),
            ],
          ),
        ),
        overrides: [...overrides, fullTranslationProvider(('demo-1', 'c1', 'zh')).overrideWith(() => controller)],
      ),
    );
    await tester.pump();
    expect(find.text('1 段未译'), findsOneWidget);
    expect(find.text('8 段'), findsOneWidget);
    expect(find.text('英文 → 中文'), findsOneWidget);
    expect(find.text('不发送（页眉、页码、已是中文）'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(controller.retryCalled, true);
    expect(tester.takeException(), isNull);
  });
}
