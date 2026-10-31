// Supply MAP_AI_PROVIDER, MAP_AI_ENDPOINT, MAP_AI_MODEL and MAP_AI_KEY through
// the environment. Never put credentials in command arguments or test evidence.
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

Future<void> main() async {
  final env = Platform.environment;
  if (['MAP_AI_PROVIDER', 'MAP_AI_ENDPOINT', 'MAP_AI_MODEL', 'MAP_AI_KEY'].any((k) => env[k]?.isNotEmpty != true)) {
    stderr.writeln('Missing MAP_AI_PROVIDER/ENDPOINT/MODEL/KEY environment configuration.');
    exitCode = 2;
    return;
  }
  ModelMapGenerator? generator;
  _SmokeClient? capture;
  try {
    final config = AssistantModel(
      provider: AssistantProvider.values.byName(env['MAP_AI_PROVIDER']!),
      endpoint: env['MAP_AI_ENDPOINT']!,
      model: env['MAP_AI_MODEL']!,
    );
    final connection = connectAssistant(
      config,
      env['MAP_AI_KEY']!,
      budget: null,
      requestTimeout: mapGenerationRequestTimeout,
    );
    capture = _SmokeClient(connection.client);
    generator = ModelMapGenerator(AssistantConnection(capture, connection.dio), config.model);
    final pages = <int, String>{};
    const subjects = [
      ('主动回想', '合上书回忆内容，再对照原文发现遗漏。直接重读容易把熟悉感误当成理解。'),
      ('间隔复习', '将复习安排在不同日期，每次先独立回答，再核对答案；根据遗忘情况调整间隔。'),
      ('交错练习', '混合不同类型题目，先判断适用方法，再求解；避免只会套用紧邻的例题。'),
      ('解释与迁移', '用自己的语言解释因果，通过新情境检验理解，并记录错误原因。'),
    ];
    for (final (i, subject) in subjects.indexed) {
      pages[i + 1] = [
        '${subject.$1}：${subject.$2}',
        for (var example = 1; example <= 110; example++)
          '练习记录 $example：学生阅读案例后先写出推理过程，比较自己的解释与原文，找出遗漏条件，记录问题，再在下一次复习中重新回答。${subject.$2}',
      ].join('\n');
    }
    MapLineContext context(MapLinePhase phase) => MapLineContext(
      phase: phase,
      mapId: 'smoke-map',
      draftPrefix: '${phase.name}-',
      documents: {'D1': 'smoke-document'},
      pages: {'D1': pages.keys.toSet()},
    );
    final points = await generator
        .readChapter(
          MapChapterInput(
            chapterId: 'learning-methods',
            documentAlias: 'D1',
            context: context(MapLinePhase.chapter),
            textByPage: pages,
            instructions: '用中文提取各学习方法的原理、适用条件、操作步骤和常见错误，保留各页的出处。',
          ),
          CancellationToken(),
        )
        .toList();
    stdout.writeln(
      jsonEncode({
        'stage': 'chapter',
        'model': config.model,
        'inputCharacters': pages.values.fold<int>(0, (n, text) => n + text.length),
        'points': points.length,
      }),
    );
    final lines = await generator
        .generate(
          MapBuildInput(
            title: '学习方法',
            generation: MapGeneration(
              sources: [MapSource(documentId: 'smoke-document', fingerprint: 'smoke', readThrough: pages.length)],
              organization: MapOrganization.topic,
              depth: 3,
              generatedAt: DateTime.now().toUtc(),
            ),
            context: context(MapLinePhase.generation),
            points: points,
          ),
          CancellationToken(),
        )
        .toList();
    stdout.writeln(
      jsonEncode({
        'stage': 'generation',
        'model': config.model,
        'topics': lines.where((line) => line.kind == MapLineKind.add).length,
      }),
    );
    if (points.isEmpty || lines.isEmpty) exitCode = 1;
  } catch (error) {
    if (capture != null && env['MAP_AI_DIAGNOSTICS'] != null) {
      await File(env['MAP_AI_DIAGNOSTICS']!).writeAsString(capture.output.toString());
    }
    if (error is MapGenerationFailure) {
      stderr.writeln(
        jsonEncode({
          'phase': error.phase.name,
          'received': error.receivedLines,
          'accepted': error.acceptedLines,
          'rejections': error.rejections,
          'stop': error.stopReason,
          'reasoningCharacters': error.reasoningCharacters,
        }),
      );
    }
    stderr.writeln(
      'Smoke failed: ${error is ResearchFailure ? '${error.kind.name}/${error.code}' : error.runtimeType}',
    );
    exitCode = 1;
  } finally {
    await generator?.close();
  }
}

// Captures only the synthetic response, never headers or credentials.
class _SmokeClient implements LLMClient {
  _SmokeClient(this.inner);
  final LLMClient inner;
  final output = StringBuffer();
  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) => inner.generate(
    messages,
    tools: tools,
    toolChoice: toolChoice,
    modelConfig: modelConfig,
    jsonOutput: jsonOutput,
    cancelToken: cancelToken,
  );
  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    output.clear();
    final source = await inner.stream(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );
    return source.map((event) {
      output.write(event.modelMessage?.textOutput ?? '');
      return event;
    });
  }
}
