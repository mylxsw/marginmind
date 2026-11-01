import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';

import 'assistant_settings_test.dart' show Secrets;

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/task_run_store.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

import '../../../packages/mm_assistant/test/task_runtime_test.dart' as fixture;

void main() {
  test('catalog dispatch reads existing SecretStore and rejects changed identity or missing key', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = Secrets()..values['assistant.service.remote'] = 'first-key';
    final services = AssistantServicesStore(prefs, secrets);
    final service = AssistantService(
      id: 'remote',
      revision: 1,
      protocol: ServiceProtocol.openai,
      name: 'Remote',
      endpoint: 'https://example.com/v1',
      models: [const ServiceModel(id: 'model')],
    );
    await services.save(AssistantServices(services: [service]));
    final dir = await Directory.systemTemp.createTemp('assembly-secret-');
    addTearDown(() => dir.delete(recursive: true));
    final assembly = PersistentTaskAssembly(
      studySetDirectory: dir.path,
      tasks: fixture.registry(),
      services: services,
      routing: AssistantRoutingStore(prefs, services),
      profiles: CapabilityProfiles(),
    );
    final encoded = encodeRunContext(fixture.context());
    encoded['identity'] = {
      ...encoded['identity'] as Map,
      'model': {'serviceId': 'remote', 'modelId': 'model'},
      'endpointFingerprint': modelEndpointFingerprint(ModelProtocol.chatCompletions, service.endpoint),
    };
    final context = decodeRunContext(encoded);
    expect((await assembly.loadModel(context)).key, 'first-key');
    secrets.values['assistant.service.remote'] = 'rotated-key';
    expect((await assembly.loadModel(context)).key, 'rotated-key');
    secrets.values.clear();
    await expectLater(assembly.loadModel(context), throwsA(isA<ConfigurationFailure>()));
    secrets.values['assistant.service.remote'] = 'restored';
    await services.save(AssistantServices(services: [service.copyWith(endpoint: 'https://changed.example/v1')]));
    await expectLater(assembly.loadModel(context), throwsA(isA<ConfigurationFailure>()));
  });
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
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secrets = Secrets();
      final services = AssistantServicesStore(prefs, secrets);
      final service = AssistantService(
        id: 'fixture-service',
        revision: 1,
        protocol: ServiceProtocol.ollama,
        name: 'Local catalog',
        endpoint: model.endpoint,
        localEnabled: true,
        models: [const ServiceModel(id: 'fixture-model', name: 'Catalog model')],
      );
      await services.save(
        AssistantServices(services: [service], defaultModel: const ModelReference('fixture-service', 'fixture-model')),
      );
      final profiles = CapabilityProfiles();
      final assembly = PersistentTaskAssembly(
        studySetDirectory: dir.path,
        tasks: fixture.registry(),
        services: services,
        routing: AssistantRoutingStore(prefs, services),
        profiles: profiles,
      );
      // Empty production profiles remain unknown; only this test supplies evidence.
      await expectLater(assembly.freeze(fixture.request(), runId: 'unknown'), throwsA(isA<ConfigurationFailure>()));
      profiles.put(caps);
      final context = await assembly.freeze(fixture.request(), runId: 'assembly');
      expect(context.config.serviceLabel, 'Local catalog');
      expect(context.modelDisplayName, 'Catalog model');
      final restored = decodeRunContext(encodeRunContext(context.child('labels-child')));
      expect(restored.config.serviceLabel, 'Local catalog');
      expect(restored.config.modelLabel, 'Catalog model');
      final result = await assembly.runtime.start(fixture.request(), context).result;
      expect(result.status, RunStatus.completed, reason: result.failureCode);
      expect(result.usage.quality, UsageQuality.reported);
      expect(result.usage.inputTokens, 9);
      expect(bodies.single['reasoning_effort'], 'none');
      final reopened = FileRunStore(dir);
      expect((await reopened.load('assembly'))!.status, RunStatus.completed);
      expect((await reopened.loadResult('assembly'))!['value'], {'title': 'Title'});
      final state = sdk.AgentState(
        sessionId: 'legacy-conversation',
        metadata: {
          'assistant.view': {
            'model': {'provider': 'ollama', 'model': 'fixture-model', 'serviceId': 'fixture-service'},
            'messages': ['keep'],
            'unknown': 7,
          },
        },
      );
      await assembly.conversations.save(state);
      final uses = await assembly.usageIndex.listModelUses();
      expect(uses.single.model, context.config.model);
      expect(
        (await assembly.conversations.loadOrCreate('legacy-conversation', null)).metadata['assistant.view'],
        isNot(contains('taskRouting')),
      );
      expect(await assembly.migrateConversation('legacy-conversation'), context.config.model);
      final migrated =
          (await assembly.conversations.loadOrCreate('legacy-conversation', null)).metadata['assistant.view'] as Map;
      expect(migrated['messages'], ['keep']);
      expect(migrated['unknown'], 7);
      expect(migrated['taskRouting'], isNotNull);
      await assembly.migrateConversation('legacy-conversation');
      await services.save(AssistantServices(services: [service.copyWith(enabled: false)]));
      await expectLater(assembly.loadModel(context), throwsA(isA<ConfigurationFailure>()));
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
