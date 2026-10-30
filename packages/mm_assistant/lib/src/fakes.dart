import 'package:mm_core/mm_core.dart';

import 'hooks.dart';

/// Test/staging executor. Real adapters must persist receipts with the graph.
class MemoryMapEditExecutor implements MapEditExecutor {
  MemoryMapEditExecutor({
    required this.studySetId,
    required this.mapId,
    this.revision = 0,
    Map<String, String?> parents = const {},
  }) : parents = Map.of(parents);
  final String studySetId, mapId;
  int revision;
  Map<String, String?> parents;
  final _receipts = <String, MapEditReceipt>{};
  final applied = <MapEditOperation>[];
  @override
  Future<MapEditReceipt?> receipt(String proposalId) async => _receipts[proposalId];
  @override
  Future<MapEditReceipt> apply(MapEditProposal p, Set<String> selectedIds) async {
    final previous = _receipts[p.id];
    if (previous != null) return previous;
    if (p.studySetId != studySetId ||
        p.mapId != mapId ||
        p.baseRevision != revision ||
        selectedIds.isEmpty ||
        selectedIds.any((id) => !p.operations.any((o) => o.id == id))) {
      throw StateError('Stale or invalid proposal');
    }
    final ops = p.operations.where((o) => selectedIds.contains(o.id)).toList();
    validateOperations(ops, parents, expansion: p.isExpansion);
    final next = Map<String, String?>.of(parents);
    final affected = <String>[];
    final temporary = <String, String>{};
    String? resolve(String? id) => temporary[id] ?? id;
    for (final op in ops) {
      final id = resolve(op.nodeId) ?? '${p.id}:${op.id}';
      if (op.nodeId == null) temporary['new:${op.id}'] = id;
      if (op.kind != MapEditKind.rename) next[id] = resolve(op.parentId);
      affected.add(id);
    }
    parents = next;
    applied.addAll(ops);
    return _receipts[p.id] = MapEditReceipt(
      proposalId: p.id,
      revision: ++revision,
      undoHandle: 'undo:${p.id}',
      operationIds: ops.map((o) => o.id).toList(),
      nodeIds: affected,
    );
  }
}

class MemoryNoteSaver implements NoteSaver {
  final notes = <String, ResearchNote>{};
  final requests = <String, SaveNoteRequest>{};
  @override
  Future<String> save({
    required String conversationId,
    required String messageId,
    required String body,
    required SaveNoteRequest request,
  }) async {
    final id = '$conversationId:$messageId';
    requests[id] = request;
    final now = DateTime.now().toUtc();
    notes[id] = ResearchNote(
      id: id,
      title: request.title,
      body: body,
      conversationId: conversationId,
      origin: NoteOrigin.ai,
      textFormat: TextFormat.markdown,
      createdAt: now,
      updatedAt: now,
    );
    return id;
  }
}

class MemoryAssistantNetwork implements AssistantNetwork {
  MemoryAssistantNetwork({this.results = const [], this.sources = const []});
  final List<AssistantSearchResult> results;
  final List<AssistantSource> sources;
  @override
  Future<List<AssistantSearchResult>> search(String keywords, CancellationToken cancel) async {
    cancel.check();
    return results;
  }

  @override
  Future<List<AssistantSource>> papers(String keywords, CancellationToken cancel) async {
    cancel.check();
    return sources.where((s) => s.kind == 'openAlex').toList();
  }

  @override
  Future<AssistantSource> fetch(Uri url, CancellationToken cancel) async {
    cancel.check();
    return sources.firstWhere(
      (s) => s.url == url,
      orElse: () => throw const ResearchFailure(ResearchFailureKind.unavailable),
    );
  }
}
