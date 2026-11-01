import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:dio/dio.dart';
import 'package:mm_core/mm_core.dart';

import '../providers.dart';
import '../services.dart';
import 'compiler.dart';
import 'routing.dart';

class CapabilityProbeResult {
  const CapabilityProbeResult({required this.identity, required this.accepted, required this.profile});
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
  RoutingCapabilityProbe({required this.resolver, required this.key, this.connection = _connection});
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
    final config = service.configuration(model);
    final secret = await cancellation.bind(key(config));
    cancellation.check();
    if (service.protocol != ServiceProtocol.ollama && secret.trim().isEmpty) {
      throw const ConfigurationFailure('secretUnavailable');
    }
    final transport = connection(config, secret, policy);
    final token = CancelToken();
    var finished = false;
    // A completed probe's cancellation listener cannot affect later connections.
    cancellation.whenCancelled.then((_) {
      if (!finished) token.cancel();
    });
    try {
      await transport.client.generate(
        [sdk.UserMessage.text('Reply OK.')],
        modelConfig: policy == null ? sdk.ModelConfig(model: model.id, maxTokens: 16) : policyModelConfig(policy),
        cancelToken: token,
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
      return CapabilityProbeResult(identity: identity, accepted: true, profile: profile);
    } catch (_) {
      cancellation.check();
      rethrow;
    } finally {
      finished = true;
      token.cancel();
      transport.close();
    }
  }
}
