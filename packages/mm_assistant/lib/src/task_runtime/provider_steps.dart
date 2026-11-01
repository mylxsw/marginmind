import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:dio/dio.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart' show UrlPolicy;

import '../model_policy/compiler.dart';
import '../providers.dart';
import '../runtime.dart' show assistantFailureKind;
import 'runtime.dart' show RuntimeModelBinding;

typedef ProviderStepConnection = AssistantConnection Function(
  AssistantModel model,
  String key,
  ProviderCallPolicy? policy,
);

AssistantConnection _connect(AssistantModel model, String key, ProviderCallPolicy? policy) => connectAssistant(
  model,
  key,
  callPolicy: policy,
  retryRequests: false,
  budget: null,
  requestTimeout: const Duration(seconds: 90),
);

/// One infrastructure request, never an Agent loop or a domain result.
/// Production task assembly supplies the same durable RunStore as the parent.
class ProviderSteps {
  ProviderSteps({this.store, this.connection = _connect});
  final RunStore? store;
  final ProviderStepConnection connection;
  final records = <String, RunManifest>{};
  final _pending = <String, (RunManifest, Map<String, dynamic>)>{};

  /// Retry a failed terminal write without issuing another provider request.
  Future<Map<String, dynamic>> retrySave(String runId) async {
    final (manifest, result) = _pending[runId]!;
    if (records[runId]!.revision < manifest.revision - 1) {
      final pending = RunManifest(
        context: manifest.context,
        taskType: manifest.taskType,
        inputFingerprint: manifest.inputFingerprint,
        promptVersion: manifest.promptVersion,
        schemaVersion: manifest.schemaVersion,
        status: RunStatus.validating,
        revision: manifest.revision - 1,
        stage: manifest.stage,
        usage: manifest.usage,
        checkpoint: {...manifest.checkpoint, 'terminalStatus': manifest.status.name},
      );
      await store?.checkpoint(pending, expectedRevision: manifest.revision - 2);
      records[runId] = pending;
    }
    await store?.complete(manifest, result, expectedRevision: manifest.revision - 1);
    records[runId] = manifest;
    _pending.remove(runId);
    return result;
  }

  /// Restart reconciliation only: no network request or tool replay.
  Future<Map<String, dynamic>> recoverSave(String runId) async {
    final saved = await store?.load(runId);
    if (saved == null ||
        saved.status != RunStatus.validating ||
        saved.checkpoint['pending'] is! Map ||
        saved.checkpoint['terminalStatus'] is! String) {
      throw const ConfigurationFailure('providerCheckpointMismatch');
    }
    final result = Map<String, dynamic>.from(saved.checkpoint['pending'] as Map);
    final terminal = RunManifest(
      context: saved.context,
      taskType: saved.taskType,
      inputFingerprint: saved.inputFingerprint,
      promptVersion: saved.promptVersion,
      schemaVersion: saved.schemaVersion,
      status: RunStatus.values.byName(saved.checkpoint['terminalStatus'] as String),
      revision: saved.revision + 1,
      stage: saved.stage,
      usage: saved.usage,
      checkpoint: saved.checkpoint,
      failureCode: result['failureCode'] as String?,
    );
    records[runId] = saved;
    _pending[runId] = (terminal, result);
    return retrySave(runId);
  }

  Future<Map<String, dynamic>> run({
    required RunContext context,
    required TaskCategory category,
    required TaskType taskType,
    required RunPurpose purpose,
    required Future<RuntimeModelBinding> Function(RunContext) loadModel,
    required CancellationToken cancellation,
    String query = 'Reply OK.',
    int limit = 5,
    bool diagnostic = false,
  }) async {
    if (!{RunPurpose.nativeSearch, RunPurpose.capabilityProbe}.contains(purpose) ||
        (diagnostic &&
            (purpose != RunPurpose.capabilityProbe ||
                category != TaskCategory.heavy ||
                context.config.policy.requested != ReasoningPolicy.auto))) {
      throw const ConfigurationFailure('invalidInfrastructurePurpose');
    }
    cancellation.check();
    final caps = context.config.capabilities;
    final frozen = context.config.policy;
    if (frozen.identity != caps.identity) throw const ConfigurationFailure('policySnapshotMismatch');
    ProviderCallPolicy policy;
    if (diagnostic) {
      // Diagnostic omission is NOT evidence for off or any task admission.
      policy = ProviderCallPolicy(
        identity: caps.identity,
        requested: ReasoningPolicy.auto,
        effective: ReasoningPolicy.auto,
        recipe: ReasoningRecipe.omitted,
        parameters: const {},
        maxOutputTokens: 16,
      );
    } else {
      policy = const DefaultProviderPolicyCompiler().compile(
        category: category,
        requested: frozen.requested,
        identity: caps.identity,
        capabilities: caps,
        maxOutputTokens: frozen.maxOutputTokens,
      );
      if (policy.effective != frozen.effective || jsonEncode(policy.parameters) != jsonEncode(frozen.parameters)) {
        throw const ConfigurationFailure('policySnapshotMismatch');
      }
    }
    if (purpose == RunPurpose.nativeSearch &&
        (category == TaskCategory.quick ||
            caps.tools != CapabilitySupport.supported ||
            !{
              ModelProtocol.anthropicMessages,
              ModelProtocol.responses,
              ModelProtocol.gemini,
            }.contains(caps.identity.protocol))) {
      throw const ConfigurationFailure('nativeSearchNotAdmitted');
    }
    final ceiling = purpose == RunPurpose.capabilityProbe ? 16 : 1024;
    final limits = [ceiling, policy.maxOutputTokens, frozen.maxOutputTokens, caps.outputTokens].whereType<int>();
    final maximum = limits.reduce((a, b) => a < b ? a : b);
    if (maximum <= 0) throw const ConfigurationFailure('invalidOutputLimit');
    final encoded = encodeRunContext(context);
    encoded['policy'] = {
      'requested': policy.requested.name,
      'effective': policy.effective.name,
      'recipe': policy.recipe.name,
      'parameters': policy.parameters,
      'maxOutputTokens': maximum,
    };
    context = decodeRunContext(encoded);
    policy = context.config.policy;
    if (records.containsKey(context.runId) || await store?.load(context.runId) != null) {
      throw const RunStoreConflict();
    }
    RunManifest snapshot(
      RunStatus status,
      int revision,
      RunUsage usage, {
      String? failure,
      Map<String, dynamic>? pending,
    }) => RunManifest(
      context: context,
      taskType: taskType,
      inputFingerprint: 'infrastructure:${purpose.name}',
      promptVersion: 'provider-step-1',
      schemaVersion: '1',
      status: status,
      revision: revision,
      stage: purpose.name,
      failureCode: failure,
      usage: usage,
      checkpoint: {'purpose': purpose.name, 'diagnostic': diagnostic, 'pending': ?pending},
    );
    final initial = snapshot(RunStatus.created, 0, const RunUsage());
    await store?.checkpoint(initial, expectedRevision: null);
    records[context.runId] = initial;
    AssistantConnection? transport;
    final token = CancelToken();
    var finished = false;
    cancellation.whenCancelled.then((_) {
      if (!finished) token.cancel();
    });
    var usage = const RunUsage();
    Map<String, dynamic>? raw;
    Map<String, dynamic> result;
    Object? failure;
    try {
      final binding = await cancellation.bind(loadModel(context));
      cancellation.check();
      if (binding.serviceRevision != caps.identity.serviceRevision) {
        throw const ConfigurationFailure('serviceConfigurationChanged');
      }
      transport = connection(binding.model, binding.key, policy);
      if (purpose == RunPurpose.nativeSearch) {
        // SDK 2.1.8 has no typed built-in search tool. Adapt only this closed
        // provider field; SDK still encodes messages, policy and decodes usage.
        transport.dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final body = options.data is String
                  ? Map<String, dynamic>.from(jsonDecode(options.data as String))
                  : Map<String, dynamic>.from(options.data as Map);
              body['tools'] = [
                switch (caps.identity.protocol) {
                  ModelProtocol.anthropicMessages => {
                    'type': 'web_search_20250305',
                    'name': 'web_search',
                    'max_uses': 1,
                  },
                  ModelProtocol.responses => {'type': 'web_search_preview'},
                  ModelProtocol.gemini => {'google_search': <String, dynamic>{}},
                  _ => throw const ConfigurationFailure('nativeSearchNotAdmitted'),
                },
              ];
              verifyPolicyPayload(policy, body);
              options.data = body;
              handler.next(options);
            },
            onResponse: (response, handler) {
              if (response.data is Map) raw = Map<String, dynamic>.from(response.data as Map);
              handler.next(response);
            },
          ),
        );
      }
      usage = const RunUsage(modelCalls: 1);
      final running = snapshot(RunStatus.running, 1, usage);
      await store?.checkpoint(running, expectedRevision: 0);
      records[context.runId] = running;
      final response = await cancellation.bind(
        transport.client.generate(
          [sdk.UserMessage.text(query)],
          modelConfig: policyModelConfig(policy),
          cancelToken: token,
        ),
      );
      cancellation.check();
      final u = response.usage;
      usage = RunUsage(
        modelCalls: 1,
        quality: u != null && (u.promptTokens > 0 || u.completionTokens > 0 || u.originalUsage != null)
            ? UsageQuality.reported
            : UsageQuality.unknown,
        inputTokens: u?.promptTokens ?? 0,
        outputTokens: u?.completionTokens ?? 0,
        reasoningTokens: u?.thoughtToken,
      );
      if (!{'stop', 'end_turn', 'tool_use', 'tool_calls', 'completed'}.contains(response.stopReason?.toLowerCase())) {
        throw const ResearchFailure(ResearchFailureKind.protocol);
      }
      result = purpose == RunPurpose.nativeSearch
          ? {'hits': _searchHits(raw ?? {}, caps.identity.protocol, limit)}
          : {'accepted': true};
    } catch (error) {
      failure = error;
      result = {'failureCode': error is ConfigurationFailure ? error.code : assistantFailureKind(error).name};
    } finally {
      finished = true;
      token.cancel();
      transport?.close();
    }
    final status = cancellation.isCancelled
        ? RunStatus.cancelled
        : failure != null
        ? RunStatus.failed
        : RunStatus.completed;
    // Pending result is durable before the terminal commit. No raw provider
    // response, credential, query or reasoning is copied into diagnostics.
    final revision = records[context.runId]!.revision;
    final terminal = snapshot(status, revision + 2, usage, failure: result['failureCode'] as String?, pending: result);
    _pending[context.runId] = (terminal, result);
    await retrySave(context.runId);
    if (failure != null) throw failure;
    cancellation.check();
    return result;
  }
}

/// Discovery URLs only. They still pass through the existing network grant,
/// page fetch and citation validation before being treated as evidence.
List<Map<String, dynamic>> _searchHits(Map<String, dynamic> data, ModelProtocol protocol, int limit) {
  final hits = <String, Map<String, dynamic>>{};
  void add(dynamic url, dynamic title) {
    if (url is! String) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) return;
    try {
      UrlPolicy.syntax(uri.removeFragment());
    } on ResearchFailure {
      return;
    }
    hits[url] = {'url': url, 'title': title is String ? title : '', 'snippet': ''};
  }

  switch (protocol) {
    case ModelProtocol.anthropicMessages:
      for (final block in data['content'] as List? ?? []) {
        if (block['type'] == 'web_search_tool_result' && block['content'] is List) {
          for (final hit in block['content']) {
            if (hit['type'] == 'web_search_result') add(hit['url'], hit['title']);
          }
        }
        for (final citation in block['citations'] as List? ?? []) {
          add(citation['url'], citation['title']);
        }
      }
    case ModelProtocol.responses:
      for (final item in data['output'] as List? ?? []) {
        for (final block in item['content'] as List? ?? []) {
          for (final citation in block['annotations'] as List? ?? []) {
            if (citation['type'] == 'url_citation') add(citation['url'], citation['title']);
          }
        }
      }
    case ModelProtocol.gemini:
      for (final candidate in data['candidates'] as List? ?? []) {
        for (final chunk in candidate['groundingMetadata']?['groundingChunks'] as List? ?? []) {
          final web = chunk['web'];
          if (web is Map) add(web['uri'], web['title']);
        }
      }
    default:
      throw const ConfigurationFailure('nativeSearchNotAdmitted');
  }
  return hits.values.take(limit.clamp(1, 20)).toList();
}

class RuntimeNativeSearch implements SearchProvider {
  RuntimeNativeSearch({
    required this.steps,
    required this.parent,
    required this.taskType,
    required this.nextRunId,
    required this.loadModel,
    required this.parentCancellation,
    this.onFinished,
  });
  final void Function()? onFinished;
  final ProviderSteps steps;
  final RunContext Function() parent;
  final TaskType taskType;
  final Future<String> Function() nextRunId;
  final Future<RuntimeModelBinding> Function(RunContext) loadModel;
  final CancellationToken parentCancellation;
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async {
    parentCancellation.check();
    cancellation.check();
    final combined = CancellationToken();
    var finished = false;
    void cancel() {
      if (!finished) combined.cancel();
    }

    parentCancellation.whenCancelled.then((_) => cancel());
    cancellation.whenCancelled.then((_) => cancel());
    var acquired = false;
    try {
      final id = await nextRunId();
      acquired = true;
      final context = parent().child(id);
      final result = await steps.run(
        context: context,
        category: taskType.category,
        taskType: taskType,
        purpose: RunPurpose.nativeSearch,
        loadModel: loadModel,
        cancellation: combined,
        query: request.query,
        limit: request.limit,
      );
      return [
        for (final h in result['hits']) SearchHit(url: Uri.parse(h['url']), title: h['title'], snippet: h['snippet']),
      ];
    } finally {
      finished = true;
      if (acquired) onFinished?.call();
    }
  }
}
