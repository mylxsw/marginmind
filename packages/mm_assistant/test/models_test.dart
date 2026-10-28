import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('context scope is immutable and only grants explicit locators', () {
    final contexts = [
      for (final k in ContextKind.values)
        ContextItem(
          id: k.name,
          kind: k,
          displayText: 'text',
          documentId: k == ContextKind.page ? 'pageDoc' : 'doc',
          page: 2,
          mapId: k == ContextKind.map ? 'whole' : 'map',
          nodeId: 'node',
          auto: true,
        ),
    ];
    final scope = scopeFromContexts('set', contexts.map((c) => ContextItem.fromJson(c.toJson())).toList());
    expect(scope.allowsPage('doc', 99), true);
    expect(scope.allowsPage('pageDoc', 2), true);
    expect(scope.allowsPage('pageDoc', 3), false);
    expect(scope.allowsBranch('whole', 'any'), true);
    expect(scope.allowsBranch('map', 'node'), true);
    expect(scope.allowsBranch('map', 'other'), false);
    expect(scope.selections, {'selection'});
    expect(() => scope.pages['pageDoc']!.add(3), throwsUnsupportedError);
    final empty = scopeFromContexts('set', []);
    expect(empty.allowsPage('doc', 1), false);
  });
  test('study-set documents stay readable beyond the focused page and without contexts', () {
    final documents = {'doc', 'other-doc'};
    final scope = scopeFromContexts('set', const [
      ContextItem(id: 'sel', kind: ContextKind.selection, displayText: '术语', documentId: 'doc', page: 194),
      ContextItem(id: 'page', kind: ContextKind.page, displayText: '书名', documentId: 'doc', page: 194, auto: true),
    ], documentIds: documents);
    documents.add('outside');
    for (final page in [1, 193, 194, 195, 300]) {
      expect(scope.allowsPage('doc', page), true);
    }
    expect(scope.allowsPage('other-doc', 1), true);
    expect(scope.allowsPage('outside', 1), false);
    expect(scope.allowsPage('doc', 0), false);
    expect(scope.selections, {'sel'});
    expect(scope.allowsBranch('map', 'node'), false);
    final withoutFocus = scopeFromContexts('set', [], documentIds: ['doc']);
    expect(withoutFocus.allowsPage('doc', 194), true);
    expect(() => scope.documents.add('outside'), throwsUnsupportedError);
  });
  test('view roundtrip retains status, citation and receipt without exposing mutable lists', () {
    final p = MapEditProposal(
      id: 'p',
      studySetId: 's',
      mapId: 'm',
      baseRevision: 0,
      operations: [const MapEditOperation(id: 'op', kind: MapEditKind.rename, nodeId: 'n', title: 'T')],
    );
    final receipt = MapEditReceipt(proposalId: 'p', revision: 1, undoHandle: 'u', operationIds: ['op'], nodeIds: ['n']);
    final conversation = Conversation(
      id: 'c',
      studySetId: 's',
      model: const AssistantModel(
        provider: AssistantProvider.responses,
        model: 'model',
        endpoint: 'https://api.openai.com/v1/responses',
      ),
      messages: [
        Message(
          id: 'a',
          requestId: 'r',
          role: MessageRole.agent,
          status: MessageStatus.error,
          errorKind: ResearchFailureKind.protocol,
          text: '[page:1]',
          online: true,
          noteId: 'n',
          traces: [const TraceStep('t', 'read_pages', TraceStatus.done)],
          citations: [const Citation(marker: '[page:1]', documentId: 'd', page: 1)],
          proposals: [ProposalView(proposal: p, status: ProposalStatus.applied, receipt: receipt)],
        ),
      ],
    );
    final copy = Conversation.fromJson(conversation.toJson());
    expect(copy.messages.single.errorKind, ResearchFailureKind.protocol);
    expect(copy.messages.single.proposals.single.receipt!.undoHandle, 'u');
    expect(copy.messages.single.citations.single.external, false);
    expect(copy.running, false);
    expect(copy.messages.single.copyWith(status: MessageStatus.running).status, MessageStatus.running);
    expect(() => copy.messages.single.proposals.single.selected.clear(), throwsUnsupportedError);
  });
}
