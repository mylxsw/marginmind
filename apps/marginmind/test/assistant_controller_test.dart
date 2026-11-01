import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../../packages/mm_assistant/test/support.dart';

class MemoryStorage implements sdk.StateStorage {
  final files = <String, String>{};
  bool fail = false;
  @override
  Future<sdk.AgentState> loadOrCreate(String id, Map<String, dynamic>? metadata) async => files[id] == null
      ? sdk.AgentState(sessionId: id, metadata: metadata)
      : sdk.AgentState.fromJson(jsonDecode(files[id]!));
  @override
  Future<void> save(sdk.AgentState state) async {
    if (fail) throw StateError('disk');
    files[state.sessionId] = jsonEncode(state.toJson());
  }

  @override
  Future<void> delete(String id) async {
    files.remove(id);
  }

  @override
  Future<bool> exist(String id) async => files.containsKey(id);
}

const model = AssistantModel(
  provider: AssistantProvider.claude,
  model: 'fake',
  endpoint: 'https://api.anthropic.com/v1/messages',
);
void main() {
  late ProviderContainer container;
  late AssistantController controller;
  late MemoryStorage storage;
  late MemoryMapEditExecutor executor;
  late MemoryNoteSaver notes;
  late ScriptClient client;
  late ProviderSubscription<Conversation> subscription;
  var factories = 0;
  AssistantRunFactory? factory;
  Future<String> Function()? titleGenerator;
  setUp(() {
    storage = MemoryStorage();
    executor = MemoryMapEditExecutor(studySetId: 'set', mapId: 'map', parents: {'root': null});
    notes = MemoryNoteSaver();
    client = ScriptClient([answer('hello'), answer('again')]);
    factories = 0;
    factory = null;
    titleGenerator = null;
    container = ProviderContainer(
      overrides: [
        assistantDependenciesProvider.overrideWithValue(
          AssistantDependencies(
            studySetId: 'set',
            model: model,
            storage: storage,
            executor: executor,
            notes: notes,
            generateTitle: (_, _) async => titleGenerator == null ? '' : await titleGenerator!(),
            runFactory: (s, c, q) async {
              factories++;
              if (factory != null) return factory!(s, c, q);
              return createAssistantRun(
                client: client,
                model: 'fake',
                state: s,
                requestId: q.requestId,
                reader: Reader(),
                scope: scopeFromContexts('set', q.contexts),
                mapId: 'map',
                baseRevision: executor.revision,
                parents: executor.parents,
                skill: q.skill,
                online: c.online,
              );
            },
          ),
        ),
      ],
    );
    subscription = container.listen(assistantControllerProvider, (_, _) {});
    controller = container.read(assistantControllerProvider.notifier);
  });
  tearDown(() {
    subscription.close();
    container.dispose();
  });
  Conversation view() => container.read(assistantControllerProvider);
  test('retry earlier answer sends only its complete prefix and archives later branch', () async {
    client = ScriptClient([answer('first-old'), answer('second-old'), answer('replacement')]);
    await controller.send('first-question');
    final firstAnswer = view().messages.last.id;
    await controller.send('second-question');
    await controller.retry(firstAnswer);
    final sent = jsonEncode(client.requests.last.map((m) => m.toJson()).toList());
    expect(sent, contains('first-question'));
    expect(sent, isNot(contains('first-old')));
    expect(sent, isNot(contains('second-question')));
    expect(sent, isNot(contains('second-old')));
    expect(view().messages.map((m) => m.text), ['first-question', 'replacement']);
    final saved = (await storage.loadOrCreate(view().id, null)).metadata;
    expect(saved['assistant.branches.v1'], isNotEmpty);
    expect(jsonEncode(saved['assistant.viewBranches.v1']), contains('second-old'));
  });
  test('tool narration never enters body; timestamps and raw failures survive persistence', () async {
    client = ScriptClient([
      sdk.ModelMessage(
        model: 'coding/auto',
        textOutput: 'Let me read the selection.',
        stopReason: 'tool_calls',
        functionCalls: [
          sdk.FunctionCall(id: 'read', name: 'functions.READ-SELECTION', arguments: '{"selectionId":"sel"}'),
        ],
      ),
      answer('**结论：这是选区的解释。**\n- 一个要点。'),
    ]);
    await controller.send(
      '解释它',
      contexts: [const ContextItem(id: 'sel', kind: ContextKind.selection, displayText: '术语')],
    );
    final result = view().messages.last;
    expect(result.text, '**结论：这是选区的解释。**\n- 一个要点。');
    expect(result.text, isNot(contains('Let me')));
    expect(result.traces.last.toolName, 'functions.READ-SELECTION');
    expect(result.startedAt, isNotNull);
    expect(result.endedAt, isNotNull);
    expect(view().title, '解释术语');
    final saved = await storage.loadOrCreate(view().id, null);
    expect(saved.metadata['assistant.diagnostics'], isNotNull);
  });
  test('retry without tools runs once with tools off; the conversation keeps its model', () async {
    final seen = <bool>[];
    factory = (s, c, q) async {
      seen.add(c.model.supportsTools);
      if (seen.length == 1) throw const ResearchFailure(ResearchFailureKind.toolProtocol);
      return createAssistantRun(
        client: client,
        model: 'fake',
        state: s,
        requestId: q.requestId,
        reader: Reader(),
        scope: scopeFromContexts('set', q.contexts),
        mapId: 'map',
        baseRevision: executor.revision,
        parents: executor.parents,
      );
    };
    await controller.send('question');
    expect(view().messages.last.errorKind, ResearchFailureKind.toolProtocol);
    await controller.retry(view().messages.last.id, tools: false);
    expect(seen, [true, false]);
    expect(view().messages.last.status, MessageStatus.done);
    expect(view().messages, hasLength(2));
    expect(view().model.supportsTools, isTrue);
  });

  test('switching from a failed answer retries its question, context and skill with the new model', () async {
    const context = ContextItem(id: 'sel', kind: ContextKind.selection, displayText: '原文');
    const replacement = AssistantModel(
      provider: AssistantProvider.responses,
      model: 'replacement',
      endpoint: 'https://example.com/v1/responses',
      serviceId: 'other-service',
    );
    final seen = <(AssistantModel, Message, bool)>[];
    factory = (s, c, q) async {
      seen.add((c.model, q, c.online));
      if (seen.length == 1) throw const ResearchFailure(ResearchFailureKind.toolProtocol);
      return createAssistantRun(
        client: client,
        model: c.model.model,
        state: s,
        requestId: q.requestId,
        reader: Reader(),
        scope: scopeFromContexts('set', q.contexts),
        mapId: 'map',
        baseRevision: executor.revision,
        parents: executor.parents,
      );
    };
    await controller.setOnline(false);
    await controller.send('解释原文', contexts: [context], skill: 'explain');
    final id = view().id;
    final old = view().messages.last;
    expect(old.status, MessageStatus.error);

    await controller.switchModel(replacement, retryMessageId: old.id);

    expect(seen, hasLength(2));
    expect(seen.last.$1, replacement);
    expect(seen.last.$2.text, '解释原文');
    expect(seen.last.$2.contexts.single.id, context.id);
    expect(seen.last.$2.skill, 'explain');
    expect(seen.last.$3, isFalse);
    expect(view().id, id);
    expect(view().messages, hasLength(2));
    expect(view().messages.last.status, MessageStatus.done);
    expect(view().messages.last.requestId, isNot(old.requestId));
    final saved = (await storage.loadOrCreate(id, null)).metadata;
    expect((saved['assistant.replaced'] as List).single['id'], old.id);
    final persisted = Conversation.fromJson(Map<String, dynamic>.from(saved['assistant.view'] as Map));
    expect(persisted.model.model, replacement.model);
    expect(persisted.messages.last.status, MessageStatus.done);
  });

  test('a failed model recovery stays retryable and does not retry in a loop', () async {
    factory = (s, c, q) async => throw const ResearchFailure(ResearchFailureKind.toolProtocol);
    await controller.send('question');
    final old = view().messages.last;
    await controller.switchModel(model, retryMessageId: old.id);
    expect(factories, 2);
    expect(view().messages, hasLength(2));
    expect(view().messages.last.status, MessageStatus.error);
    expect(view().messages.last.id, isNot(old.id));
    expect(controller.busy, isFalse);
  });

  test('a failed model save does not start recovery or replace the failed answer', () async {
    factory = (s, c, q) async => throw const ResearchFailure(ResearchFailureKind.toolProtocol);
    await controller.send('question');
    final old = view().messages.last;
    storage.fail = true;
    await expectLater(controller.switchModel(model, retryMessageId: old.id), throwsStateError);
    expect(factories, 1);
    expect(view().messages.last.id, old.id);
    expect(controller.busy, isFalse);
  });

  test('new conversations start with the current default model', () async {
    AssistantModel? current;
    final c = ProviderContainer(
      overrides: [
        assistantDependenciesProvider.overrideWithValue(
          AssistantDependencies(
            studySetId: 'set',
            model: model,
            defaultModel: () => current,
            storage: storage,
            executor: executor,
            notes: notes,
            runFactory: (s, c, q) async => throw const ResearchFailure(ResearchFailureKind.unavailable),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final sub = c.listen(assistantControllerProvider, (_, _) {});
    addTearDown(sub.close);
    expect(c.read(assistantControllerProvider).model.model, 'fake');
    current = const AssistantModel(provider: AssistantProvider.gemini, model: 'g', endpoint: 'https://g.example');
    await c.read(assistantControllerProvider.notifier).newConversation();
    expect(c.read(assistantControllerProvider).model.model, 'g');
  });

  test('factory failures use shared classification instead of network fallback', () async {
    factory = (_, _, _) async => throw const ResearchFailure(ResearchFailureKind.toolProtocol);
    await controller.send('question');
    expect(view().messages.last.errorKind, ResearchFailureKind.toolProtocol);
    expect(view().messages.last.endedAt, isNotNull);
  });
  test('generated title is persisted; failed generation keeps placeholder', () async {
    titleGenerator = () async => '主题标题';
    await controller.send('很长的问题');
    expect(view().title, '主题标题');
    await controller.newConversation();
    titleGenerator = () async => throw StateError('title service');
    await controller.send('备用标题');
    expect(view().title, '备用标题');
  });
  test('a manual rename made during title generation wins', () async {
    final pending = Completer<String>();
    final started = Completer<void>();
    titleGenerator = () {
      started.complete();
      return pending.future;
    };
    final sending = controller.send('question');
    await started.future;
    await controller.rename('用户标题');
    pending.complete('自动标题');
    await sending;
    expect(view().title, '用户标题');
  });
  test('three unknown tools produce an ordered, merged failure activity and safe diagnostics', () async {
    client = ScriptClient([for (var i = 0; i < 3; i++) call('unknown', '{}', id: 'bad$i'), answer('**直接回答。**')]);
    await controller.send('解释上下文');
    final result = view().messages.last;
    expect(result.activity.first.count, 3);
    expect(result.activity.first.reason, '不存在的工具 unknown');
    expect(result.activity.last.narration, contains('已关闭本轮工具'));
    expect(result.diagnostics!.tools, hasLength(3));
    expect(result.diagnostics!.fallback, true);
    final saved = Conversation.fromJson((await storage.loadOrCreate(view().id, null)).metadata['assistant.view']);
    expect(saved.messages.last.diagnostics!.tools.first.toolName, 'unknown');
  });
  test('narrations stay between actions and a repeated tool id does not rewrite prior actions', () async {
    client = ScriptClient([
      for (final narration in ['先读取所选内容。', '再读取以确认。'])
        sdk.ModelMessage(
          model: 'fake',
          textOutput: narration,
          stopReason: 'tool_calls',
          functionCalls: [sdk.FunctionCall(id: 'same', name: 'read_selection', arguments: '{"selectionId":"sel"}')],
        ),
      answer('**最终回答。**'),
    ]);
    await controller.send(
      '解释选区',
      contexts: [const ContextItem(id: 'sel', kind: ContextKind.selection, displayText: '术语')],
    );
    final result = view().messages.last;
    expect(result.text, '**最终回答。**');
    expect(result.activity.map((t) => t.narration ?? t.toolName), [
      '先读取所选内容。',
      'read_selection',
      '再读取以确认。',
      'read_selection',
    ]);
    expect(result.traces.where((t) => t.narration == null).map((t) => t.status), everyElement(TraceStatus.done));
  });
  test('legacy conversations reject mutations without contacting the provider', () async {
    final legacy = Conversation(
      id: 'legacy',
      studySetId: 'set',
      model: model,
      online: false,
      readOnly: true,
      messages: [Message(id: 'answer', requestId: 'request', role: MessageRole.agent, text: 'Archive')],
    );
    await storage.save(sdk.AgentState(sessionId: 'legacy', metadata: {'assistant.view': legacy.toJson()}));
    await controller.openConversation('legacy');
    expect(() => controller.send('change'), throwsStateError);
    await expectLater(controller.saveNote('answer', const SaveNoteRequest(title: 'x')), throwsStateError);
    await expectLater(controller.switchModel(model), throwsStateError);
    await expectLater(controller.setOnline(true), throwsStateError);
    await expectLater(controller.selectOperation('p', 'op', true), throwsStateError);
    await expectLater(controller.applyProposal('p'), throwsStateError);
    await expectLater(controller.dismissProposal('p'), throwsStateError);
    await expectLater(controller.reopenProposal('p'), throwsStateError);
    expect(factories, 0);
    await controller.newConversation();
    expect(container.read(assistantControllerProvider).readOnly, isFalse);
    expect(container.read(assistantControllerProvider).online, isTrue);
  });

  test('stream, save, retry original context, new/open and model switching', () async {
    const context = ContextItem(id: 'sel', kind: ContextKind.selection, displayText: 'Selection', auto: true);
    await controller.send('hello', contexts: [context], skill: 'explain');
    expect(view().messages.last.text, 'hello');
    expect(view().messages.last.status, MessageStatus.done);
    expect(() => view().messages.clear(), throwsUnsupportedError);
    await controller.saveNote(view().messages.last.id, const SaveNoteRequest(title: 'Title'));
    expect(notes.notes.values.single.conversationId, view().id);
    final old = view().messages.last;
    await controller.retry(old.id);
    // Regenerating replaces the answer; the old one stays in the saved state only.
    expect(view().messages, hasLength(2));
    expect(view().messages.first.contexts.single.id, 'sel');
    expect(view().messages.last.requestId, isNot(old.requestId));
    expect(view().messages.last.text, 'again');
    final saved = (await storage.loadOrCreate(view().id, null)).metadata;
    expect((saved['assistant.replaced'] as List).single['id'], old.id);
    expect((saved['assistant.view'] as Map)['messages'], hasLength(2));
    await expectLater(controller.retry(view().messages.first.id), throwsStateError);
    await controller.setOnline(false);
    expect(view().online, false);
    await controller.switchModel(
      const AssistantModel(
        provider: AssistantProvider.responses,
        model: 'other',
        endpoint: 'https://api.openai.com/v1/responses',
      ),
    );
    expect(view().model.model, 'other');
    expect(factories, 2); // An ordinary model change does not regenerate a completed answer.
    final id = view().id;
    await controller.newConversation();
    expect(view().messages, isEmpty);
    await controller.openConversation(id);
    expect(view().messages, hasLength(2));
    expect(factories, 2);
  });
  test('proposal lifecycle, dependent selections and duplicate apply', () async {
    client = ScriptClient([
      call(
        'propose_map_edits',
        '{"ops":[{"id":"a","kind":"addTopic","parentId":"root","title":"A"},{"id":"b","kind":"addNote","parentId":"new:a","title":"B","body":"Body"}]}',
      ),
    ]);
    await controller.send('organize', skill: 'organize');
    expect(view().messages.last.traces.single.status, TraceStatus.done);
    final id = view().messages.last.proposals.single.proposal.id;
    await controller.selectOperation(id, 'a', false);
    expect(view().messages.last.proposals.single.selected, isEmpty);
    await expectLater(controller.applyProposal(id), throwsStateError);
    await controller.selectOperation(id, 'b', true);
    expect(view().messages.last.proposals.single.selected, {'a', 'b'});
    await controller.dismissProposal(id);
    expect(view().messages.last.proposals.single.status, ProposalStatus.dismissed);
    await controller.reopenProposal(id);
    await Future.wait([controller.applyProposal(id), controller.applyProposal(id)]);
    expect(executor.applied, hasLength(2));
    expect(view().messages.last.proposals.single.status, ProposalStatus.applied);
    await expectLater(controller.dismissProposal(id), throwsStateError);
    await expectLater(controller.reopenProposal(id), throwsStateError);
    await expectLater(controller.selectOperation(id, 'a', false), throwsStateError);
  });
  test('recover interrupted without provider and reconcile committed receipt', () async {
    final proposal = MapEditProposal(
      id: 'p',
      studySetId: 'set',
      mapId: 'map',
      baseRevision: 0,
      operations: [const MapEditOperation(id: 'a', kind: MapEditKind.addTopic, parentId: 'root', title: 'A')],
    );
    final restored = Conversation(
      id: 'recover',
      studySetId: 'set',
      model: model,
      messages: [
        Message(
          id: 'm',
          requestId: 'r',
          role: MessageRole.agent,
          status: MessageStatus.running,
          text: 'partial',
          proposals: [ProposalView(proposal: proposal)],
        ),
      ],
    );
    await storage.save(
      sdk.AgentState(sessionId: 'recover', isRunning: true, metadata: {'assistant.view': restored.toJson()}),
    );
    await executor.apply(proposal, {'a'});
    await controller.openConversation('recover');
    expect(view().messages.single.status, MessageStatus.interrupted);
    expect(view().messages.single.proposals.single.status, ProposalStatus.applied);
    expect((await storage.loadOrCreate('recover', null)).isRunning, false);
    expect(factories, 0);
  });
  test('persistence failure never requests provider', () async {
    storage.fail = true;
    await expectLater(controller.send('question'), throwsStateError);
    expect(factories, 0);
    expect(view().messages.last.status, MessageStatus.error);
  });
  test('protocol error keeps partial text', () async {
    client = ScriptClient([answer('partial', stop: null)]);
    await controller.send('question');
    expect(view().messages.last.text, 'partial');
    expect(view().messages.last.errorKind, ResearchFailureKind.protocol);
  });
  test('stop during factory prevents late run and duplicate send', () async {
    final gate = Completer<void>();
    factory = (s, c, q) async {
      await gate.future;
      return makeRun(client, state: s);
    };
    final pending = controller.send('question');
    await Future<void>.delayed(Duration.zero);
    expect(() => controller.send('duplicate'), throwsStateError);
    final stopping = controller.stop();
    gate.complete();
    await Future.wait([pending, stopping]);
    expect(client.calls, 0);
    expect(view().messages.last.status, MessageStatus.stopped);
    await controller.newConversation();
    expect(view().messages, isEmpty);
  });
  test('wrong study set cannot replace current state', () async {
    final id = view().id;
    await storage.save(
      sdk.AgentState(
        sessionId: 'wrong',
        metadata: {'assistant.view': Conversation(id: 'wrong', studySetId: 'another', model: model).toJson()},
      ),
    );
    await expectLater(controller.openConversation('wrong'), throwsFormatException);
    expect(view().id, id);
  });
  test('cancel during streamed answer retains partial text and releases stream', () async {
    final output = StreamController<sdk.StreamingMessage>();
    final gotPartial = Completer<void>();
    client = StreamClient((token) {
      token!.whenCancel.then((_) => output.close());
      return output.stream;
    });
    final observer = container.listen(assistantControllerProvider, (_, next) {
      if (next.messages.isNotEmpty && next.messages.last.text == 'partial' && !gotPartial.isCompleted) {
        gotPartial.complete();
      }
    });
    final pending = controller.send('question');
    output.add(sdk.StreamingMessage(modelMessage: answer('partial', stop: null)));
    await gotPartial.future;
    await controller.stop();
    await pending;
    expect(view().messages.last.text, 'partial');
    expect(view().messages.last.status, MessageStatus.stopped);
    expect(output.isClosed, true);
    observer.close();
  });
  test('dispose stops current transport and does not auto restart', () async {
    final output = StreamController<sdk.StreamingMessage>();
    final ready = Completer<void>();
    client = StreamClient((token) {
      token!.whenCancel.then((_) => output.close());
      ready.complete();
      return output.stream;
    });
    final pending = controller.send('question');
    await ready.future;
    container.dispose();
    await pending;
    expect(output.isClosed, true);
    expect(client.calls, 1);
  });
}
