import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:mm_core/mm_core.dart';

import 'citations.dart';
import 'hooks.dart';
import 'models.dart';
import 'knowledge/registry.dart';
import 'permissions.dart';
import 'runtime.dart';
import 'task_runtime/history.dart';
import 'task_runtime/registry.dart';
import 'tools.dart';

const assistantTaskTools = {
  'read_selection',
  'read_pages',
  'search_study_set',
  'read_branch',
  'read_more',
  'read_history',
};
final assistantChatSpec = _spec(TaskType.assistantChat, {...assistantTaskTools, 'propose_map_edits'});
final conversationSummarySpec = _spec(TaskType.conversationSummarize, const {});
final documentSummarySpec = _spec(TaskType.documentSummarize, const {});
final researchTaskSpec = _spec(TaskType.research, {
  ...assistantTaskTools,
  'web_search',
  'search_papers',
  'fetch_source',
});
final reviewCardsSpec = _spec(TaskType.reviewCards, {...assistantTaskTools, 'propose_map_edits'});
final assistantTaskSpecs = [
  assistantChatSpec,
  conversationSummarySpec,
  documentSummarySpec,
  researchTaskSpec,
  reviewCardsSpec,
];
TaskSpec _spec(TaskType type, Set<String> tools) => TaskSpec(
  type: type,
  inputSchema: 'assistant-input-1',
  resultSchema: 'A nonempty answer grounded in the supplied range; never claim unprocessed ranges are complete',
  promptVersion: 'assistant-task-1',
  schemaVersion: '1',
  completionRule:
      'Answer the question using read evidence; disclose missing information. Writes remain pending proposals.',
  allowedTools: tools,
  requiredCapabilities: {if (tools.isNotEmpty) ModelCapability.tools, ModelCapability.historyReplay},
  maxOutputTokens: 8192,
);

/// Explicit product actions choose their own route; ordinary text stays chat.
TaskSpec assistantSpecFor(String? skill, List<ContextItem> contexts) => switch (skill) {
  'verify' || 'papers' || 'videos' => researchTaskSpec,
  'quiz' => reviewCardsSpec,
  'summarize' => contexts.isEmpty ? conversationSummarySpec : documentSummarySpec,
  _ => assistantChatSpec,
};

/// Per-request owner of permissions, evidence and proposal hooks. No model client
/// lives here: the only executing agent is constructed by SdkAgentRuntime.
class AssistantTaskOwner implements AssistantRun {
  AssistantTaskOwner({
    required this.conversationState,
    required this.reader,
    required this.scope,
    required this.requestId,
    required this.mapId,
    required this.baseRevision,
    required this.parents,
    required this.online,
    this.primaryDocumentId,
    this.network,
    required this.execute,
  }) {
    permissions = AssistantPermissions(cancel);
    citations = CitationRegistry(
      primaryDocumentId: primaryDocumentId,
      online: online,
      persistentState: conversationState.metadata,
    );
    proposals = _proposal();
  }
  final sdk.AgentState conversationState;
  final StudySetReader reader;
  final ReadScope scope;
  final String requestId, mapId;
  final int baseRevision;
  final Map<String, String?> parents;
  final bool online;
  final String? primaryDocumentId;
  AssistantNetwork? network;
  final Future<RunResult<String>> Function(String text) execute;
  @override
  final cancel = CancellationToken();
  @override
  RunBudget budget = RunBudget();
  @override
  late CitationRegistry citations;
  @override
  late ProposalHook proposals;
  @override
  late AssistantPermissions permissions;
  @override
  late sdk.StatefulAgent agent;
  final _events = StreamController<sdk.StreamingEvent>();
  sdk.AgentState? _state;
  bool _started = false;

  ProposalHook _proposal() => ProposalHook(
    studySetId: scope.studySetId,
    mapId: mapId,
    baseRevision: baseRevision,
    parents: parents,
    requestId: requestId,
  );

  TaskBindings bindings(RunContext context, sdk.AgentState state, Map<String, dynamic> input) {
    // Seed only a new run. Recovery retains the runtime's durable state.
    if (!state.metadata.containsKey('assistant.taskOwner.v1')) {
      final saved = sdk.AgentState.fromJson(jsonDecode(jsonEncode(conversationState.toJson())));
      state.metadata.addAll(saved.metadata);
      final identity = jsonEncode([
        context.config.model.toJson(),
        context.config.capabilities.identity.protocol.name,
        context.config.capabilities.identity.endpointFingerprint,
        context.config.capabilities.identity.serviceRevision,
      ]);
      if (input['units'] == null &&
          saved.metadata['assistant.taskModel.v1'] == identity &&
          saved.metadata.containsKey('assistant.evidence.v1')) {
        state.history = saved.history;
      } else if (saved.history.messages.isNotEmpty) {
        (state.metadata.putIfAbsent('runtime.history.v1', () => <dynamic>[]) as List).add(saved.history.toJson());
      }
      state.metadata['assistant.taskModel.v1'] = identity;
      state.metadata['assistant.taskOwner.v1'] = requestId;
      final before = input['units'] == null ? state.toJson() : saved.toJson();
      before['metadata'] = {
        'assistant.taskModel.v1': input['units'] == null ? identity : saved.metadata['assistant.taskModel.v1'],
        'assistant.configuration.v1': state.metadata['assistant.configuration.v1'],
        'assistant.evidence.v1': state.metadata['assistant.evidence.v1'],
      };
      (state.metadata.putIfAbsent('assistant.before.v1', () => <String, dynamic>{}) as Map)[requestId] = jsonDecode(
        jsonEncode(before),
      );
    }
    if (input['units'] != null) state.metadata['assistant.summaryStage.v1'] = true;
    _state = state;
    budget = RunBudget();
    citations = CitationRegistry(primaryDocumentId: primaryDocumentId, online: online, persistentState: state.metadata);
    proposals = _proposal();
    state.metadata['assistant.diagnostics'] ??= <String, dynamic>{};
    (state.metadata['assistant.diagnostics'] as Map)[requestId] = {
      'requestId': requestId,
      'model': context.config.model.modelId,
      'host': '',
      'tools': <dynamic>[],
    };
    final tools = AssistantTools(
      reader: reader,
      scope: scope,
      cancel: cancel,
      citations: citations,
      budget: budget,
      network: network,
      permissions: permissions,
    ).build();
    tools.add(
      archivedHistoryTool(
        state,
        available: () => budget.remainingReadCharacters,
        consume: (size) {
          budget.takeContextSpace(size);
        },
      ),
    );
    return TaskBindings(
      tools: tools,
      hooks: [
        PolicyHook(
          allowed: {...tools.map((t) => t.name)},
          budget: budget,
          online: online,
          toolsEnabled: input['toolsEnabled'] != false,
          requestId: requestId,
        ),
        if (input['reviewOnly'] == true) _GroundedReviewHook(this),
        proposals,
        CitationHook(citations),
        _AssistantEvents(this),
      ],
    );
  }

  void synchronize() {
    final state = _state;
    if (state == null) return;
    if (!state.metadata.containsKey('assistant.summaryStage.v1')) conversationState.history = state.history;
    // View/confirmation state is owned by the controller, never overwritten by
    // a checkpoint taken before a user decision or receipt was persisted.
    for (final entry in state.metadata.entries) {
      if (state.metadata.containsKey('assistant.summaryStage.v1') && entry.key == 'assistant.taskModel.v1') continue;
      if (entry.key.startsWith('assistant.') &&
              !{'assistant.view', 'assistant.proposalViews', 'assistant.summaryStage.v1'}.contains(entry.key) ||
          entry.key == 'runtime.history.v1') {
        conversationState.metadata[entry.key] = entry.value;
      }
    }
  }

  @override
  Stream<sdk.StreamingEvent> run(String text) async* {
    if (_started) throw StateError('Run already started');
    _started = true;
    final work = () async {
      try {
        final result = await execute(text);
        synchronize();
        if (result.value != null) {
          _events.add(
            sdk.StreamingEvent(
              eventType: sdk.StreamingEventType.fullModelMessage,
              data: sdk.ModelMessage(model: '', textOutput: result.value, stopReason: 'stop'),
            ),
          );
        }
        if (result.status != RunStatus.completed) {
          throw ResearchFailure(
            result.status == RunStatus.cancelled ? ResearchFailureKind.cancelled : ResearchFailureKind.protocol,
          );
        }
      } catch (error, stack) {
        _events.addError(error, stack);
      } finally {
        synchronize();
        await _events.close();
      }
    }();
    try {
      yield* _events.stream;
    } finally {
      stop();
      await work;
    }
  }

  @override
  void stop() => cancel.cancel();
}

/// Each host supplies a fresh owner; definitions never retain another run's grants.
void registerAssistantTasks(TaskRegistry registry, AssistantTaskOwner owner) {
  for (final spec in assistantTaskSpecs) {
    registry.register<String>(
      TaskDefinition<String>(
        spec: spec,
        instructions:
            '$assistantSystemPrompt\n${switch (spec.type) {
              TaskType.conversationSummarize => 'Summarize only the explicitly selected message IDs. Output JSON: {text: string, coveredIds: string[], decisions: string[], suggestions: string[], unresolved: string[]}. Copy exactly every assigned unit ID into coveredIds. Preserve source markers. Distinguish decisions from suggestions and unresolved questions.',
              TaskType.documentSummarize => 'Summarize only this assigned chunk or merge group. Output JSON: {text: string, coveredIds: string[], decisions: string[], suggestions: string[], unresolved: string[]}. Copy exactly every assigned unit ID into coveredIds. Preserve source markers. Never infer coverage of an unread range.',
              TaskType.research => 'Discover candidate URLs, fetch actual body snapshots, then compare evidence and conflicts. Output JSON: {claims: [{text: string, verified: boolean, evidence: string[]}], conflicts: string[], unresolved: string[]}. Each verified claim must include its read snapshot markers in both text and evidence. Metadata and snippets are not full text. Unsupported conclusions must have verified:false.',
              TaskType.reviewCards => 'Read evidence before proposing review cards. Every question and answer must have a read evidence citation. Only addReviewCard operations are allowed. User confirmation applies changes.',
              _ => 'Answer directly when no tools are needed. Distinguish source statements from inference.',
            }}',
        decode: (text) => text.trim(),
        encode: (text) => {'text': text},
        restore: (json) => json['text'] as String,
        validateInput: (input) => input['question'] is String && (input['question'] as String).trim().isNotEmpty
            ? ValidationReport()
            : _invalid('question', 'Question required'),
        validator: _AnswerValidator(spec.type, owner),
        createBindings: owner.bindings,
      ),
    );
  }
}

ValidationReport _invalid(String code, String reason) => ValidationReport(
  issues: [ValidationIssue(code: code, path: r'$', reason: reason)],
);

class _AnswerValidator implements TaskValidator<String> {
  _AnswerValidator(this.type, this.owner);
  final TaskType type;
  final AssistantTaskOwner owner;
  @override
  ValidationReport validate(String value, Map<String, dynamic> input) {
    if (type == TaskType.conversationSummarize || type == TaskType.documentSummarize) {
      try {
        final summary = AssistantSummary.parse(value);
        final expected = {for (final unit in input['units'] as List) unit['id'] as String};
        if (summary.coveredIds.length != expected.length || !summary.coveredIds.toSet().containsAll(expected)) {
          return _invalid('coverage', 'Summary must cover exactly the assigned IDs');
        }
      } catch (_) {
        return _invalid('summarySchema', 'Invalid summary schema');
      }
    }
    if (type == TaskType.research) {
      try {
        final research = AssistantResearch.parse(value);
        for (final claim in research.claims) {
          if (!claim.verified) continue;
          final registered = {
            for (final citation in owner.citations.items)
              if (owner.online && citation.kind == 'snapshot' && citation.quote.trim().isNotEmpty) citation.marker,
          };
          if (claim.evidence.isEmpty ||
              claim.evidence.any((marker) => !registered.contains(marker) || !claim.text.contains(marker))) {
            return _invalid('unreadEvidence', 'Verified claims require read body snapshot markers');
          }
        }
        if (research.claims.every((claim) => !claim.verified)) {
          return _invalid('unverified', 'No body-supported conclusion');
        }
      } catch (_) {
        return _invalid('researchSchema', 'Invalid research schema');
      }
    }
    if (value.isEmpty && owner.proposals.proposals.isEmpty) return _invalid('empty', 'Answer required');
    if (type == TaskType.reviewCards && owner.proposals.proposals.isEmpty) {
      return _invalid('proposal', 'No grounded review proposal');
    }
    return ValidationReport();
  }
}

class _GroundedReviewHook extends sdk.AgentHook {
  _GroundedReviewHook(this.owner);
  final AssistantTaskOwner owner;
  @override
  sdk.ToolCallHookResult beforeToolCall(sdk.ToolCallHookContext context) {
    if (context.call.name != 'propose_map_edits') return const sdk.ToolCallHookResult.proceed();
    try {
      final ops = (jsonDecode(context.call.arguments) as Map)['ops'] as List;
      if (ops.isEmpty ||
          ops.any(
            (op) => op['kind'] != 'addReviewCard' || owner.citations.used('${op['question']} ${op['answer']}').isEmpty,
          )) {
        throw const FormatException();
      }
      return const sdk.ToolCallHookResult.proceed();
    } catch (_) {
      return sdk.ToolCallHookResult.deny(
        reason: 'Read evidence required',
        content: [sdk.TextPart('Only review cards with read evidence citations are allowed.')],
      );
    }
  }
}

class _AssistantEvents extends sdk.AgentHook {
  _AssistantEvents(this.owner);
  final AssistantTaskOwner owner;
  @override
  sdk.ModelCallHookResult beforeModelCall(sdk.ModelCallHookContext context) {
    owner.agent = context.agent;
    owner.synchronize();
    owner._events.add(sdk.StreamingEvent(eventType: sdk.StreamingEventType.beforeCallModel, data: null));
    return const sdk.ModelCallHookResult.proceed();
  }

  @override
  sdk.ToolCallHookResult beforeToolCall(sdk.ToolCallHookContext context) {
    owner._events.add(sdk.StreamingEvent(eventType: sdk.StreamingEventType.functionCallRequest, data: [context.call]));
    return const sdk.ToolCallHookResult.proceed();
  }

  @override
  sdk.ToolResultHookResult afterToolCall(sdk.ToolResultHookContext context) {
    owner.synchronize();
    owner._events.add(
      sdk.StreamingEvent(
        eventType: sdk.StreamingEventType.functionCallResult,
        data: sdk.FunctionExecutionResultMessage(results: [context.result]),
      ),
    );
    return const sdk.ToolResultHookResult.proceed();
  }
}

class AssistantSummary {
  AssistantSummary(this.text, this.coveredIds, this.decisions, this.suggestions, this.unresolved);
  final String text;
  final List<String> coveredIds, decisions, suggestions, unresolved;
  factory AssistantSummary.parse(String raw) {
    final json = jsonDecode(raw) as Map;
    final text = json['text'] as String;
    if (text.trim().isEmpty) throw const FormatException('Empty summary');
    return AssistantSummary(
      text,
      List<String>.from(json['coveredIds']),
      List<String>.from(json['decisions']),
      List<String>.from(json['suggestions']),
      List<String>.from(json['unresolved']),
    );
  }
  Map<String, dynamic> toJson() => {
    'text': text,
    'coveredIds': coveredIds,
    'decisions': decisions,
    'suggestions': suggestions,
    'unresolved': unresolved,
  };
}

class ResearchClaim {
  const ResearchClaim(this.text, this.verified, this.evidence);
  final String text;
  final bool verified;
  final List<String> evidence;
}

class AssistantResearch {
  AssistantResearch(this.claims, this.conflicts, this.unresolved);
  final List<ResearchClaim> claims;
  final List<String> conflicts, unresolved;
  factory AssistantResearch.parse(String raw) {
    final json = jsonDecode(raw) as Map;
    final claims = [
      for (final claim in json['claims'] as List)
        ResearchClaim(claim['text'] as String, claim['verified'] as bool, List<String>.from(claim['evidence'])),
    ];
    if (claims.isEmpty || claims.any((claim) => claim.text.trim().isEmpty)) throw const FormatException('Empty claims');
    return AssistantResearch(claims, List<String>.from(json['conflicts']), List<String>.from(json['unresolved']));
  }
  String render({required bool chinese}) => [
    for (final claim in claims)
      '${claim.verified
          ? ''
          : chinese
          ? '[未核实] '
          : '[Unverified] '}${claim.text}',
    if (conflicts.isNotEmpty) '${chinese ? '来源冲突' : 'Conflicts'}\n${conflicts.join('\n')}',
    if (unresolved.isNotEmpty) '${chinese ? '未决问题' : 'Unresolved'}\n${unresolved.join('\n')}',
  ].join('\n\n');
}

/// Domain-owned pack export. Keep the standard evidence rules, and retain
/// conversation proposals behind the existing confirmation hook.
List<KnowledgeBundle> assistantTaskKnowledgeBundles() {
  final standard = standardKnowledgeRegistry();
  final bundles = <String, KnowledgeBundle>{};
  for (final spec in assistantTaskSpecs) {
    for (final bundle in standard.resolve(spec, standardKnowledgeVersions(spec))) {
      bundles[bundle.id] = KnowledgeBundle(
        id: bundle.id,
        version: bundle.version,
        instructions: bundle.instructions,
        tools: {...bundle.tools, if (bundle.id == 'assistant.core') 'propose_map_edits'},
      );
    }
  }
  return bundles.values.toList();
}

VersionedKnowledgeRegistry assistantTaskKnowledgeRegistry() =>
    VersionedKnowledgeRegistry(assistantTaskKnowledgeBundles());
