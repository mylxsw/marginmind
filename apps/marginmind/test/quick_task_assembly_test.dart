import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/quick_tasks.dart';
import 'package:marginmind/features/assistant/task_run_store.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'assistant_settings_test.dart' show Secrets;
import '../../../packages/mm_assistant/test/word_lookup_test.dart' as words;

class DiskRepository extends InMemoryStudySetContentRepository {
  DiskRepository(this.directory) : super({});
  final String directory;
  @override
  String resolveFile(String studySetId, String fileName) => '$directory/$fileName';
}

void main() {
  test('production quick factories persist runs and send off on initial, HTTP retry and repair', () async {
    final dir = await Directory.systemTemp.createTemp('quick-assembly-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <Map<String, dynamic>>[];
    var call = 0;
    final replies = <String>['bad', '# 你好 {name}', '{}', jsonEncode(words.value()), 'x' * 25, 'Title', 'Offline title'];
    final sub = server.listen((request) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      if (call++ == 0) {
        request.response.statusCode = 503;
        request.response.headers.set('retry-after', '0');
        request.response.write('{"error":{"message":"fixture"}}');
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'fixture',
            'object': 'chat.completion',
            'model': 'fixture-model',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': replies.removeAt(0)},
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 9, 'completion_tokens': 2, 'total_tokens': 11},
          }),
        );
      }
      await request.response.close();
    });
    ProviderContainer? container;
    try {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secrets = Secrets();
      final services = AssistantServicesStore(prefs, secrets);
      final service = AssistantService(
        id: 'local',
        revision: 1,
        protocol: ServiceProtocol.ollama,
        name: 'Fixture',
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        localEnabled: true,
        models: [
          const ServiceModel(id: 'fixture-model'),
          const ServiceModel(id: 'title-model'),
        ],
      );
      await services.save(
        AssistantServices(services: [service], defaultModel: const ModelReference('local', 'fixture-model')),
      );
      final routing = AssistantRoutingStore(prefs, services);
      await routing.load();
      await routing.save(
        RoutingConfig(
          document: {
            'version': 1,
            'revision': 0,
            'defaults': {
              'quick': {'serviceId': 'local', 'modelId': 'fixture-model'},
            },
            'bindings': {
              'title_generate': {
                'mode': 'explicit',
                'model': {'serviceId': 'local', 'modelId': 'title-model'},
              },
            },
          },
        ),
        expectedRevision: 0,
      );
      final profiles = CapabilityProfiles();
      container = ProviderContainer(
        overrides: [
          contentRepositoryProvider.overrideWithValue(DiskRepository(dir.path)),
          sharedPreferencesProvider.overrideWithValue(prefs),
          assistantServicesStoreProvider.overrideWithValue(services),
          assistantRoutingStoreProvider.overrideWithValue(routing),
          assistantCapabilityProfilesProvider.overrideWithValue(profiles),
        ],
      );
      final execute = container.read(quickTaskExecutorProvider('study'));
      await expectLater(
        execute(TaskType.titleGenerate, {'question': 'question'}, CancellationToken()),
        throwsA(isA<ConfigurationFailure>()),
      );
      expect(bodies, isEmpty);
      // Synthetic admission is test-only. No production profile is installed.
      for (final model in service.models) {
        profiles.put(
          ModelCapabilityProfile(
            identity: serviceCapabilityIdentity(service, model),
            thinking: ThinkingCapability.switchable,
            policies: {ReasoningPolicy.off: ReasoningRecipe.effortNone},
            evidence: CapabilityEvidence(
              source: CapabilityEvidenceSource.maintainedProfile,
              reference: 'test-only',
              semanticBasis: 'Synthetic loopback fixture, no real provider verification',
              verifiedAt: DateTime.utc(2026),
              wireVerified: true,
            ),
          ),
        );
      }
      final translator = await container.read(selectionTranslatorProvider('study'))();
      final translated = await translator.translate(
        TranslationParagraph(
          documentId: 'doc',
          page: 1,
          index: 0,
          text: '# Hello {name}',
          fingerprint: 'input',
          rects: [],
        ),
        'zh',
        CancellationToken(),
        2048,
        sourceLanguage: 'en',
      );
      expect(translated.text, '# 你好 {name}');
      translator.close();
      final lookup = WordLookup.tasks(execute);
      expect(
        (await lookup.lookup(
          term: 'plateau',
          sentence: 'Progress plateaus.',
          targetLanguage: 'zh',
          model: null,
          cancel: CancellationToken(),
        )).lemma,
        'plateau',
      );
      expect(await generateAssistantTitle(execute, 'question'), 'Title');
      expect(bodies, hasLength(7));
      expect(bodies.map((b) => b['max_completion_tokens']), [2048, 2048, 2048, 8192, 8192, 64, 64]);
      expect(bodies.every((b) => b['reasoning_effort'] == 'none'), true);
      expect(bodies.every((b) => !b.containsKey('tools') || (b['tools'] as List).isEmpty), true);
      expect(bodies.take(5).every((b) => b['model'] == 'fixture-model'), true);
      expect(bodies.skip(5).every((b) => b['model'] == 'title-model'), true);
      final assembly = container.read(
        persistentTaskAssemblyProvider((directory: '${dir.path}/', tasks: container.read(quickTaskRegistryProvider))),
      );
      final files = await Directory('${dir.path}/ai-runs/v1').list().toList();
      final manifests = files.whereType<File>().where(
        (f) => f.path.endsWith('.json') && !f.path.endsWith('.result.json'),
      );
      expect(manifests, hasLength(3));
      for (final file in manifests) {
        final manifest = decodeRunManifest(
          Map<String, dynamic>.from(jsonDecode(await file.readAsString())['manifest']),
        );
        expect(manifest.status, RunStatus.completed);
        expect(manifest.usage.repairs, 1);
        expect(await assembly.runs.loadResult(manifest.context.runId), isNotNull);
      }
      // Offline admission uses the routed model, never the conversation/default model.
      await prefs.setBool('assistant.online.study', false);
      final before = bodies.length;
      expect(await generateAssistantTitle(execute, 'offline local'), isNotEmpty);
      expect(bodies.length, before + 1);
      final remote = AssistantService(
        id: service.id,
        revision: service.revision,
        protocol: ServiceProtocol.openai,
        name: service.name,
        endpoint: service.endpoint,
        models: service.models,
      );
      await services.save(
        AssistantServices(services: [remote], defaultModel: const ModelReference('local', 'fixture-model')),
      );
      secrets.values['assistant.service.local'] = 'test-key';
      for (final model in remote.models) {
        profiles.put(
          ModelCapabilityProfile(
            identity: serviceCapabilityIdentity(remote, model),
            thinking: ThinkingCapability.switchable,
            policies: {ReasoningPolicy.off: ReasoningRecipe.effortNone},
            evidence: CapabilityEvidence(
              source: CapabilityEvidenceSource.maintainedProfile,
              reference: 'test-only',
              semanticBasis: 'Synthetic offline test',
              verifiedAt: DateTime.utc(2026),
              wireVerified: true,
            ),
          ),
        );
      }
      await expectLater(
        generateAssistantTitle(execute, 'offline remote'),
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.network)),
      );
      expect(bodies.length, before + 1);
      await prefs.setBool('assistant.online.study', true);
      await expectLater(
        execute(TaskType.wordLookup, {
          'term': 'pain',
          'sentence': 'pain',
          'targetLanguage': 'zh',
          'sourceLanguage': 'fr',
          'contextOnly': false,
          'online': false,
        }, CancellationToken()),
        throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.network)),
      );
      expect(bodies.length, before + 1);
    } finally {
      container?.dispose();
      await sub.cancel();
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
