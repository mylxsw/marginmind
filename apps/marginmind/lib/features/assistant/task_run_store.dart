import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'assistant_services.dart';
import 'assistant_routing.dart';
import 'assistant_settings.dart';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_assistant/mm_assistant.dart';

/// Study-set scoped production assembly shared by task migrations. Routing and
/// secret lookup remain injected by the host, never persisted in run manifests.
SdkAgentRuntime createPersistentTaskRuntime({
  required String studySetDirectory,
  required TaskRegistry tasks,
  VersionedKnowledgeRegistry? knowledge,
  required Future<RuntimeModelBinding> Function(RunContext) loadModel,
}) => SdkAgentRuntime(
  store: FileRunStore(Directory(studySetDirectory)),
  tasks: tasks,
  knowledge: knowledge ?? standardKnowledgeRegistry(),
  loadModel: loadModel,
);

/// Application composition for S3/S4. Catalog identity and credentials are read
/// at every dispatch; neither keys nor mutable catalog objects enter snapshots.
class PersistentTaskAssembly {
  PersistentTaskAssembly({
    required String studySetDirectory,
    required TaskRegistry tasks,
    required this.services,
    required this.routing,
    required CapabilityProfiles profiles,
    VersionedKnowledgeRegistry? knowledge,
  }) : runs = FileRunStore(Directory(studySetDirectory)),
       conversations = ConversationStorage(Directory(studySetDirectory)) {
    resolver = TaskModelResolver(
      catalog: services.load,
      profiles: profiles,
      credentialsAvailable: (service) async =>
          service.protocol == ServiceProtocol.ollama ||
          (await assistantServiceKey(services.secrets, service.id, service.provider))?.trim().isNotEmpty == true,
    );
    runtime = SdkAgentRuntime(
      store: runs,
      tasks: tasks,
      knowledge: knowledge ?? standardKnowledgeRegistry(),
      loadModel: loadModel,
    );
    usageIndex = ArchiveRoutingUsageIndex(
      conversations: () async => {
        for (final id in await conversations.list())
          id: Map<String, dynamic>.from(
            (await conversations.loadOrCreate(id, null)).metadata['assistant.view'] as Map? ?? {},
          ),
      },
      runs: runs.resumable,
    );
  }

  final AssistantServicesStore services;
  final AssistantRoutingStore routing;
  final FileRunStore runs;
  final ConversationStorage conversations;
  late final TaskModelResolver resolver;
  late final SdkAgentRuntime runtime;
  late final RoutingUsageIndex usageIndex;

  Future<RuntimeModelBinding> loadModel(RunContext context) async {
    final catalog = await services.load();
    final service = catalog.services.where((s) => s.id == context.config.model.serviceId).firstOrNull;
    final model = service?.models.where((m) => m.id == context.config.model.modelId).firstOrNull;
    if (service == null ||
        model == null ||
        !service.enabled ||
        !model.enabled ||
        (service.protocol == ServiceProtocol.ollama && !service.localEnabled) ||
        serviceCapabilityIdentity(service, model) != context.config.capabilities.identity) {
      throw const ConfigurationFailure('serviceConfigurationChanged');
    }
    final String? key;
    try {
      key = await assistantServiceKey(services.secrets, service.id, service.provider);
    } catch (_) {
      throw const ConfigurationFailure('secretUnavailable');
    }
    if (service.protocol != ServiceProtocol.ollama && (key == null || key.trim().isEmpty)) {
      throw const ConfigurationFailure('secretUnavailable');
    }
    return RuntimeModelBinding(model: service.configuration(model), key: key ?? '', serviceRevision: service.revision);
  }

  Future<RunContext> freeze<T>(
    TaskRequest<T> request, {
    required String runId,
    Map<String, String>? knowledgeVersions,
    Map<String, dynamic> inputRange = const {},
  }) async => RunContext(
    runId: runId,
    config: await resolver.resolve(request, await routing.load()),
    knowledgeVersions: knowledgeVersions ?? standardKnowledgeVersions(request.spec),
    inputRange: inputRange,
  );

  Future<RuntimeRunHandle<T>> start<T>(
    TaskRequest<T> request, {
    required String runId,
    Map<String, String>? knowledgeVersions,
    Map<String, dynamic> inputRange = const {},
  }) async => runtime.start(
    request,
    await freeze(request, runId: runId, knowledgeVersions: knowledgeVersions, inputRange: inputRange),
  );

  /// Explicit archive migration persists only the routing addition. The usage
  /// index performs the same interpretation read-only and never saves archives.
  Future<ModelReference?> migrateConversation(String conversationId) async {
    if (!await conversations.exist(conversationId)) throw StateError('Conversation missing');
    final state = await conversations.loadOrCreate(conversationId, null);
    final view = Map<String, dynamic>.from(state.metadata['assistant.view'] as Map? ?? {});
    final migrated = migrateConversationRouting(view);
    final model = conversationRoutingOverride(migrated, TaskType.assistantChat);
    if (!view.containsKey('taskRouting')) {
      state.metadata['assistant.view'] = migrated;
      await conversations.save(state);
    }
    return model;
  }
}

/// Uses the application's existing platform SecretStore (Keychain on Apple).
final persistentTaskAssemblyProvider =
    Provider.family<PersistentTaskAssembly, ({String directory, TaskRegistry tasks})>(
      (ref, scope) => PersistentTaskAssembly(
        studySetDirectory: scope.directory,
        tasks: scope.tasks,
        services: ref.watch(assistantServicesStoreProvider),
        routing: ref.watch(assistantRoutingStoreProvider),
        profiles: ref.watch(assistantCapabilityProfilesProvider),
      ),
    );
