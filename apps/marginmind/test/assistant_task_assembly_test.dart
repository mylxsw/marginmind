import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_tasks.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

import 'assistant_settings_test.dart' show Secrets;
import '../../../packages/mm_assistant/test/support.dart' show Reader;

class _Disk implements StudySetContentRepository {
  _Disk(this.path);
  final String path;
  @override
  String resolveFile(String studySetId, String fileName) => '$path/$fileName';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('production chat and summaries use independent frozen routes and disk RunStore', () async {
    final dir = await Directory.systemTemp.createTemp('assistant-task-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <Map<String, dynamic>>[];
    final sub = server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      bodies.add(body);
      final content = (body['messages'] as List).last['content'];
      final text = content is String ? content : (content as List).map((p) => p['text'] ?? '').join();
      final input = jsonDecode(text) as Map;
      final response = input['units'] == null
          ? 'Answer'
          : jsonEncode(
              AssistantSummary('Summary', [for (final u in input['units']) u['id'] as String], ['Decision'], [], [
                'Open',
              ]).toJson(),
            );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'fixture',
          'object': 'chat.completion',
          'model': body['model'],
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': response},
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 9, 'completion_tokens': 2, 'total_tokens': 11},
        }),
      );
      await request.response.close();
    });
    ProviderContainer? container;
    try {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final services = AssistantServicesStore(prefs, Secrets());
      final service = AssistantService(
        id: 'local',
        revision: 1,
        protocol: ServiceProtocol.ollama,
        name: 'Fixture',
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        localEnabled: true,
        models: [
          const ServiceModel(id: 'chat'),
          const ServiceModel(id: 'summary'),
          const ServiceModel(id: 'quick'),
        ],
      );
      await services.save(AssistantServices(services: [service], defaultModel: const ModelReference('local', 'chat')));
      final routing = AssistantRoutingStore(prefs, services);
      await routing.load();
      await routing.save(
        RoutingConfig(
          document: {
            'version': 1,
            'revision': 0,
            'defaults': {
              'heavy': {'serviceId': 'local', 'modelId': 'chat'},
              'quick': {'serviceId': 'local', 'modelId': 'quick'},
            },
            'heavyReasoning': 'off',
            'bindings': {
              for (final type in [TaskType.conversationSummarize, TaskType.documentSummarize])
                type.key: {
                  'mode': 'explicit',
                  'model': {'serviceId': 'local', 'modelId': 'summary'},
                },
            },
          },
        ),
        expectedRevision: 0,
      );
      final profiles = CapabilityProfiles();
      for (final model in service.models) {
        profiles.put(
          ModelCapabilityProfile(
            identity: serviceCapabilityIdentity(service, model),
            thinking: ThinkingCapability.switchable,
            tools: CapabilitySupport.supported,
            historyReplay: CapabilitySupport.supported,
            policies: {ReasoningPolicy.off: ReasoningRecipe.effortNone},
            evidence: CapabilityEvidence(
              source: CapabilityEvidenceSource.maintainedProfile,
              reference: 'test-only',
              wireVerified: true,
              semanticBasis: 'Synthetic loopback; no real model admission',
              verifiedAt: DateTime.utc(2026),
            ),
          ),
        );
      }
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          contentRepositoryProvider.overrideWithValue(_Disk(dir.path)),
          assistantServicesStoreProvider.overrideWithValue(services),
          assistantRoutingStoreProvider.overrideWithValue(routing),
          assistantCapabilityProfilesProvider.overrideWithValue(profiles),
        ],
      );
      final state = sdk.AgentState(sessionId: 'conversation');
      var conversation = Conversation(
        id: 'conversation',
        studySetId: 'study',
        model: service.configuration(service.models.first),
      );
      Future<void> run(Message question) async {
        final provider = Provider(
          (ref) => createPersistentAssistantRun(
            ref: ref,
            directory: dir.path,
            state: state,
            conversation: conversation,
            question: question,
            reader: Reader(),
            documents: [],
            mapId: 'map',
            revision: 0,
            parents: {'root': null},
          ),
        );
        await container!.read(provider).run(question.text).toList();
      }

      await run(Message(id: 'q1', requestId: 'r1', role: MessageRole.user, text: 'question'));
      conversation = conversation.copyWith(
        messages: [Message(id: 'a1', requestId: 'r1', role: MessageRole.agent, text: 'old answer')],
      );
      await run(
        Message(
          id: 'q2',
          requestId: 'r2',
          role: MessageRole.user,
          text: 'summarize',
          skill: 'summarize',
          summaryMessageIds: ['a1'],
        ),
      );
      await run(
        Message(
          id: 'q3',
          requestId: 'r3',
          role: MessageRole.user,
          text: 'summarize',
          skill: 'summarize',
          contexts: [
            const ContextItem(
              id: 'sel',
              kind: ContextKind.selection,
              documentId: 'doc',
              displayText: 'Text to summarize',
            ),
          ],
        ),
      );
      await run(
        Message(
          id: 'q4',
          requestId: 'r4',
          role: MessageRole.user,
          text: 'translate',
          skill: 'translate',
          contexts: [
            const ContextItem(
              id: 'sel',
              kind: ContextKind.selection,
              documentId: 'doc',
              displayText: 'Text to translate',
            ),
          ],
        ),
      );
      expect(bodies.map((body) => body['model']), ['chat', 'summary', 'summary', 'quick']);
      expect(bodies.last['reasoning_effort'], 'none');
      expect(bodies.take(3).every((body) => body['max_tokens'] == 8192 || body['max_completion_tokens'] == 8192), true);
      expect(await FileRunStore(dir).resumable(), isEmpty);
      expect(state.metadata['assistant.summaryCoverage.v1'], isNotEmpty);
      expect(await Directory('${dir.path}/ai-runs/v1').exists(), true);
    } finally {
      container?.dispose();
      await sub.cancel();
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
