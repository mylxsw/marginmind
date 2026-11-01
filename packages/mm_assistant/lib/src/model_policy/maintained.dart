import 'package:mm_core/mm_core.dart';

import '../services.dart';
import 'routing.dart';

/// Bump when semantic sources, endpoint scope, or audited SDK wire behavior change.
const maintainedCapabilityRevision = 'official-2026-11-01-v1';

/// Exact, reviewed allowlist. Catalog tools flags and model-name fragments are
/// never evidence. See docs/ai-capability-profiles.md for sources and wire tests.
ModelCapabilityProfile? maintainedCapabilityProfile(AssistantService service, ServiceModel model) {
  final uri = Uri.tryParse(service.endpoint.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final identity = serviceCapabilityIdentity(service, model);
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  String? reference, basis;
  var thinking = ThinkingCapability.unknown;
  var policies = <ReasoningPolicy, ReasoningRecipe>{};
  int? context, output;
  var replay = CapabilitySupport.unknown;
  if (uri.host == 'api.openai.com' &&
      {'gpt-4.1-2025-04-14', 'gpt-5.1-2025-11-13'}.contains(model.id) &&
      ((identity.protocol == ModelProtocol.chatCompletions && {'', '/v1', '/v1/chat/completions'}.contains(path)) ||
          (identity.protocol == ModelProtocol.responses && {'', '/v1', '/v1/responses'}.contains(path)))) {
    reference = 'https://developers.openai.com/api/docs/models/gpt-4.1';
    basis =
        'Pinned GPT-4.1 snapshot is non-reasoning; omit reasoning controls. '
        'SDK 2.1.8 exact Chat Completions/Responses encoding audited by maintained_capabilities_test.';
    thinking = ThinkingCapability.notApplicable;
    context = 1047576;
    output = 32768;
    if (model.id == 'gpt-5.1-2025-11-13') {
      reference = 'https://developers.openai.com/api/docs/models/gpt-5.1';
      basis =
          'Pinned GPT-5.1 supports none, medium and high reasoning effort. '
          'SDK 2.1.8 exact Chat Completions/Responses encoding audited by maintained_capabilities_test.';
      thinking = ThinkingCapability.switchable;
      policies = {
        ReasoningPolicy.off: ReasoningRecipe.effortNone,
        ReasoningPolicy.standard: ReasoningRecipe.effortMedium,
        ReasoningPolicy.deep: ReasoningRecipe.effortHigh,
      };
      context = 400000;
      output = 128000;
    }
    replay = identity.protocol == ModelProtocol.chatCompletions
        ? CapabilitySupport.supported
        : CapabilitySupport.unsupported;
  } else if (uri.host == 'generativelanguage.googleapis.com' &&
      identity.protocol == ModelProtocol.gemini &&
      {'', '/v1beta'}.contains(path) &&
      model.id == 'gemini-2.5-flash') {
    reference = 'https://ai.google.dev/gemini-api/docs/generate-content/thinking';
    basis =
        'Gemini 2.5 Flash GenerateContent supports disabling thinking with thinkingBudget=0; '
        'SDK 2.1.8 merges extras into generationConfig, audited by maintained_capabilities_test. '
        'This is not an Interactions or Vertex API rule.';
    thinking = ThinkingCapability.switchable;
    policies = {ReasoningPolicy.off: ReasoningRecipe.thinkingBudgetZero};
    context = 1048576;
    output = 65536;
    replay = CapabilitySupport.unsupported;
  }
  if (reference == null) return null;
  return ModelCapabilityProfile(
    identity: identity,
    thinking: thinking,
    // Remote support alone does not prove a full SDK feature/replay contract.
    historyReplay: replay,
    contextTokens: context,
    outputTokens: output,
    policies: policies,
    evidence: CapabilityEvidence(
      source: CapabilityEvidenceSource.maintainedProfile,
      reference: reference,
      semanticBasis: basis,
      verifiedAt: DateTime.utc(2026, 11, 1),
      wireVerified: true,
    ),
  );
}

Map<String, dynamic> capabilityIdentityJson(CapabilityIdentity id) => {
  'model': id.model.toJson(),
  'protocol': id.protocol.name,
  'endpointFingerprint': id.endpointFingerprint,
  'adapterVersion': id.adapterVersion,
  'serviceRevision': id.serviceRevision,
  'modelRevision': id.modelRevision,
};
