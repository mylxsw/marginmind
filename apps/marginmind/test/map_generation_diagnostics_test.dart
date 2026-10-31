import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/widgets/map_generation_failure.dart';
import 'package:marginmind/l10n/generated/app_localizations_zh.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'map_generation_ui_test.dart' show openWorkspace, runGeneration;

void main() {
  testWidgets('format failure remains visible, explains rejection and copies safe details', (tester) async {
    final fake = FakeMapGenerator(
      chapters: {
        'c1-all': ['{"k":"point","id":"p1","title":"Point"}'],
      },
      generationFailure: MapGenerationFailure(
        const ResearchFailure(ResearchFailureKind.protocol, 'noValidMapContent', 'private provider body'),
        phase: MapLinePhase.generation,
        model: 'deepseek-flash',
        receivedLines: 4,
        acceptedLines: 0,
        rejections: {'duplicateTitle': 1, 'unknownParent': 3},
        stopReason: 'stop',
      ),
    );
    final container = await openWorkspace(
      tester,
      overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
    );
    final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
    await runGeneration(
      tester,
      () => controller.start(
        const MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: 'map-error',
          title: '诊断测试',
          sources: [MapDocumentSelection(documentId: 'c1')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.state?.phase, MapGenerationPhase.failed);
    expect(find.text('模型返回内容未通过脑图格式校验'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-generation-error-details-button')));
    await tester.pumpAndSettle();
    final details = mapGenerationFailureReport(AppLocalizationsZh(), controller.state!);
    expect(find.text('生成未完成'), findsOneWidget);
    expect(find.text('错误码'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('map-generation-diagnostics-0')));
    await tester.pumpAndSettle();
    expect(find.text('错误码'), findsOneWidget);
    expect(find.text('protocol / noValidMapContent'), findsOneWidget);
    expect(details, contains('失败阶段: 组织脑图'));
    expect(details, contains('使用模型: deepseek-flash'));
    expect(details, contains('返回行数 / 通过校验行数: 4 / 0'));
    expect(details, contains('父节点不存在或无效 (unknownParent) × 3'));
    expect(details, isNot(contains('private provider body')));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.tap(find.byKey(const ValueKey('map-generation-copy-error-button')));
    await tester.pump();
    expect(copied, details);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    expect(find.text('已拷贝'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-generation-close-error-button')));
    await tester.pumpAndSettle();
    fake.generationFailure = null;
    fake.generation.add('{"ref":"a","parent":"ROOT","title":"恢复后的主题"}');
    await runGeneration(tester, controller.retry);
    await tester.pumpAndSettle();
    expect(controller.state?.phase, MapGenerationPhase.review);
    expect(controller.state?.failure, isNull);
    expect(find.text('恢复后的主题'), findsOneWidget);
  });

  testWidgets('chapter retry and subsequent partial failure leave an actionable state', (tester) async {
    final fake = FakeMapGenerator(chapterFailures: {'c1-all': const ResearchFailure(ResearchFailureKind.timeout)});
    final container = await openWorkspace(
      tester,
      overrides: [mapGeneratorProvider.overrideWithValue(() async => fake)],
    );
    final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
    await runGeneration(
      tester,
      () => controller.start(
        const MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: 'map-retry',
          title: '章节重试',
          sources: [MapDocumentSelection(documentId: 'c1')],
        ),
      ),
    );
    final chapter = controller.state!.chapterFailures.keys.first;
    fake.chapterFailures.clear();
    fake.chapters['c1-all'] = ['{"k":"point","id":"p1","title":"Point"}'];
    fake.generationFailure = const ResearchFailure(ResearchFailureKind.network);
    await runGeneration(tester, () => controller.retryChapter(chapter));
    await tester.pumpAndSettle();
    expect(controller.state!.phase, MapGenerationPhase.failed);
    expect(controller.state!.chapterProgress[chapter], MapChapterStatus.done);
    expect(controller.state!.chapterFailures, isEmpty);
    expect(find.byKey(const ValueKey('map-generation-failed-retry-button')), findsOneWidget);
    fake.generation.add('{"ref":"a","parent":"ROOT","title":"已生成部分"}');
    fake.generationFailure = const ResearchFailure(ResearchFailureKind.timeout);
    await runGeneration(tester, controller.retry);
    await tester.pumpAndSettle();
    expect(controller.state!.phase, MapGenerationPhase.stopped);
    expect(controller.state!.lines.single.title, '已生成部分');
    expect(controller.state!.failure!.kind, ResearchFailureKind.timeout);
    expect(find.byKey(const ValueKey('map-generation-error-details-button')), findsOneWidget);
    await runGeneration(tester, controller.regenerate);
    await tester.pumpAndSettle();
    expect(controller.state!.phase, MapGenerationPhase.stopped);
    expect(controller.state!.lines.single.title, '已生成部分');
  });

  test('truncated output and HTTP failures have distinct user-facing reasons', () {
    final l = AppLocalizationsZh();
    expect(
      mapGenerationFailureSummary(l, const ResearchFailure(ResearchFailureKind.authentication, 'secret_store')),
      '无法读取 API Key，请重新填写并保存。',
    );
    expect(
      mapGenerationFailureSummary(l, const ResearchFailure(ResearchFailureKind.budget, 'outputTruncated')),
      '模型输出被截断，请重试',
    );
    expect(mapGenerationFailureSummary(l, const ResearchFailure(ResearchFailureKind.timeout)), '模型请求超时，请重试');
    expect(mapGenerationFailureSummary(l, const ResearchFailure(ResearchFailureKind.authentication)), 'API Key 无效');
    expect(mapGenerationFailureSummary(l, const ResearchFailure(ResearchFailureKind.rateLimited)), '模型服务请求过于频繁，请稍后重试');
  });
}
