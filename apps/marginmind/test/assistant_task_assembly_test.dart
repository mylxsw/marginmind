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

class _Network implements AssistantNetwork {
  int searched = 0, fetched = 0;
  @override
  Future<List<AssistantSearchResult>> search(String keywords, CancellationToken cancel) async {
    searched++;
    return [AssistantSearchResult('Candidate', Uri.parse('https://example.com/article'), 'Discovery only')];
  }

  @override
  Future<AssistantSource> fetch(Uri url, CancellationToken cancel) async {
    fetched++;
    return AssistantSource(
      id: 'body',
      version: 1,
      kind: 'snapshot',
      title: 'Body',
      url: url,
      paragraphs: {'p1': 'Actual body evidence'},
      snapshotFile: 'snapshot.md',
    );
  }

  @override
  Future<List<AssistantSource>> papers(String keywords, CancellationToken cancel) async => [];
}

void main() {
  test('production chat and summaries use independent frozen routes and disk RunStore', () async {
    final dir = await Directory.systemTemp.createTemp('assistant-task-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <Map<String, dynamic>>[];
    final sub = server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      bodies.add(body);
      final messages = body['messages'] as List;
      final userIndex = messages.lastIndexWhere((m) => m['role'] == 'user');
      final content = messages[userIndex]['content'];
      final text = content is String ? content : (content as List).map((p) => p['text'] ?? '').join();
      final input = jsonDecode(text) as Map;
      var response = input['units'] == null
          ? 'Answer'
          : jsonEncode(
              AssistantSummary('Summary', [for (final u in input['units']) u['id'] as String], ['Decision'], [], [
                'Open',
              ]).toJson(),
            );
      final toolCount = messages.skip(userIndex + 1).where((m) => m['role'] == 'tool').length;
      Map<String, dynamic>? tool;
      void invoke(String name, Map<String, dynamic> args) {
        tool = {
          'id': '$name-$toolCount',
          'type': 'function',
          'function': {'name': name, 'arguments': jsonEncode(args)},
        };
      }

      if (input['question'] == 'research entry') {
        if (toolCount == 0) {
          invoke('web_search', {'query': 'evidence research'});
        } else if (toolCount == 1) {
          invoke('fetch_source', {'url': 'https://example.com/article'});
        } else {
          response = jsonEncode({
            'claims': [
              {
                'text': 'Body finding [source:1]',
                'verified': true,
                'evidence': ['[source:1]'],
              },
            ],
            'conflicts': ['Disagreement'],
            'unresolved': ['Unknown'],
          });
        }
      } else if (input['question'] == 'review entry') {
        if (toolCount == 0) {
          invoke('read_pages', {'documentId': 'doc', 'from': 1, 'to': 1});
        } else if (toolCount == 1) {
          invoke('propose_map_edits', {
            'ops': [
              {
                'id': 'card',
                'kind': 'addReviewCard',
                'parentId': 'root',
                'question': 'Question [page:1]',
                'answer': 'Answer [page:1]',
              },
            ],
          });
        } else {
          response = 'Review ready [page:1]';
        }
      }
      final message = tool == null
          ? {'role': 'assistant', 'content': response}
          : {
              'role': 'assistant',
              'content': null,
              'tool_calls': [tool!],
            };
      final delta = tool == null
          ? {'content': response}
          : {
              'tool_calls': [
                {'index': 0, ...tool!},
              ],
            };
      final finish = tool == null ? 'stop' : 'tool_calls';
      if (body['stream'] == true) {
        request.response.headers.contentType = ContentType('text', 'event-stream');
        for (final chunk in [
          {
            'choices': [
              {'index': 0, 'delta': delta, 'finish_reason': null},
            ],
          },
          {
            'choices': [
              {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': finish},
            ],
            'usage': {'prompt_tokens': 9, 'completion_tokens': 2, 'total_tokens': 11},
          },
        ]) {
          request.response.write('data: ${jsonEncode(chunk)}\n\n');
        }
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'fixture',
          'object': 'chat.completion',
          'model': body['model'],
          'choices': [
            {'index': 0, 'message': message, 'finish_reason': finish},
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
          const ServiceModel(id: 'research'),
          const ServiceModel(id: 'review'),
        ],
      );
      final unrelated = AssistantService(
        id: 'cloud',
        name: 'No credentials',
        protocol: ServiceProtocol.openai,
        endpoint: 'https://unrelated.example/v1',
        models: [const ServiceModel(id: 'missing-key')],
      );
      await services.save(
        AssistantServices(services: [unrelated, service], defaultModel: const ModelReference('cloud', 'missing-key')),
      );
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
              TaskType.assistantChat.key: {
                'mode': 'explicit',
                'model': {'serviceId': 'local', 'modelId': 'chat'},
              },
              TaskType.research.key: {
                'mode': 'explicit',
                'model': {'serviceId': 'local', 'modelId': 'research'},
              },
              TaskType.reviewCards.key: {
                'mode': 'explicit',
                'model': {'serviceId': 'local', 'modelId': 'review'},
              },
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
            multimodal: CapabilitySupport.supported,
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
      final network = _Network();
      AssistantTaskOwner? lastOwner;
      final networkModels = <String>[];
      Future<void> run(Message question) async {
        final provider = Provider(
          (ref) => createPersistentAssistantRun(
            ref: ref,
            directory: dir.path,
            state: state,
            conversation: conversation,
            question: question,
            reader: Reader(),
            images: (_) async => question.id == 'q1' ? [sdk.ImagePart('AQID', 'image/png')] : [],
            networkFactory: (model, nativeSearch) async {
              networkModels.add(model.model);
              return network;
            },
            documents: [],
            mapId: 'map',
            revision: 0,
            parents: {'root': null},
          ),
        );
        final owner = container!.read(provider);
        lastOwner = owner;
        owner.permissions.onRequest = (_) async => true;
        final events = await owner.run(question.text).toList();
        if (question.id == 'q1') {
          expect(events.where((e) => e.eventType == sdk.StreamingEventType.modelChunkMessage), isNotEmpty);
          expect(jsonEncode(bodies.first), contains('data:image/png;base64,AQID'));
        }
      }

      await run(Message(id: 'q1', requestId: 'r1', role: MessageRole.user, text: 'question'));
      conversation = conversation.copyWith(
        archiveFields: {
          'taskRouting': {
            'version': 1,
            'assistantChat': {'serviceId': 'cloud', 'modelId': 'missing-key'},
          },
        },
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
      conversation = conversation.copyWith(
        online: true,
        model: AssistantModel.fromJson({...conversation.model.toJson(), 'supportsTools': false}),
      );
      await run(Message(id: 'q5', requestId: 'r5', role: MessageRole.user, text: 'research entry', skill: 'verify'));
      expect(networkModels, ['research']);
      expect(network.searched, 1);
      expect(network.fetched, 1);
      expect(lastOwner!.citations.items.any((c) => c.kind == 'snapshot'), true);
      conversation = conversation.copyWith(online: false);
      await run(
        Message(
          id: 'q6',
          requestId: 'r6',
          role: MessageRole.user,
          text: 'review entry',
          skill: 'quiz',
          contexts: [
            const ContextItem(id: 'sel', kind: ContextKind.document, documentId: 'doc', displayText: 'source'),
          ],
        ),
      );
      expect(lastOwner!.proposals.proposals, hasLength(1));
      expect(lastOwner!.proposals.proposals.values.single.operations.single.kind, MapEditKind.addReviewCard);
      expect(bodies.skip(4).map((b) => b['model']), ['research', 'research', 'research', 'review', 'review']);

      // A per-message chat override is also resolved independently of the
      // credential-less conversation override and old global default.
      await run(
        Message(
          id: 'q7',
          requestId: 'r7',
          role: MessageRole.user,
          text: 'override',
          taskModel: const ModelReference('local', 'chat'),
        ),
      );
      expect(bodies.last['model'], 'chat');
      expect(bodies[3]['reasoning_effort'], 'none');
      expect(bodies.take(3).every((body) => body['max_tokens'] == 8192 || body['max_completion_tokens'] == 8192), true);
      final purchased = bodies.length;
      await services.save(
        AssistantServices(
          services: [unrelated, service.copyWith(enabled: false)],
          defaultModel: const ModelReference('cloud', 'missing-key'),
        ),
      );
      await expectLater(
        run(
          Message(
            id: 'q8',
            requestId: 'r8',
            role: MessageRole.user,
            text: 'recheck',
            taskModel: const ModelReference('local', 'chat'),
          ),
        ),
        throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'current service', 'serviceOff')),
      );
      expect(bodies.length, purchased);
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
