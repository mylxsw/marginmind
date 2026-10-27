import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_writes.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';

void main() {
  late ProviderContainer container;
  late WorkspaceController workspace;
  late MapEditExecutor executor;
  late NoteSaver notes;
  setUp(() async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    container = ProviderContainer(overrides: await testOverrides(content: repo));
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    workspace = container.read(workspaceProvider('demo-1').notifier);
    executor = container.read(assistantMapEditExecutorProvider('demo-1'));
    notes = container.read(assistantNoteSaverProvider('demo-1'));
  });
  tearDown(() => container.dispose());
  test('combined proposal is one undo step, updates counts and recovers receipt', () async {
    final before = workspace.content.cards.length;
    final due = workspace.content.dueCount(testNow);
    final p = MapEditProposal(
      id: 'p',
      studySetId: 'demo-1',
      mapId: 'main',
      baseRevision: assistantMapRevision(workspace.content, 'main'),
      operations: const [
        MapEditOperation(id: 't', kind: MapEditKind.addTopic, parentId: 'main', title: 'New'),
        MapEditOperation(id: 'q', kind: MapEditKind.addReviewCard, parentId: 'new:t', question: 'Q', answer: 'A'),
        MapEditOperation(id: 'r', kind: MapEditKind.rename, nodeId: 'new:t', title: 'Renamed'),
      ],
    );
    final both = await Future.wait([
      executor.apply(p, {'t', 'q', 'r'}),
      executor.apply(p, {'t', 'q', 'r'}),
    ]);
    expect(both[0].toJson(), both[1].toJson());
    expect(workspace.content.cards.length, before + 2);
    expect(workspace.content.dueCount(testNow), due + 1);
    expect(container.read(workspaceProvider('demo-1')).flashCardId, both.first.nodeIds.last);
    expect((await executor.receipt('p'))!.nodeIds.length, 2);
    expect(await executor.receipt('unknown'), isNull);
    await workspace.undo();
    expect(workspace.content.cards.length, before);
    expect(workspace.content.dueCount(testNow), due);
    expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
    // Undo voids the receipt, so the proposal is not taken for applied.
    expect(await executor.receipt('p'), isNull);
    await workspace.redo();
    expect(workspace.content.cards.length, before + 2);
    expect((await executor.receipt('p'))!.proposalId, 'p');
    await workspace.beginTransaction();
    await expectLater(executor.apply(p, {'t'}), throwsStateError);
    await workspace.abortTransaction();
  });
  test('an undone proposal applies again as a new undo step', () async {
    final before = workspace.content.cards.length;
    final p = MapEditProposal(
      id: 'again',
      studySetId: 'demo-1',
      mapId: 'main',
      baseRevision: assistantMapRevision(workspace.content, 'main'),
      operations: const [MapEditOperation(id: 't', kind: MapEditKind.addTopic, parentId: 'main', title: 'Again')],
    );
    final first = await executor.apply(p, {'t'});
    await workspace.undo();
    expect(workspace.content.cards.length, before);
    final second = await executor.apply(p, {'t'});
    expect(second.nodeIds, hasLength(1));
    expect(workspace.content.cards.length, before + 1);
    expect(workspace.content.assistantReceipts.where((r) => r.proposalId == 'again'), hasLength(1));
    expect(first.proposalId, second.proposalId);
    // Redo history was replaced by the new apply; undo takes it away again.
    expect(container.read(workspaceProvider('demo-1')).canRedo, isFalse);
    await workspace.undo();
    expect(await executor.receipt('again'), isNull);
    expect(workspace.content.cards.length, before);
  });

  test('every nonempty operation combination undoes and redoes as one step', () async {
    const ops = [
      MapEditOperation(id: 't', kind: MapEditKind.addTopic, parentId: 'main', title: 'Topic'),
      MapEditOperation(id: 'n', kind: MapEditKind.addNote, parentId: 'c3', title: 'Note', body: 'Body'),
      MapEditOperation(
        id: 'q',
        kind: MapEditKind.addReviewCard,
        parentId: 'c3',
        question: 'Question',
        answer: 'Answer',
      ),
      MapEditOperation(id: 'm', kind: MapEditKind.move, nodeId: 'c6', parentId: 'c4'),
      MapEditOperation(id: 'r', kind: MapEditKind.rename, nodeId: 'c3', title: 'Renamed'),
    ];
    Map<String, Object?> edits(StudySetContent c) => {...c.toJson()}..remove('assistantReceipts');
    for (var mask = 1; mask < 32; mask++) {
      final before = workspace.content;
      final selected = {
        for (var i = 0; i < ops.length; i++)
          if (mask & (1 << i) != 0) ops[i].id,
      };
      final proposal = MapEditProposal(
        id: 'combination-$mask',
        studySetId: 'demo-1',
        mapId: 'main',
        baseRevision: assistantMapRevision(before, 'main'),
        operations: ops,
      );
      final receipt = await executor.apply(proposal, selected);
      expect(receipt.operationIds.toSet(), selected);
      final applied = workspace.content;
      if (receipt.nodeIds.isNotEmpty) {
        expect(container.read(workspaceProvider('demo-1')).flashCardIds, receipt.nodeIds.toSet());
      }
      await workspace.undo();
      expect(edits(workspace.content), edits(before));
      expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
      await workspace.redo();
      expect(edits(workspace.content), edits(applied));
      await workspace.undo();
    }
  });

  test('AI note save retry, PDF and map, delete and history', () async {
    await expectLater(
      notes.save(
        conversationId: 'c',
        messageId: '',
        body: 'b',
        request: const SaveNoteRequest(title: 'x', mapId: 'main'),
      ),
      throwsArgumentError,
    );
    final before = workspace.content;
    final doc = before.documents.first;
    final request = SaveNoteRequest(
      title: 'AI',
      mapId: 'main',
      anchor: SourceAnchor(
        target: PdfTarget(
          documentId: doc.id,
          pages: const [AnnotationPage(page: 1, rects: [])],
        ),
      ),
    );
    final id = await notes.save(conversationId: 'conversation', messageId: 'message', body: 'Answer', request: request);
    expect(
      await notes.save(conversationId: 'conversation', messageId: 'message', body: 'Answer', request: request),
      id,
    );
    expect(workspace.content.researchNote(id)!.conversationId, 'conversation');
    expect(workspace.content.noteAttachments.where((a) => a.noteId == id).length, 2);
    await workspace.undo();
    expect(workspace.content.researchNote(id), isNull);
    expect(container.read(workspaceProvider('demo-1')).canUndo, isFalse);
    await workspace.redo();
    await workspace.setCardBody(workspace.content.cards.last.id, 'Updated');
    expect(workspace.content.cards.last.body, 'Updated');
    await workspace.deleteResearchNote(id);
    expect(workspace.content.noteAttachments.where((a) => a.noteId == id), isEmpty);
    await workspace.undo();
    expect(workspace.content.researchNote(id), isNotNull);
  });
  testWidgets('review answer is visible and editable in card details', (tester) async {
    final app = await pumpApp(tester);
    await tester.tap(find.text('Starred'));
    await tester.pumpAndSettle();
    await doubleTap(tester, find.text('认知科学入门'));
    final workspace = app.read(workspaceProvider('demo-1').notifier);
    final proposal = MapEditProposal(
      id: 'body-ui',
      studySetId: 'demo-1',
      mapId: 'main',
      baseRevision: assistantMapRevision(workspace.content, 'main'),
      operations: const [
        MapEditOperation(
          id: 'q',
          kind: MapEditKind.addReviewCard,
          parentId: 'main',
          question: 'Question?',
          answer: 'Answer',
        ),
      ],
    );
    final receipt = await app.read(assistantMapEditExecutorProvider('demo-1')).apply(proposal, {'q'});
    workspace.showDetails(receipt.nodeIds.single);
    await tester.pumpAndSettle();
    final body = find.descendant(
      of: find.byKey(ValueKey('details-body-${receipt.nodeIds.single}')),
      matching: find.byType(TextField),
    );
    expect(body, findsOneWidget);
    await tester.enterText(body, 'Revised answer');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(workspace.content.card(receipt.nodeIds.single)!.body, 'Revised answer');
    expect(
      buildReviewFace(workspace.content.card(receipt.nodeIds.single)!, workspace.content).back.notes.first.text,
      'Revised answer',
    );
    expect(tester.takeException(), isNull);
  });
}
