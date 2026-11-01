import 'package:mm_core/mm_core.dart';

import '../providers.dart';
import '../services.dart';
import 'compiler.dart';

/// Display snapshots are kept alongside references, never used for lookup.
Map<String, dynamic> routeModelSnapshot(ModelReference model, AssistantServices catalog) {
  final service = catalog.services.where((s) => s.id == model.serviceId).firstOrNull;
  final entry = service?.models.where((m) => m.id == model.modelId).firstOrNull;
  return {
    ...model.toJson(),
    'serviceLabel': service?.name ?? model.serviceId,
    'modelLabel': entry?.displayName ?? model.modelId,
  };
}

CapabilityIdentity serviceCapabilityIdentity(
  AssistantService service,
  ServiceModel model, {
  String adapterVersion = modelPolicyAdapterVersion,
}) {
  final protocol = switch (service.provider) {
    AssistantProvider.claude => ModelProtocol.anthropicMessages,
    AssistantProvider.responses => ModelProtocol.responses,
    AssistantProvider.gemini => ModelProtocol.gemini,
    AssistantProvider.ollama => ModelProtocol.ollamaChat,
    AssistantProvider.compatible => ModelProtocol.chatCompletions,
  };
  return CapabilityIdentity(
    model: ModelReference(service.id, model.id),
    protocol: protocol,
    endpointFingerprint: modelEndpointFingerprint(protocol, service.endpoint),
    adapterVersion: adapterVersion,
    serviceRevision: service.revision,
  );
}

enum RoutingIssue {
  none,
  unset,
  deleted,
  modelOff,
  serviceOff,
  serviceRemoved,
  secretUnavailable,
  thinkingAlwaysOn,
  capabilityMissing,
  unknown,
  invalidConfiguration,
}

class RoutingRowState {
  const RoutingRowState({
    required this.effective,
    required this.source,
    required this.issue,
    this.config,
    this.failureCode,
    this.serviceLabel,
    this.modelLabel,
  });
  final ModelReference? effective;
  final RoutingSource source;
  final RoutingIssue issue;
  final ResolvedTaskConfig? config;
  final String? failureCode, serviceLabel, modelLabel;
  bool get ready => issue == RoutingIssue.none;
}

/// The resolver reads current catalog/credentials per dispatch. Its result has
/// no mutable service object or secret, so editing settings cannot change a run.
class TaskModelResolver implements ModelResolver {
  TaskModelResolver({required this.catalog, required this.profiles, this.credentialsAvailable});
  final Future<AssistantServices> Function() catalog;
  final CapabilityProfiles profiles;
  final Future<bool> Function(AssistantService service)? credentialsAvailable;
  static const compiler = DefaultProviderPolicyCompiler();

  @override
  Future<ResolvedTaskConfig> resolve<T>(TaskRequest<T> request, RoutingConfig routing) async {
    final row = await inspect(request, routing);
    if (!row.ready) throw ConfigurationFailure(row.failureCode ?? row.issue.name);
    return row.config!;
  }

  Future<RoutingRowState> inspect<T>(TaskRequest<T> request, RoutingConfig routing) async {
    ModelReference? selected;
    var source = RoutingSource.categoryDefault;
    Map? snapshot;
    try {
      final binding = routing.binding(request.spec.type);
      final ReasoningPolicy reasoning;
      if (request.modelOverride != null) {
        selected = request.modelOverride;
        source = RoutingSource.explicitRequest;
        reasoning = request.reasoning ?? routing.heavyReasoning;
      } else if (binding.mode == TaskBindingMode.explicit) {
        selected = binding.model;
        source = RoutingSource.functionBinding;
        snapshot = ((routing.document['bindings'] as Map?)?[request.spec.type.key] as Map?)?['model'] as Map?;
        reasoning = request.reasoning ?? binding.reasoning ?? routing.heavyReasoning;
      } else {
        selected = routing.defaultModel(request.spec.category);
        snapshot = (routing.document['defaults'] as Map?)?[request.spec.category.name] as Map?;
        reasoning = request.reasoning ?? routing.heavyReasoning;
      }
      RoutingRowState failure(RoutingIssue issue, [String? code]) => RoutingRowState(
        effective: selected,
        source: source,
        issue: issue,
        failureCode: code ?? issue.name,
        serviceLabel: snapshot?['serviceLabel'] as String? ?? selected?.serviceId,
        modelLabel: snapshot?['modelLabel'] as String? ?? selected?.modelId,
      );
      if (selected == null) return failure(RoutingIssue.unset);
      final services = await catalog();
      final service = services.services.where((s) => s.id == selected!.serviceId).firstOrNull;
      if (service == null) return failure(RoutingIssue.serviceRemoved);
      if (!service.enabled || (service.protocol == ServiceProtocol.ollama && !service.localEnabled)) {
        return failure(RoutingIssue.serviceOff);
      }
      final model = service.models.where((m) => m.id == selected!.modelId).firstOrNull;
      if (model == null) return failure(RoutingIssue.deleted);
      if (!model.enabled) return failure(RoutingIssue.modelOff);
      if (credentialsAvailable != null) {
        try {
          if (!await credentialsAvailable!(service)) return failure(RoutingIssue.secretUnavailable);
        } catch (_) {
          return failure(RoutingIssue.secretUnavailable);
        }
      }
      snapshot = {'serviceLabel': service.name, 'modelLabel': model.displayName};
      final identity = serviceCapabilityIdentity(service, model);
      final capabilities = profiles.lookup(identity);
      validateTaskCapabilities(request.spec, capabilities);
      final policy = compiler.compile(
        category: request.spec.category,
        requested: reasoning,
        identity: identity,
        capabilities: capabilities,
      );
      final config = ResolvedTaskConfig(
        capabilities: capabilities,
        policy: policy,
        routingRevision: routing.revision,
        source: source,
        serviceLabel: service.name,
        modelLabel: model.displayName,
      );
      return RoutingRowState(
        effective: selected,
        source: source,
        issue: RoutingIssue.none,
        config: config,
        serviceLabel: service.name,
        modelLabel: model.displayName,
      );
    } on ConfigurationFailure catch (e) {
      final issue = switch (e.code) {
        'thinkingCannotDisable' => RoutingIssue.thinkingAlwaysOn,
        'unverifiedCapabilities' || 'staleCapabilities' => RoutingIssue.unknown,
        'unsupportedReasoningPolicy' ||
        'unsupportedProtocolRecipe' ||
        'sdkHistoryReplayUnsupported' => RoutingIssue.capabilityMissing,
        _ =>
          e.code.endsWith(':unknown')
              ? RoutingIssue.unknown
              : e.code.endsWith(':unsupported')
              ? RoutingIssue.capabilityMissing
              : RoutingIssue.invalidConfiguration,
      };
      return RoutingRowState(
        effective: selected,
        source: source,
        issue: issue,
        failureCode: e.code,
        serviceLabel: snapshot?['serviceLabel'] as String? ?? selected?.serviceId,
        modelLabel: snapshot?['modelLabel'] as String? ?? selected?.modelId,
      );
    } on FormatException {
      return RoutingRowState(
        effective: selected,
        source: source,
        issue: RoutingIssue.invalidConfiguration,
        failureCode: 'invalidRoutingDocument',
      );
    } on ArgumentError {
      return RoutingRowState(
        effective: selected,
        source: source,
        issue: RoutingIssue.invalidConfiguration,
        failureCode: 'invalidRoutingDocument',
      );
    } on TypeError {
      return RoutingRowState(
        effective: selected,
        source: source,
        issue: RoutingIssue.invalidConfiguration,
        failureCode: 'invalidRoutingDocument',
      );
    }
  }

  /// Call before every new dispatch, including resumed/repaired requests.
  Future<void> validateCurrent(ResolvedTaskConfig snapshot) async {
    final services = await catalog();
    final service = services.services.where((s) => s.id == snapshot.model.serviceId).firstOrNull;
    final model = service?.models.where((m) => m.id == snapshot.model.modelId).firstOrNull;
    if (service == null ||
        model == null ||
        !service.enabled ||
        !model.enabled ||
        (service.protocol == ServiceProtocol.ollama && !service.localEnabled) ||
        serviceCapabilityIdentity(service, model) != snapshot.capabilities.identity) {
      throw const ConfigurationFailure('serviceConfigurationChanged');
    }
  }

  Set<ReasoningPolicy> reasoningOptions(ModelCapabilityProfile profile) => Set.unmodifiable({
    for (final reasoning in ReasoningPolicy.values)
      if (_compiles(profile, reasoning)) reasoning,
  });
  bool _compiles(ModelCapabilityProfile profile, ReasoningPolicy reasoning) {
    try {
      compiler.compile(
        category: TaskCategory.heavy,
        requested: reasoning,
        identity: profile.identity,
        capabilities: profile,
      );
      return true;
    } on ConfigurationFailure {
      return false;
    }
  }
}

enum RoutingUsageKind { categoryDefault, functionBinding, conversationOverride, recoverableRun }

class RoutingUse {
  const RoutingUse(this.kind, this.id, this.model);
  final RoutingUsageKind kind;
  final String id;
  final ModelReference model;
}

/// Hosts implement this read-only port with their archive/run index. No Runtime
/// instance is required, and omitted indexes cannot silently underreport users.
abstract interface class RoutingUsageIndex {
  Future<List<RoutingUse>> listModelUses();
}

/// Conservative model-usage predicate for archive/RunStore composition. Partial
/// runs can retry missing work; failed runs with checkpoints may replay through
/// their adapter. This is an impact query, not authorization to execute a run.
bool routingRunMayResume(RunManifest run) => runMayResume(run);

/// Reads archive JSON and run manifests through indexes, without importing SDK
/// storage or the Runtime. Corrupt/unknown archives fail the query rather than
/// telling a deletion dialog that nothing uses the model.
class ArchiveRoutingUsageIndex implements RoutingUsageIndex {
  ArchiveRoutingUsageIndex({required this.conversations, required this.runs});
  final Future<Map<String, Map<String, dynamic>>> Function() conversations;
  final Future<List<RunManifest>> Function() runs;
  @override
  Future<List<RoutingUse>> listModelUses() async {
    final uses = <RoutingUse>[];
    for (final entry in (await conversations()).entries) {
      final model = conversationRoutingOverride(entry.value, TaskType.assistantChat);
      if (model != null) uses.add(RoutingUse(RoutingUsageKind.conversationOverride, entry.key, model));
    }
    for (final run in await runs()) {
      if (routingRunMayResume(run)) {
        uses.add(RoutingUse(RoutingUsageKind.recoverableRun, run.context.runId, run.context.config.model));
      }
    }
    return List.unmodifiable(uses);
  }
}

class RoutingUsage {
  RoutingUsage({required this.routing, required this.index});
  final Future<RoutingConfig> Function() routing;
  final RoutingUsageIndex index;
  Future<List<RoutingUse>> of({ModelReference? model, String? serviceId}) async {
    if ((model == null) == (serviceId == null)) throw ArgumentError('Supply model or serviceId');
    final config = await routing();
    final uses = <RoutingUse>[];
    for (final category in TaskCategory.values) {
      final ref = config.defaultModel(category);
      if (ref != null) uses.add(RoutingUse(RoutingUsageKind.categoryDefault, category.name, ref));
    }
    // Include forward-version task keys too: deleting a service must not hide them.
    for (final entry in ((config.document['bindings'] as Map?) ?? {}).entries) {
      final binding = TaskModelBinding.fromJson(Map<String, dynamic>.from(entry.value as Map));
      if (binding.model != null) {
        uses.add(RoutingUse(RoutingUsageKind.functionBinding, entry.key as String, binding.model!));
      }
    }
    uses.addAll(await index.listModelUses());
    return List.unmodifiable(uses.where((u) => model != null ? u.model == model : u.model.serviceId == serviceId));
  }
}

/// Archive migration is idempotent and preserves messages/unknown fields. A
/// present null explicitly means "follow settings"; it must not resurrect legacy model.
Map<String, dynamic> migrateConversationRouting(Map<String, dynamic> view) {
  if (view.containsKey('taskRouting')) return freezeAgentJson(view);
  final old = view['model'] as Map?;
  final id = old?['model'] as String?;
  final provider = old?['provider'] as String?;
  return freezeAgentJson({
    ...view,
    'taskRouting': {
      'version': 1,
      'assistantChat': id == null || id.isEmpty || provider == null
          ? null
          : {'serviceId': old?['serviceId'] ?? 'legacy-$provider', 'modelId': id},
    },
  });
}

ModelReference? conversationRoutingOverride(Map<String, dynamic> view, TaskType type) {
  if (type != TaskType.assistantChat) return null;
  final routing = migrateConversationRouting(view)['taskRouting'] as Map;
  if (routing['version'] != 1) throw const ConfigurationFailure('unsupportedConversationRoutingVersion');
  final model = routing['assistantChat'] as Map?;
  return model == null ? null : ModelReference.fromJson(Map<String, dynamic>.from(model));
}
