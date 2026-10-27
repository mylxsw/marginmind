import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'assistant_settings.dart';

/// Persistence is serialized by the controller. Secrets are copied before the
/// migration marker (the versioned JSON) is committed; legacy data is retained.
class AssistantServicesStore {
  AssistantServicesStore(this.prefs, this.secrets);
  final SharedPreferences prefs;
  final SecretStore secrets;
  static const settingsKey = 'assistant.services.v1';
  static String account(String id) => 'assistant.service.$id';
  static String legacyId(AssistantProvider provider) => 'legacy-${provider.name}';
  Future<AssistantServices>? _loading;
  Future<AssistantServices> load() => _loading ??= _load().whenComplete(() => _loading = null);
  Future<AssistantServices> _load() async {
    final json = prefs.getString(settingsKey);
    if (json != null) return AssistantServices.fromJson(jsonDecode(json));
    final services = <AssistantService>[];
    final selected = prefs.getString('assistant.provider') ?? 'claude';
    for (final p in AssistantProvider.values) {
      final storedModel = prefs.getString('assistant.model.${p.name}') ?? '';
      final model = storedModel.isEmpty ? legacyAssistantModel(p) : storedModel;
      final key = await secrets.read(legacyAssistantAccount(p));
      final endpoint =
          prefs.getString('assistant.endpoint.${p.name}') ??
          switch (p) {
            AssistantProvider.claude => 'https://api.anthropic.com/v1/messages',
            AssistantProvider.responses => 'https://api.openai.com/v1/responses',
            AssistantProvider.gemini => 'https://generativelanguage.googleapis.com/v1beta',
            AssistantProvider.ollama => 'http://localhost:11434/v1/chat/completions',
            _ => '',
          };
      if (p.name != selected && model.isEmpty && key == null && !prefs.containsKey('assistant.endpoint.${p.name}')) {
        continue;
      }
      final id = legacyId(p);
      if (key != null) await secrets.write(account(id), key);
      services.add(
        AssistantService(
          id: id,
          protocol: switch (p) {
            AssistantProvider.claude => ServiceProtocol.anthropic,
            AssistantProvider.gemini => ServiceProtocol.gemini,
            AssistantProvider.ollama => ServiceProtocol.ollama,
            _ => ServiceProtocol.openai,
          },
          name: p.name,
          endpoint: endpoint,
          responses: p == AssistantProvider.responses,
          localEnabled: prefs.getBool('assistant.localEnabled') ?? false,
          models: model.isEmpty ? [] : [ServiceModel(id: model)],
        ),
      );
    }
    final selectedService = services.where((s) => s.id == 'legacy-$selected').firstOrNull;
    final result = AssistantServices(
      services: services,
      defaultModel: selectedService?.models.isNotEmpty == true
          ? ModelReference(selectedService!.id, selectedService.models.first.id)
          : null,
    );
    if (!prefs.containsKey('assistant.search.v1')) {
      final endpoint = prefs.getString('assistant.searxng') ?? '';
      if (!await prefs.setString(
        'assistant.search.v1',
        jsonEncode(
          WebSearchSettings(
            backend: endpoint.isEmpty ? WebSearchBackend.model : WebSearchBackend.searxng,
            endpoint: endpoint,
          ).toJson(),
        ),
      )) {
        throw StateError('Settings write failed');
      }
    }
    await save(result);
    return result;
  }

  Future<void> save(AssistantServices value) async {
    if (!await prefs.setString(settingsKey, jsonEncode(value.toJson()))) throw StateError('Settings write failed');
  }

  Future<AssistantModel> resolve(AssistantModel old, {bool quick = false}) async {
    final value = await load();
    final id = old.serviceId ?? legacyId(old.provider);
    final service = value.services.where((s) => s.id == id && s.enabled).firstOrNull;
    if (service == null || (service.protocol == ServiceProtocol.ollama && !service.localEnabled)) {
      throw const ResearchFailure(ResearchFailureKind.unavailable, 'select_model');
    }
    final model = service.models.where((m) => m.id == old.model && m.enabled).firstOrNull;
    if (model == null) throw const ResearchFailure(ResearchFailureKind.unavailable, 'select_model');
    final current = service.configuration(model);
    return quick ? quickModelFor(service, current) : current;
  }
}

final assistantServicesStoreProvider = Provider<AssistantServicesStore>(
  (ref) => AssistantServicesStore(ref.watch(sharedPreferencesProvider), ref.watch(assistantSecretsProvider)),
);
final assistantServicesProvider = AsyncNotifierProvider<AssistantServicesController, AssistantServices>(
  AssistantServicesController.new,
);
final enabledAssistantModelsProvider = Provider<Map<String, List<AssistantModel>>>(
  (ref) => ref.watch(assistantServicesProvider).asData?.value.enabledModelsByService ?? {},
);
final serviceCatalogProvider = Provider<ServiceCatalog>((ref) => ServiceCatalog());

class AssistantServicesController extends AsyncNotifier<AssistantServices> {
  Future<void> _tail = Future.value();
  @override
  Future<AssistantServices> build() => ref.watch(assistantServicesStoreProvider).load();
  Future<void> _change(Future<AssistantServices> Function(AssistantServices value) operation) {
    final next = _tail.then((_) async {
      final value = await future;
      final result = await operation(value);
      await ref.read(assistantServicesStoreProvider).save(result);
      state = AsyncData(result);
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> upsert(AssistantService service) => _change((v) async => v.upsert(service));
  Future<void> setEnabled(String id, bool enabled) =>
      _change((v) async => v.upsert(_service(v, id).copyWith(enabled: enabled)));
  Future<void> setDefault(ModelReference model) => _change((v) async => v.select(model));
  AssistantService _service(AssistantServices value, String id) => value.services.firstWhere((s) => s.id == id);
  Future<void> remove(String id) => _change((v) async {
    final service = _service(v, id);
    await ref.read(assistantSecretsProvider).delete(AssistantServicesStore.account(id));
    if (id == AssistantServicesStore.legacyId(service.provider)) {
      await ref.read(assistantSecretsProvider).delete(legacyAssistantAccount(service.provider));
    }
    ref.read(assistantKeysProvider.notifier).changed();
    return v.remove(id);
  });
  Future<void> saveKey(String id, String key) => _change((v) async {
    _service(v, id);
    final secrets = ref.read(assistantSecretsProvider), account = AssistantServicesStore.account(id);
    if (key.trim().isEmpty) {
      await secrets.delete(account);
    } else {
      await secrets.write(account, key.trim());
    }
    ref.read(assistantKeysProvider.notifier).changed();
    return v;
  });
  Future<void> upsertModel(String id, ServiceModel model) => _change((v) async {
    final service = _service(v, id);
    return v.upsert(
      service.copyWith(
        models: service.models.any((m) => m.id == model.id)
            ? [for (final m in service.models) m.id == model.id ? model : m]
            : [...service.models, model],
      ),
    );
  });
  Future<void> setModelEnabled(String id, String modelId, bool enabled) => _change((v) async {
    final service = _service(v, id);
    return v.upsert(
      service.copyWith(
        models: [for (final model in service.models) model.id == modelId ? model.copyWith(enabled: enabled) : model],
      ),
    );
  });
  Future<void> removeModel(String id, String modelId) => _change((v) async {
    final service = _service(v, id);
    return v.upsert(service.copyWith(models: service.models.where((m) => m.id != modelId).toList()));
  });
  Future<void> addDiscoveredModel(String id, ServiceModel model, {CancellationToken? cancellation}) async {
    final service = _service(await future, id);
    final key = await ref.read(assistantSecretsProvider).read(AssistantServicesStore.account(id)) ?? '';
    final checked = await ref.read(serviceCatalogProvider).probe(service, model, key, cancellation: cancellation);
    await _change((value) async {
      final current = _service(value, id);
      if (current.endpoint != service.endpoint || current.protocol != service.protocol) {
        throw StateError('Service changed during capability probe');
      }
      return value.upsert(
        current.copyWith(
          models: [
            for (final m in current.models)
              if (m.id != checked.id) m,
            checked,
          ],
        ),
      );
    });
  }
}

final webSearchSettingsProvider = NotifierProvider<WebSearchSettingsController, WebSearchSettings>(
  WebSearchSettingsController.new,
);

class WebSearchSettingsController extends Notifier<WebSearchSettings> {
  static String account(WebSearchBackend backend) => 'assistant.search.${backend.name}';
  static const cloudflareAccount = 'assistant.search.cloudflare.account';
  @override
  WebSearchSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final raw = prefs.getString('assistant.search.v1');
    if (raw != null) return WebSearchSettings.fromJson(jsonDecode(raw));
    final endpoint = prefs.getString('assistant.searxng') ?? '';
    return WebSearchSettings(
      backend: endpoint.isEmpty ? WebSearchBackend.model : WebSearchBackend.searxng,
      endpoint: endpoint,
    );
  }

  Future<void> configure(WebSearchSettings value) async {
    if (!await ref.read(sharedPreferencesProvider).setString('assistant.search.v1', jsonEncode(value.toJson()))) {
      throw StateError('Settings write failed');
    }
    state = value;
  }

  Future<void> saveKey(WebSearchBackend backend, String key, {String? accountId}) async {
    final secrets = ref.read(assistantSecretsProvider);
    Future<void> put(String name, String value) =>
        value.trim().isEmpty ? secrets.delete(name) : secrets.write(name, value.trim());
    await put(account(backend), key);
    if (backend == WebSearchBackend.cloudflare && accountId != null) await put(cloudflareAccount, accountId);
  }
}

/// The address a new service starts with. OpenAI-compatible services start
/// at OpenAI's own API; most then change it.
String defaultServiceEndpoint(ServiceProtocol protocol) => switch (protocol) {
  ServiceProtocol.anthropic => 'https://api.anthropic.com',
  ServiceProtocol.openai => 'https://api.openai.com/v1',
  ServiceProtocol.gemini => 'https://generativelanguage.googleapis.com',
  ServiceProtocol.ollama => 'http://localhost:11434',
};

/// Whether the address can be left at its default (Anthropic, Gemini): the
/// settings hide it until “Use Custom Address”.
bool serviceEndpointOptional(ServiceProtocol protocol) =>
    protocol == ServiceProtocol.anthropic || protocol == ServiceProtocol.gemini;

bool _openAiHost(String endpoint) => Uri.tryParse(endpoint.trim())?.host == 'api.openai.com';

/// A service added from the settings tiles, with an ID no other service has.
/// Adding Ollama is the explicit permission to use this Mac's server.
AssistantService newAssistantService(ServiceProtocol protocol, String name, Iterable<String> taken) {
  final ids = taken.toSet();
  var n = DateTime.now().microsecondsSinceEpoch;
  while (ids.contains('service-$n')) {
    n++;
  }
  final endpoint = defaultServiceEndpoint(protocol);
  return AssistantService(
    id: 'service-$n',
    protocol: protocol,
    name: name,
    endpoint: endpoint,
    localEnabled: protocol == ServiceProtocol.ollama,
    responses: protocol == ServiceProtocol.openai && _openAiHost(endpoint),
  );
}

/// [service] at [endpoint]. OpenAI's own API is called through Responses
/// (it can search the web); other OpenAI-compatible ones through Chat
/// Completions. The service keeps its ID, models and key.
AssistantService serviceWithEndpoint(AssistantService service, String endpoint) => AssistantService(
  id: service.id,
  protocol: service.protocol,
  name: service.name,
  endpoint: endpoint,
  enabled: service.enabled,
  localEnabled: service.localEnabled,
  responses: service.protocol != ServiceProtocol.openai
      ? service.responses
      : _openAiHost(endpoint) || (service.responses && !_openAiHost(service.endpoint)),
  models: service.models,
);
