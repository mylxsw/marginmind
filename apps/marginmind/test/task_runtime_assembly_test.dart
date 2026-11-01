import 'dart:convert';
import 'dart:io';
import 'dart:async';

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

class DelayedSecrets extends Secrets {
  Completer<void>? entered, release;
  @override
  Future<String?> read(String name) async {
    entered?.complete();
    if (release != null) await release!.future;
    return super.read(name);
  }
}

void main() {
  test('catalog dispatch reads existing SecretStore and rejects changed identity or missing key', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = DelayedSecrets()..values['assistant.service.remote'] = 'first-key';
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
    await services.save(AssistantServices(services: [service]));
    secrets.entered = Completer<void>();
    secrets.release = Completer<void>();
    final pending = assembly.loadModel(context);
    await secrets.entered!.future;
    // The controller persists this fence before mutating Keychain. A read that
    // began earlier must not combine the new key with the old capability identity.
    await services.save(AssistantServices(services: [service.copyWith(enabled: false, revision: 2)]));
    secrets.values['assistant.service.remote'] = 'new-generation';
    secrets.release!.complete();
    await expectLater(pending, throwsA(isA<ConfigurationFailure>()));
  });
  test('production assembly uses guarded SDK HTTP and persists real study-set run envelope', () async {
    final dir = await Directory.systemTemp.createTemp('runtime-assembly-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <Map<String, dynamic>>[];
    final subscription = server.listen((request) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      if (bodies.last['stream'] == true) {
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: ${jsonEncode({
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Image title'},
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 9, 'completion_tokens': 2, 'total_tokens': 11},
          })}\n\ndata: [DONE]\n\n',
        );
        await request.response.close();
        return;
      }
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
        multimodal: CapabilitySupport.supported,
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
      final imageRequest = TaskRequest<String>(
        spec: fixture.spec,
        input: {'text': 'image question'},
        inputFingerprint: 'image',
        images: [TaskImage(base64Data: 'AQID', mimeType: 'image/png')],
        streamDrafts: true,
        maxOutputTokens: 21,
      );
      final imageHandle = await assembly.start(imageRequest, runId: 'assembly-image');
      final drafts = <String>[];
      imageHandle.events.listen((e) {
        if (e.draft != null) drafts.add(e.draft!);
      });
      expect((await imageHandle.result).value, 'Image title');
      await pumpEventQueue();
      expect(drafts.join(), 'Image title');
      expect(jsonEncode(bodies.last['messages']), contains('data:image/png;base64,AQID'));
      expect(bodies.last['max_completion_tokens'], 21);
      expect(
        (await reopened.load('assembly-image'))!.checkpoint['images'],
        imageRequest.images.map((i) => i.toJson()).toList(),
      );
      // Probe factory shares the durable store but never upgrades an unknown profile.
      profiles.clear();
      final probe = assembly.createCapabilityProbe();
      final probeResult = await probe.probe(context.config.model, cancellation: CancellationToken());
      expect(probeResult.issue, RoutingIssue.unknown);
      final probeRecord = probe.steps.records.values.singleWhere((r) => r.stage == RunPurpose.capabilityProbe.name);
      expect((await reopened.load(probeRecord.context.runId))!.usage.inputTokens, 9);
      expect(bodies.last['max_completion_tokens'], 16);
      expect(bodies.last.containsKey('reasoning_effort'), false);
      await expectLater(
        assembly.freeze(fixture.request(), runId: 'still-unknown'),
        throwsA(isA<ConfigurationFailure>()),
      );
      profiles.put(caps);
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
