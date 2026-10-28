import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../research/research_origin.dart' show researchCardTitle;

/// The id the map's root has in contexts and proposals: it is not a card.
/// Same as the map canvas's root node.
const assistantRootId = '__root__';

/// The study set as the assistant may read it, one run at a time. Selected
/// text comes from the question's own contexts, so a conversation reopened
/// after a restart reads exactly what the user attached. Every method checks
/// [ReadScope] again; the tools check it first.
class WorkspaceReader implements StudySetReader, ReadPermissionResolver {
  WorkspaceReader({required this.content, required this.contexts, required this.filePath, required this.pageText});

  final StudySetContent Function() content;
  final List<ContextItem> contexts;
  final String Function(Document document) filePath;
  final Future<String?> Function(String path, int page) pageText;

  static const maxBranchNodes = 200;

  @override
  ReadPermissionRequest? describeReadPermission(String tool, Map<String, dynamic> arguments) {
    final c = content();
    switch (tool) {
      case 'read_pages':
        final document = c.document(arguments['documentId'] as String);
        final from = arguments['from'] as int, to = arguments['to'] as int;
        if (document == null || from < 1 || to < from || to > document.pageCount) return null;
        return ReadPermissionRequest(
          kind: ReadPermissionKind.pages,
          title: document.title,
          targetId: document.id,
          documentId: document.id,
          from: from,
          to: to,
        );
      case 'read_selection':
        final item = contexts
            .where((item) => item.id == arguments['selectionId'] && item.kind == ContextKind.selection)
            .firstOrNull;
        if (item == null || item.documentId == null || c.document(item.documentId!) == null) return null;
        return ReadPermissionRequest(
          kind: ReadPermissionKind.selection,
          title: item.displayText,
          targetId: item.id,
          documentId: item.documentId,
          from: item.page,
          to: item.page,
        );
      case 'read_branch':
        final map = c.map(arguments['mapId'] as String);
        final nodeId = arguments['nodeId'] as String;
        if (map == null || (nodeId != assistantRootId && c.node(nodeId, mapId: map.id) == null)) return null;
        return ReadPermissionRequest(
          kind: nodeId == assistantRootId ? ReadPermissionKind.map : ReadPermissionKind.branch,
          title: nodeId == assistantRootId ? map.title : researchCardTitle(c, nodeId),
          targetId: nodeId,
          mapId: map.id,
        );
      default:
        return null;
    }
  }

  @override
  Future<List<ReadPage>> readSelection(String selectionId, ReadScope scope, CancellationToken cancel) async {
    cancel.check();
    if (!scope.selections.contains(selectionId)) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    final item = contexts.where((c) => c.id == selectionId && c.kind == ContextKind.selection).firstOrNull;
    if (item == null || item.documentId == null || content().document(item.documentId!) == null) return const [];
    return [ReadPage(item.documentId!, item.page ?? 1, item.displayText)];
  }

  @override
  Future<List<ReadPage>> readPages(
    String documentId,
    int from,
    int to,
    ReadScope scope,
    CancellationToken cancel,
  ) async {
    final document = content().document(documentId);
    if (document == null) return const [];
    final pages = <ReadPage>[];
    for (var page = from; page <= to && page <= document.pageCount; page++) {
      cancel.check();
      if (!scope.allowsPage(documentId, page)) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
      final text = await pageText(filePath(document), page);
      if (text != null && text.trim().isNotEmpty) pages.add(ReadPage(documentId, page, text));
    }
    cancel.check();
    return pages;
  }

  @override
  Future<List<StudySearchHit>> searchStudySet(
    String query,
    int limit,
    ReadScope scope,
    CancellationToken cancel,
  ) async {
    cancel.check();
    final c = content();
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final hits = <StudySearchHit>[];
    for (final a in c.annotations) {
      if (hits.length >= limit) break;
      if (a.quote.toLowerCase().contains(needle) && scope.allowsPage(a.documentId, a.page)) {
        hits.add(StudySearchHit(title: a.quote, locator: 'page:${a.documentId}:${a.page}'));
      }
    }
    for (final n in c.nodes) {
      if (hits.length >= limit) break;
      if (!_inScope(c, scope, n.mapId, n.cardId)) continue;
      final title = researchCardTitle(c, n.cardId);
      if (title.toLowerCase().contains(needle)) {
        hits.add(StudySearchHit(title: title, locator: 'node:${n.mapId}:${n.cardId}'));
      }
    }
    return hits;
  }

  @override
  Future<List<BranchNode>> readBranch(String mapId, String nodeId, ReadScope scope, CancellationToken cancel) async {
    cancel.check();
    if (!scope.allowsBranch(mapId, nodeId)) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    final c = content();
    final out = <BranchNode>[];
    final root = nodeId == assistantRootId;
    if (!root) {
      final node = c.node(nodeId, mapId: mapId);
      if (node == null) return const [];
      out.add(_branchNode(c, nodeId, node.parentId ?? assistantRootId));
    }
    final queue = [if (root) null else nodeId];
    while (queue.isNotEmpty && out.length < maxBranchNodes) {
      final parent = queue.removeAt(0);
      for (final child in c.childrenOf(parent, mapId: mapId)) {
        if (out.length >= maxBranchNodes) break;
        out.add(_branchNode(c, child.cardId, parent ?? assistantRootId));
        queue.add(child.cardId);
      }
    }
    return out;
  }

  BranchNode _branchNode(StudySetContent c, String id, String parentId) {
    final card = c.card(id);
    final body = card?.kind == CardKind.research ? c.researchNote(card!.researchNoteId ?? '')?.body ?? '' : '';
    return BranchNode(id: id, parentId: parentId, title: researchCardTitle(c, id), body: body);
  }

  /// Whether [cardId] of [mapId] is inside an authorized map or branch.
  static bool _inScope(StudySetContent c, ReadScope scope, String mapId, String cardId) {
    if (scope.maps.contains(mapId)) return true;
    final roots = scope.branches[mapId];
    if (roots == null) return false;
    if (roots.contains(assistantRootId)) return true;
    String? id = cardId;
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      if (roots.contains(id)) return true;
      id = c.node(id, mapId: mapId)?.parentId;
    }
    return false;
  }
}

/// The target map's nodes and their parents, for proposals. The map's root
/// is the map ID itself (the writes contract): top-level nodes hang under it.
Map<String, String?> mapParents(StudySetContent content, String mapId) => {
  mapId: null,
  for (final n in content.nodes)
    if (n.mapId == mapId) n.cardId: n.parentId ?? mapId,
};
