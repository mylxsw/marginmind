import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/map_task_factory.dart';
import 'package:marginmind/features/assistant/map_task_route.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

import 'assistant_settings_test.dart' show Secrets;
import 'quick_task_assembly_test.dart' show DiskRepository;

void main() {
  test(
    'production map factories resolve bindings, freeze children, persist partials, and reject unknown profiles',
    () async {
      final directory = await Directory.systemTemp.createTemp('map-runtime-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bodies = <Map<String, dynamic>>[];
      final sub = server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'fixture',
            'object': 'chat.completion',
            'model': 'fixture',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': 'fixture'},
                'finish_reason': 'stop',
              },
            ],
            'usage': {'prompt_tokens': 10, 'completion_tokens': 1, 'total_tokens': 11},
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
          id: 'loopback',
          revision: 1,
          protocol: ServiceProtocol.ollama,
          name: 'Fixture',
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          localEnabled: true,
          models: [
            const ServiceModel(id: 'default'),
            const ServiceModel(id: 'expand'),
            const ServiceModel(id: 'generate'),
          ],
        );
        await services.save(
          AssistantServices(services: [service], defaultModel: const ModelReference('loopback', 'default')),
        );
        final routing = AssistantRoutingStore(prefs, services);
        await routing.load();
        await routing.save(
          RoutingConfig(
            document: {
              'version': 1,
              'revision': 0,
              'defaults': {
                'heavy': {'serviceId': 'loopback', 'modelId': 'default'},
              },
              'bindings': {
                for (final name in ['expand', 'generate'])
                  'map_$name': {
                    'mode': 'explicit',
                    'model': {'serviceId': 'loopback', 'modelId': name},
                  },
              },
            },
          ),
          expectedRevision: 0,
        );
        final profiles = CapabilityProfiles();
        container = ProviderContainer(
          overrides: [
            contentRepositoryProvider.overrideWithValue(DiskRepository(directory.path)),
            sharedPreferencesProvider.overrideWithValue(prefs),
            assistantServicesStoreProvider.overrideWithValue(services),
            assistantRoutingStoreProvider.overrideWithValue(routing),
            assistantCapabilityProfilesProvider.overrideWithValue(profiles),
          ],
        );
        final factory = Provider<MapTaskSession>((ref) => MapTaskSession(ref, 'study', mapExpandSpec));
        final session = container.read(factory);
        final execute = session.execute;
        await expectLater(
          execute('Fixed instructions', {'stage': 'one'}, CancellationToken(), (_) => ValidationReport()),
          throwsA(isA<ConfigurationFailure>()),
        );
        expect(bodies, isEmpty);
        // Unknown identities are never admitted in production. Only this test
        // supplies synthetic evidence for its own loopback transport.
        for (final model in service.models) {
          profiles.put(
            ModelCapabilityProfile(
              identity: serviceCapabilityIdentity(service, model),
              thinking: ThinkingCapability.notApplicable,
              tools: CapabilitySupport.supported,
              historyReplay: CapabilitySupport.supported,
              contextTokens: 32000,
              outputTokens: 16000,
              evidence: CapabilityEvidence(
                source: CapabilityEvidenceSource.maintainedProfile,
                reference: 'test fixture',
                semanticBasis: 'Synthetic transport only',
                verifiedAt: DateTime.utc(2026),
                wireVerified: true,
              ),
            ),
          );
        }
        // Rejected admission made no run. Corrected evidence can now pin the session.
        final fresh = execute;
        final cacheIdentity = await session.cacheIdentity();
        await fresh(
          'Fixed instructions',
          {'stage': 'one'},
          CancellationToken(),
          (_) => ValidationReport(
            issues: [const ValidationIssue(code: 'missing', path: r'$', reason: 'Missing target')],
            missingInputIds: {'T2'},
          ),
        );
        // Changing settings cannot change a running multi-stage feature's route.
        final config = await routing.load();
        await routing.save(
          RoutingConfig(document: {...config.toJson(), 'bindings': <String, dynamic>{}}),
          expectedRevision: config.revision,
        );
        expect(await session.cacheIdentity(), cacheIdentity);
        await fresh('Fixed instructions', {'stage': 'repair'}, CancellationToken(), (_) => ValidationReport());
        final generateFactory = Provider<MapTaskSession>((ref) => MapTaskSession(ref, 'study', mapGenerateSpec));
        container
            .read(mapTaskChoicesProvider.notifier)
            .select(mapRouteKey('study', TaskType.mapGenerate), const ModelReference('loopback', 'generate'));
        final generateSession = container.read(generateFactory)..missingRangeIds = {'chapter:missing'};
        await generateSession.execute(
          'Fixed instructions',
          {'stage': 'generate'},
          CancellationToken(),
          (_) => ValidationReport(),
        );
        expect(bodies.map((b) => b['model']), ['expand', 'expand', 'generate']);
        expect(bodies.every((b) => b['max_completion_tokens'] == 8192), isTrue);
        final files = await Directory('${directory.path}/ai-runs/v1').list().toList();
        final manifests = <RunManifest>[];
        for (final file in files.whereType<File>().where(
          (f) => f.path.endsWith('.json') && !f.path.endsWith('.result.json'),
        )) {
          manifests.add(
            decodeRunManifest(Map<String, dynamic>.from(jsonDecode(await file.readAsString())['manifest'])),
          );
        }
        expect(manifests, hasLength(3));
        final partial = manifests.singleWhere((m) => m.status == RunStatus.partial && m.taskType == TaskType.mapExpand);
        final child = manifests.singleWhere((m) => m.context.parentRunId == partial.context.runId);
        final generated = manifests.singleWhere((m) => m.taskType == TaskType.mapGenerate);
        expect(generated.status, RunStatus.partial);
        expect(
          (await FileRunStore(Directory(directory.path)).loadResult(generated.context.runId))!['missingInputIds'],
          ['chapter:missing'],
        );
        expect(child.context.config.model, partial.context.config.model);
        expect(child.context.knowledgeVersions, partial.context.knowledgeVersions);
        expect((await FileRunStore(Directory(directory.path)).loadResult(partial.context.runId))!['missingInputIds'], [
          'T2',
        ]);
        final remote = AssistantService(
          id: 'remote',
          revision: 1,
          protocol: ServiceProtocol.openai,
          name: 'No credential',
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          models: [const ServiceModel(id: 'remote-model')],
        );
        await services.save(
          AssistantServices(services: [service, remote], defaultModel: const ModelReference('loopback', 'default')),
        );
        container
            .read(mapTaskChoicesProvider.notifier)
            .select(mapRouteKey('study', TaskType.mapGenerate), const ModelReference('remote', 'remote-model'));
        final noKeyFactory = Provider<MapTaskExecutor>((ref) => createMapTaskExecutor(ref, 'study', mapGenerateSpec));
        await expectLater(
          container.read(noKeyFactory)(
            'Fixed instructions',
            {'stage': 'no-key'},
            CancellationToken(),
            (_) => ValidationReport(),
          ),
          throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'secretUnavailable')),
        );
        expect(bodies, hasLength(3));
      } finally {
        container?.dispose();
        await sub.cancel();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
