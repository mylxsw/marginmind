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
  setUp(() {
    storage = MemoryStorage();
    executor = MemoryMapEditExecutor(studySetId: 'set', mapId: 'map', parents: {'root': null});
    notes = MemoryNoteSaver();
    client = ScriptClient([answer('hello'), answer('again')]);
    factories = 0;
    factory = null;
    container = ProviderContainer(
      overrides: [
        assistantDependenciesProvider.overrideWithValue(
          AssistantDependencies(
            studySetId: 'set',
            model: model,
            storage: storage,
            executor: executor,
            notes: notes,
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
