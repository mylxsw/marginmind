import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_core/mm_core.dart';

const modelPolicyAdapterVersion = 'dart-agent-core-2.1.8/policy-1';

String modelEndpointFingerprint(ModelProtocol protocol, String endpoint) {
  final uri = Uri.parse(endpoint.trim());
  if (!uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !{'https', 'http'}.contains(uri.scheme)) {
    throw const ConfigurationFailure('invalidEndpoint');
  }
  return sha256.convert(utf8.encode('${protocol.name}\n$uri')).toString();
}

/// In-memory compatibility entrypoint; production supplies a durable subclass.
class CapabilityProfiles {
  final _profiles = <CapabilityIdentity, ModelCapabilityProfile>{};
  Future<void> refresh() async {}
  Future<void> recordProbe(CapabilityIdentity identity, ReasoningPolicy reasoning) async {}
  void clear() => _profiles.clear();
  void put(ModelCapabilityProfile profile) => _profiles[profile.identity] = profile;
  ModelCapabilityProfile lookup(CapabilityIdentity identity) =>
      _profiles[identity] ?? ModelCapabilityProfile(identity: identity);
  void invalidateService(String serviceId) =>
      _profiles.removeWhere((identity, _) => identity.model.serviceId == serviceId);
}

class DefaultProviderPolicyCompiler implements ProviderPolicyCompiler {
  const DefaultProviderPolicyCompiler();
  @override
  ProviderCallPolicy compile({
    required TaskCategory category,
    required ReasoningPolicy requested,
    required CapabilityIdentity identity,
    required ModelCapabilityProfile capabilities,
    int? maxOutputTokens,
  }) {
    if (identity != capabilities.identity || identity.adapterVersion != modelPolicyAdapterVersion) {
      throw const ConfigurationFailure('staleCapabilities');
    }
    final desired = category == TaskCategory.quick ? ReasoningPolicy.off : requested;
    var effective = desired;
    var recipe = ReasoningRecipe.omitted;
    // Capability metadata helps choose optional parameters; it never grants or
    // denies access to a configured model. Unknown models use provider defaults.
    if (desired != ReasoningPolicy.auto) {
      final configured = capabilities.evidence?.admitsPolicy == true ? capabilities.policies[desired] : null;
      if (capabilities.thinking == ThinkingCapability.notApplicable && desired == ReasoningPolicy.off) {
        effective = ReasoningPolicy.off;
      } else if (capabilities.thinking != ThinkingCapability.alwaysOn &&
          configured != null &&
          configured != ReasoningRecipe.omitted) {
        recipe = configured;
      } else {
        effective = ReasoningPolicy.auto;
      }
    }
    if ((effective == ReasoningPolicy.off &&
            !{
              ReasoningRecipe.omitted,
              ReasoningRecipe.effortNone,
              ReasoningRecipe.thinkingDisabled,
              ReasoningRecipe.thinkingBudgetZero,
            }.contains(recipe)) ||
        (effective == ReasoningPolicy.standard && recipe != ReasoningRecipe.effortMedium) ||
        (effective == ReasoningPolicy.deep && recipe != ReasoningRecipe.effortHigh)) {
      throw const ConfigurationFailure('invalidReasoningRecipe');
    }
    final parameters = _parameters(identity.protocol, recipe);
    final limits = [maxOutputTokens, capabilities.outputTokens].whereType<int>().toList();
    if (limits.any((n) => n <= 0)) throw const ConfigurationFailure('invalidOutputLimit');
    final limit = limits.isEmpty ? null : limits.reduce((a, b) => a < b ? a : b);
    return ProviderCallPolicy(
      identity: identity,
      requested: requested,
      effective: effective,
      recipe: recipe,
      parameters: parameters,
      maxOutputTokens: limit,
    );
  }
}

Map<String, dynamic> _parameters(ModelProtocol protocol, ReasoningRecipe recipe) {
  if (recipe == ReasoningRecipe.omitted) return {};
  final effort = switch (recipe) {
    ReasoningRecipe.effortNone => 'none',
    ReasoningRecipe.effortMedium => 'medium',
    ReasoningRecipe.effortHigh => 'high',
    _ => null,
  };
  if (effort != null) {
    if (protocol == ModelProtocol.responses) {
      return {
        'reasoning': {'effort': effort},
      };
    }
    if ({ModelProtocol.chatCompletions, ModelProtocol.ollamaChat}.contains(protocol)) {
      return {'reasoning_effort': effort};
    }
  }
  if (recipe == ReasoningRecipe.thinkingDisabled && protocol == ModelProtocol.anthropicMessages) {
    return {
      'thinking': {'type': 'disabled'},
    };
  }
  if (recipe == ReasoningRecipe.thinkingBudgetZero && protocol == ModelProtocol.gemini) {
    return {
      'generationConfig': {
        'thinkingConfig': {'thinkingBudget': 0},
      },
    };
  }
  throw const ConfigurationFailure('unsupportedProtocolRecipe');
}

/// The only translation from domain policy to SDK extras. No arbitrary extra map.
ModelConfig policyModelConfig(ProviderCallPolicy policy, {int? maxTokens}) {
  final parameters = policy.parameters;
  final extra = policy.identity.protocol == ModelProtocol.gemini && parameters.isNotEmpty
      ? Map<String, dynamic>.from(parameters['generationConfig'] as Map)
      : parameters;
  final limit = policy.maxOutputTokens;
  if (limit != null && maxTokens != null && maxTokens != limit) {
    throw const ConfigurationFailure('outputLimitOverride');
  }
  return ModelConfig(model: policy.identity.model.modelId, maxTokens: limit ?? maxTokens, extra: extra);
}

/// Checked after SDK encoding on every attempt. Missing fields never trigger a parameter-free retry.
void verifyPolicyPayload(ProviderCallPolicy policy, Map<String, dynamic> body) {
  if (body['model'] != null && body['model'] != policy.identity.model.modelId) {
    throw const ConfigurationFailure('policyModelMismatch');
  }
  final limit = policy.maxOutputTokens;
  if (limit != null) {
    final actualLimit = switch (policy.identity.protocol) {
      ModelProtocol.responses => body['max_output_tokens'],
      ModelProtocol.gemini => (body['generationConfig'] as Map?)?['maxOutputTokens'],
      ModelProtocol.anthropicMessages => body['max_tokens'],
      _ => body['max_completion_tokens'],
    };
    if (actualLimit != limit) throw const ConfigurationFailure('outputLimitPayloadMismatch');
  }
  final expected = _parameters(policy.identity.protocol, policy.recipe);
  // Reject extra reasoning knobs as well as missing ones, including nested display/effort settings.
  final actual = <String, dynamic>{
    for (final key in ['reasoning', 'reasoning_effort', 'thinking', 'output_config', 'enable_thinking', 'think'])
      if (body.containsKey(key)) key: body[key],
    if ((body['generationConfig'] as Map?)?.containsKey('thinkingConfig') ?? false)
      'generationConfig': {'thinkingConfig': (body['generationConfig'] as Map)['thinkingConfig']},
  };
  if (jsonEncode(actual) != jsonEncode(expected)) throw const ConfigurationFailure('policyPayloadMismatch');
}

/// Capability metadata is advisory. Send the requested task to the configured
/// provider and report actual API failures instead of imposing an allowlist.
/// Kept for callers using the public model-policy API.
void validateTaskCapabilities(TaskSpec spec, ModelCapabilityProfile capabilities) {}
