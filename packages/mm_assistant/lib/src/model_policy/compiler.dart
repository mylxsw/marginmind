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

/// No built-in model-name profiles. Admission is supplied by verified catalog data.
class CapabilityProfiles {
  final _profiles = <CapabilityIdentity, ModelCapabilityProfile>{};
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
  }) {
    if (identity != capabilities.identity || identity.adapterVersion != modelPolicyAdapterVersion) {
      throw const ConfigurationFailure('staleCapabilities');
    }
    final effective = category == TaskCategory.quick ? ReasoningPolicy.off : requested;
    if (capabilities.thinking == ThinkingCapability.unknown || capabilities.evidence?.admitsPolicy != true) {
      throw const ConfigurationFailure('unverifiedCapabilities');
    }
    if (effective == ReasoningPolicy.off && capabilities.thinking == ThinkingCapability.alwaysOn) {
      throw const ConfigurationFailure('thinkingCannotDisable');
    }
    final ReasoningRecipe recipe;
    if (effective == ReasoningPolicy.auto ||
        (effective == ReasoningPolicy.off && capabilities.thinking == ThinkingCapability.notApplicable)) {
      recipe = ReasoningRecipe.omitted;
    } else {
      final configured = capabilities.policies[effective];
      if (configured == null || configured == ReasoningRecipe.omitted) {
        throw const ConfigurationFailure('unsupportedReasoningPolicy');
      }
      recipe = configured;
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
    return ProviderCallPolicy(
      identity: identity,
      requested: requested,
      effective: effective,
      recipe: recipe,
      parameters: parameters,
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
  return ModelConfig(model: policy.identity.model.modelId, maxTokens: maxTokens, extra: extra);
}

/// Checked after SDK encoding on every attempt. Missing fields never trigger a parameter-free retry.
void verifyPolicyPayload(ProviderCallPolicy policy, Map<String, dynamic> body) {
  if (body['model'] != null && body['model'] != policy.identity.model.modelId) {
    throw const ConfigurationFailure('policyModelMismatch');
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

/// S1 calls this for the selected TaskSpec before constructing a resolved snapshot.
void validateTaskCapabilities(TaskSpec spec, ModelCapabilityProfile capabilities) {
  for (final requirement in spec.requiredCapabilities) {
    // 2.1.8 cannot guarantee general replay on these protocols, even if remote
    // model metadata advertises tool support. Re-admit only after a codec fix.
    if (requirement == ModelCapability.historyReplay &&
        {ModelProtocol.responses, ModelProtocol.gemini}.contains(capabilities.identity.protocol)) {
      throw const ConfigurationFailure('sdkHistoryReplayUnsupported');
    }
    final support = switch (requirement) {
      ModelCapability.tools => capabilities.tools,
      ModelCapability.structuredOutput => capabilities.structuredOutput,
      ModelCapability.multimodal => capabilities.multimodal,
      ModelCapability.historyReplay => capabilities.historyReplay,
    };
    if (support != CapabilitySupport.supported) {
      throw ConfigurationFailure('${requirement.name}:${support.name}');
    }
  }
}
