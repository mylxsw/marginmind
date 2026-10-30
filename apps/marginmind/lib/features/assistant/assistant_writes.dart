import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../workspace/workspace_controller.dart';

final assistantMapEditExecutorProvider = Provider.family<MapEditExecutor, String>((ref, studySetId) {
  final editor = ref.watch(editorProvider);
  return WorkspaceMapEditExecutor(
    ref.watch(workspaceProvider(studySetId).notifier),
    ref.watch(contentRepositoryProvider),
    AssistantWrites(studySetId: studySetId, newId: editor.newId, now: editor.now),
  );
});
final assistantNoteSaverProvider = Provider.family<NoteSaver, String>((ref, studySetId) {
  final editor = ref.watch(editorProvider);
  return WorkspaceNoteSaver(
    ref.watch(workspaceProvider(studySetId).notifier),
    AssistantWrites(studySetId: studySetId, newId: editor.newId, now: editor.now),
  );
});

class WorkspaceMapEditExecutor implements MapEditExecutor {
  WorkspaceMapEditExecutor(this.workspace, this.repository, this.writes);
  final WorkspaceController workspace;
  final StudySetContentRepository repository;
  final AssistantWrites writes;
  @override
  Future<MapEditReceipt?> receipt(String proposalId) async =>
      (await repository.load(writes.studySetId)).assistantReceipts.where((r) => r.proposalId == proposalId).firstOrNull;
  @override
  Future<MapEditReceipt> apply(MapEditProposal proposal, Set<String> selectedIds) async {
    final selection = Set<String>.of(selectedIds);
    final next = await workspace.applyAssistantChange(
      (c) => writes.apply(c, proposal, selection),
      expansion: proposal.isExpansion,
    );
    final result = next.assistantReceipts.firstWhere((r) => r.proposalId == proposal.id);
    workspace.flashAssistantNodes(result.nodeIds);
    return result;
  }
}

class WorkspaceNoteSaver implements NoteSaver {
  WorkspaceNoteSaver(this.workspace, this.writes);
  final WorkspaceController workspace;
  final AssistantWrites writes;
  @override
  Future<String> save({
    required String conversationId,
    required String messageId,
    required String body,
    required SaveNoteRequest request,
  }) async {
    if (messageId.trim().isEmpty) throw ArgumentError('Missing message ID');
    // A retry after conversation persistence failed resolves to the same note.
    final id = 'assistant-note:${conversationId.length}:$conversationId:$messageId';
    final next = await workspace.applyAssistantChange(
      (c) => writes.saveNote(c, noteId: id, conversationId: conversationId, body: body, request: request),
    );
    workspace.flashAssistantNodes([
      for (final card in next.cards)
        if (card.researchNoteId == id) card.id,
    ]);
    return id;
  }
}
