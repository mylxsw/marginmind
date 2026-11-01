import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/workspace/document_translation_runtime.dart';
import 'package:marginmind/features/workspace/translation_schedulers.dart';
import 'package:mm_core/testing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/task_run_store.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_settings_test.dart' show Secrets;

void main() {
  test('removing translations invalidates Runtime cache scope across document reopening', () async {
    final directory = await Directory.systemTemp.createTemp('translation-cache-scope-');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        contentRepositoryProvider.overrideWithValue(DiskScopeRepository(directory.path)),
        assistantSecretsProvider.overrideWithValue(Secrets()),
        translationStoreProvider('set').overrideWith((ref) async => InMemoryTranslationStore()),
        translationConnectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    try {
      final factory = container.read(documentTranslatorFactoryProvider);
      final scope = (setId: 'set', documentId: 'doc', language: 'zh', model: null);
      final paragraphs = [
        TranslationParagraph(documentId: 'doc', page: 1, index: 0, fingerprint: 'p', text: 'Source', rects: const []),
      ];
      final first = await factory(scope, paragraphs) as RuntimeDocumentTranslator;
      final reopened = await factory(scope, paragraphs) as RuntimeDocumentTranslator;
      expect(reopened.scopeId, first.scopeId);
      final owners = container.read(translationSchedulersProvider('set'));
      await owners.removeTranslations('doc', 'zh');
      final afterRemoval = await factory(scope, paragraphs) as RuntimeDocumentTranslator;
      expect(afterRemoval.scopeId, isNot(first.scopeId));
      await owners.close();
    } finally {
      container.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('document translation freezes its function binding and reopens real disk results through SDK HTTP', () async {
    final directory = await Directory.systemTemp.createTemp('document-translation-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <Map<String, dynamic>>[];
    final subscription = server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      bodies.add(body);
      final input = jsonDecode((body['messages'] as List).last['content'] as String) as Map;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'fixture',
          'object': 'chat.completion',
          'model': 'heavy-model',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': jsonEncode({'id': input['id'], 'text': '译文 {name}'}),
              },
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 12, 'completion_tokens': 6, 'total_tokens': 18},
        }),
      );
      await request.response.close();
    });
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
          const ServiceModel(id: 'heavy-model'),
          const ServiceModel(id: 'quick-model'),
        ],
      );
      await services.save(
        AssistantServices(services: [service], defaultModel: const ModelReference('local', 'quick-model')),
      );
      final routing = AssistantRoutingStore(prefs, services);
      final current = await routing.load();
      await routing.save(
        RoutingConfig(
          document: {
            ...current.toJson(),
            'bindings': {
              'document_translate': {
                'mode': 'explicit',
                'model': {'serviceId': 'local', 'modelId': 'heavy-model'},
              },
            },
            'heavyReasoning': 'off',
          },
        ),
        expectedRevision: current.revision,
      );
      final profiles = CapabilityProfiles();
      final registry = TaskRegistry();
      registerDocumentTranslation(registry);
      final assembly = PersistentTaskAssembly(
        studySetDirectory: directory.path,
        tasks: registry,
        services: services,
        routing: routing,
        profiles: profiles,
      );
      var sequence = 0;
      RuntimeDocumentTranslator translator() => RuntimeDocumentTranslator(
        runtime: assembly.runtime,
        store: assembly.runs,
        reader: assembly.runs,
        freeze: (request, id, range) => assembly.freeze(request, runId: id, inputRange: range),
        scopeId: 'document',
        documentId: 'doc',
        language: 'zh',
        inputIds: ['p', 'q'],
        nextId: () => 'attempt-${sequence++}',
      );
      final paragraph = TranslationParagraph(
        documentId: 'doc',
        page: 1,
        index: 0,
        fingerprint: 'p',
        text: 'Translate this {name}',
        rects: const [],
      );
      await expectLater(
        translator().translatePack([paragraph], 'zh', CancellationToken(), 64),
        throwsA(isA<ConfigurationFailure>()),
      );
      expect(bodies, isEmpty);
      profiles.put(
        ModelCapabilityProfile(
          identity: serviceCapabilityIdentity(service, service.models.first),
          thinking: ThinkingCapability.switchable,
          contextTokens: 64000,
          outputTokens: 8192,
          policies: {ReasoningPolicy.off: ReasoningRecipe.effortNone},
          evidence: CapabilityEvidence(
            source: CapabilityEvidenceSource.maintainedProfile,
            reference: 'loopback-test-only',
            semanticBasis: 'Synthetic SDK transport, no production admission',
            wireVerified: true,
            verifiedAt: DateTime.utc(2026),
          ),
        ),
      );
      final first = translator();
      expect((await first.translatePack([paragraph], 'zh', CancellationToken(), 64)).texts, ['译文 {name}']);
      expect(bodies.single['model'], 'heavy-model');
      expect((await assembly.runs.load('document'))!.context.config.model.modelId, 'heavy-model');
      final changed = await routing.load();
      await routing.save(
        RoutingConfig(document: {...changed.toJson(), 'bindings': <String, dynamic>{}}),
        expectedRevision: changed.revision,
      );
      final nextParagraph = TranslationParagraph(
        documentId: 'doc',
        page: 1,
        index: 1,
        fingerprint: 'q',
        text: 'Next {name}',
        rects: const [],
      );
      expect((await first.translatePack([nextParagraph], 'zh', CancellationToken(), 64)).texts, ['译文 {name}']);
      expect((await translator().translatePack([paragraph], 'zh', CancellationToken(), 64)).texts, ['译文 {name}']);
      expect(bodies, hasLength(2));
      expect(bodies.every((body) => body['model'] == 'heavy-model'), isTrue);
      expect((await first.readUsage()).requests, 2);
      expect((await first.readUsage()).inputTokens, 24);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}

class DiskScopeRepository extends InMemoryStudySetContentRepository {
  DiskScopeRepository(this.directory);
  final String directory;
  @override
  String resolveFile(String studySetId, String fileName) => '$directory/$fileName';
}
