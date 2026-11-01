import 'models.dart';
import 'runs.dart';
import 'tasks.dart';

Map<String, dynamic> encodeRunContext(RunContext c) {
  final caps = c.config.capabilities, policy = c.config.policy, id = caps.identity;
  return {
    'runId': c.runId,
    'parentRunId': c.parentRunId,
    'branchId': c.branchId,
    'knowledgeVersions': c.knowledgeVersions,
    'phase': c.phase,
    'modelDisplayName': c.modelDisplayName,
    'serviceDisplayName': c.serviceDisplayName,
    'inputRange': c.inputRange,
    'identity': {
      'model': id.model.toJson(),
      'protocol': id.protocol.name,
      'endpointFingerprint': id.endpointFingerprint,
      'adapterVersion': id.adapterVersion,
      'serviceRevision': id.serviceRevision,
      'modelRevision': id.modelRevision,
    },
    'capabilities': {
      'thinking': caps.thinking.name,
      'tools': caps.tools.name,
      'structuredOutput': caps.structuredOutput.name,
      'multimodal': caps.multimodal.name,
      'historyReplay': caps.historyReplay.name,
      'contextTokens': caps.contextTokens,
      'outputTokens': caps.outputTokens,
      'policies': {for (final e in caps.policies.entries) e.key.name: e.value.name},
      if (caps.evidence case final e?)
        'evidence': {
          'source': e.source.name,
          'reference': e.reference,
          'verifiedAt': e.verifiedAt.toIso8601String(),
          'semanticBasis': e.semanticBasis,
          'wireVerified': e.wireVerified,
        },
    },
    'policy': {
      'requested': policy.requested.name,
      'effective': policy.effective.name,
      'recipe': policy.recipe.name,
      'parameters': policy.parameters,
      'maxOutputTokens': policy.maxOutputTokens,
    },
    'routingRevision': c.config.routingRevision,
    'serviceLabel': c.config.serviceLabel,
    'modelLabel': c.config.modelLabel,
    'source': c.config.source.name,
  };
}

RunContext decodeRunContext(Map<String, dynamic> j) {
  final i = j['identity'] as Map, c = j['capabilities'] as Map, p = j['policy'] as Map;
  final id = CapabilityIdentity(
    model: ModelReference.fromJson(Map<String, dynamic>.from(i['model'])),
    protocol: ModelProtocol.values.byName(i['protocol']),
    endpointFingerprint: i['endpointFingerprint'],
    adapterVersion: i['adapterVersion'],
    serviceRevision: i['serviceRevision'],
    modelRevision: i['modelRevision'],
  );
  final e = c['evidence'] as Map?;
  return RunContext(
    runId: j['runId'],
    parentRunId: j['parentRunId'],
    branchId: j['branchId'],
    phase: j['phase'] ?? 0,
    modelDisplayName: j['modelDisplayName'] ?? '',
    serviceDisplayName: j['serviceDisplayName'] ?? '',
    inputRange: Map<String, dynamic>.from(j['inputRange'] ?? {}),
    knowledgeVersions: Map<String, String>.from(j['knowledgeVersions']),
    config: ResolvedTaskConfig(
      routingRevision: j['routingRevision'],
      serviceLabel: j['serviceLabel'] ?? j['serviceDisplayName'],
      modelLabel: j['modelLabel'] ?? j['modelDisplayName'],
      source: RoutingSource.values.byName(j['source']),
      capabilities: ModelCapabilityProfile(
        identity: id,
        thinking: ThinkingCapability.values.byName(c['thinking']),
        tools: CapabilitySupport.values.byName(c['tools']),
        structuredOutput: CapabilitySupport.values.byName(c['structuredOutput']),
        multimodal: CapabilitySupport.values.byName(c['multimodal']),
        historyReplay: CapabilitySupport.values.byName(c['historyReplay']),
        contextTokens: c['contextTokens'],
        outputTokens: c['outputTokens'],
        policies: {
          for (final e in (c['policies'] as Map).entries)
            ReasoningPolicy.values.byName(e.key): ReasoningRecipe.values.byName(e.value),
        },
        evidence: e == null
            ? null
            : CapabilityEvidence(
                source: CapabilityEvidenceSource.values.byName(e['source']),
                reference: e['reference'],
                verifiedAt: DateTime.parse(e['verifiedAt']),
                semanticBasis: e['semanticBasis'],
                wireVerified: e['wireVerified'],
              ),
      ),
      policy: ProviderCallPolicy(
        identity: id,
        maxOutputTokens: p.containsKey('maxOutputTokens') ? p['maxOutputTokens'] : c['outputTokens'],
        requested: ReasoningPolicy.values.byName(p['requested']),
        effective: ReasoningPolicy.values.byName(p['effective']),
        recipe: ReasoningRecipe.values.byName(p['recipe']),
        parameters: Map<String, dynamic>.from(p['parameters']),
      ),
    ),
  );
}

Map<String, dynamic> encodeRunUsage(RunUsage u) => {
  'quality': u.quality.name,
  'modelCalls': u.modelCalls,
  'repairs': u.repairs,
  'inputTokens': u.inputTokens,
  'outputTokens': u.outputTokens,
  'reasoningTokens': u.reasoningTokens,
  'elapsedUs': u.elapsed.inMicroseconds,
};
RunUsage decodeRunUsage(Map j) => RunUsage(
  quality: UsageQuality.values.byName(j['quality'] ?? 'unknown'),
  modelCalls: j['modelCalls'] ?? 0,
  repairs: j['repairs'] ?? 0,
  inputTokens: j['inputTokens'] ?? 0,
  outputTokens: j['outputTokens'] ?? 0,
  reasoningTokens: j['reasoningTokens'],
  elapsed: Duration(microseconds: j['elapsedUs'] ?? 0),
);
Map<String, dynamic> encodeRunManifest(RunManifest m) => {
  'version': 1,
  'context': encodeRunContext(m.context),
  'taskType': m.taskType.key,
  'inputFingerprint': m.inputFingerprint,
  'promptVersion': m.promptVersion,
  'schemaVersion': m.schemaVersion,
  'status': m.status.name,
  'revision': m.revision,
  'stage': m.stage,
  'failureCode': m.failureCode,
  'resultReference': m.resultReference,
  'usage': encodeRunUsage(m.usage),
  'evidenceIds': m.evidenceIds,
  'configurationPhases': m.configurationPhases.map(encodeRunContext).toList(),
  'checkpoint': m.checkpoint,
};
RunManifest decodeRunManifest(Map<String, dynamic> j) {
  if (j['version'] != 1) throw const FormatException('Unsupported run version');
  return RunManifest(
    context: decodeRunContext(Map<String, dynamic>.from(j['context'])),
    taskType: TaskType.fromKey(j['taskType']) ?? (throw const FormatException('Unknown task')),
    inputFingerprint: j['inputFingerprint'],
    promptVersion: j['promptVersion'],
    schemaVersion: j['schemaVersion'],
    status: RunStatus.values.byName(j['status']),
    revision: j['revision'],
    stage: j['stage'],
    failureCode: j['failureCode'],
    resultReference: j['resultReference'],
    usage: decodeRunUsage(j['usage']),
    evidenceIds: List<String>.from(j['evidenceIds']),
    configurationPhases: [
      for (final c in j['configurationPhases'] ?? []) decodeRunContext(Map<String, dynamic>.from(c)),
    ],
    checkpoint: Map<String, dynamic>.from(j['checkpoint']),
  );
}
