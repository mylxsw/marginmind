import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_settings_test.dart' show Secrets;

class LockedSecrets extends Secrets {
  @override
  Future<String?> read(String name) async => throw const ResearchFailure(ResearchFailureKind.authentication);
}

class OfflineSecrets extends Secrets {
  bool offline = false;
  @override
  Future<String?> read(String name) async {
    if (offline) throw StateError('Saving models must not read the keychain');
    return super.read(name);
  }
}

class RecordingServicesStore extends AssistantServicesStore {
  RecordingServicesStore(super.prefs, super.secrets);
  int writes = 0;
  bool fail = false;
  @override
  Future<void> save(AssistantServices value) async {
    writes++;
    if (fail) throw StateError('Local write failed');
    await super.save(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('migration never accesses keys and preserves legacy settings and credentials', () async {
    SharedPreferences.setMockInitialValues({
      'assistant.model.claude': '',
      'assistant.provider': 'responses',
      'assistant.model.responses': 'gpt',
      'assistant.endpoint.responses': 'https://proxy.example/v1/responses',
      'assistant.model.compatible': 'custom',
      'assistant.endpoint.compatible': 'https://other.example/v1',
      'assistant.localEnabled': true,
      'assistant.online': false,
      'assistant.searxng': 'http://localhost:8888/search',
    });
    final prefs = await SharedPreferences.getInstance();
    final secrets = OfflineSecrets()
      ..offline = true
      ..values.addAll({'anthropic': 'a', 'openai': 'b', 'compatible': 'c'});
    final store = AssistantServicesStore(prefs, secrets);
    final value = await store.load();
    expect(value.defaultModel!.serviceId, 'legacy-responses');
    expect(value.configuration!.endpoint, 'https://proxy.example/v1/responses');
    expect(value.services.length, 3);
    expect(value.services.first.models.first.id, 'claude-opus-5-5');
    expect(secrets.values, {'anthropic': 'a', 'openai': 'b', 'compatible': 'c'});
    expect(prefs.getBool('assistant.online'), false);
    expect(prefs.getString('assistant.model.responses'), 'gpt');
    expect((await store.load()).toJson(), value.toJson());
    secrets.offline = false;
    expect(await assistantModelKey(secrets, value.configuration!), 'b');
    final old = AssistantModel(provider: AssistantProvider.responses, model: 'gpt', endpoint: 'old');
    expect((await store.resolve(old)).serviceId, 'legacy-responses');
    final responseService = value.services.firstWhere((s) => s.id == 'legacy-responses');
    await store.save(
      value.upsert(
        responseService.copyWith(
          models: [
            ...responseService.models,
            const ServiceModel(id: 'gpt-mini'),
          ],
        ),
      ),
    );
    expect((await store.resolve(old, quick: true)).model, 'gpt-mini');
    expect((await store.resolve(old)).model, 'gpt');
    await store.save(value.remove('legacy-responses'));
    await expectLater(store.resolve(old), throwsA(isA<ResearchFailure>()));
    expect(old.endpoint, 'old');
    expect(jsonEncode(value.toJson()), isNot(contains('secret')));
  });
  test('locked keys do not break settings and legacy keys never leak into unrelated services', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(LockedSecrets()),
      ],
    );
    addTearDown(c.dispose);
    expect((await c.read(assistantServicesProvider.future)).services, isNotEmpty);
    expect(await c.read(assistantConfiguredProvider.future), isFalse);
    expect(await assistantServiceKey(LockedSecrets(), 'legacy-ollama', AssistantProvider.ollama), isNull);

    final secrets = Secrets()..values['anthropic'] = 'old';
    expect(await assistantServiceKey(secrets, 'legacy-claude', AssistantProvider.claude), 'old');
    expect(await assistantServiceKey(secrets, 'custom', AssistantProvider.claude), isNull);
    secrets.values['assistant.service.legacy-claude'] = 'new';
    expect(await assistantServiceKey(secrets, 'legacy-claude', AssistantProvider.claude), 'new');

    final editable = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(editable.dispose);
    await editable.read(assistantServicesProvider.future);
    await editable.read(assistantServicesProvider.notifier).saveKey('legacy-claude', '');
    expect(await assistantServiceKey(secrets, 'legacy-claude', AssistantProvider.claude), isNull);
  });
  test('Riverpod serial CRUD, default repair, isolated keys, model actions and old adapter', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = Secrets();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(c.dispose);
    await c.read(assistantServicesProvider.future);
    final actions = c.read(assistantServicesProvider.notifier);
    AssistantService service(String id) => AssistantService(
      id: id,
      protocol: ServiceProtocol.openai,
      name: id,
      endpoint: 'https://example.com/v1',
      models: [const ServiceModel(id: 'model')],
    );
    await Future.wait([actions.upsert(service('one')), actions.upsert(service('two'))]);
    await actions.saveKey('one', 'secret-one');
    await actions.saveKey('two', 'secret-two');
    await actions.setDefault(const ModelReference('two', 'model'));
    expect(c.read(assistantDefaultModelProvider)!.serviceId, 'two');
    expect((await c.read(assistantServicesProvider.future)).enabledModels.length, 3);
    expect(await c.read(assistantConfiguredProvider.future), isTrue);
    await actions.setEnabled('two', false);
    expect((await c.read(assistantServicesProvider.future)).defaultModel!.serviceId, 'legacy-claude');
    await actions.upsertModel('one', const ServiceModel(id: 'mini', tools: ToolCapability.unsupported));
    await actions.upsertModel('one', const ServiceModel(id: 'mini', name: 'Small', enabled: false));
    expect(c.read(enabledAssistantModelsProvider)['one']!.length, 1);
    await actions.removeModel('one', 'mini');
    await actions.saveKey('one', '');
    expect(secrets.values.containsKey(AssistantServicesStore.account('one')), false);
    await actions.remove('one');
    expect(secrets.values[AssistantServicesStore.account('two')], 'secret-two');
    await expectLater(actions.setDefault(const ModelReference('missing', 'model')), throwsArgumentError);
    await actions.setEnabled('two', true); // A rejected queued mutation does not poison later writes.
    // Removing the migrated service also removes the key of the old settings.
    secrets.values['openai'] = 'legacy-key';
    await actions.upsert(
      AssistantService(
        id: 'legacy-responses',
        protocol: ServiceProtocol.openai,
        name: 'OpenAI',
        endpoint: 'https://api.openai.com/v1/responses',
        responses: true,
        models: [const ServiceModel(id: 'gpt')],
      ),
    );
    await actions.remove('legacy-responses');
    expect(secrets.values.containsKey('openai'), false);
  });
  test('bulk model saving is local, atomic and preserves catalog capabilities', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance(), secrets = OfflineSecrets();
    final store = RecordingServicesStore(prefs, secrets);
    final c = ProviderContainer(overrides: [assistantServicesStoreProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    await c.read(assistantServicesProvider.future);
    final controller = c.read(assistantServicesProvider.notifier);
    secrets.offline = true;
    final writes = store.writes;
    await controller.addModels('legacy-claude', const [
      ServiceModel(id: 'mini'),
      ServiceModel(id: 'no-tools', tools: ToolCapability.unsupported),
      ServiceModel(id: 'with-tools', tools: ToolCapability.supported),
    ]);
    expect(store.writes, writes + 1);
    final saved = (await store.load()).services.first;
    expect(saved.models.map((m) => m.id), ['claude-opus-5-5', 'mini', 'no-tools', 'with-tools']);
    expect(saved.models[1].tools, ToolCapability.unknown);
    expect(saved.models[2].supportsTools, false);
    expect(saved.models[3].supportsTools, true);
    expect(c.read(enabledAssistantModelsProvider)['legacy-claude']!.length, 4);

    // Failed persistence leaves both the saved data and visible state intact.
    store.fail = true;
    await expectLater(controller.addModels('legacy-claude', const [ServiceModel(id: 'failed')]), throwsStateError);
    expect(
      c.read(assistantServicesProvider).value!.services.first.models.map((m) => m.id),
      saved.models.map((m) => m.id),
    );
    expect((await store.load()).services.first.models.map((m) => m.id), saved.models.map((m) => m.id));
    store.fail = false;
    // Uses the current service, preserving a concurrent rename and existing models.
    await Future.wait([
      controller.upsert(saved.copyWith(name: 'Renamed')),
      controller.addModels('legacy-claude', const [ServiceModel(id: 'mini', name: 'Mini'), ServiceModel(id: 'other')]),
    ]);
    final updated = c.read(assistantServicesProvider).value!.services.first;
    expect(updated.name, 'Renamed');
    expect(updated.models.where((m) => m.id == 'mini').single.name, 'Mini');
    expect(updated.models.last.id, 'other');
    expect(updated.models, hasLength(5));
    await controller.setModelEnabled('legacy-claude', 'mini', false);
    expect(c.read(enabledAssistantModelsProvider)['legacy-claude']!.length, 4);
  });
  test('new services, endpoints, and the configured state', () async {
    final service = newAssistantService(ServiceProtocol.openai, 'OpenAI', ['service-1']);
    expect(service.responses, isTrue);
    expect(service.endpoint, 'https://api.openai.com/v1');
    final proxy = serviceWithEndpoint(service, 'https://proxy.example/v1');
    expect(proxy.responses, isFalse);
    expect(proxy.id, service.id);
    expect(serviceWithEndpoint(proxy, 'https://api.openai.com/v1').responses, isTrue);
    // A legacy Responses proxy keeps its protocol when its address changes.
    final legacy = AssistantService(
      id: 'legacy-responses',
      protocol: ServiceProtocol.openai,
      name: 'x',
      endpoint: 'https://a.example/v1/responses',
      responses: true,
    );
    expect(serviceWithEndpoint(legacy, 'https://b.example/v1/responses').responses, isTrue);
    final anthropic = serviceWithEndpoint(
      newAssistantService(ServiceProtocol.anthropic, 'A', const []),
      'https://other.example',
    );
    expect(anthropic.responses, isFalse);
    expect(newAssistantService(ServiceProtocol.ollama, 'O', const []).localEnabled, isTrue);
    expect(serviceEndpointOptional(ServiceProtocol.gemini), isTrue);
    expect(serviceEndpointOptional(ServiceProtocol.openai), isFalse);
    for (final p in ServiceProtocol.values) {
      expect(Uri.parse(defaultServiceEndpoint(p)).host, isNotEmpty);
    }
    expect(legacyAssistantAccount(AssistantProvider.responses), 'openai');
    expect(legacyAssistantModel(AssistantProvider.claude), 'claude-opus-5-5');

    SharedPreferences.setMockInitialValues({'assistant.provider': 'ollama', 'assistant.model.ollama': 'llama'});
    final prefs = await SharedPreferences.getInstance(), secrets = Secrets();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(c.dispose);
    // Ollama not yet allowed: nothing to answer with.
    expect(await c.read(assistantConfiguredProvider.future), isFalse);
    final ollama = (await c.read(assistantServicesProvider.future)).services.firstWhere((s) => s.id == 'legacy-ollama');
    await c.read(assistantServicesProvider.notifier).upsert(ollama.copyWith(localEnabled: true));
    await c.read(assistantServicesProvider.notifier).setDefault(const ModelReference('legacy-ollama', 'llama'));
    expect(await c.read(assistantConfiguredProvider.future), isTrue);
    expect(assistantOnlineKey('s'), 'assistant.online.s');
  });

  test('search selection and Cloudflare secrets persist independently', () async {
    SharedPreferences.setMockInitialValues({'assistant.searxng': 'http://localhost:8888/search'});
    final prefs = await SharedPreferences.getInstance(), secrets = Secrets();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(webSearchSettingsProvider).backend, WebSearchBackend.searxng);
    final controller = c.read(webSearchSettingsProvider.notifier);
    await controller.configure(const WebSearchSettings(backend: WebSearchBackend.cloudflare));
    await controller.saveKey(WebSearchBackend.cloudflare, 'token', accountId: 'account-id');
    c.invalidate(webSearchSettingsProvider);
    expect(c.read(webSearchSettingsProvider).backend, WebSearchBackend.cloudflare);
    expect(secrets.values[WebSearchSettingsController.cloudflareAccount], 'account-id');
    expect(prefs.getString('assistant.search.v1'), isNot(contains('token')));
    expect(prefs.getString('assistant.search.v1'), isNot(contains('account-id')));
    await controller.saveKey(WebSearchBackend.cloudflare, '', accountId: '');
    expect(secrets.values, isEmpty);
  });
}
