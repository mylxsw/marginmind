import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../content/editor.dart';
import '../content/models.dart';
import '../content/research.dart';
import '../content/study_set_content.dart';
import 'proposals.dart';

/// Stable across restarts and sensitive to all editable map content. Receipt
/// bookkeeping and reader/review metadata do not invalidate a proposal.
int assistantMapRevision(StudySetContent content, String mapId) {
  final ids = content.nodes.where((n) => n.mapId == mapId).map((n) => n.cardId).toSet();
  final value = {
    'map': content.map(mapId)?.toJson(),
    'nodes': [
      for (final n in content.nodes)
        if (n.mapId == mapId) n.toJson(),
    ],
    'cards': [
      for (final c in content.cards)
        if (ids.contains(c.id)) c.toJson(),
    ],
    'notes': [
      for (final n in content.researchNotes)
        if (content.cards.any((c) => ids.contains(c.id) && c.researchNoteId == n.id)) n.toJson(),
    ],
  };
  return int.parse(sha256.convert(utf8.encode(jsonEncode(value))).toString().substring(0, 12), radix: 16);
}

/// Pure transaction body. The host persists its result once through the same
/// serialized writer used by undo/redo; no partial operation is published.
class AssistantWrites {
  AssistantWrites({required this.studySetId, required this.newId, required this.now});
  final String studySetId;
  final String Function() newId;
  final DateTime Function() now;

  StudySetContent apply(StudySetContent content, MapEditProposal proposal, Set<String> selected) {
    if (proposal.studySetId != studySetId) throw ArgumentError('Wrong study set');
    if (content.assistantReceipts.any((r) => r.proposalId == proposal.id)) return content;
    if (content.map(proposal.mapId) == null) throw StateError('Map no longer exists');
    if (assistantMapRevision(content, proposal.mapId) != proposal.baseRevision) throw StateError('Map has changed');
    final ids = proposal.operations.map((o) => o.id).toSet();
    if (proposal.operations.length > 50 ||
        ids.length != proposal.operations.length ||
        !ids.containsAll(selected) ||
        selected.isEmpty) {
      throw ArgumentError('Invalid operation selection');
    }
    final editor = StudySetEditor(newId: newId, now: now, mapId: proposal.mapId);
    var next = content;
    final temporary = <String, String>{};
    final applied = <String>[], nodes = <String>[];
    final skipped = <String, String>{};
    final earlierAdds = <String>{};
    for (final raw in proposal.operations) {
      // Validate even constructed operations; model-side validation is insufficient.
      final op = MapEditOperation.fromJson(raw.toJson().cast<String, dynamic>());
      final adding = {MapEditKind.addTopic, MapEditKind.addNote, MapEditKind.addReviewCard}.contains(op.kind);
      for (final ref in [op.parentId, op.nodeId]) {
        if (ref != null && ref.startsWith('new:') && !earlierAdds.contains(ref)) {
          throw ArgumentError('Invalid operation dependency');
        }
      }
      if (adding) earlierAdds.add('new:${op.id}');
      if (!selected.contains(op.id)) continue;
      String? resolve(String? ref) => ref != null && ref.startsWith('new:') ? temporary[ref] : ref;
      final parent = resolve(op.parentId), node = resolve(op.nodeId);
      // A map ID is the explicitly authorized virtual root.
      final root = op.parentId == proposal.mapId;
      if ((op.parentId != null && !root && (parent == null || next.node(parent, mapId: proposal.mapId) == null)) ||
          (op.nodeId != null && (node == null || next.node(node, mapId: proposal.mapId) == null))) {
        skipped[op.id] = 'Target no longer exists or dependency was not selected';
        continue;
      }
      final destination = root ? null : parent;
      String? created;
      switch (op.kind) {
        case MapEditKind.addTopic:
          final result = editor.addTopic(next, title: op.title!, parentId: destination);
          next = result.$1;
          created = result.$2.id;
        case MapEditKind.addNote || MapEditKind.addReviewCard:
          final result = editor.addNote(next, text: op.title ?? op.question!, parentId: destination);
          created = result.$2.id;
          next = result.$1.copyWith(
            cards: [
              for (final card in result.$1.cards)
                card.id == created ? card.copyWith(body: op.body ?? op.answer!) : card,
            ],
          );
        case MapEditKind.move:
          if (destination != null && next.branch(node!, mapId: proposal.mapId).contains(destination)) {
            throw ArgumentError('Move would create a cycle');
          }
          next = editor.move(next, node!, destination);
        case MapEditKind.rename:
          final card = next.card(node!);
          next = card?.researchNoteId == null
              ? editor.rename(next, node, op.title!)
              : editor.editResearchNote(next, card!.researchNoteId!, title: op.title!);
      }
      applied.add(op.id);
      if (created != null) {
        temporary['new:${op.id}'] = created;
        nodes.add(created);
      }
    }
    final receipt = MapEditReceipt(
      proposalId: proposal.id,
      revision: assistantMapRevision(next, proposal.mapId),
      undoHandle: proposal.id,
      operationIds: applied,
      nodeIds: nodes,
      skipped: skipped,
    );
    return next.copyWith(assistantReceipts: [...next.assistantReceipts, receipt]);
  }

  StudySetContent saveNote(
    StudySetContent content, {
    required String noteId,
    required String conversationId,
    required String body,
    required SaveNoteRequest request,
  }) {
    if (conversationId.trim().isEmpty || request.title.trim().isEmpty || body.trim().isEmpty) {
      throw ArgumentError('Empty note');
    }
    if (content.researchNote(noteId) != null) return content;
    if ((request.parentId != null && request.mapId == null) || (request.mapId == null && request.anchor == null)) {
      throw ArgumentError('Missing note destination');
    }
    if (request.mapId != null &&
        (content.map(request.mapId!) == null ||
            (request.parentId != null && content.node(request.parentId!, mapId: request.mapId!) == null))) {
      throw ArgumentError('Invalid note destination');
    }
    final anchor = request.anchor;
    if (anchor?.target case CardTarget(:final cardId)) {
      if (anchor!.mapId == null || content.node(cardId, mapId: anchor.mapId!) == null) {
        throw ArgumentError('Invalid note anchor');
      }
    }
    final time = now();
    final note = ResearchNote(
      id: noteId,
      title: request.title.trim(),
      body: body,
      conversationId: conversationId,
      origin: NoteOrigin.ai,
      textFormat: TextFormat.markdown,
      createdAt: time,
      updatedAt: time,
    );
    return StudySetEditor(newId: newId, now: now, mapId: request.mapId ?? MindMap.defaultId).saveResearchNote(
      content,
      note,
      targets: [if (anchor != null) anchor.target],
      createCard: request.mapId != null,
      parentId: request.parentId,
    );
  }
}
