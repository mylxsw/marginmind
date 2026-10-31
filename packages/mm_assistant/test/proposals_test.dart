import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  MapEditProposal proposal(List<MapEditOperation> ops, {String id = 'proposal', int revision = 0}) =>
      MapEditProposal(id: id, studySetId: 'set', mapId: 'map', baseRevision: revision, operations: ops);
  const add = MapEditOperation(id: 'add', kind: MapEditKind.addTopic, parentId: 'root', title: 'Topic');
  test('atomic graph validation, idempotent receipt and revision conflict', () async {
    final executor = MemoryMapEditExecutor(studySetId: 'set', mapId: 'map', parents: {'root': null, 'child': 'root'});
    final p = proposal([
      add,
      const MapEditOperation(id: 'note', kind: MapEditKind.addNote, parentId: 'new:add', title: 'Note', body: 'Body'),
      const MapEditOperation(id: 'quiz', kind: MapEditKind.addReviewCard, parentId: 'root', question: 'Q', answer: 'A'),
      const MapEditOperation(id: 'rename', kind: MapEditKind.rename, nodeId: 'child', title: 'Renamed'),
      const MapEditOperation(id: 'move', kind: MapEditKind.move, nodeId: 'child', parentId: 'new:add'),
    ]);
    final copy = MapEditProposal.fromJson(Map<String, dynamic>.from(p.toJson()));
    await expectLater(executor.apply(copy, {'note'}), throwsFormatException);
    expect(executor.revision, 0);
    expect(executor.applied, isEmpty);
    final receipt = await executor.apply(copy, copy.operations.map((o) => o.id).toSet());
    expect(receipt.operationIds, hasLength(5));
    expect((await executor.apply(copy, {'add'})).undoHandle, receipt.undoHandle);
    expect((await executor.receipt(p.id))!.revision, 1);
    expect(MapEditReceipt.fromJson(Map<String, dynamic>.from(receipt.toJson())).nodeIds, receipt.nodeIds);
    await expectLater(executor.apply(proposal([add], id: 'stale'), {'add'}), throwsStateError);
    await expectLater(executor.apply(proposal([add], id: 'empty', revision: 1), {}), throwsStateError);
  });
  test('invalid operation fields, missing IDs and cycles fail closed', () {
    for (final json in [
      {'id': 'x', 'kind': 'delete'},
      {'id': 'x', 'kind': 'addTopic', 'parentId': 'root'},
      {'id': 'x', 'kind': 'rename', 'nodeId': 'root', 'title': '', 'extra': true},
      {'id': 'x', 'kind': 'rename', 'nodeId': 'root', 'title': 12},
    ]) {
      expect(() => MapEditOperation.fromJson(json), throwsA(anything));
    }
    expect(() => validateOperations([], {'root': null}), throwsFormatException);
    expect(() => validateOperations([add, add], {'root': null}), throwsFormatException);
    expect(
      () => validateOperations(
        [const MapEditOperation(id: 'x', kind: MapEditKind.move, nodeId: 'root', parentId: 'child')],
        {'root': null, 'child': 'root'},
      ),
      throwsFormatException,
    );
    expect(
      () => validateOperations(
        [const MapEditOperation(id: 'x', kind: MapEditKind.rename, nodeId: 'other', title: 'new')],
        {'root': null},
      ),
      throwsFormatException,
    );
  });
  test('document-only edits stay out of conversation schema and hook', () {
    final tools = AssistantTools(
      reader: Reader(),
      scope: ReadScope(studySetId: 'set', documents: {'doc'}, selections: {}, maps: {'map'}),
      cancel: CancellationToken(),
      citations: CitationRegistry(primaryDocumentId: 'doc', online: false),
      budget: RunBudget(),
    ).build();
    final schema = tools.singleWhere((t) => t.name == 'propose_map_edits').parameters;
    final kinds = schema['properties']['ops']['items']['properties']['kind']['enum'];
    expect(kinds, ['addTopic', 'addNote', 'addReviewCard', 'move', 'rename']);
    final run = makeRun(ScriptClient([]), skill: 'organize');
    for (final raw in [
      '{"ops":[{"id":"e","kind":"addExcerpt","parentId":"root","annotationId":"mark"}]}',
      '{"ops":[{"id":"d","kind":"remove","nodeId":"child","reason":"obsolete"}]}',
    ]) {
      final request = call('propose_map_edits', raw);
      expect(
        run.proposals
            .beforeToolCall(
              ToolCallHookContext(
                run.agent,
                call: request.functionCalls.single,
                modelMessage: request,
                availableTools: [],
              ),
            )
            .action,
        ToolCallHookAction.deny,
      );
    }
    expect(run.agent.state.metadata['assistant.proposals'], isNull);
  });
  test('proposal hook duplicate call is stable and malformed proposal denied', () {
    final run = makeRun(ScriptClient([]), skill: 'organize');
    final good = call(
      'propose_map_edits',
      '{"ops":[{"id":"add","kind":"addTopic","parentId":"root","title":"Title"}]}',
    );
    final context = ToolCallHookContext(
      run.agent,
      call: good.functionCalls.single,
      modelMessage: good,
      availableTools: [],
    );
    expect(run.proposals.beforeToolCall(context).action, ToolCallHookAction.defer);
    expect(run.proposals.beforeToolCall(context).action, ToolCallHookAction.defer);
    expect(run.agent.state.metadata['assistant.proposals'], hasLength(1));
    final bad = call('propose_map_edits', '{"ops":[],"delete":true}', id: 'bad');
    expect(
      run.proposals
          .beforeToolCall(
            ToolCallHookContext(run.agent, call: bad.functionCalls.single, modelMessage: bad, availableTools: []),
          )
          .action,
      ToolCallHookAction.deny,
    );
  });
  test('memory note saver retains conversation and placement request', () async {
    final notes = MemoryNoteSaver();
    final id = await notes.save(
      conversationId: 'c',
      messageId: 'm',
      body: 'Body',
      request: const SaveNoteRequest(title: 'Title', mapId: 'map', parentId: 'root'),
    );
    expect(notes.notes[id]!.conversationId, 'c');
    expect(notes.requests[id]!.mapId, 'map');
  });
}
