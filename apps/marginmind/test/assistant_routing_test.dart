import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'assistant_services_test.dart' show OfflineSecrets;

class FailingPreferences extends InMemorySharedPreferencesStore {
  FailingPreferences(super.data) : super.withData();
  bool fail = true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      fail ? false : super.setValue(valueType, key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late OfflineSecrets secrets;
  late AssistantServicesStore services;
  late AssistantRoutingStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secrets = OfflineSecrets()..offline = true;
    services = AssistantServicesStore(prefs, secrets);
    await services.save(
      AssistantServices(
        services: [
          AssistantService(
            id: 's',
            protocol: ServiceProtocol.openai,
            name: 'Service',
            endpoint: 'https://fixture.test/v1',
            models: const [ServiceModel(id: 'm', name: 'Model')],
          ),
        ],
        defaultModel: const ModelReference('s', 'm'),
      ),
    );
    store = AssistantRoutingStore(prefs, services);
  });
  test('legacy default migrates both classes without Keychain access and reentry is idempotent', () async {
    final initial = await store.load();
    for (final category in TaskCategory.values) {
      expect(initial.defaultModel(category), const ModelReference('s', 'm'));
    }
    expect((initial.document['defaults'] as Map)['quick']['serviceLabel'], 'Service');
    final raw = prefs.getString(AssistantRoutingStore.settingsKey);
    expect((await AssistantRoutingStore(prefs, services).load()).toJson(), initial.toJson());
    expect(prefs.getString(AssistantRoutingStore.settingsKey), raw);
    expect(secrets.values, isEmpty);
  });
  test('invalid stored legacy default is retained rather than first enabled', () async {
    final raw = jsonDecode(prefs.getString(AssistantServicesStore.settingsKey)!) as Map<String, dynamic>;
    raw['default'] = {'serviceId': 'removed', 'modelId': 'm'};
    await prefs.setString(AssistantServicesStore.settingsKey, jsonEncode(raw));
    expect((await store.load()).defaultModel(TaskCategory.heavy), const ModelReference('removed', 'm'));
  });
  test('serialized CAS rejects stale drafts even across store instances and queue recovers', () async {
    final initial = await store.load();
    final other = AssistantRoutingStore(prefs, services);
    final first = store.save(initial, expectedRevision: 0);
    final second = other.save(initial, expectedRevision: 0);
    expect((await first).revision, 1);
    await expectLater(second, throwsA(isA<RoutingRevisionConflict>()));
    expect((await other.save(initial, expectedRevision: 1)).revision, 2);
  });
  test('unknown fields/tasks survive typed saves; missing defaults and explicit binding remain independent', () async {
    await prefs.setString(
      AssistantRoutingStore.settingsKey,
      jsonEncode({
        'version': 1,
        'revision': 4,
        'future': {'value': true},
        'defaults': {
          'future': {'serviceId': 'x', 'modelId': 'y'},
        },
        'bindings': {
          'future_task': {'mode': 'next-version', 'payload': true},
        },
      }),
    );
    final saved = await store.save(
      RoutingConfig(
        document: {
          'version': 1,
          'revision': 4,
          'bindings': {'assistant_chat': const TaskModelBinding.explicit(ModelReference('s', 'm')).toJson()},
        },
      ),
      expectedRevision: 4,
    );
    expect(saved.document['future'], {'value': true});
    expect((saved.document['bindings'] as Map)['future_task']['payload'], true);
    expect(saved.defaultModel(TaskCategory.heavy), isNull);
    expect(saved.binding(TaskType.assistantChat).model, const ModelReference('s', 'm'));
    expect((saved.document['bindings'] as Map)['assistant_chat']['model']['modelLabel'], 'Model');
  });
  test('unknown versions and malformed known bindings cannot be overwritten', () async {
    final draft = await store.load();
    for (final raw in [
      '{"version":2,"revision":8,"future":true}',
      '{"version":1,"revision":8,"bindings":{"assistant_chat":{"mode":"future"}}}',
    ]) {
      await prefs.setString(AssistantRoutingStore.settingsKey, raw);
      await expectLater(store.load(), throwsA(isA<ConfigurationFailure>()));
      await expectLater(store.save(draft, expectedRevision: 8), throwsA(isA<ConfigurationFailure>()));
      expect(prefs.getString(AssistantRoutingStore.settingsKey), raw);
    }
  });
  test('failed platform writes restore cached revision and allow retry', () async {
    final initial = await store.load();
    final platform = FailingPreferences({for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!});
    final original = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    await expectLater(store.save(initial, expectedRevision: 0), throwsStateError);
    expect((await store.load()).revision, 0);
    platform.fail = false;
    expect((await store.save(initial, expectedRevision: 0)).revision, 1);
  });
  test('deleting all services retains routing and deleted display snapshots', () async {
    final initial = await store.load();
    await services.save(AssistantServices());
    final saved = await store.save(
      RoutingConfig(
        document: {
          ...initial.document,
          'defaults': {
            'quick': const ModelReference('s', 'm').toJson(),
            'heavy': const ModelReference('s', 'm').toJson(),
          },
        },
      ),
      expectedRevision: initial.revision,
    );
    expect(saved.defaultModel(TaskCategory.quick), const ModelReference('s', 'm'));
    expect((saved.document['defaults'] as Map)['quick']['modelLabel'], 'Model');
    final resolver = TaskModelResolver(catalog: services.load, profiles: CapabilityProfiles());
    final row = await resolver.inspect(
      TaskRequest<String>(
        spec: TaskSpec(
          type: TaskType.titleGenerate,
          inputSchema: 'i',
          resultSchema: 'o',
          promptVersion: '1',
          schemaVersion: '1',
          completionRule: 'ok',
        ),
        input: {},
        inputFingerprint: 'test',
      ),
      saved,
    );
    expect(row.issue, RoutingIssue.serviceRemoved);
    expect(row.modelLabel, 'Model');
  });
  test('provider saves publish only committed state and credential edits revise the service', () async {
    secrets.offline = false;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(container.dispose);
    final initial = await container.read(assistantRoutingProvider.future);
    await container.read(assistantRoutingProvider.notifier).save(initial, expectedRevision: 0);
    expect(container.read(assistantRoutingProvider).value!.revision, 1);
    await expectLater(
      container.read(assistantRoutingProvider.notifier).save(initial, expectedRevision: 0),
      throwsA(isA<RoutingRevisionConflict>()),
    );
    expect(container.read(assistantRoutingProvider).value!.revision, 1);
    await container.read(assistantServicesProvider.future);
    await container.read(assistantServicesProvider.notifier).saveKey('s', 'fixture-key');
    expect((await services.load()).services.single.revision, 2);
    expect(prefs.getString(AssistantRoutingStore.settingsKey), isNot(contains('fixture-key')));
  });
  test('clearing owned binding fields retains unknown fields and inherits reasoning', () async {
    final initial = await store.load();
    final first = await store.save(
      RoutingConfig(
        document: {
          ...initial.document,
          'heavyReasoning': 'standard',
          'bindings': {
            'assistant_chat': const TaskModelBinding.explicit(
              ModelReference('s', 'm'),
              reasoning: ReasoningPolicy.deep,
            ).toJson()..['futureField'] = {'retained': true},
          },
        },
      ),
      expectedRevision: initial.revision,
    );
    final cleared = await store.save(
      RoutingConfig(
        document: {
          ...first.document,
          'bindings': {'assistant_chat': const TaskModelBinding.explicit(ModelReference('s', 'm')).toJson()},
        },
      ),
      expectedRevision: first.revision,
    );
    expect(cleared.binding(TaskType.assistantChat).reasoning, isNull);
    expect((cleared.document['bindings'] as Map)['assistant_chat']['futureField'], {'retained': true});
    final catalog = await services.load();
    final identity = serviceCapabilityIdentity(catalog.services.single, catalog.services.single.models.single);
    final profiles = CapabilityProfiles()
      ..put(
        ModelCapabilityProfile(
          identity: identity,
          thinking: ThinkingCapability.switchable,
          policies: {ReasoningPolicy.standard: ReasoningRecipe.effortMedium},
          evidence: CapabilityEvidence(
            source: CapabilityEvidenceSource.maintainedProfile,
            reference: 'fixture',
            semanticBasis: 'Synthetic fixture only',
            wireVerified: true,
            verifiedAt: DateTime.utc(2026),
          ),
        ),
      );
    final request = TaskRequest<String>(
      spec: TaskSpec(
        type: TaskType.assistantChat,
        inputSchema: 'i',
        resultSchema: 'o',
        promptVersion: '1',
        schemaVersion: '1',
        completionRule: 'ok',
      ),
      input: {},
      inputFingerprint: 'fixture',
    );
    final resolved = await TaskModelResolver(catalog: services.load, profiles: profiles).resolve(request, cleared);
    expect(resolved.policy.effective, ReasoningPolicy.standard);
    final inherited = await store.save(
      RoutingConfig(
        document: {
          ...cleared.document,
          'bindings': {
            'assistant_chat': {
              'mode': 'inherit',
              'model': const ModelReference('s', 'm').toJson(),
              'reasoning': 'deep',
            },
          },
        },
      ),
      expectedRevision: cleared.revision,
    );
    final raw = (inherited.document['bindings'] as Map)['assistant_chat'] as Map;
    expect(raw['mode'], 'inherit');
    expect(raw.containsKey('model'), false);
    expect(raw.containsKey('reasoning'), false);
    expect(raw['futureField'], {'retained': true});
    expect((await store.load()).binding(TaskType.assistantChat).mode, TaskBindingMode.inherit);
  });
}
