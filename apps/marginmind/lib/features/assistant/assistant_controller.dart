import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

export 'package:mm_assistant/mm_assistant.dart'
    show
        Conversation,
        Message,
        MessageRole,
        MessageStatus,
        ContextItem,
        ContextKind,
        TraceStep,
        TraceStatus,
        Citation,
        ProposalView,
        ProposalStatus,
        AssistantModel,
        AssistantProvider;

typedef AssistantRunFactory = Future<AssistantRun> Function(
  sdk.AgentState state,
  Conversation conversation,
  Message question,
);

class AssistantDependencies {
  const AssistantDependencies({
    required this.studySetId,
    required this.model,
    required this.storage,
    required this.runFactory,
    required this.executor,
    required this.notes,
    this.online = true,
  });
  final String studySetId;
  final AssistantModel model;
  final sdk.StateStorage storage;
  final AssistantRunFactory runFactory;
  final MapEditExecutor executor;
  final NoteSaver notes;
  final bool online;
}

/// Override per study-set panel scope. There is deliberately no UI binding yet.
final assistantDependenciesProvider = Provider<AssistantDependencies>(
  (ref) => throw StateError('Assistant dependencies must be supplied'),
);
final assistantControllerProvider = NotifierProvider.autoDispose<AssistantController, Conversation>(
  AssistantController.new,
);

class AssistantController extends Notifier<Conversation> {
  late AssistantDependencies _deps;
  late sdk.AgentState _agentState;
  AssistantRun? _run;
  Future<void>? _running;
  bool _disposed = false;
  int _epoch = 0, _sequence = 0;
  final _applying = <String, Future<void>>{};
  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
  @override
  Conversation build() {
    _deps = ref.read(assistantDependenciesProvider);
    _agentState = sdk.AgentState(sessionId: _id());
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
      _run?.stop();
    });
    return Conversation(
      id: _agentState.sessionId,
      studySetId: _deps.studySetId,
      model: _deps.model,
      online: _deps.online,
    );
  }

  Future<void> _persist() {
    _agentState.metadata['assistant.view'] = state.toJson();
    _agentState.metadata['assistant.proposalViews'] = [
      for (final m in state.messages)
        for (final p in m.proposals) p.toJson(),
    ];
    _agentState.lastError = null; // SDK diagnostic strings may contain provider data.
    return _deps.storage.save(_agentState);
  }

  void _replace(Message next) {
    state = state.copyWith(messages: [for (final m in state.messages) m.id == next.id ? next : m]);
  }

  Message _message(String id) => state.messages.firstWhere((m) => m.id == id);
  Future<void> send(String text, {List<ContextItem> contexts = const [], String? skill}) {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    if (_running != null || _disposed) throw StateError('Assistant is busy');
    if (text.trim().isEmpty || text.length > 60000) throw const FormatException('Invalid question');
    final requestId = _id();
    final question = Message(
      id: _id(),
      requestId: requestId,
      role: MessageRole.user,
      text: text,
      contexts: contexts,
      skill: skill,
    );
    final answer = Message(id: _id(), requestId: requestId, role: MessageRole.agent, status: MessageStatus.running);
    state = state.copyWith(
      title: state.title.isEmpty ? text.substring(0, text.length.clamp(0, 80)) : state.title,
      messages: [...state.messages, question, answer],
    );
    final epoch = ++_epoch;
    final future = _send(question, answer.id, epoch);
    _running = future;
    return future.whenComplete(() {
      if (identical(_running, future)) _running = null;
    });
  }

  Future<void> _send(Message question, String answerId, int epoch) async {
    bool active() => !_disposed && epoch == _epoch;
    var segmentStart = 0;
    try {
      await _persist(); // Do not contact provider if question cannot be saved.
      if (!active()) return;
      final run = await _deps.runFactory(_agentState, state, question);
      if (!active()) {
        run.stop();
        return;
      }
      _run = run;
      await for (final event in run.run(question.text)) {
        if (!active()) break;
        var answer = _message(answerId);
        switch (event.eventType) {
          case sdk.StreamingEventType.beforeCallModel:
            segmentStart = answer.text.length;
          case sdk.StreamingEventType.modelChunkMessage:
            answer = answer.copyWith(text: answer.text + ((event.data as sdk.ModelMessage).textOutput ?? ''));
          case sdk.StreamingEventType.fullModelMessage:
            answer = answer.copyWith(
              text: answer.text.substring(0, segmentStart) + ((event.data as sdk.ModelMessage).textOutput ?? ''),
            );
          case sdk.StreamingEventType.functionCallRequest:
            final calls = event.data as List<sdk.FunctionCall>;
            answer = answer.copyWith(
              traces: [...answer.traces, for (final call in calls) TraceStep(call.id, call.name, TraceStatus.running)],
            );
          case sdk.StreamingEventType.functionCallResult:
            final results = (event.data as sdk.FunctionExecutionResultMessage).results;
            final byId = {for (final r in results) r.id: r};
            answer = answer.copyWith(
              traces: [
                for (final t in answer.traces)
                  byId.containsKey(t.id)
                      ? TraceStep(t.id, t.toolName, byId[t.id]!.isError ? TraceStatus.error : TraceStatus.done)
                      : t,
              ],
              proposals: run.proposals.proposals.values.map((p) => ProposalView(proposal: p)).toList(),
            );
          case sdk.StreamingEventType.modelRetrying:
            throw const ResearchFailure(ResearchFailureKind.protocol);
        }
        answer = answer.copyWith(
          citations: run.citations.used(answer.text),
          online: answer.traces.any(
            (t) => {'web_search', 'search_papers', 'fetch_source'}.contains(t.toolName) && t.status == TraceStatus.done,
          ),
        );
        _replace(answer);
        final reads = _agentState.metadata.putIfAbsent('assistant.reads', () => <String, dynamic>{}) as Map;
        reads[question.requestId] = run.citations.items.map((c) => c.toJson()).toList();
        await _persist();
      }
      if (active()) _replace(_message(answerId).copyWith(status: MessageStatus.done));
    } catch (error) {
      if (active()) {
        final kind = error is ResearchFailure ? error.kind : ResearchFailureKind.unavailable;
        _replace(
          _message(answerId).copyWith(
            status: kind == ResearchFailureKind.cancelled ? MessageStatus.stopped : MessageStatus.error,
            errorKind: kind,
          ),
        );
      }
    } finally {
      _run?.stop();
      _run = null;
      if (active()) {
        _agentState.isRunning = false;
        await _persist();
      }
    }
  }

  Future<void> stop() async {
    final running = _running;
    if (running == null) return;
    _epoch++;
    _run?.stop();
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          m.status == MessageStatus.running ? m.copyWith(status: MessageStatus.stopped) : m,
      ],
    );
    await running;
    _running = null;
    _agentState.isRunning = false;
    await _persist();
  }

  Future<void> retry(String messageId) async {
    final old = _message(messageId);
    final question = state.messages.firstWhere((m) => m.requestId == old.requestId && m.role == MessageRole.user);
    await send(question.text, contexts: question.contexts, skill: question.skill);
  }

  Future<void> newConversation() async {
    await stop();
    await Future.wait(_applying.values.toList());
    _agentState = sdk.AgentState(sessionId: _id());
    state = Conversation(
      id: _agentState.sessionId,
      studySetId: _deps.studySetId,
      model: state.readOnly ? _deps.model : state.model,
      online: state.readOnly ? _deps.online : state.online,
    );
    await _persist();
  }

  Future<void> openConversation(String id) async {
    await stop();
    await Future.wait(_applying.values.toList());
    final loaded = await _deps.storage.loadOrCreate(id, null);
    final data = loaded.metadata['assistant.view'];
    var view = data == null
        ? Conversation(id: id, studySetId: _deps.studySetId, model: state.model)
        : Conversation.fromJson(Map<String, dynamic>.from(data));
    if (view.id != id || view.studySetId != _deps.studySetId) throw const FormatException('Wrong study set');
    final messages = <Message>[];
    for (final m in view.messages) {
      final proposals = <ProposalView>[];
      for (final p in m.proposals) {
        final receipt = await _deps.executor.receipt(p.proposal.id);
        proposals.add(
          receipt == null
              ? p
              : p.copyWith(status: ProposalStatus.applied, receipt: receipt, selected: receipt.operationIds.toSet()),
        );
      }
      messages.add(
        m.copyWith(
          status: m.status == MessageStatus.running ? MessageStatus.interrupted : m.status,
          proposals: proposals,
        ),
      );
    }
    view = view.copyWith(messages: messages);
    _agentState = loaded..isRunning = false;
    state = view;
    await _persist();
  }

  /// Renames the open conversation (UI extension; does not stop a run).
  Future<void> rename(String title) async {
    final value = title.trim();
    if (value.isEmpty || value.length > 200) throw const FormatException('Invalid title');
    state = state.copyWith(title: value);
    await _persist();
  }

  Future<void> switchModel(AssistantModel model) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    await stop();
    state = state.copyWith(model: model);
    await _persist();
  }

  Future<void> setOnline(bool enabled) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    await stop();
    state = state.copyWith(online: enabled);
    await _persist();
  }

  ProposalView _proposal(String id) => state.messages.expand((m) => m.proposals).firstWhere((p) => p.proposal.id == id);
  Future<void> _updateProposal(ProposalView next) async {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          m.copyWith(proposals: [for (final p in m.proposals) p.proposal.id == next.proposal.id ? next : p]),
      ],
    );
    await _persist();
  }

  Future<void> selectOperation(String proposalId, String opId, bool selected) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    if (_applying.containsKey(proposalId)) throw StateError('Proposal is being applied');
    final p = _proposal(proposalId);
    if (p.status != ProposalStatus.pending || !p.proposal.operations.any((o) => o.id == opId)) {
      throw StateError('Invalid selection');
    }
    final ids = Set<String>.of(p.selected);
    if (selected) {
      void add(String id) {
        final op = p.proposal.operations.firstWhere((o) => o.id == id);
        for (final ref in [op.parentId, op.nodeId]) {
          if (ref != null && ref.startsWith('new:')) add(ref.substring(4));
        }
        ids.add(id);
      }

      add(opId);
    } else {
      ids.remove(opId);
      var changed = true;
      while (changed) {
        changed = false;
        for (final op in p.proposal.operations) {
          if (ids.contains(op.id) &&
              [
                op.parentId,
                op.nodeId,
              ].any((ref) => ref != null && ref.startsWith('new:') && !ids.contains(ref.substring(4)))) {
            ids.remove(op.id);
            changed = true;
          }
        }
      }
    }
    await _updateProposal(p.copyWith(selected: ids));
  }

  Future<void> applyProposal(String id) => _applying.putIfAbsent(
    id,
    () => _apply(id).whenComplete(() {
      _applying.remove(id);
    }),
  );
  Future<void> _apply(String id) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    final p = _proposal(id);
    if (p.status != ProposalStatus.pending) throw StateError('Proposal is not pending');
    final receipt = await _deps.executor.receipt(id) ?? await _deps.executor.apply(p.proposal, p.selected);
    if (!_disposed) {
      await _updateProposal(
        p.copyWith(status: ProposalStatus.applied, receipt: receipt, selected: receipt.operationIds.toSet()),
      );
    }
  }

  Future<void> dismissProposal(String id) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    final p = _proposal(id);
    if (p.status != ProposalStatus.pending || _applying.containsKey(id)) {
      throw StateError('Proposal cannot be dismissed');
    }
    await _updateProposal(p.copyWith(status: ProposalStatus.dismissed));
  }

  Future<void> reopenProposal(String id) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    final p = _proposal(id);
    if (p.status != ProposalStatus.dismissed) throw StateError('Proposal cannot be reopened');
    await _updateProposal(p.copyWith(status: ProposalStatus.pending));
  }

  Future<void> saveNote(String messageId, SaveNoteRequest request) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    final m = _message(messageId);
    if (m.role != MessageRole.agent || m.status == MessageStatus.running || m.text.isEmpty) {
      throw StateError('No answer to save');
    }
    final conversationId = state.id;
    final id = await _deps.notes.save(
      conversationId: conversationId,
      messageId: messageId,
      body: m.text,
      request: request,
    );
    if (!_disposed && state.id == conversationId) {
      _replace(_message(messageId).copyWith(noteId: id));
      await _persist();
    }
  }
}
