import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

class RunBudget {
  RunBudget({this.limits = const ResearchBudget(), this.maxCalls = 20, this.maxModels = 8}) {
    limits.validate();
  }
  final ResearchBudget limits;
  final int maxCalls, maxModels;
  int calls = 0, models = 0, searches = 0, pages = 0, bytes = 0, outputTokens = 0;
  void reserve({int readPages = 0, bool search = false}) {
    if (++calls > maxCalls || (pages += readPages) > limits.pages || (search && ++searches > limits.searches)) {
      throw const ResearchFailure(ResearchFailureKind.budget);
    }
  }
}

class PolicyHook extends AgentHook {
  PolicyHook({required this.allowed, required this.budget, required this.online, UrlPolicy? urls})
    : urls = urls ?? UrlPolicy();
  final Set<String> allowed;
  final RunBudget budget;
  final bool online;
  final UrlPolicy urls;
  bool _awaitingResponse = false;
  @override
  ModelCallHookResult beforeModelCall(ModelCallHookContext context) {
    if (_awaitingResponse) return const ModelCallHookResult.abort(error: ResearchFailure(ResearchFailureKind.protocol));
    _awaitingResponse = true;
    if (++budget.models > budget.maxModels ||
        jsonEncode({
              'messages': context.request.toCallLLMParams().messages.map((m) => m.toJson()).toList(),
              'tools': context.request.tools.map((t) => t.toJson()).toList(),
            }).length >
            budget.limits.inputCharacters) {
      return const ModelCallHookResult.abort(error: ResearchFailure(ResearchFailureKind.budget));
    }
    final config = context.request.modelConfig;
    final remaining = budget.limits.outputTokens - budget.outputTokens;
    if (remaining <= 0) return const ModelCallHookResult.abort(error: ResearchFailure(ResearchFailureKind.budget));
    return ModelCallHookResult.proceed(
      request: context.request.copyWith(
        modelConfig: ModelConfig(model: config.model, maxTokens: remaining, extra: config.extra),
      ),
    );
  }

  @override
  ModelChunkHookResult onModelChunk(ModelChunkHookContext context) {
    budget.bytes += utf8.encode(jsonEncode(context.chunk.toJson())).length;
    if (budget.bytes > budget.limits.responseBytes) {
      return const ModelChunkHookResult.abort(error: ResearchFailure(ResearchFailureKind.budget));
    }
    return const ModelChunkHookResult.proceed();
  }

  @override
  ModelResponseHookResult afterModelCall(ModelResponseHookContext context) {
    _awaitingResponse = false;
    if ({'refusal', 'content_filter'}.contains(context.response.stopReason)) {
      return const ModelResponseHookResult.abort(error: ResearchFailure(ResearchFailureKind.refusal));
    }
    if ({'max_tokens', 'length'}.contains(context.response.stopReason)) {
      return const ModelResponseHookResult.abort(error: ResearchFailure(ResearchFailureKind.budget));
    }
    budget.outputTokens += context.response.usage?.completionTokens ?? 0;
    if (budget.outputTokens > budget.limits.outputTokens) {
      return const ModelResponseHookResult.abort(error: ResearchFailure(ResearchFailureKind.budget));
    }
    // Prevent SDK's implicit retry of empty or truncated responses.
    if (context.response.stopReason == null ||
        context.response.stopReason!.isEmpty ||
        !{'stop', 'end_turn', 'tool_use', 'tool_calls', 'completed'}.contains(context.response.stopReason)) {
      return const ModelResponseHookResult.abort(error: ResearchFailure(ResearchFailureKind.protocol));
    }
    return const ModelResponseHookResult.proceed();
  }

  @override
  Future<ToolCallHookResult> beforeToolCall(ToolCallHookContext context) async {
    final name = context.call.name;
    if (!allowed.contains(name) || (!online && {'web_search', 'search_papers', 'fetch_source'}.contains(name))) {
      return const ToolCallHookResult.deny(reason: 'Tool is not authorized');
    }
    try {
      final args = jsonDecode(context.call.arguments) as Map<String, dynamic>;
      final pages = name == 'read_pages' ? (args['to'] as int) - (args['from'] as int) + 1 : 0;
      if (pages < 0) return const ToolCallHookResult.deny(reason: 'Invalid page range');
      budget.reserve(readPages: pages, search: {'web_search', 'search_papers', 'search_study_set'}.contains(name));
      if (name == 'fetch_source') await urls.validate(Uri.parse(args['url'] as String));
      return const ToolCallHookResult.proceed();
    } on ResearchFailure catch (e) {
      if (e.kind == ResearchFailureKind.budget) return ToolCallHookResult.abort(error: e);
      return const ToolCallHookResult.deny(reason: 'Unsafe URL');
    } catch (_) {
      return const ToolCallHookResult.deny(reason: 'Invalid arguments');
    }
  }
}

class ProposalHook extends AgentHook {
  ProposalHook({
    required this.studySetId,
    required this.mapId,
    required this.baseRevision,
    required Map<String, String?> parents,
    required this.requestId,
  }) : parents = Map.unmodifiable(parents);
  final String studySetId, mapId, requestId;
  final int baseRevision;
  final Map<String, String?> parents;
  final proposals = <String, MapEditProposal>{};
  @override
  ToolCallHookResult beforeToolCall(ToolCallHookContext context) {
    if (context.call.name != 'propose_map_edits') return const ToolCallHookResult.proceed();
    try {
      if (!proposals.containsKey(context.call.id)) {
        final j = jsonDecode(context.call.arguments) as Map<String, dynamic>;
        if (j.keys.any((k) => k != 'ops')) throw const FormatException('Unknown field');
        final ops = [for (final o in j['ops'] as List) MapEditOperation.fromJson(Map<String, dynamic>.from(o))];
        validateOperations(ops, parents);
        proposals[context.call.id] = MapEditProposal(
          id: '$requestId-${context.call.id}',
          studySetId: studySetId,
          mapId: mapId,
          baseRevision: baseRevision,
          operations: ops,
        );
        context.state.metadata['assistant.proposals'] = [
          ...context.state.metadata['assistant.proposals'] as List? ?? [],
          proposals[context.call.id]!.toJson(),
        ];
      }
      return ToolCallHookResult.defer(
        content: [TextPart('Proposal submitted for confirmation; nothing applied.')],
        metadata: {'proposalId': proposals[context.call.id]!.id},
      );
    } catch (_) {
      return const ToolCallHookResult.deny(reason: 'Invalid proposal');
    }
  }

  @override
  ToolResultHookResult afterToolCall(ToolResultHookContext context) => proposals.containsKey(context.result.id)
      ? const ToolResultHookResult.stop(reason: 'Awaiting user confirmation')
      : const ToolResultHookResult.proceed();
}

/// Temporary node references are `new:<opId>` and must refer to an earlier add.
void validateOperations(List<MapEditOperation> ops, Map<String, String?> parents) {
  if (ops.isEmpty || ops.length > 50) throw const FormatException('Invalid operation count');
  final graph = Map<String, String?>.of(parents);
  final ids = <String>{};
  for (final op in ops) {
    MapEditOperation.fromJson(Map<String, dynamic>.from(op.toJson()));
    if (!ids.add(op.id) ||
        (op.nodeId != null && !graph.containsKey(op.nodeId)) ||
        (op.parentId != null && !graph.containsKey(op.parentId))) {
      throw const FormatException('Unknown or duplicate node');
    }
    if (op.kind == MapEditKind.move) {
      String? p = op.parentId;
      final visited = <String>{};
      while (p != null) {
        if (p == op.nodeId || !visited.add(p)) throw const FormatException('Cycle');
        p = graph[p];
      }
      graph[op.nodeId!] = op.parentId;
    } else if ({MapEditKind.addTopic, MapEditKind.addNote, MapEditKind.addReviewCard}.contains(op.kind)) {
      if (graph.containsKey('new:${op.id}')) throw const FormatException('Duplicate temporary ID');
      graph['new:${op.id}'] = op.parentId;
    }
  }
}
