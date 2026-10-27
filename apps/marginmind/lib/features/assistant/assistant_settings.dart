import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import 'assistant_controller.dart';
import 'assistant_services.dart';

final assistantSecretsProvider = Provider<SecretStore>((ref) => const KeychainSecretStore());

/// Keychain accounts of the settings before services (GUL-535): read by the
/// one-time migration and by conversations saved without a service ID.
String legacyAssistantAccount(AssistantProvider provider) => switch (provider) {
  AssistantProvider.claude => 'anthropic',
  AssistantProvider.responses => 'openai',
  AssistantProvider.compatible => 'compatible',
  AssistantProvider.ollama => 'assistant.ollama',
  AssistantProvider.gemini => 'assistant.gemini',
};

/// The model the old settings used when none was typed: only Claude had one.
String legacyAssistantModel(AssistantProvider provider) =>
    provider == AssistantProvider.claude ? 'claude-opus-5-5' : '';

/// What a conversation starts with before any service is set up.
const unconfiguredAssistantModel = AssistantModel(provider: AssistantProvider.claude, model: '', endpoint: '');

/// The default model of new conversations; null until a model is enabled.
final assistantDefaultModelProvider = Provider<AssistantModel?>(
  (ref) => ref.watch(assistantServicesProvider).value?.configuration,
);

/// Whether answers may use the web: the composer's toggle, remembered per
/// study set (on by default; the old global setting is the fallback).
bool assistantOnlineDefault(Ref ref, String studySetId) {
  final prefs = ref.read(sharedPreferencesProvider);
  return prefs.getBool(assistantOnlineKey(studySetId)) ?? prefs.getBool('assistant.online') ?? true;
}

String assistantOnlineKey(String studySetId) => 'assistant.online.$studySetId';

/// Bumped whenever a service key is saved or removed.
final assistantKeysProvider = NotifierProvider<AssistantKeys, int>(AssistantKeys.new);

class AssistantKeys extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

/// Whether the assistant can answer: a default model, and a key for its
/// service unless it runs on this Mac.
final assistantConfiguredProvider = FutureProvider<bool>((ref) async {
  ref.watch(assistantKeysProvider);
  final services = await ref.watch(assistantServicesProvider.future);
  final model = services.configuration;
  if (model == null) return false;
  if (model.provider == AssistantProvider.ollama) return model.localEnabled;
  final key = await ref.watch(assistantSecretsProvider).read(AssistantServicesStore.account(model.serviceId!));
  return key != null && key.isNotEmpty;
});

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
        ? legacyAssistantAccount(config.provider)
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
      // “Answer without tools” turns them off for one request.
      supportsTools: config.supportsTools && conversation.model.supportsTools,
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
