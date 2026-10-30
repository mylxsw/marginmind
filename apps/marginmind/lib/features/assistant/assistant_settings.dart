import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import 'assistant_controller.dart';
import 'assistant_services.dart';

final assistantSecretsProvider = Provider<SecretStore>((ref) => const KeychainSecretStore());

/// Original Keychain accounts (before GUL-535), retained for migrated services
/// and conversations saved without a service ID.
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

/// Prefer a newly saved key, then the original account of a migrated service.
/// Never fall back across unrelated services of the same provider.
Future<String?> assistantServiceKey(SecretStore secrets, String? serviceId, AssistantProvider provider) async {
  if (provider == AssistantProvider.ollama) return null;
  if (serviceId == null) return secrets.read(legacyAssistantAccount(provider));
  final key = await secrets.read(AssistantServicesStore.account(serviceId));
  if (key != null || serviceId != AssistantServicesStore.legacyId(provider)) return key;
  return secrets.read(legacyAssistantAccount(provider));
}

Future<String?> assistantModelKey(SecretStore secrets, AssistantModel model) =>
    assistantServiceKey(secrets, model.serviceId, model.provider);

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

enum AssistantCredentialState { unconfigured, missingKey, unavailable, ready }

/// Missing configuration and inaccessible saved credentials need different
/// recovery instructions. An unavailable key is not an invalid provider key.
final assistantCredentialStateProvider = FutureProvider<AssistantCredentialState>((ref) async {
  ref.watch(assistantKeysProvider);
  final services = await ref.watch(assistantServicesProvider.future);
  final model = services.configuration;
  if (model == null) return AssistantCredentialState.unconfigured;
  if (model.provider == AssistantProvider.ollama) {
    return model.localEnabled ? AssistantCredentialState.ready : AssistantCredentialState.unconfigured;
  }
  try {
    final key = await assistantModelKey(ref.watch(assistantSecretsProvider), model);
    return key != null && key.isNotEmpty ? AssistantCredentialState.ready : AssistantCredentialState.missingKey;
  } on ResearchFailure {
    return AssistantCredentialState.unavailable;
  }
});

final assistantConfiguredProvider = FutureProvider<bool>(
  (ref) async => await ref.watch(assistantCredentialStateProvider.future) == AssistantCredentialState.ready,
);

/// Application composition point. Reader, graph snapshot and network adapters
/// are injected by the owning study-set surface; no global filesystem authority.
AssistantRunFactory assistantRunFactory({
  required SecretStore secrets,
  required StudySetReader reader,
  required List<Document> documents,
  required String mapId,
  required int Function() revision,
  required Map<String, String?> Function() parents,
  AssistantNetwork? network,
  AssistantServicesStore? services,
  Future<List<sdk.ImagePart>> Function(List<ContextItem>)? images,
}) => (agent, conversation, question) async {
  final config = services == null
      ? conversation.model
      : await services.resolve(conversation.model, quick: question.skill == 'translate');
  final key = await assistantModelKey(secrets, config);
  if (config.provider != AssistantProvider.ollama && (key == null || key.isEmpty)) {
    throw const ResearchFailure(ResearchFailureKind.authentication);
  }
  final connection = connectAssistant(config, key ?? '');
  try {
    return createAssistantRun(
      client: connection.client,
      model: config.model,
      images: await images?.call(question.contexts) ?? const [],
      // “Answer without tools” turns them off for one request.
      supportsTools: config.supportsTools && conversation.model.supportsTools,
      serviceHost: Uri.parse(config.endpoint).host,
      attachedContext: [
        ...question.contexts.map((c) => c.displayText),
        '当前学习集文档目录（可按需读取任意页）：${jsonEncode([
          for (final document in documents) {'documentId': document.id, 'title': document.title, 'pageCount': document.pageCount},
        ])}',
      ],
      state: agent,
      requestId: question.requestId,
      reader: reader,
      scope: scopeFromContexts(
        conversation.studySetId,
        question.contexts,
        documentIds: documents.map((document) => document.id),
      ),
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
