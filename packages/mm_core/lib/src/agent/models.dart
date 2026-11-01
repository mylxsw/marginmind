/// Stable service/model identity, shared with the existing service catalog.
class ModelReference {
  const ModelReference(this.serviceId, this.modelId);
  final String serviceId, modelId;
  Map<String, dynamic> toJson() => {'serviceId': serviceId, 'modelId': modelId};
  factory ModelReference.fromJson(Map<String, dynamic> json) =>
      ModelReference(json['serviceId'] as String, json['modelId'] as String);
  @override
  bool operator ==(Object other) => other is ModelReference && serviceId == other.serviceId && modelId == other.modelId;
  @override
  int get hashCode => Object.hash(serviceId, modelId);
}

enum ModelProtocol { chatCompletions, responses, anthropicMessages, gemini, ollamaChat }

enum ModelCapability { tools, structuredOutput, multimodal, historyReplay }

enum CapabilitySupport { unknown, supported, unsupported }

enum ThinkingCapability { notApplicable, switchable, alwaysOn, unknown }

enum ReasoningPolicy { auto, off, standard, deep }

enum CapabilityEvidenceSource { officialMetadata, maintainedProfile, wireProbe, userDeclared }

/// HTTP success proves acceptance only. Semantic evidence must be independent.
class CapabilityEvidence {
  const CapabilityEvidence({
    required this.source,
    required this.reference,
    required this.verifiedAt,
    this.semanticBasis,
    this.wireVerified = false,
  });
  final CapabilityEvidenceSource source;
  final String reference;
  final DateTime verifiedAt;
  final String? semanticBasis;
  final bool wireVerified;
  bool get admitsPolicy =>
      wireVerified &&
      reference.isNotEmpty &&
      (semanticBasis?.trim().isNotEmpty ?? false) &&
      (source == CapabilityEvidenceSource.officialMetadata || source == CapabilityEvidenceSource.maintainedProfile);
}

/// Identity includes the exact configured endpoint (no name-based inference).
class CapabilityIdentity {
  const CapabilityIdentity({
    required this.model,
    required this.protocol,
    required this.endpointFingerprint,
    required this.adapterVersion,
    required this.serviceRevision,
    this.modelRevision,
  });
  final ModelReference model;
  final ModelProtocol protocol;
  final String endpointFingerprint, adapterVersion;
  final int serviceRevision;
  final String? modelRevision;
  @override
  bool operator ==(Object other) =>
      other is CapabilityIdentity &&
      model == other.model &&
      protocol == other.protocol &&
      endpointFingerprint == other.endpointFingerprint &&
      adapterVersion == other.adapterVersion &&
      serviceRevision == other.serviceRevision &&
      modelRevision == other.modelRevision;
  @override
  int get hashCode => Object.hash(model, protocol, endpointFingerprint, adapterVersion, serviceRevision, modelRevision);
}

/// Closed set of recipes; callers cannot supply arbitrary HTTP keys.
enum ReasoningRecipe { omitted, effortNone, effortMedium, effortHigh, thinkingDisabled, thinkingBudgetZero }

class ModelCapabilityProfile {
  ModelCapabilityProfile({
    required this.identity,
    this.thinking = ThinkingCapability.unknown,
    this.tools = CapabilitySupport.unknown,
    this.structuredOutput = CapabilitySupport.unknown,
    this.multimodal = CapabilitySupport.unknown,
    this.historyReplay = CapabilitySupport.unknown,
    this.contextTokens,
    this.outputTokens,
    Map<ReasoningPolicy, ReasoningRecipe> policies = const {},
    this.evidence,
  }) : policies = Map.unmodifiable(policies);
  final CapabilityIdentity identity;
  final ThinkingCapability thinking;
  final CapabilitySupport tools, structuredOutput, multimodal, historyReplay;
  final int? contextTokens, outputTokens;
  final Map<ReasoningPolicy, ReasoningRecipe> policies;
  final CapabilityEvidence? evidence;
}

enum RoutingSource { explicitRequest, functionBinding, categoryDefault, parentRun }

class ConfigurationFailure implements Exception {
  const ConfigurationFailure(this.code);
  final String code;
  @override
  String toString() => 'ConfigurationFailure($code)';
}

class ProviderCallPolicy {
  ProviderCallPolicy({
    required this.identity,
    required this.requested,
    required this.effective,
    required this.recipe,
    required Map<String, dynamic> parameters,
    this.maxOutputTokens,
  }) : parameters = freezeAgentJson(parameters);
  final CapabilityIdentity identity;
  final ReasoningPolicy requested, effective;

  /// Frozen per-request ceiling, never an aggregate run quota.
  final int? maxOutputTokens;
  final ReasoningRecipe recipe;

  /// SDK-independent protocol parameters, never credentials or user extras.
  final Map<String, dynamic> parameters;
}

class ResolvedTaskConfig {
  ResolvedTaskConfig({
    required this.capabilities,
    required this.policy,
    required this.routingRevision,
    required this.source,
    this.serviceLabel,
    this.modelLabel,
  }) {
    if (capabilities.identity != policy.identity) {
      throw const ConfigurationFailure('snapshotIdentityMismatch');
    }
  }
  final ModelCapabilityProfile capabilities;
  final ProviderCallPolicy policy;
  final int routingRevision;
  final RoutingSource source;
  final String? serviceLabel, modelLabel;
  ModelReference get model => capabilities.identity.model;
}

/// Deeply freezes JSON snapshots; rejects SDK objects and other mutable values.
Map<String, dynamic> freezeAgentJson(Map<String, dynamic> value) =>
    Map.unmodifiable(value.map((key, value) => MapEntry(key, _freeze(value))));
Object? _freeze(Object? value) {
  if (value == null || value is String || value is bool || value is num) return value;
  if (value is Map<String, dynamic>) return freezeAgentJson(value);
  if (value is List) return List.unmodifiable(value.map(_freeze));
  throw ArgumentError('Agent snapshots must contain JSON values');
}
