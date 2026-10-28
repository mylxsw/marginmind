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
        AssistantProvider,
        AssistantDiagnostics;

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
    this.generateTitle,
    this.defaultModel,
  });
  final String studySetId;

  /// The model when [defaultModel] has none (nothing set up yet).
  final AssistantModel model;

  /// The current default model of new conversations, read when one opens.
  final AssistantModel? Function()? defaultModel;
  AssistantModel get initialModel => defaultModel?.call() ?? model;
  final sdk.StateStorage storage;
  final AssistantRunFactory runFactory;
  final MapEditExecutor executor;
  final NoteSaver notes;
  final bool online;
  final Future<String> Function(AssistantModel model, String question)? generateTitle;
}

/// Override per study-set panel scope. There is deliberately no UI binding yet.
final assistantDependenciesProvider = Provider<AssistantDependencies>(
  (ref) => throw StateError('Assistant dependencies must be supplied'),
);
final assistantControllerProvider = NotifierProvider.autoDispose<AssistantController, Conversation>(
  AssistantController.new,
);

/// The conversation answering out of view, while another one is open; null
/// when the open conversation is the one running (or nothing runs). Override
/// it in the same scope as [assistantControllerProvider].
final assistantBackgroundProvider = NotifierProvider.autoDispose<AssistantBackground, Conversation?>(
  AssistantBackground.new,
);

class AssistantBackground extends Notifier<Conversation?> {
  @override
  Conversation? build() => null;

  void set(Conversation? value) {
    if (ref.mounted) state = value;
  }
}

/// One conversation and its agent state; a run, when it is answering.
class _Session {
  _Session(this.agent, this.view);
  sdk.AgentState agent;
  Conversation view;
  AssistantRun? run;
  Future<void>? running;
  int epoch = 0;
}

class AssistantController extends Notifier<Conversation> {
  late AssistantDependencies _deps;

  /// The conversation the panel shows.
  late _Session _open;

  /// The conversation answering (at most one per study set): the open one,
  /// or one the user left, which keeps answering out of view.
  _Session? _busy;
  bool _disposed = false;
  int _sequence = 0;
  final _applying = <String, Future<void>>{};
  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
  @override
  Conversation build() {
    _deps = ref.read(assistantDependenciesProvider);
    // Lives (and resets) with the controller.
    ref.listen(assistantBackgroundProvider, (_, _) {});
    final agent = sdk.AgentState(sessionId: _id());
    ref.onDispose(() {
      _disposed = true;
      for (final s in {_open, ?_busy}) {
        s.epoch++;
        s.run?.stop();
      }
    });
    _open = _Session(
      agent,
      Conversation(id: agent.sessionId, studySetId: _deps.studySetId, model: _deps.initialModel, online: _deps.online),
    );
    return _open.view;
  }

  /// Whether an answer is being written in any conversation of the study set.
  bool get busy => _busy != null;

  void _publishBackground() {
    final busy = _busy;
    ref.read(assistantBackgroundProvider.notifier).set(busy == null || identical(busy, _open) ? null : busy.view);
  }

  void _set(_Session session, Conversation next) {
    session.view = next;
    if (_disposed) return;
    if (identical(session, _open)) {
      state = next;
    } else if (identical(session, _busy)) {
      _publishBackground();
    }
  }

  Future<void> _persist([_Session? session]) {
    final s = session ?? _open;
    s.agent.metadata['assistant.view'] = s.view.toJson();
    s.agent.metadata['assistant.proposalViews'] = [
      for (final m in s.view.messages)
        for (final p in m.proposals) p.toJson(),
    ];
    s.agent.lastError = null; // SDK diagnostic strings may contain provider data.
    return _deps.storage.save(s.agent);
  }

  void _replace(_Session session, Message next) {
    _set(session, session.view.copyWith(messages: [for (final m in session.view.messages) m.id == next.id ? next : m]));
  }

  Message _message(String id, [_Session? session]) => (session ?? _open).view.messages.firstWhere((m) => m.id == id);
  Future<void> send(String text, {List<ContextItem> contexts = const [], String? skill}) =>
      _start(text, contexts: contexts, skill: skill);

  /// Asks [text] in the open conversation. With [replacing] (an answer and
  /// its question) the new pair takes their place instead of following the
  /// conversation; the old answer stays in the saved state only.
  Future<void> _start(
    String text, {
    List<ContextItem> contexts = const [],
    String? skill,
    (Message, Message)? replacing,
    bool tools = true,
  }) {
    final session = _open;
    if (session.view.readOnly) throw StateError('Legacy conversation is read only');
    if (_busy != null || _disposed) throw StateError('Assistant is busy');
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
    final answer = Message(
      id: _id(),
      requestId: requestId,
      role: MessageRole.agent,
      status: MessageStatus.running,
      startedAt: DateTime.now(),
    );
    final view = session.view;
    final List<Message> messages;
    if (replacing case (final oldQuestion, final oldAnswer)) {
      final replaced = session.agent.metadata.putIfAbsent('assistant.replaced', () => <dynamic>[]) as List;
      replaced.add(oldAnswer.toJson());
      messages = [
        for (final m in view.messages)
          if (m.id == oldQuestion.id) question else if (m.id == oldAnswer.id) answer else m,
      ];
    } else {
      messages = [...view.messages, question, answer];
    }
    _set(
      session,
      view.copyWith(
        title: view.title.isEmpty ? assistantTitlePlaceholder(text, contexts) : view.title,
        messages: messages,
      ),
    );
    final epoch = ++session.epoch;
    _busy = session;
    final future = _send(session, question, answer.id, epoch, tools: tools);
    session.running = future;
    return future.whenComplete(() {
      if (identical(session.running, future)) session.running = null;
      if (identical(_busy, session) && session.running == null) {
        _busy = null;
        if (!_disposed) _publishBackground();
      }
    });
  }

  Future<void> _send(_Session session, Message question, String answerId, int epoch, {bool tools = true}) async {
    bool active() => !_disposed && epoch == session.epoch;
    var segmentStart = 0;
    var fallbackRecorded = false;
    final allDiagnostics =
        session.agent.metadata.putIfAbsent('assistant.diagnostics', () => <String, dynamic>{}) as Map;
    allDiagnostics[question.requestId] = {
      'requestId': question.requestId,
      'model': session.view.model.model,
      'host': Uri.tryParse(session.view.model.endpoint)?.host ?? '',
      'tools': <dynamic>[],
    };
    AssistantDiagnostics diagnosticView() =>
        AssistantDiagnostics.fromJson(Map<String, dynamic>.from(allDiagnostics[question.requestId]));
    _replace(session, _message(answerId, session).copyWith(diagnostics: diagnosticView()));
    try {
      await _persist(session); // Do not contact provider if question cannot be saved.
      if (!active()) return;
      final view = session.view;
      final run = await _deps.runFactory(
        session.agent,
        tools ? view : view.copyWith(model: _withoutTools(view.model)),
        question,
      );
      if (!active()) {
        run.stop();
        return;
      }
      session.run = run;
      await for (final event in run.run(question.text)) {
        if (!active()) break;
        var answer = _message(answerId, session);
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
              text: '',
              traces: [
                ...answer.traces,
                if (answer.text.trim().isNotEmpty &&
                    (!RegExp(r'[\u4e00-\u9fff]').hasMatch(question.text) ||
                        RegExp(r'[\u4e00-\u9fff]').hasMatch(answer.text)))
                  TraceStep('narration-${answer.traces.length}', '', TraceStatus.done, narration: answer.text.trim()),
                for (final call in calls) TraceStep(call.id, call.name, TraceStatus.running),
              ],
            );
            segmentStart = 0;
          case sdk.StreamingEventType.functionCallResult:
            final results = (event.data as sdk.FunctionExecutionResultMessage).results;
            final byId = {for (final r in results) r.id: r};
            answer = answer.copyWith(
              traces: [
                for (final t in answer.traces)
                  byId.containsKey(t.id) && t.status == TraceStatus.running && t.narration == null
                      ? TraceStep(
                          t.id,
                          t.toolName,
                          byId[t.id]!.isError ? TraceStatus.error : TraceStatus.done,
                          reason: byId[t.id]!.isError
                              ? (byId[t.id]!.metadata?['reason'] as String? ?? '工具拒绝了无效或未授权的请求')
                              : null,
                        )
                      : t,
              ],
              proposals: run.proposals.proposals.values.map((p) => ProposalView(proposal: p)).toList(),
            );
          case sdk.StreamingEventType.modelRetrying:
            throw const ResearchFailure(ResearchFailureKind.protocol);
        }
        final diagnostics = (session.agent.metadata['assistant.diagnostics'] as Map?)?[question.requestId] as Map?;
        if (!fallbackRecorded && diagnostics?['fallback'] == true) {
          fallbackRecorded = true;
          final english = !RegExp(r'[\u4e00-\u9fff]').hasMatch(question.text);
          answer = answer.copyWith(
            traces: [
              ...answer.traces,
              TraceStep(
                'fallback',
                '',
                TraceStatus.done,
                narration: english
                    ? 'Tools failed three times. Answering from the attached context.'
                    : '工具连续失败三次，已关闭本轮工具，改用附带的上下文回答。',
              ),
            ],
          );
        }
        answer = answer.copyWith(
          diagnostics: diagnosticView(),
          citations: run.citations.used(answer.text),
          online: answer.traces.any(
            (t) =>
                {'web_search', 'search_papers', 'fetch_source'}.contains(PolicyHook.normalizeName(t.toolName)) &&
                t.status == TraceStatus.done,
          ),
        );
        _replace(session, answer);
        final reads = session.agent.metadata.putIfAbsent('assistant.reads', () => <String, dynamic>{}) as Map;
        reads[question.requestId] = run.citations.items.map((c) => c.toJson()).toList();
        await _persist(session);
      }
      if (active()) {
        _replace(session, _message(answerId, session).copyWith(status: MessageStatus.done, endedAt: DateTime.now()));
      }
    } catch (error) {
      if (active()) {
        final kind = assistantFailureKind(error);
        final diagnostics = (session.agent.metadata['assistant.diagnostics'] as Map?)?[question.requestId] as Map?;
        diagnostics?['failure'] = kind.name;
        final status = assistantFailureStatus(error);
        if (status != null) diagnostics?['httpStatus'] = status;
        for (final tool in diagnostics?['tools'] as List? ?? []) {
          if (tool['result'] == 'running') {
            tool['result'] = 'error';
            tool['reason'] = kind.name;
          }
        }
        _replace(
          session,
          _message(answerId, session).copyWith(
            status: kind == ResearchFailureKind.cancelled ? MessageStatus.stopped : MessageStatus.error,
            errorKind: kind,
            diagnostics: diagnosticView(),
            traces: [
              for (final t in _message(answerId, session).traces)
                t.status == TraceStatus.running ? TraceStep(t.id, t.toolName, TraceStatus.error, reason: kind.name) : t,
            ],
            endedAt: DateTime.now(),
          ),
        );
      }
    } finally {
      session.run?.stop();
      session.run = null;
      if (active()) {
        if (_message(answerId, session).status == MessageStatus.done &&
            session.view.messages.where((m) => m.role == MessageRole.user).length == 1 &&
            assistantSelectionTitle(question.text, question.contexts) == null &&
            session.view.title == assistantTitlePlaceholder(question.text, question.contexts) &&
            _deps.generateTitle != null) {
          final placeholder = session.view.title;
          try {
            final title = await _deps.generateTitle!(session.view.model, question.text);
            if (active() && session.view.title == placeholder && title.trim().isNotEmpty) {
              _set(session, session.view.copyWith(title: assistantTitlePlaceholder(title, const [])));
            }
          } catch (_) {
            /* A title failure keeps the question placeholder. */
          }
        }
        session.agent.isRunning = false;
        await _persist(session);
      }
    }
  }

  /// Stops the open conversation's answer; one answering out of view goes on.
  Future<void> stop() => _stop(_open);

  /// Stops the answer of conversation [id], open or not.
  Future<void> stopConversation(String id) async {
    final busy = _busy;
    if (busy != null && busy.view.id == id) await _stop(busy);
  }

  Future<void> _stop(_Session session) async {
    final running = session.running;
    if (running == null) return;
    session.epoch++;
    session.run?.stop();
    Message stopped(Message m) {
      if (m.status != MessageStatus.running) return m;
      final diagnostic = (session.agent.metadata['assistant.diagnostics'] as Map?)?[m.requestId] as Map?;
      diagnostic?['failure'] = ResearchFailureKind.cancelled.name;
      for (final tool in diagnostic?['tools'] as List? ?? []) {
        if (tool['result'] == 'running') {
          tool['result'] = 'error';
          tool['reason'] = 'cancelled';
        }
      }
      return m.copyWith(
        status: MessageStatus.stopped,
        endedAt: DateTime.now(),
        diagnostics: diagnostic == null ? null : AssistantDiagnostics.fromJson(Map<String, dynamic>.from(diagnostic)),
        traces: [
          for (final t in m.traces)
            t.status == TraceStatus.running ? TraceStep(t.id, t.toolName, TraceStatus.error, reason: 'cancelled') : t,
        ],
      );
    }

    _set(session, session.view.copyWith(messages: session.view.messages.map(stopped).toList()));
    await running;
    session.running = null;
    if (identical(_busy, session)) {
      _busy = null;
      if (!_disposed) _publishBackground();
    }
    session.agent.isRunning = false;
    await _persist(session);
  }

  static AssistantModel _withoutTools(AssistantModel m) => AssistantModel(
    provider: m.provider,
    model: m.model,
    endpoint: m.endpoint,
    localEnabled: m.localEnabled,
    serviceId: m.serviceId,
    supportsTools: false,
  );

  /// Asks the question of [messageId] again; the new answer replaces it.
  /// Without [tools] the model answers from the attached context only.
  Future<void> retry(String messageId, {bool tools = true}) async {
    final old = _message(messageId);
    if (old.role != MessageRole.agent) throw StateError('Not an answer');
    final question = _open.view.messages.firstWhere((m) => m.requestId == old.requestId && m.role == MessageRole.user);
    await _start(
      question.text,
      contexts: question.contexts,
      skill: question.skill,
      replacing: (question, old),
      tools: tools,
    );
  }

  /// Opens an empty conversation. An answer being written goes on out of view.
  Future<void> newConversation() async {
    await Future.wait(_applying.values.toList());
    final agent = sdk.AgentState(sessionId: _id());
    final previous = _open.view;
    _show(
      _Session(
        agent,
        Conversation(
          id: agent.sessionId,
          studySetId: _deps.studySetId,
          model: _deps.defaultModel?.call() ?? (previous.readOnly ? _deps.model : previous.model),
          online: previous.readOnly ? _deps.online : previous.online,
        ),
      ),
    );
    await _persist();
  }

  void _show(_Session session) {
    _open = session;
    state = session.view;
    _publishBackground();
  }

  /// Opens saved conversation [id]; the one answering is shown as it is now.
  Future<void> openConversation(String id) async {
    await Future.wait(_applying.values.toList());
    if (_open.view.id == id) return;
    final busy = _busy;
    if (busy != null && busy.view.id == id) return _show(busy);
    final loaded = await _deps.storage.loadOrCreate(id, null);
    final data = loaded.metadata['assistant.view'];
    var view = data == null
        ? Conversation(id: id, studySetId: _deps.studySetId, model: _open.view.model)
        : Conversation.fromJson(Map<String, dynamic>.from(data));
    if (view.id != id || view.studySetId != _deps.studySetId) throw const FormatException('Wrong study set');
    final messages = <Message>[];
    for (final m in view.messages) {
      final proposals = <ProposalView>[];
      for (final p in m.proposals) {
        proposals.add(_reconciled(p, await _deps.executor.receipt(p.proposal.id)));
      }
      messages.add(
        m.copyWith(
          status: m.status == MessageStatus.running ? MessageStatus.interrupted : m.status,
          proposals: proposals,
        ),
      );
    }
    view = view.copyWith(messages: messages);
    if (_disposed || (_busy?.view.id == id)) return;
    _show(_Session(loaded..isRunning = false, view));
    await _persist();
  }

  /// [p] as its committed [receipt] says: applied while there is one, back to
  /// pending (with what was applied still checked) once it was undone.
  static ProposalView _reconciled(ProposalView p, MapEditReceipt? receipt) {
    if (receipt != null) {
      return p.status == ProposalStatus.applied && p.receipt?.revision == receipt.revision
          ? p
          : p.copyWith(status: ProposalStatus.applied, receipt: receipt, selected: receipt.operationIds.toSet());
    }
    if (p.status != ProposalStatus.applied) return p;
    final selected = p.selected.isEmpty ? null : p.selected;
    return ProposalView(proposal: p.proposal, selected: selected);
  }

  /// Brings the proposal cards in line with the committed receipts, after an
  /// undo or redo changed them: an undone proposal is pending again and can
  /// be applied again.
  Future<void> syncReceipts() => _syncing = _syncing.then((_) => _syncReceipts()).catchError((Object _) {});
  Future<void> _syncing = Future.value();

  Future<void> _syncReceipts() async {
    for (final session in {_open, ?_busy}) {
      for (final m in session.view.messages) {
        for (final p in m.proposals) {
          if (p.status == ProposalStatus.dismissed || _applying.containsKey(p.proposal.id)) continue;
          final receipt = await _deps.executor.receipt(p.proposal.id);
          if (_disposed) return;
          if (_applying.containsKey(p.proposal.id)) continue;
          final current = _findProposal(session, p.proposal.id);
          if (current == null) continue;
          final next = _reconciled(current, receipt);
          if (!identical(next, current)) await _updateProposal(next, session);
        }
      }
    }
  }

  /// Returns an applied proposal whose change was undone to pending, so it
  /// can be checked and applied again. Fails while its receipt still stands.
  Future<void> revertProposal(String id) async {
    if (_open.view.readOnly) throw StateError('Legacy conversation is read only');
    final p = _proposal(id);
    if (p.status != ProposalStatus.applied || _applying.containsKey(id)) throw StateError('Proposal is not applied');
    if (await _deps.executor.receipt(id) != null) throw StateError('Proposal is still applied');
    final current = _findProposal(_open, id);
    if (current == null || current.status != ProposalStatus.applied) return;
    await _updateProposal(_reconciled(current, null));
  }

  /// Renames the open conversation, or with [conversationId] the one
  /// answering out of view (UI extension; does not stop a run). Returns false
  /// when [conversationId] is neither: its file is renamed elsewhere.
  Future<bool> rename(String title, {String? conversationId}) async {
    final value = title.trim();
    if (value.isEmpty || value.length > 200) throw const FormatException('Invalid title');
    final session = [_open, ?_busy].where((s) => s.view.id == (conversationId ?? _open.view.id)).firstOrNull;
    if (session == null) return false;
    _set(session, session.view.copyWith(title: value));
    await _persist(session);
    return true;
  }

  /// Changes the conversation's model. From an answer's recovery action,
  /// [retryMessageId] also re-asks that answer's original question.
  Future<void> switchModel(AssistantModel model, {String? retryMessageId}) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    final session = _open;
    if (retryMessageId != null) {
      if (_busy != null) throw StateError('Assistant is busy');
      if (_message(retryMessageId, session).role != MessageRole.agent) throw StateError('Not an answer');
    }
    await _stop(session);
    if (_disposed || !identical(session, _open)) return;
    _set(session, session.view.copyWith(model: model));
    await _persist(session);
    if (retryMessageId != null && !_disposed && identical(session, _open)) {
      await retry(retryMessageId);
    }
  }

  Future<void> setOnline(bool enabled) async {
    if (state.readOnly) throw StateError('Legacy conversation is read only');
    await stop();
    _set(_open, _open.view.copyWith(online: enabled));
    await _persist();
  }

  ProposalView _proposal(String id) => _findProposal(_open, id) ?? (throw StateError('No such proposal'));
  static ProposalView? _findProposal(_Session session, String id) =>
      session.view.messages.expand((m) => m.proposals).where((p) => p.proposal.id == id).firstOrNull;
  Future<void> _updateProposal(ProposalView next, [_Session? session]) async {
    final s = session ?? _open;
    _set(
      s,
      s.view.copyWith(
        messages: [
          for (final m in s.view.messages)
            m.copyWith(proposals: [for (final p in m.proposals) p.proposal.id == next.proposal.id ? next : p]),
        ],
      ),
    );
    await _persist(s);
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
    final session = _open;
    final p = _proposal(id);
    if (p.status != ProposalStatus.pending) throw StateError('Proposal is not pending');
    final receipt = await _deps.executor.receipt(id) ?? await _deps.executor.apply(p.proposal, p.selected);
    final current = _findProposal(session, id);
    if (!_disposed && current != null) {
      await _updateProposal(
        current.copyWith(status: ProposalStatus.applied, receipt: receipt, selected: receipt.operationIds.toSet()),
        session,
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
    final session = _open;
    final conversationId = state.id;
    final id = await _deps.notes.save(
      conversationId: conversationId,
      messageId: messageId,
      body: m.text,
      request: request,
    );
    if (!_disposed && session.view.messages.any((m) => m.id == messageId)) {
      _replace(session, _message(messageId, session).copyWith(noteId: id));
      await _persist(session);
    }
  }
}
