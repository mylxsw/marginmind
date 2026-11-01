import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/task_run_store.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

import '../../../packages/mm_assistant/test/task_runtime_test.dart' as fixture;

void main() {
  test('production assembly uses guarded SDK HTTP and persists real study-set run envelope', () async {
    final dir = await Directory.systemTemp.createTemp('runtime-assembly-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <Map<String, dynamic>>[];
    final subscription = server.listen((request) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'fixture-response',
          'object': 'chat.completion',
          'model': 'fixture-model',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'Title'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 9, 'completion_tokens': 2, 'total_tokens': 11},
        }),
      );
      await request.response.close();
    });
    try {
      final model = AssistantModel(
        provider: AssistantProvider.ollama,
        model: 'fixture-model',
        serviceId: 'fixture-service',
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        localEnabled: true,
      );
      final identity = CapabilityIdentity(
        model: const ModelReference('fixture-service', 'fixture-model'),
        protocol: ModelProtocol.ollamaChat,
        endpointFingerprint: modelEndpointFingerprint(ModelProtocol.ollamaChat, model.endpoint),
        adapterVersion: modelPolicyAdapterVersion,
        serviceRevision: 1,
      );
      final caps = ModelCapabilityProfile(
        identity: identity,
        thinking: ThinkingCapability.switchable,
        policies: {ReasoningPolicy.off: ReasoningRecipe.effortNone},
        evidence: CapabilityEvidence(
          source: CapabilityEvidenceSource.maintainedProfile,
          reference: 'local-test-only',
          semanticBasis: 'Synthetic fixture, not real model verification',
          verifiedAt: DateTime.utc(2026),
          wireVerified: true,
        ),
      );
      final context = RunContext(
        runId: 'assembly',
        knowledgeVersions: {},
        config: ResolvedTaskConfig(
          capabilities: caps,
          policy: const DefaultProviderPolicyCompiler().compile(
            category: TaskCategory.quick,
            requested: ReasoningPolicy.off,
            identity: identity,
            capabilities: caps,
          ),
          routingRevision: 1,
          source: RoutingSource.categoryDefault,
        ),
      );
      final runtime = createPersistentTaskRuntime(
        studySetDirectory: dir.path,
        tasks: fixture.registry(),
        knowledge: VersionedKnowledgeRegistry([]),
        loadModel: (_) async => RuntimeModelBinding(model: model, key: 'fixture', serviceRevision: 1),
      );
      final result = await runtime.start(fixture.request(), context).result;
      expect(result.status, RunStatus.completed, reason: result.failureCode);
      expect(result.usage.quality, UsageQuality.reported);
      expect(result.usage.inputTokens, 9);
      expect(bodies.single['reasoning_effort'], 'none');
      final reopened = FileRunStore(dir);
      expect((await reopened.load('assembly'))!.status, RunStatus.completed);
      expect((await reopened.loadResult('assembly'))!['value'], {'title': 'Title'});
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
