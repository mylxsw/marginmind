import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

import 'tools.dart' show mapEditProposalInstructions;

class RunBudget {
  RunBudget({this.limits = const ResearchBudget(), this.maxCalls = 20, this.maxModels = 8}) {
    limits.validate();
  }
  final ResearchBudget limits;
  final int maxCalls, maxModels;
  int calls = 0, models = 0, searches = 0, pages = 0, bytes = 0, outputTokens = 0;
  void reserve({int readPages = 0, bool search = false}) {
    if (++calls > maxCalls) throw const ResearchFailure(ResearchFailureKind.loop);
    if ((pages += readPages) > limits.pages || (search && ++searches > limits.searches)) {
      throw const ResearchFailure(ResearchFailureKind.budget);
    }
  }
}

class PolicyHook extends AgentHook {
  PolicyHook({
    required this.allowed,
    required this.budget,
    required this.online,
    this.toolsEnabled = true,
    this.requestId,
    UrlPolicy? urls,
  }) : urls = urls ?? UrlPolicy();
  final Set<String> allowed;
  final RunBudget budget;
  final bool online;
  final UrlPolicy urls;
  bool _awaitingResponse = false;
  bool toolsEnabled;
  final String? requestId;
  int _failures = 0, _attempts = 0;
  final _entries = <String, Map<String, dynamic>>{};
  static String normalizeName(String name) => name.trim().split('.').last.toLowerCase().replaceAll('-', '_');
  static String diagnosticName(String name) =>
      name.length <= 100 && RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name) ? name : '<invalid>';
  @override
  ModelCallHookResult beforeModelCall(ModelCallHookContext context) {
    if (_awaitingResponse) return const ModelCallHookResult.abort(error: ResearchFailure(ResearchFailureKind.protocol));
    _awaitingResponse = true;
    // The SDK concatenates base tools and every active skill's tools. Our
    // skills share the same tool instances; expose each name only once on
    // every turn, including after the model activates more skills.
    final names = <String>{};
    final tools = toolsEnabled ? context.request.tools.where((tool) => names.add(tool.name)).toList() : <Tool>[];
    if (++budget.models > budget.maxModels ||
        jsonEncode({
              'messages': context.request.toCallLLMParams().messages.map((m) => m.toJson()).toList(),
              'tools': tools.map((t) => t.toJson()).toList(),
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
        tools: tools,
        clearToolChoice: !toolsEnabled,
        systemMessage: toolsEnabled
            ? null
            : SystemMessage(
                '${context.request.systemMessage?.content ?? ""}\n工具已关闭。仅用已附带的上下文和已读取的内容直接回答；不足时明确说明，不补充书外事实。',
              ),
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
    final raw = context.call;
    final name = normalizeName(raw.name);
    final entry = <String, dynamic>{'name': diagnosticName(raw.name), 'result': 'running', 'reason': null};
    _entries[raw.id] = entry;
    final diagnostics = (context.state.metadata['assistant.diagnostics'] as Map?)?[requestId] as Map?;
    (diagnostics?['tools'] as List?)?.add(entry);
    ToolCallHookResult deny(String reason) {
      entry['result'] = 'error';
      entry['reason'] = reason;
      return ToolCallHookResult.deny(reason: reason, content: [TextPart(reason)], metadata: {'reason': reason});
    }

    ToolCallHookResult abort(ResearchFailureKind kind) {
      entry['result'] = 'error';
      entry['reason'] = kind.name;
      return ToolCallHookResult.abort(error: ResearchFailure(kind));
    }

    if (++_attempts > budget.maxCalls) return abort(ResearchFailureKind.loop);
    if (!toolsEnabled) return abort(ResearchFailureKind.toolProtocol);
    if (!allowed.contains(name)) return deny('不存在的工具 ${diagnosticName(raw.name)}');
    if (!online && {'web_search', 'search_papers', 'fetch_source'}.contains(name)) return deny('已被策略拒绝：联网已关闭');
    try {
      final decoded = jsonDecode(raw.arguments);
      if (decoded is! Map<String, dynamic>) return deny('参数应为 JSON 对象');
      final args = Map<String, dynamic>.of(decoded);
      for (final key in ['from', 'to', 'limit']) {
        if (!args.containsKey(key)) continue;
        if (args[key] is String) args[key] = int.tryParse((args[key] as String).trim()) ?? args[key];
        if (args[key] is! int) return deny('参数 $key 应为整数');
      }
      if (name == 'read_pages') {
        for (final key in ['from', 'to']) {
          if (args[key] is! int) return deny('参数 $key 应为整数');
        }
      }
      final tool = context.availableTools.where((t) => t.name == name).firstOrNull;
      final properties = tool?.parameters['properties'] as Map? ?? {};
      for (final key in tool?.parameters['required'] as List? ?? []) {
        if (!args.containsKey(key)) return deny('缺少参数 $key');
      }
      for (final key in properties.keys) {
        if (args.containsKey(key) && (properties[key] as Map)['type'] == 'string' && args[key] is! String) {
          return deny('参数 $key 应为字符串');
        }
      }
      final pages = switch (name) {
        'read_pages' => (args['to'] as int) - (args['from'] as int) + 1,
        'fetch_source' => 1,
        _ => 0,
      };
      if (name == 'read_pages' && ((args['from'] as int) < 1 || pages < 1)) return deny('参数页码范围无效');
      budget.reserve(readPages: pages, search: {'web_search', 'search_papers', 'search_study_set'}.contains(name));
      if (name == 'fetch_source') await urls.validate(Uri.parse(args['url'] as String));
      return ToolCallHookResult.proceed(FunctionCall(id: raw.id, name: name, arguments: jsonEncode(args)));
    } on ResearchFailure catch (e) {
      if ({ResearchFailureKind.budget, ResearchFailureKind.loop}.contains(e.kind)) {
        return abort(e.kind);
      }
      return deny('已被策略拒绝：不安全的地址');
    } catch (_) {
      return deny('参数格式错误：应为 JSON 对象');
    }
  }

  @override
  ToolResultHookResult afterToolCall(ToolResultHookContext context) {
    final result = context.result;
    // Only our own bounded reasons enter diagnostics; never provider text or arguments.
    final reason = result.isError ? (result.metadata?['reason'] as String? ?? '工具拒绝了无效或未授权的请求') : null;
    final diagnostics = (context.state.metadata['assistant.diagnostics'] as Map?)?[requestId] as Map?;
    final entry = _entries.remove(result.id);
    if (entry != null) {
      entry['result'] = result.isError ? 'error' : 'done';
      entry['reason'] = reason;
    }
    if (reason == null) {
      _failures = 0;
    } else {
      if (++_failures >= 3) {
        toolsEnabled = false;
        diagnostics?['fallback'] = true;
      }
    }
    return const ToolResultHookResult.proceed();
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
      return ToolCallHookResult.deny(
        reason: 'Invalid proposal',
        content: [TextPart('Invalid proposal. Correct the fields and references:\n$mapEditProposalInstructions')],
      );
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
