import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../content/editor.dart';
import '../content/models.dart';
import '../content/map_generation.dart';
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
    final newMap = proposal.createMap;
    if (newMap != null) {
      if (!proposal.isDocumentGeneration ||
          newMap.id != proposal.mapId ||
          content.map(newMap.id) != null ||
          content.cards.any((c) => c.id == newMap.id)) {
        throw ArgumentError('Invalid new map');
      }
    } else if (content.map(proposal.mapId) == null) {
      throw StateError('Map no longer exists');
    }
    if (assistantMapRevision(content, proposal.mapId) != proposal.baseRevision) throw StateError('Map has changed');
    if (proposal.generation?.sources.any((s) => content.document(s.documentId) == null) ?? false) {
      throw StateError('Source document no longer exists');
    }
    final ids = proposal.operations.map((o) => o.id).toSet();
    if ((!proposal.isExpansion && !proposal.isDocumentGeneration && proposal.operations.length > 50) ||
        (proposal.isExpansion &&
            proposal.operations.any((o) => o.kind != MapEditKind.addTopic && o.kind != MapEditKind.move)) ||
        ids.length != proposal.operations.length ||
        !ids.containsAll(selected) ||
        selected.isEmpty) {
      throw ArgumentError('Invalid operation selection');
    }
    final editor = StudySetEditor(newId: newId, now: now, mapId: proposal.mapId);
    var next = newMap == null ? content : content.copyWith(maps: [...content.maps, newMap.copyWith(generation: null)]);
    final generated = Map<String, String>.of(content.map(proposal.mapId)?.generation?.generated ?? {});
    final aiChanged = <String>{};
    final temporary = <String, String>{};
    final applied = <String>[], nodes = <String>[];
    final skipped = <String, String>{};
    final earlierAdds = <String>{};
    // Explicit child removals happen first; never cascade into unselected content.
    int depth(String? id) {
      var n = content.node(id ?? '', mapId: proposal.mapId), d = 0;
      final seen = <String>{};
      while (n != null && seen.add(n.cardId)) {
        d++;
        n = content.node(n.parentId ?? '', mapId: proposal.mapId);
      }
      return d;
    }

    final removals = proposal.operations.where((o) => o.kind == MapEditKind.remove).toList()
      ..sort((a, b) => depth(b.nodeId).compareTo(depth(a.nodeId)));
    final operations = [...proposal.operations.where((o) => o.kind != MapEditKind.remove), ...removals];
    for (final raw in operations) {
      // Validate even constructed operations; model-side validation is insufficient.
      final op = MapEditOperation.fromJson(
        raw.toJson().cast<String, dynamic>(),
        documentGeneration: proposal.isDocumentGeneration,
      );
      final adding = {
        MapEditKind.addTopic,
        MapEditKind.addNote,
        MapEditKind.addReviewCard,
        MapEditKind.addExcerpt,
      }.contains(op.kind);
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
      if (proposal.isDocumentGeneration &&
          {MapEditKind.rename, MapEditKind.move, MapEditKind.remove}.contains(op.kind)) {
        if (node == null ||
            isMapNodeProtected(content, proposal.mapId, node) ||
            // A shared title mutation would also edit a different map.
            (op.kind == MapEditKind.rename &&
                content.nodes.any((n) => n.cardId == node && n.mapId != proposal.mapId))) {
          skipped[op.id] = 'Protected node';
          continue;
        }
      }
      final destination = root ? null : parent;
      String? created;
      switch (op.kind) {
        case MapEditKind.addTopic:
          final result = editor.addTopic(next, title: op.title!, parentId: destination);
          next = result.$1;
          created = result.$2.id;
          if (op.source case final source?) {
            final doc = next.document(source.documentId);
            if (doc != null &&
                source.page <= doc.pageCount &&
                proposal.generation!.sources.any((s) => s.documentId == source.documentId)) {
              next = next.copyWith(
                cards: [for (final c in next.cards) c.id == created ? c.copyWith(source: source) : c],
              );
            }
          }
          aiChanged.add(created);
        case MapEditKind.addExcerpt:
          final staged = proposal.excerptAnnotations.where((a) => a.id == op.annotationId).firstOrNull;
          if (staged != null && next.annotation(staged.id) == null) {
            final doc = next.document(staged.documentId);
            if (doc == null ||
                staged.kind != AnnotationKind.underline ||
                staged.lineStyle != AnnotationLineStyle.dashed ||
                staged.quote.trim().isEmpty ||
                (!staged.isText && staged.pages.any((p) => p.page < 1 || p.page > doc.pageCount || p.rects.isEmpty)) ||
                !proposal.generation!.sources.any((s) => s.documentId == staged.documentId)) {
              throw ArgumentError('Invalid staged excerpt');
            }
            next = next.copyWith(annotations: [...next.annotations, staged]);
          }
          final annotation = next.annotation(op.annotationId!);
          if (annotation == null || !proposal.generation!.sources.any((s) => s.documentId == annotation.documentId)) {
            skipped[op.id] = 'Annotation no longer exists or is outside sources';
            continue;
          }
          final existing = next.cardForAnnotation(op.annotationId!);
          if (existing != null && next.node(existing.id, mapId: proposal.mapId) != null) {
            skipped[op.id] = 'Annotation already placed';
            continue;
          }
          final result = editor.attachCard(next, op.annotationId!, parentId: destination);
          next = result.$1;
          created = result.$2.id;
        case MapEditKind.remove:
          if (next.childrenOf(node, mapId: proposal.mapId).isNotEmpty) {
            skipped[op.id] = 'Remove requires explicit removal of every child';
            continue;
          }
          next = editor.removeFromMap(next, node!);
          generated.remove(node);
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
          aiChanged.add(node);
        case MapEditKind.rename:
          final card = next.card(node!);
          next = card?.researchNoteId == null
              ? editor.rename(next, node, op.title!)
              : editor.editResearchNote(next, card!.researchNoteId!, title: op.title!);
          aiChanged.add(node);
      }
      applied.add(op.id);
      if (created != null) {
        temporary['new:${op.id}'] = created;
        nodes.add(created);
      }
    }
    if (proposal.generation case final metadata?) {
      if (applied.isEmpty) throw StateError('No applicable changes');
      for (final id in aiChanged) {
        final card = next.card(id), node = next.node(id, mapId: proposal.mapId);
        if (card != null && node != null) generated[id] = generatedNodeHash(card, node);
      }
      // Never rebaseline untouched user changes or trust caller-supplied hashes.
      next = next.copyWith(
        maps: [
          for (final m in next.maps)
            m.id == proposal.mapId ? m.copyWith(generation: metadata.withGenerated(generated)) : m,
        ],
      );
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
