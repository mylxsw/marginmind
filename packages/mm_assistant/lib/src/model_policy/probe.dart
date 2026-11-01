import 'package:mm_core/mm_core.dart';

import '../providers.dart';
import '../services.dart';
import 'routing.dart';
import '../task_runtime/provider_steps.dart';
import '../task_runtime/runtime.dart' show RuntimeModelBinding;

class CapabilityProbeResult {
  const CapabilityProbeResult({
    required this.identity,
    required this.accepted,
    required this.profile,
    this.runId,
    this.usage = const RunUsage(),
  });
  final String? runId;
  final RunUsage usage;
  final CapabilityIdentity identity;
  final bool accepted;
  final ModelCapabilityProfile profile;
  RunPurpose get purpose => RunPurpose.capabilityProbe;

  /// Connectivity cannot resolve missing independent semantic evidence.
  String? get admissionFailureCode => issue == RoutingIssue.unknown ? 'maintainedEvidenceRequired' : null;
  RoutingIssue get issue => profile.evidence?.admitsPolicy == true ? RoutingIssue.none : RoutingIssue.unknown;
}

typedef ProbeConnectionFactory = AssistantConnection Function(
  AssistantModel model,
  String key,
  ProviderCallPolicy? policy,
);
AssistantConnection _connection(AssistantModel model, String key, ProviderCallPolicy? policy) =>
    connectAssistant(model, key, callPolicy: policy, retryRequests: false, requestTimeout: const Duration(seconds: 20));

/// Infrastructure-only single SDK request. No Agent tools are registered or
/// executed. Unknown profiles stay unknown even after a successful response.
class RoutingCapabilityProbe {
  RoutingCapabilityProbe({
    required this.resolver,
    required this.key,
    this.connection = _connection,
    ProviderSteps? steps,
  }) : steps = steps ?? ProviderSteps(connection: connection);
  final ProviderSteps steps;
  int _sequence = 0;
  final TaskModelResolver resolver;
  final Future<String> Function(AssistantModel) key;
  final ProbeConnectionFactory connection;
  Future<CapabilityProbeResult> probe(
    ModelReference reference, {
    required CancellationToken cancellation,
    ReasoningPolicy reasoning = ReasoningPolicy.auto,
  }) async {
    cancellation.check();
    final catalog = await cancellation.bind(resolver.catalog());
    cancellation.check();
    final service = catalog.services.where((s) => s.id == reference.serviceId).firstOrNull;
    final model = service?.models.where((m) => m.id == reference.modelId).firstOrNull;
    if (service == null ||
        model == null ||
        !service.enabled ||
        !model.enabled ||
        (service.protocol == ServiceProtocol.ollama && !service.localEnabled)) {
      throw const ConfigurationFailure('probeModelUnavailable');
    }
    final identity = serviceCapabilityIdentity(service, model);
    await cancellation.bind(resolver.profiles.refresh());
    final profile = resolver.profiles.lookup(identity);
    ProviderCallPolicy? policy;
    if (profile.evidence?.admitsPolicy == true) {
      policy = TaskModelResolver.compiler.compile(
        category: TaskCategory.heavy,
        requested: reasoning,
        identity: identity,
        capabilities: profile,
        maxOutputTokens: 16,
      );
    } else if (reasoning != ReasoningPolicy.auto) {
      throw const ConfigurationFailure('unverifiedCapabilities');
    }
    final diagnostic = policy == null;
    policy ??= ProviderCallPolicy(
      identity: identity,
      requested: ReasoningPolicy.auto,
      effective: ReasoningPolicy.auto,
      recipe: ReasoningRecipe.omitted,
      parameters: const {},
      maxOutputTokens: 16,
    );
    final context = RunContext(
      runId: 'probe-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      config: ResolvedTaskConfig(
        capabilities: profile,
        policy: policy,
        routingRevision: 0,
        source: RoutingSource.explicitRequest,
      ),
      knowledgeVersions: const {},
    );
    try {
      await steps.run(
        context: context,
        category: TaskCategory.heavy,
        taskType: TaskType.assistantChat,
        purpose: RunPurpose.capabilityProbe,
        cancellation: cancellation,
        diagnostic: diagnostic,
        loadModel: (_) async {
          final config = service.configuration(model);
          final secret = await cancellation.bind(key(config));
          if (service.protocol != ServiceProtocol.ollama && secret.trim().isEmpty) {
            throw const ConfigurationFailure('secretUnavailable');
          }
          final latest = await cancellation.bind(resolver.catalog());
          final currentService = latest.services.where((s) => s.id == reference.serviceId).firstOrNull;
          final currentModel = currentService?.models.where((m) => m.id == reference.modelId).firstOrNull;
          if (currentService == null ||
              currentModel == null ||
              !currentService.enabled ||
              !currentModel.enabled ||
              serviceCapabilityIdentity(currentService, currentModel) != identity) {
            throw const ConfigurationFailure('serviceConfigurationChanged');
          }
          return RuntimeModelBinding(model: config, key: secret, serviceRevision: service.revision);
        },
      );
      cancellation.check();
      final latest = await cancellation.bind(resolver.catalog());
      final currentService = latest.services.where((s) => s.id == reference.serviceId).firstOrNull;
      final currentModel = currentService?.models.where((m) => m.id == reference.modelId).firstOrNull;
      if (currentService == null ||
          currentModel == null ||
          !currentService.enabled ||
          !currentModel.enabled ||
          serviceCapabilityIdentity(currentService, currentModel) != identity) {
        throw const ConfigurationFailure('serviceConfigurationChanged');
      }
      await cancellation.bind(resolver.profiles.recordProbe(identity, reasoning));
      return CapabilityProbeResult(
        identity: identity,
        accepted: true,
        profile: profile,
        runId: context.runId,
        usage: steps.records[context.runId]!.usage,
      );
    } catch (_) {
      cancellation.check();
      rethrow;
    }
  }
}
