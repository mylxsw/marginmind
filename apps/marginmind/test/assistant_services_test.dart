import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_settings_test.dart' show Secrets;

class FailingSecrets extends Secrets {
  bool fail = true;
  @override
  Future<void> write(String name, String value) async {
    if (fail && name.startsWith('assistant.service.')) throw StateError('Keychain unavailable');
    await super.write(name, value);
  }
}

class Catalog extends ServiceCatalog {
  final result = Completer<ServiceModel>();
  @override
  Future<ServiceModel> probe(
    AssistantService service,
    ServiceModel model,
    String key, {
    CancellationToken? cancellation,
  }) => result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('migration copies all keys before commit, retries safely and preserves legacy data', () async {
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
    final secrets = FailingSecrets()..values.addAll({'anthropic': 'a', 'openai': 'b', 'compatible': 'c'});
    final store = AssistantServicesStore(prefs, secrets);
    await expectLater(store.load(), throwsStateError);
    expect(prefs.containsKey(AssistantServicesStore.settingsKey), false);
    secrets.fail = false;
    final value = await store.load();
    expect(value.defaultModel!.serviceId, 'legacy-responses');
    expect(value.configuration!.endpoint, 'https://proxy.example/v1/responses');
    expect(value.services.length, 3);
    expect(value.services.first.models.first.id, 'claude-opus-5-5');
    expect(secrets.values['assistant.service.legacy-compatible'], 'c');
    expect(secrets.values['compatible'], 'c');
    expect(prefs.getBool('assistant.online'), false);
    expect(prefs.getString('assistant.model.responses'), 'gpt');
    expect((await store.load()).toJson(), value.toJson());
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
    expect(c.read(assistantSettingsProvider).serviceId, 'two');
    expect(c.read(assistantSettingsProvider.notifier).models().length, 3);
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
    await c
        .read(assistantSettingsProvider.notifier)
        .configure(
          const AssistantSettings(
            provider: AssistantProvider.responses,
            model: 'gpt',
            endpoint: 'https://api.openai.com/v1/responses',
          ),
        );
    await c.read(assistantSettingsProvider.notifier).saveKey('legacy-key');
    expect((await c.read(assistantServicesProvider.future)).defaultModel!.serviceId, 'legacy-responses');
    expect(secrets.values[AssistantServicesStore.account('legacy-responses')], 'legacy-key');
    await c.read(assistantSettingsProvider.notifier).select(AssistantProvider.compatible);
    expect(c.read(assistantSettingsProvider).serviceId, 'two');
    await actions.remove('legacy-responses');
    expect(secrets.values.containsKey('openai'), false);
  });
  test('adding probes capabilities, persists results and refuses stale connection results', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance(), secrets = Secrets(), catalog = Catalog();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
        serviceCatalogProvider.overrideWithValue(catalog),
      ],
    );
    addTearDown(c.dispose);
    await c.read(assistantServicesProvider.future);
    final controller = c.read(assistantServicesProvider.notifier);
    final add = controller.addDiscoveredModel('legacy-claude', const ServiceModel(id: 'mini'));
    catalog.result.complete(const ServiceModel(id: 'mini', tools: ToolCapability.unsupported));
    await add;
    expect((await c.read(assistantServicesProvider.future)).services.first.models.last.supportsTools, false);
    await controller.setModelEnabled('legacy-claude', 'mini', false);
    expect(c.read(enabledAssistantModelsProvider)['legacy-claude']!.length, 1);
    final second = Catalog();
    c.updateOverrides([
      sharedPreferencesProvider.overrideWithValue(prefs),
      assistantSecretsProvider.overrideWithValue(secrets),
      serviceCatalogProvider.overrideWithValue(second),
    ]);
    final pending = controller.addDiscoveredModel('legacy-claude', const ServiceModel(id: 'other'));
    await Future<void>.delayed(Duration.zero);
    final service = (await c.read(assistantServicesProvider.future)).services.first;
    await controller.upsert(service.copyWith(endpoint: 'https://new.example/v1/messages'));
    second.result.complete(const ServiceModel(id: 'other'));
    await expectLater(pending, throwsStateError);
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
