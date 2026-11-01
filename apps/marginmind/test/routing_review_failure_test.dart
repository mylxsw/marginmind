import 'dart:async';

import 'package:mm_core/mm_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'assistant_routing_test.dart' show FailingPreferences;
import 'assistant_services_test.dart' show OfflineSecrets;

class FaultPreferences extends InMemorySharedPreferencesStore {
  FaultPreferences(super.data) : super.withData();
  int writes = 0;
  int failAt = -1;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${AssistantServicesStore.settingsKey}' && ++writes == failAt) return false;
    return super.setValue(valueType, key, value);
  }
}

class FaultSecrets extends OfflineSecrets {
  bool failAfterWrite = false;
  String? failDelete;
  Completer<void>? started, release;
  int mutations = 0;
  @override
  Future<void> write(String name, String value) async {
    mutations++;
    started?.complete();
    if (release != null) await release!.future;
    await super.write(name, value);
    if (failAfterWrite) throw StateError('Keychain verification failed');
  }

  @override
  Future<void> delete(String name) async {
    mutations++;
    if (name == failDelete) throw StateError('Keychain deletion failed');
    await super.delete(name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('credential write failure cannot retain the prior capability identity with a new key', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = OfflineSecrets();
    final store = AssistantServicesStore(prefs, secrets);
    await store.save(
      AssistantServices(
        services: [
          AssistantService(
            id: 's',
            protocol: ServiceProtocol.openai,
            name: 'Service',
            endpoint: 'https://fixture.test/v1',
            models: const [ServiceModel(id: 'm')],
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(container.dispose);
    await container.read(assistantServicesProvider.future);
    final platform = FailingPreferences({for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!});
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    await expectLater(
      container.read(assistantServicesProvider.notifier).saveKey('s', 'new-fixture-key'),
      throwsStateError,
    );
    await prefs.reload();
    final keyChanged = secrets.values[AssistantServicesStore.account('s')] == 'new-fixture-key';
    final revision = (await store.load()).services.single.revision;
    expect(
      keyChanged && revision == 0,
      isFalse,
      reason: 'A failed credential update must roll back the key or durably invalidate prior evidence.',
    );
  });
  group('credential invalidation fence', () {
    const id = 'legacy-claude';
    const reference = ModelReference(id, 'm');
    late SharedPreferences prefs;
    late FaultSecrets secrets;
    late AssistantServicesStore store;
    late ProviderContainer container;
    late AssistantServicesController actions;
    late FaultPreferences platform;
    late TaskModelResolver resolver;
    late ResolvedTaskConfig snapshot;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secrets = FaultSecrets()
        ..values.addAll({AssistantServicesStore.account(id): 'old-fixture', 'anthropic': 'legacy-fixture'});
      store = AssistantServicesStore(prefs, secrets);
      await store.save(
        AssistantServices(
          services: [
            AssistantService(
              id: id,
              protocol: ServiceProtocol.anthropic,
              name: 'Service',
              endpoint: 'https://fixture.test',
              models: const [ServiceModel(id: 'm')],
            ),
          ],
          defaultModel: reference,
        ),
      );
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          assistantSecretsProvider.overrideWithValue(secrets),
        ],
      );
      addTearDown(container.dispose);
      final catalog = await container.read(assistantServicesProvider.future);
      actions = container.read(assistantServicesProvider.notifier);
      final identity = serviceCapabilityIdentity(catalog.services.single, catalog.services.single.models.single);
      final profiles = CapabilityProfiles()
        ..put(
          ModelCapabilityProfile(
            identity: identity,
            thinking: ThinkingCapability.notApplicable,
            evidence: CapabilityEvidence(
              source: CapabilityEvidenceSource.maintainedProfile,
              reference: 'fixture',
              semanticBasis: 'Synthetic fixture only',
              wireVerified: true,
              verifiedAt: DateTime.utc(2026),
            ),
          ),
        );
      resolver = TaskModelResolver(catalog: store.load, profiles: profiles);
      snapshot = await resolver.resolve(
        TaskRequest<String>(
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
          modelOverride: reference,
        ),
        RoutingConfig(document: {'version': 1, 'revision': 0}),
      );
      platform = FaultPreferences({for (final key in prefs.getKeys()) 'flutter.$key': prefs.get(key)!});
      final previous = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = platform;
      addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    });

    Future<AssistantServices> consistentState() async {
      final cached = prefs.getString(AssistantServicesStore.settingsKey);
      await prefs.reload();
      expect(
        prefs.getString(AssistantServicesStore.settingsKey),
        cached,
        reason: 'Failed writes must restore the preferences cache.',
      );
      final durable = await store.load();
      expect(container.read(assistantServicesProvider).value!.toJson(), durable.toJson());
      expect(cached, isNot(contains('new-fixture')));
      return durable;
    }

    final operations = <String, Future<void> Function(AssistantServicesController)>{
      'saveKey': (c) => c.saveKey(id, 'new-fixture'),
      'updateDetails with key': (c) =>
          c.updateDetails(id, name: 'Edited', endpoint: 'https://edited.test', key: 'new-fixture'),
      'saveKey empty': (c) => c.saveKey(id, ''),
      'updateDetails empty key': (c) => c.updateDetails(id, name: 'Edited', key: '  '),
      'remove': (c) => c.remove(id),
    };
    for (final operation in operations.entries) {
      test('${operation.key}: failed fence leaves credentials and old identity unchanged', () async {
        platform.failAt = 1;
        final before = Map.of(secrets.values);
        await expectLater(operation.value(actions), throwsStateError);
        final durable = await consistentState();
        expect(secrets.mutations, 0);
        expect(secrets.values, before);
        expect(durable.services.single.revision, snapshot.capabilities.identity.serviceRevision);
        expect(durable.services.single.enabled, true);
        await resolver.validateCurrent(snapshot);
        // The failed queue is reusable, including a normal detail-only edit.
        await actions.updateDetails(id, name: 'Retried');
        expect((await consistentState()).services.single.name, 'Retried');
      });
      test('${operation.key}: failed final save retains disabled newer identity', () async {
        platform.failAt = 2;
        await expectLater(operation.value(actions), throwsStateError);
        final durable = await consistentState();
        expect(secrets.mutations, greaterThan(0));
        expect(durable.services.single.revision, greaterThan(snapshot.capabilities.identity.serviceRevision));
        expect(durable.services.single.enabled, false);
        expect(durable.services.single.name, 'Service');
        expect(durable.services.single.endpoint, 'https://fixture.test');
        await expectLater(resolver.validateCurrent(snapshot), throwsA(isA<ConfigurationFailure>()));
        // Explicit recovery has a fresh identity; the old evidence stays unusable.
        await actions.setEnabled(id, true);
        await expectLater(resolver.validateCurrent(snapshot), throwsA(isA<ConfigurationFailure>()));
        await consistentState();
      });
    }
    for (final operation in ['saveKey', 'updateDetails with key']) {
      test('$operation: Keychain write followed by failure leaves service disabled', () async {
        secrets.failAfterWrite = true;
        await expectLater(operations[operation]!(actions), throwsStateError);
        expect(secrets.values[AssistantServicesStore.account(id)], 'new-fixture');
        final durable = await consistentState();
        expect(durable.services.single.enabled, false);
        expect(durable.services.single.revision, greaterThan(snapshot.capabilities.identity.serviceRevision));
        await expectLater(resolver.validateCurrent(snapshot), throwsA(isA<ConfigurationFailure>()));
      });
    }
    for (final operation in ['saveKey empty', 'updateDetails empty key', 'remove']) {
      test('$operation: partial deletion of migrated accounts is fenced', () async {
        secrets.failDelete = 'anthropic';
        final epoch = container.read(assistantKeysProvider);
        await expectLater(operations[operation]!(actions), throwsStateError);
        expect(secrets.values.containsKey(AssistantServicesStore.account(id)), false);
        expect(secrets.values['anthropic'], 'legacy-fixture');
        expect(container.read(assistantKeysProvider), greaterThan(epoch));
        final durable = await consistentState();
        expect(durable.services.single.enabled, false);
        expect(durable.services.single.revision, greaterThan(snapshot.capabilities.identity.serviceRevision));
        await expectLater(resolver.validateCurrent(snapshot), throwsA(isA<ConfigurationFailure>()));
      });
    }
    test('in-flight credential mutation is disabled before Keychain changes', () async {
      secrets.started = Completer<void>();
      secrets.release = Completer<void>();
      final pending = actions.saveKey(id, 'new-fixture');
      await secrets.started!.future;
      final during = await consistentState();
      expect(during.services.single.enabled, false);
      await expectLater(resolver.validateCurrent(snapshot), throwsA(isA<ConfigurationFailure>()));
      expect(secrets.values[AssistantServicesStore.account(id)], 'old-fixture');
      secrets.release!.complete();
      await pending;
      final after = await consistentState();
      expect(after.services.single.enabled, true);
      expect(after.services.single.revision, greaterThan(during.services.single.revision));
      expect(after.defaultModel, reference);
    });
    test('successful credential update preserves the selected default across the fence', () async {
      await actions.upsert(
        AssistantService(
          id: 'other',
          protocol: ServiceProtocol.openai,
          name: 'Other',
          endpoint: 'https://other.test',
          models: const [ServiceModel(id: 'm')],
        ),
      );
      await actions.setDefault(reference);
      await actions.saveKey(id, 'new-fixture');
      final after = await consistentState();
      expect(after.defaultModel, reference);
      expect(after.services.first.enabled, true);
    });
  });
}
