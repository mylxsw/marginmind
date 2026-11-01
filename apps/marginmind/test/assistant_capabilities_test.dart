import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'assistant_routing_test.dart' show FailingPreferences;
import '../../../packages/mm_assistant/test/support.dart' show ScriptClient, answer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_capabilities.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_settings_test.dart' show Secrets;

class PendingProbe extends ScriptClient {
  PendingProbe() : super([]);
  final started = Completer<void>();
  final response = Completer<sdk.ModelMessage>();
  @override
  Future<sdk.ModelMessage> generate(
    List<sdk.LLMMessage> messages, {
    List<sdk.Tool>? tools,
    sdk.ToolChoice? toolChoice,
    required sdk.ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) {
    started.complete();
    return response.future;
  }
}

void main() {
  late SharedPreferences prefs;
  late AssistantServicesStore services;
  late AssistantService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    services = AssistantServicesStore(prefs, Secrets());
    service = AssistantService(
      id: 's',
      protocol: ServiceProtocol.openai,
      name: 'Test',
      endpoint: 'https://api.openai.com/v1',
      revision: 1,
      models: [const ServiceModel(id: 'gpt-4.1-2025-04-14')],
    );
    await services.save(AssistantServices(services: [service], revision: 1));
  });
  test('production provider resolver loads maintained evidence and persists restart observation', () async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(Secrets()..values['assistant.service.s'] = 'secret'),
      ],
    );
    addTearDown(container.dispose);
    final resolver = container.read(assistantModelResolverProvider);
    final config = await resolver.resolve(
      TaskRequest<String>(spec: titleGenerationSpec, input: {'question': 'test'}, inputFingerprint: 'x'),
      RoutingConfig(
        document: {
          'version': 1,
          'revision': 0,
          'defaults': {'quick': ModelReference('s', service.models.single.id).toJson()},
        },
      ),
    );
    expect(config.policy.maxOutputTokens, 64);
    expect(config.policy.effective, ReasoningPolicy.off);
    final profiles = container.read(assistantCapabilityStoreProvider);
    await profiles.recordProbe(config.policy.identity, ReasoningPolicy.off);
    final restored = AssistantCapabilityProfiles(prefs, services);
    await restored.refresh();
    expect(restored.lookup(config.policy.identity).evidence!.admitsPolicy, isTrue);
    expect(restored.probeObservation(config.policy.identity)?['reasoning'], 'off');
    expect(prefs.getString(AssistantCapabilityProfiles.settingsKey), isNot(contains('secret')));
  });
  test('edits, credentials revision, deletion/reused ID and stale probes lose old evidence', () async {
    final profiles = AssistantCapabilityProfiles(prefs, services);
    await profiles.refresh();
    final old = serviceCapabilityIdentity(service, service.models.single);
    await profiles.recordProbe(old, ReasoningPolicy.off);
    var catalog = await services.load();
    catalog = catalog.upsert(service.copyWith(revision: 2));
    await services.save(catalog);
    await expectLater(profiles.recordProbe(old, ReasoningPolicy.off), throwsA(isA<ConfigurationFailure>()));
    await profiles.refresh();
    expect(profiles.lookup(old).thinking, ThinkingCapability.unknown);
    final current = serviceCapabilityIdentity(catalog.services.single, service.models.single);
    expect(profiles.probeObservation(current), isNull);
    catalog = catalog.remove('s').upsert(service);
    await services.save(catalog);
    await profiles.refresh();
    expect(profiles.lookup(current).thinking, ThinkingCapability.unknown);
    expect(catalog.services.single.revision, greaterThan(current.serviceRevision));
    await services.save(catalog.upsert(catalog.services.single.copyWith(endpoint: 'https://proxy.example/v1')));
    await profiles.refresh();
    final proxy = (await services.load()).services.single;
    final unknown = serviceCapabilityIdentity(proxy, proxy.models.single);
    await profiles.recordProbe(unknown, ReasoningPolicy.auto);
    expect(profiles.lookup(unknown).thinking, ThinkingCapability.unknown);
    expect(profiles.probeObservation(unknown), isNotNull);
  });
  test('failed persistence preserves durable data, cache and retry', () async {
    final profiles = AssistantCapabilityProfiles(prefs, services);
    await profiles.refresh();
    final before = prefs.getString(AssistantCapabilityProfiles.settingsKey);
    final platform = FailingPreferences({for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!});
    final original = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    final identity = serviceCapabilityIdentity(service, service.models.single);
    await expectLater(profiles.recordProbe(identity, ReasoningPolicy.off), throwsStateError);
    expect(prefs.getString(AssistantCapabilityProfiles.settingsKey), before);
    expect(profiles.probeObservation(identity), isNull);
    platform.fail = false;
    await profiles.recordProbe(identity, ReasoningPolicy.off);
    expect(profiles.probeObservation(identity), isNotNull);
  });
  test('real probe port rejects late acceptance after edit, and persists fresh acceptance', () async {
    final profiles = AssistantCapabilityProfiles(prefs, services);
    final resolver = TaskModelResolver(catalog: services.load, profiles: profiles);
    final client = PendingProbe();
    final probe = RoutingCapabilityProbe(
      resolver: resolver,
      key: (_) async => 'test',
      connection: (_, _, _) => AssistantConnection(client, Dio()),
    );
    final pending = probe.probe(
      ModelReference('s', service.models.single.id),
      cancellation: CancellationToken(),
      reasoning: ReasoningPolicy.off,
    );
    await client.started.future;
    final next = (await services.load()).upsert(service.copyWith(revision: 2));
    await services.save(next);
    client.response.complete(answer('OK'));
    await expectLater(pending, throwsA(isA<ConfigurationFailure>()));
    final fresh = RoutingCapabilityProbe(
      resolver: resolver,
      key: (_) async => 'test',
      connection: (_, _, _) => AssistantConnection(ScriptClient([answer('OK')]), Dio()),
    );
    final result = await fresh.probe(
      ModelReference('s', service.models.single.id),
      cancellation: CancellationToken(),
      reasoning: ReasoningPolicy.off,
    );
    expect(profiles.probeObservation(result.identity), isNotNull);
    expect(profiles.probeObservation(serviceCapabilityIdentity(service, service.models.single)), isNull);
  });
  test('known previous rule revision is rebuilt and old acceptance is discarded', () async {
    final profiles = AssistantCapabilityProfiles(prefs, services);
    await profiles.refresh();
    final identity = serviceCapabilityIdentity(service, service.models.single);
    await profiles.recordProbe(identity, ReasoningPolicy.off);
    final raw = prefs.getString(AssistantCapabilityProfiles.settingsKey)!;
    await prefs.setString(
      AssistantCapabilityProfiles.settingsKey,
      raw.replaceAll(maintainedCapabilityRevision, previousMaintainedCapabilityRevisions.single),
    );
    await profiles.refresh();
    expect(profiles.lookup(identity).tools, CapabilitySupport.supported);
    expect(profiles.probeObservation(identity), isNull);
    expect(prefs.getString(AssistantCapabilityProfiles.settingsKey), contains(maintainedCapabilityRevision));
  });
  test('concurrent instances merge observations without last-writer loss', () async {
    service = service.copyWith(
      models: [
        ...service.models,
        const ServiceModel(id: 'unknown'),
      ],
    );
    await services.save(AssistantServices(services: [service]));
    final a = AssistantCapabilityProfiles(prefs, services), b = AssistantCapabilityProfiles(prefs, services);
    final first = serviceCapabilityIdentity(service, service.models.first);
    final second = serviceCapabilityIdentity(service, service.models.last);
    await Future.wait([a.recordProbe(first, ReasoningPolicy.off), b.recordProbe(second, ReasoningPolicy.auto)]);
    await a.refresh();
    expect(a.probeObservation(first), isNotNull);
    expect(a.probeObservation(second), isNotNull);
    expect(a.lookup(second).evidence, isNull);
  });
  test('corrupt or future documents fail closed and are never overwritten', () async {
    final profiles = AssistantCapabilityProfiles(prefs, services);
    await profiles.refresh();
    for (final raw in [
      '{',
      jsonEncode({'version': 2}),
      jsonEncode({
        'version': 1,
        'rules': maintainedCapabilityRevision,
        'entries': [
          {'identity': {}, 'rule': null},
        ],
      }),
      jsonEncode({'version': 1, 'rules': 'future', 'entries': []}),
    ]) {
      await prefs.setString(AssistantCapabilityProfiles.settingsKey, raw);
      await expectLater(profiles.refresh(), throwsA(isA<ConfigurationFailure>()));
      expect(profiles.lookup(serviceCapabilityIdentity(service, service.models.single)).evidence, isNull);
      expect(prefs.getString(AssistantCapabilityProfiles.settingsKey), raw);
    }
  });
}
