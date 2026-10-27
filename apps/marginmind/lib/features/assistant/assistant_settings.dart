import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import 'assistant_controller.dart';
import 'assistant_services.dart';

class AssistantSettings {
  const AssistantSettings({
    this.provider = AssistantProvider.claude,
    this.model = '',
    this.endpoint = '',
    this.online = true,
    this.localEnabled = false,
    this.searxngEndpoint = '',
    this.serviceId,
    this.supportsTools = true,
  });
  final AssistantProvider provider;
  final String? serviceId;
  final bool supportsTools;
  final String model, endpoint, searxngEndpoint;
  final bool online, localEnabled;
  AssistantModel get configuration => AssistantModel(
    provider: provider,
    model: model,
    endpoint: endpoint,
    localEnabled: localEnabled,
    serviceId: serviceId,
    supportsTools: supportsTools,
  );
}

final assistantSecretsProvider = Provider<SecretStore>((ref) => const KeychainSecretStore());
final assistantSettingsProvider = NotifierProvider<AssistantSettingsController, AssistantSettings>(
  AssistantSettingsController.new,
);

class AssistantSettingsController extends Notifier<AssistantSettings> {
  @override
  AssistantSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final provider =
        AssistantProvider.values.where((p) => p.name == prefs.getString('assistant.provider')).firstOrNull ??
        AssistantProvider.claude;
    final raw = prefs.getString(AssistantServicesStore.settingsKey);
    if (raw != null) {
      final model = AssistantServices.fromJson(jsonDecode(raw)).configuration;
      if (model != null) {
        return AssistantSettings(
          provider: model.provider,
          model: model.model,
          endpoint: model.endpoint,
          serviceId: model.serviceId,
          supportsTools: model.supportsTools,
          localEnabled: model.localEnabled,
          online: prefs.getBool('assistant.online') ?? true,
          searxngEndpoint: prefs.getString('assistant.searxng') ?? '',
        );
      }
      return AssistantSettings(
        online: prefs.getBool('assistant.online') ?? true,
        searxngEndpoint: prefs.getString('assistant.searxng') ?? '',
      );
    }
    return saved(provider);
  }

  /// The settings saved for [provider], whether or not it is the current one.
  AssistantSettings saved(AssistantProvider provider) {
    final prefs = ref.read(sharedPreferencesProvider);
    return AssistantSettings(
      provider: provider,
      model: switch (prefs.getString('assistant.model.${provider.name}') ?? '') {
        '' => defaultModel(provider),
        final m => m,
      },
      endpoint:
          prefs.getString('assistant.endpoint.${provider.name}') ??
          switch (provider) {
            AssistantProvider.claude => 'https://api.anthropic.com/v1/messages',
            AssistantProvider.responses => 'https://api.openai.com/v1/responses',
            AssistantProvider.ollama => 'http://localhost:11434/v1/chat/completions',
            AssistantProvider.compatible => '',
            AssistantProvider.gemini => 'https://generativelanguage.googleapis.com/v1beta',
          },
      online: prefs.getBool('assistant.online') ?? true,
      localEnabled: prefs.getBool('assistant.localEnabled') ?? false,
      searxngEndpoint: prefs.getString('assistant.searxng') ?? '',
    );
  }

  /// The model to use when none was typed: only Claude has a default.
  static String defaultModel(AssistantProvider provider) =>
      provider == AssistantProvider.claude ? 'claude-opus-5-5' : '';

  /// Switches to [provider] with the model and endpoint saved for it.
  Future<void> select(AssistantProvider provider) async {
    final raw = ref.read(sharedPreferencesProvider).getString(AssistantServicesStore.settingsKey);
    if (raw != null) {
      final services = AssistantServices.fromJson(jsonDecode(raw));
      final model = services.enabledModels.where((m) => m.provider == provider).firstOrNull;
      if (model != null) {
        await ref.read(assistantServicesProvider.notifier).setDefault(ModelReference(model.serviceId!, model.model));
        await ref.read(sharedPreferencesProvider).setString('assistant.provider', provider.name);
        ref.invalidateSelf();
        return;
      }
    }
    await ref.read(sharedPreferencesProvider).setString('assistant.provider', provider.name);
    state = saved(provider);
  }

  /// Models the model menu lists: the current one and every other service
  /// with a saved model. The local model only while it is allowed.
  List<AssistantModel> models() {
    final raw = ref.read(sharedPreferencesProvider).getString(AssistantServicesStore.settingsKey);
    if (raw != null) return AssistantServices.fromJson(jsonDecode(raw)).enabledModels;
    final prefs = ref.read(sharedPreferencesProvider);
    return [
      for (final p in AssistantProvider.values)
        if (p == state.provider)
          state.configuration
        else if ((prefs.getString('assistant.model.${p.name}') ?? '').isNotEmpty &&
            (p != AssistantProvider.ollama || state.localEnabled))
          saved(p).configuration,
    ];
  }

  Future<void> configure(AssistantSettings settings) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final previousSearch = prefs.getString('assistant.searxng') ?? '';
    await prefs.setString('assistant.provider', settings.provider.name);
    await prefs.setString('assistant.model.${settings.provider.name}', settings.model);
    await prefs.setString('assistant.endpoint.${settings.provider.name}', settings.endpoint);
    await prefs.setBool('assistant.online', settings.online);
    await prefs.setBool('assistant.localEnabled', settings.localEnabled);
    await prefs.setString('assistant.searxng', settings.searxngEndpoint);
    if (prefs.containsKey(AssistantServicesStore.settingsKey)) {
      final controller = ref.read(assistantServicesProvider.notifier);
      final value = await ref.read(assistantServicesProvider.future);
      final id = settings.serviceId ?? AssistantServicesStore.legacyId(settings.provider);
      final existing = value.services.where((s) => s.id == id).firstOrNull;
      final model =
          existing?.models.where((m) => m.id == settings.model).firstOrNull ?? ServiceModel(id: settings.model);
      final service = AssistantService(
        id: id,
        protocol: switch (settings.provider) {
          AssistantProvider.claude => ServiceProtocol.anthropic,
          AssistantProvider.gemini => ServiceProtocol.gemini,
          AssistantProvider.ollama => ServiceProtocol.ollama,
          _ => ServiceProtocol.openai,
        },
        name: existing?.name ?? settings.provider.name,
        endpoint: settings.endpoint,
        localEnabled: settings.localEnabled,
        responses: settings.provider == AssistantProvider.responses,
        models: [
          for (final m in existing?.models ?? <ServiceModel>[])
            if (m.id != model.id) m,
          if (model.id.isNotEmpty) model,
        ],
      );
      await controller.upsert(service);
      if (model.id.isNotEmpty && (service.protocol != ServiceProtocol.ollama || service.localEnabled)) {
        await controller.setDefault(ModelReference(id, model.id));
      }
    }
    if (prefs.containsKey('assistant.search.v1') && previousSearch != settings.searxngEndpoint) {
      await ref
          .read(webSearchSettingsProvider.notifier)
          .configure(
            WebSearchSettings(
              backend: settings.searxngEndpoint.isEmpty ? WebSearchBackend.model : WebSearchBackend.searxng,
              endpoint: settings.searxngEndpoint,
            ),
          );
    }
    state = settings;
  }

  static String account(AssistantProvider provider) => switch (provider) {
    AssistantProvider.claude => 'anthropic',
    AssistantProvider.responses => 'openai',
    AssistantProvider.compatible => 'compatible',
    AssistantProvider.ollama => 'assistant.ollama',
    AssistantProvider.gemini => 'assistant.gemini',
  };
  Future<void> saveKey(String key) async {
    final store = ref.read(assistantSecretsProvider),
        name = state.serviceId == null ? account(state.provider) : AssistantServicesStore.account(state.serviceId!);
    if (key.trim().isEmpty) {
      await store.delete(name);
    } else {
      await store.write(name, key.trim());
    }
    if (ref.read(sharedPreferencesProvider).containsKey(AssistantServicesStore.settingsKey)) {
      await ref
          .read(assistantServicesProvider.notifier)
          .saveKey(state.serviceId ?? AssistantServicesStore.legacyId(state.provider), key);
    }
    ref.read(_assistantKeysProvider.notifier).changed();
  }
}

/// Whether the current service can be used: a model, and a key unless it is
/// the local model. Refreshed when settings change or a key is saved.
final assistantConfiguredProvider = FutureProvider<bool>((ref) async {
  ref.watch(_assistantKeysProvider);
  final settings = ref.watch(assistantSettingsProvider);
  if (settings.model.trim().isEmpty) return false;
  if (settings.provider == AssistantProvider.ollama) return settings.localEnabled;
  final key = await ref
      .watch(assistantSecretsProvider)
      .read(
        settings.serviceId == null
            ? AssistantSettingsController.account(settings.provider)
            : AssistantServicesStore.account(settings.serviceId!),
      );
  return key != null && key.isNotEmpty;
});

/// Bumped whenever a key is saved or removed.
final _assistantKeysProvider = NotifierProvider<_AssistantKeys, int>(_AssistantKeys.new);

class _AssistantKeys extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

/// Checks a service before it is saved: null when it answers, else why not.
typedef AssistantConnectionTester = Future<ResearchFailureKind?> Function(AssistantModel model, String key);

/// One tiny request through the same bounded transport as real runs.
final assistantConnectionTesterProvider = Provider<AssistantConnectionTester>(
  (ref) => (model, key) async {
    AssistantConnection? connection;
    try {
      connection = connectAssistant(model, key);
      await connection.client.generate([
        sdk.UserMessage.text('ping'),
      ], modelConfig: sdk.ModelConfig(model: model.model, maxTokens: 1, extra: {'store': false}));
      return null;
    } catch (e) {
      return assistantFailureKind(e);
    } finally {
      connection?.close();
    }
  },
);

/// Application composition point. Reader, graph snapshot and network adapters
/// are injected by the owning study-set surface; no global filesystem authority.
AssistantRunFactory assistantRunFactory({
  required SecretStore secrets,
  required StudySetReader reader,
  required String mapId,
  required int Function() revision,
  required Map<String, String?> Function() parents,
  AssistantNetwork? network,
  AssistantServicesStore? services,
}) => (agent, conversation, question) async {
  final config = services == null
      ? conversation.model
      : await services.resolve(conversation.model, quick: question.skill == 'translate');
  final key = await secrets.read(
    config.serviceId == null
        ? AssistantSettingsController.account(config.provider)
        : AssistantServicesStore.account(config.serviceId!),
  );
  if (config.provider != AssistantProvider.ollama && (key == null || key.isEmpty)) {
    throw const ResearchFailure(ResearchFailureKind.authentication);
  }
  final connection = connectAssistant(config, key ?? '');
  try {
    return createAssistantRun(
      client: connection.client,
      model: config.model,
      supportsTools: config.supportsTools,
      serviceHost: Uri.parse(config.endpoint).host,
      attachedContext: question.contexts.map((c) => c.displayText).toList(),
      state: agent,
      requestId: question.requestId,
      reader: reader,
      scope: scopeFromContexts(conversation.studySetId, question.contexts),
      mapId: mapId,
      baseRevision: revision(),
      parents: parents(),
      primaryDocumentId: question.contexts.map((c) => c.documentId).whereType<String>().firstOrNull,
      online: conversation.online,
      skill: question.skill,
      network: network,
      close: connection.close,
    );
  } catch (_) {
    connection.close();
    rethrow;
  }
};
