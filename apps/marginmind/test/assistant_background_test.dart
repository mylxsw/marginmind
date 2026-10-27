import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../../packages/mm_assistant/test/support.dart';
import 'assistant_controller_test.dart' show MemoryStorage, model;

/// Answers [replies] in order; a reply whose index has a gate waits for it,
/// and a cancelled request ends at once, as a real one does.
class GatedClient extends StreamClient {
  GatedClient(List<sdk.ModelMessage> replies) : this._(_Gates(replies));
  GatedClient._(_Gates gates) : _gates = gates, super(gates.next);
  final _Gates _gates;

  /// Replies the model gave, not counting cancelled requests.
  int get answered => _gates.answered;
  Completer<void> gate(int call) => _gates.gates[call] = Completer<void>();
  Future<void> waitStarted(int call) => _gates.started(call).future;
}

class _Gates {
  _Gates(this.replies);
  final List<sdk.ModelMessage> replies;
  final gates = <int, Completer<void>>{};
  final _started = <int, Completer<void>>{};
  var requests = 0, answered = 0;
  Completer<void> started(int call) => _started[call] ??= Completer<void>();

  Stream<sdk.StreamingMessage> next(CancelToken? token) {
    final index = requests++;
    started(index).complete();
    return Stream.fromFuture(() async {
      final gate = gates[index];
      if (gate != null) {
        await Future.any([gate.future, if (token != null) token.whenCancel]);
        if (token?.isCancelled ?? false) throw StateError('cancelled');
      }
      answered++;
      return sdk.StreamingMessage(modelMessage: replies[index]);
    }());
  }
}

/// Receipts the test can take away and bring back, as undo and redo do.
class ReceiptExecutor implements MapEditExecutor {
  final receipts = <String, MapEditReceipt>{};
  var applies = 0;
  @override
  Future<MapEditReceipt?> receipt(String proposalId) async => receipts[proposalId];
  @override
  Future<MapEditReceipt> apply(MapEditProposal proposal, Set<String> selectedIds) async {
    applies++;
    return receipts[proposal.id] = MapEditReceipt(
      proposalId: proposal.id,
      revision: applies,
      undoHandle: proposal.id,
      operationIds: selectedIds.toList(),
      nodeIds: ['node-$applies'],
    );
  }
}

void main() {
  late ProviderContainer container;
  late AssistantController controller;
  late MemoryStorage storage;
  late ReceiptExecutor executor;
  late GatedClient client;
  late ProviderSubscription<Conversation> subscription;
  setUp(() {
    storage = MemoryStorage();
    executor = ReceiptExecutor();
    client = GatedClient([answer('first answer'), answer('second answer'), answer('third answer')]);
    container = ProviderContainer(
      overrides: [
        assistantDependenciesProvider.overrideWithValue(
          AssistantDependencies(
            studySetId: 'set',
            model: model,
            storage: storage,
            executor: executor,
            notes: MemoryNoteSaver(),
            runFactory: (s, c, q) async => createAssistantRun(
              client: client,
              model: 'fake',
              state: s,
              requestId: q.requestId,
              reader: Reader(),
              scope: scopeFromContexts('set', q.contexts),
              mapId: 'map',
              baseRevision: 0,
              parents: {'root': null},
              skill: q.skill,
              online: c.online,
            ),
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
  Conversation? background() => container.read(assistantBackgroundProvider);
  Future<Conversation> saved(String id) async => Conversation.fromJson(
    Map<String, dynamic>.from((await storage.loadOrCreate(id, null)).metadata['assistant.view']),
  );

  group('answers out of view', () {
    test('a new conversation leaves the answer running; coming back shows it live', () async {
      final gate = client.gate(0);
      final pending = controller.send('first');
      await client.waitStarted(0);
      final first = view().id;
      expect(controller.busy, isTrue);
      expect(background(), isNull);

      await controller.newConversation();
      expect(view().messages, isEmpty);
      expect(background()!.id, first);
      expect(background()!.running, isTrue);
      expect(controller.busy, isTrue);
      // One answer at a time per study set.
      expect(() => controller.send('second'), throwsStateError);
      final list = mergeLive(const [], view(), background: background());
      expect(list.single.id, first);
      expect(list.single.state, ConversationState.running);

      await controller.openConversation(first);
      expect(view().id, first);
      expect(view().running, isTrue);
      expect(background(), isNull);

      await controller.newConversation();
      final other = view().id;
      gate.complete();
      await pending;
      expect(controller.busy, isFalse);
      expect(background(), isNull);
      expect(view().id, other);
      expect((await saved(first)).messages.last.text, 'first answer');
      expect((await saved(first)).messages.last.status, MessageStatus.done);

      await controller.openConversation(first);
      expect(view().messages.last.text, 'first answer');
      await controller.send('again');
      expect(view().messages.last.text, 'second answer');
    });

    test('opening a saved conversation keeps the answer running in the other', () async {
      await controller.send('first');
      final first = view().id;
      await controller.newConversation();
      final gate = client.gate(1);
      final pending = controller.send('second');
      await client.waitStarted(1);
      final second = view().id;
      await controller.openConversation(first);
      expect(view().id, first);
      expect(background()!.id, second);
      gate.complete();
      await pending;
      expect(background(), isNull);
      // The open conversation did not change while the other one finished.
      expect(view().id, first);
      expect(view().messages, hasLength(2));
      expect((await saved(second)).messages.last.text, 'second answer');
    });

    test('stop and model switches act on the open conversation; stopConversation on any', () async {
      final gate = client.gate(0);
      final pending = controller.send('first');
      await client.waitStarted(0);
      final first = view().id;
      await controller.newConversation();
      await controller.stop();
      await controller.setOnline(false);
      await controller.switchModel(model);
      expect(background()!.running, isTrue);
      await controller.stopConversation('unknown');
      expect(background(), isNotNull);

      await controller.stopConversation(first);
      expect(background(), isNull);
      expect(controller.busy, isFalse);
      gate.complete();
      await pending;
      expect((await saved(first)).messages.last.status, MessageStatus.stopped);
      expect(client.answered, 0);
    });

    test('renaming the conversation answering out of view keeps the new title', () async {
      final gate = client.gate(0);
      final pending = controller.send('first');
      await client.waitStarted(0);
      final first = view().id;
      await controller.newConversation();
      expect(await controller.rename('Renamed', conversationId: first), isTrue);
      expect(background()!.title, 'Renamed');
      expect(await controller.rename('Elsewhere', conversationId: 'saved-only'), isFalse);
      expect(await controller.rename('Open'), isTrue);
      expect(view().title, 'Open');
      gate.complete();
      await pending;
      expect((await saved(first)).title, 'Renamed');
      await expectLater(controller.rename(' '), throwsFormatException);
    });

    test('closing the window stops an answer running out of view', () async {
      final gate = client.gate(0);
      final pending = controller.send('first');
      await client.waitStarted(0);
      await controller.newConversation();
      subscription.close();
      container.dispose();
      gate.complete();
      await pending;
      // The request was cancelled before the model answered.
      expect(client.answered, 0);
    });
  });

  group('undone proposals', () {
    const ops =
        '{"ops":[{"id":"a","kind":"addTopic","parentId":"root","title":"A"},{"id":"b","kind":"addTopic","parentId":"root","title":"B"}]}';

    Future<String> propose() async {
      client = GatedClient([call('propose_map_edits', ops)]);
      await controller.send('organize', skill: 'organize');
      return view().messages.last.proposals.single.proposal.id;
    }

    ProposalView proposal() => view().messages.last.proposals.single;

    test('an undone apply is pending again and can be applied again; redo shows it applied', () async {
      final id = await propose();
      await controller.selectOperation(id, 'b', false);
      await controller.applyProposal(id);
      expect(proposal().status, ProposalStatus.applied);

      // Undo takes the receipt away.
      final receipt = executor.receipts.remove(id)!;
      await controller.syncReceipts();
      expect(proposal().status, ProposalStatus.pending);
      expect(proposal().receipt, isNull);
      expect(proposal().selected, {'a'});
      final stored = (await storage.loadOrCreate(view().id, null)).metadata['assistant.proposalViews'] as List;
      expect(stored.single['status'], 'pending');

      // Checked again and applied a second time, not mistaken for the first.
      await controller.selectOperation(id, 'b', true);
      await controller.applyProposal(id);
      expect(executor.applies, 2);
      expect(proposal().status, ProposalStatus.applied);
      expect(proposal().selected, {'a', 'b'});

      // Redo of the first apply brings its receipt back.
      executor.receipts[id] = receipt;
      await controller.syncReceipts();
      expect(proposal().status, ProposalStatus.applied);
      expect(proposal().receipt!.revision, receipt.revision);
      // Nothing changed: the proposal stays as it is.
      final before = proposal();
      await controller.syncReceipts();
      expect(identical(proposal(), before), isTrue);
    });

    test('overlapping syncs end with the latest receipts', () async {
      final id = await propose();
      await controller.applyProposal(id);
      final receipt = executor.receipts.remove(id)!;
      final undo = controller.syncReceipts();
      executor.receipts[id] = receipt; // Redo before the first sync looked.
      final redo = controller.syncReceipts();
      await Future.wait([undo, redo]);
      expect(proposal().status, ProposalStatus.applied);
    });

    test('revertProposal returns an undone proposal to pending, never one still applied', () async {
      final id = await propose();
      await expectLater(controller.revertProposal(id), throwsStateError);
      await controller.applyProposal(id);
      await expectLater(controller.revertProposal(id), throwsStateError);
      expect(proposal().status, ProposalStatus.applied);
      executor.receipts.remove(id);
      await controller.revertProposal(id);
      expect(proposal().status, ProposalStatus.pending);
      expect(proposal().selected, {'a', 'b'});
      await expectLater(controller.revertProposal('missing'), throwsStateError);
    });

    test('dismissed proposals stay dismissed; opening a conversation drops a lost receipt', () async {
      final id = await propose();
      await controller.dismissProposal(id);
      executor.receipts[id] = MapEditReceipt(
        proposalId: id,
        revision: 9,
        undoHandle: id,
        operationIds: const ['a'],
        nodeIds: const [],
      );
      await controller.syncReceipts();
      expect(proposal().status, ProposalStatus.dismissed);

      await controller.reopenProposal(id);
      executor.receipts.clear();
      await controller.applyProposal(id);
      final conversation = view().id;
      await controller.newConversation();
      executor.receipts.clear(); // Undone, then the window closed.
      await controller.openConversation(conversation);
      expect(proposal().status, ProposalStatus.pending);
    });
  });
}
