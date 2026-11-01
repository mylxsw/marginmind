part of 'editor.dart';

/// Stable reason codes; the UI supplies localized hover text.
enum MapEditReason {
  tooFewCards,
  missingCard,
  centerTopic,
  imageCard,
  summaryTopic,
  unsupportedCard,
  notMerged,
  differentParents,
  overlappingSummary,
  missingSummary,
}

/// One atomic content replacement, including information for the undo notice.
class MapEditResult<T> {
  const MapEditResult(
    this.content, {
    this.value,
    this.reason,
    this.removedRelationCount = 0,
    this.removedSummaryCount = 0,
  });
  final StudySetContent content;
  final T? value;
  final MapEditReason? reason;
  final int removedRelationCount;
  final int removedSummaryCount;
  bool get succeeded => reason == null;
}

extension MindMapEditing on StudySetEditor {
  StudySetContent setMapBackgroundColor(StudySetContent c, int? color) => c.copyWith(
    maps: [
      for (final m in c.maps)
        m.id == mapId ? m.copyWith(backgroundColor: color == null ? null : 0xFF000000 | (color & 0xFFFFFF)) : m,
    ],
  );

  StudySetContent setMapStructure(StudySetContent c, MapStructure structure) =>
      c.copyWith(maps: [for (final m in c.maps) m.id == mapId ? m.copyWith(structure: structure) : m]);

  StudySetContent setMapPalette(StudySetContent c, MapPalette palette) =>
      c.copyWith(maps: [for (final m in c.maps) m.id == mapId ? m.copyWith(palette: palette) : m]);

  List<MapNode> _preorder(StudySetContent c) {
    final result = <MapNode>[];
    final visited = <String>{};
    void walk(String? parent) {
      for (final n in c.childrenOf(parent, mapId: mapId)) {
        if (!visited.add(n.cardId)) continue;
        result.add(n);
        walk(n.cardId);
      }
      for (final s in c.summaries.where((s) => s.mapId == mapId && s.parentId == parent)) {
        if (s.cardId != null && visited.add(s.cardId!)) walk(s.cardId);
      }
    }

    walk(null);
    return result;
  }

  bool _movesIntoDependentSummary(StudySetContent c, Iterable<String> ids, String? parent) {
    if (parent == null) return false;
    final moved = {for (final id in ids) ..._subtree(c, id)};
    for (final s in c.summaries.where((s) => s.mapId == mapId && s.cardId != null)) {
      if (_subtree(c, s.cardId!).contains(parent) && (c.summaryRange(s) ?? []).any(moved.contains)) return true;
    }
    return false;
  }

  MapEditReason? mergeReason(StudySetContent c, Iterable<String> cardIds) {
    final ids = cardIds.toSet();
    if (ids.length < 2) return MapEditReason.tooFewCards;
    for (final id in ids) {
      if (id == mapId || id == 'root') return MapEditReason.centerTopic;
      if (c.summaries.any((s) => s.mapId == mapId && s.cardId == id)) return MapEditReason.summaryTopic;
      final card = c.card(id);
      if (card == null || c.node(id, mapId: mapId) == null) return MapEditReason.missingCard;
      if (card.kind == CardKind.image) return MapEditReason.imageCard;
      if (card.kind == CardKind.research) return MapEditReason.unsupportedCard;
    }
    if (_preorder(c).where((n) => ids.contains(n.cardId)).length != ids.length) return MapEditReason.missingCard;
    return null;
  }

  /// Uses this editor's mapId. Selection order never determines the survivor.
  MapEditResult<Card> mergeCards(StudySetContent c, Iterable<String> cardIds) {
    final ids = cardIds.toSet();
    final reason = mergeReason(c, ids);
    if (reason != null) return MapEditResult(c, reason: reason);
    final preorder = _preorder(c);
    final selected = preorder.where((n) => ids.contains(n.cardId)).toList();
    final survivor = c.card(selected.first.cardId)!;
    final consumed = ids.difference({survivor.id});
    final cards = selected.map((n) => c.card(n.cardId)!).toList();
    final segments = [for (final card in cards) ...c.segmentsOf(card)];
    final source = segments.where((s) => s.annotationId != null).firstOrNull?.annotationId;
    final title = cards.where((card) => card.title.trim().isNotEmpty).firstOrNull?.title ?? '';
    final merged = survivor.copyWith(
      kind: source == null ? CardKind.topic : CardKind.excerpt,
      title: source == null ? segments.map((s) => s.text).join('\n') : title,
      body: '',
      annotationId: source,
      segments: segments,
      tags: {for (final card in cards) ...card.tags}.toList(),
    );
    // Only direct children of selected nodes move. This also handles selecting
    // both an ancestor and a descendant without creating a cycle.
    final children = preorder.where((n) => !ids.contains(n.cardId) && ids.contains(n.parentId)).toList();
    final orders = {for (var i = 0; i < children.length; i++) children[i].cardId: (i + 1).toDouble()};
    final relations = <MapRelation>[];
    final seen = <(String, String)>{};
    var removedRelations = 0;
    for (final r in c.relations) {
      if (r.mapId != mapId) {
        relations.add(r);
        continue;
      }
      final from = consumed.contains(r.fromId) ? survivor.id : r.fromId;
      final to = consumed.contains(r.toId) ? survivor.id : r.toId;
      final key = from.compareTo(to) < 0 ? (from, to) : (to, from);
      if (from == to || !seen.add(key)) {
        removedRelations++;
        continue;
      }
      relations.add(r.copyWith(fromId: from, toId: to));
    }
    var next = c.copyWith(
      cards: [
        for (final card in c.cards)
          if (card.id == survivor.id)
            merged
          else if (!consumed.contains(card.id))
            card
          // Other maps keep their placements/content; merged-away review state
          // remains archived and must no longer enter any review queue.
          else if (c.nodes.any((n) => n.mapId != mapId && n.cardId == card.id))
            card.copyWith(suspended: true),
      ],
      nodes: [
        for (final n in c.nodes)
          if (n.mapId != mapId)
            n
          else if (!consumed.contains(n.cardId))
            orders.containsKey(n.cardId) ? n.copyWith(parentId: survivor.id, order: orders[n.cardId]) : n,
      ],
      relations: relations,
      // Summaries over a consumed card's children follow those children to the
      // survivor; they stay one contiguous block, so ranges remain valid.
      summaries: [
        for (final s in c.summaries)
          s.mapId == mapId && consumed.contains(s.parentId) ? s.copyWith(parentId: survivor.id) : s,
      ],
      noteAttachments: [
        for (final a in c.noteAttachments)
          if (a.target is CardTarget && consumed.contains((a.target as CardTarget).cardId))
            NoteAttachment(
              id: a.id,
              noteId: a.noteId,
              target: CardTarget(cardId: survivor.id),
            )
          else
            a,
      ],
      marginNotes: [
        for (final note in c.marginNotes)
          (note.mapId ?? MindMap.defaultId) == mapId && consumed.contains(note.nodeId)
              ? note.copyWith(nodeId: survivor.id)
              : note,
      ],
    );
    next = _keepSummaries(c, next);
    return MapEditResult(
      next,
      value: merged,
      removedRelationCount: removedRelations + relations.length - next.relations.length,
      removedSummaryCount: c.summaries.length - next.summaries.length,
    );
  }

  /// Splitting keeps the first segment's identity, children and connections.
  /// Remaining segments become fresh adjacent cards with fresh schedules.
  MapEditResult<List<Card>> splitCard(StudySetContent c, String cardId) {
    final card = c.card(cardId);
    final node = c.node(cardId, mapId: mapId);
    if (card == null || node == null) return MapEditResult(c, reason: MapEditReason.missingCard);
    if (card.segments.length < 2) return MapEditResult(c, reason: MapEditReason.notMerged);
    final split = <Card>[];
    for (var i = 0; i < card.segments.length; i++) {
      final s = card.segments[i];
      final kind = s.annotationId == null ? CardKind.topic : CardKind.excerpt;
      final title = s.annotationId == null ? s.text : (i == 0 ? card.title : '');
      split.add(
        i == 0
            ? card.copyWith(kind: kind, title: title, body: '', annotationId: s.annotationId, segments: [s])
            : Card(
                id: newId(),
                kind: kind,
                title: title,
                annotationId: s.annotationId,
                segments: [s],
                createdAt: now(),
                tags: card.tags,
              ),
      );
    }
    final placements = c.nodes.where((n) => n.cardId == cardId).toList();
    final orders = <(String, String), double>{};
    final addedNodes = <MapNode>[];
    // Content is shared: splitting must retain every segment in every map.
    for (final placement in placements) {
      final siblings = c.childrenOf(placement.parentId, mapId: placement.mapId);
      final index = siblings.indexWhere((n) => n.cardId == cardId);
      final additions = [
        for (final added in split.skip(1))
          MapNode(
            cardId: added.id,
            mapId: placement.mapId,
            parentId: placement.parentId,
            order: 0,
            width: placement.width,
          ),
      ];
      siblings.insertAll(index + 1, additions);
      for (var i = 0; i < siblings.length; i++) {
        orders[(placement.mapId, siblings[i].cardId)] = (i + 1).toDouble();
      }
      addedNodes.addAll(additions);
    }
    final next = c.copyWith(
      cards: [for (final old in c.cards) old.id == cardId ? split.first : old, ...split.skip(1)],
      nodes: [
        for (final n in [...c.nodes, ...addedNodes])
          orders.containsKey((n.mapId, n.cardId)) ? n.copyWith(order: orders[(n.mapId, n.cardId)]) : n,
      ],
      summaries: [for (final s in c.summaries) s.toId == cardId ? s.copyWith(toId: split.last.id) : s],
    );
    return MapEditResult(next, value: List.unmodifiable(split));
  }

  MapEditReason? summaryReason(StudySetContent c, Iterable<String> cardIds, {String? excludingSummaryId}) {
    final ids = cardIds.toSet();
    if (ids.isEmpty) return MapEditReason.tooFewCards;
    for (final id in ids) {
      if (id == mapId || id == 'root') return MapEditReason.centerTopic;
      if (c.summaries.any((s) => s.mapId == mapId && s.cardId == id)) return MapEditReason.summaryTopic;
      if (c.node(id, mapId: mapId) == null || c.card(id) == null) return MapEditReason.missingCard;
    }
    final parent = c.node(ids.first, mapId: mapId)!.parentId;
    if (ids.any((id) => c.node(id, mapId: mapId)!.parentId != parent)) return MapEditReason.differentParents;
    final siblings = c.childrenOf(parent, mapId: mapId).map((n) => n.cardId).toList();
    final positions = ids.map(siblings.indexOf).toList()..sort();
    final range = siblings.sublist(positions.first, positions.last + 1).toSet();
    for (final s in c.summaries.where((s) => s.mapId == mapId && s.id != excludingSummaryId && s.parentId == parent)) {
      if ((c.summaryRange(s) ?? []).any(range.contains)) return MapEditReason.overlappingSummary;
    }
    return null;
  }

  MapEditResult<MapSummary> createSummary(StudySetContent c, Iterable<String> cardIds, {String label = ''}) {
    final ids = cardIds.toSet();
    final reason = summaryReason(c, ids);
    if (reason != null) return MapEditResult(c, reason: reason);
    final parent = c.node(ids.first, mapId: mapId)!.parentId;
    final selected = c.childrenOf(parent, mapId: mapId).where((n) => ids.contains(n.cardId)).toList();
    final topic = Card(id: newId(), kind: CardKind.topic, title: label.trim(), createdAt: now());
    final summary = MapSummary(
      id: newId(),
      mapId: mapId,
      parentId: parent,
      fromId: selected.first.cardId,
      toId: selected.last.cardId,
      label: topic.title,
      cardId: topic.id,
    );
    return MapEditResult(
      c.copyWith(cards: [...c.cards, topic], summaries: [...c.summaries, summary]),
      value: summary,
    );
  }

  MapEditResult<MapSummary> adjustSummaryRange(StudySetContent c, String summaryId, Iterable<String> cardIds) {
    final summary = c.summaries.where((s) => s.mapId == mapId && s.id == summaryId).firstOrNull;
    if (summary == null) return MapEditResult(c, reason: MapEditReason.missingSummary);
    final ids = cardIds.toSet();
    final reason = summaryReason(c, ids, excludingSummaryId: summaryId);
    if (reason != null) return MapEditResult(c, reason: reason);
    final parent = c.node(ids.first, mapId: mapId)!.parentId;
    if (parent != summary.parentId) return MapEditResult(c, reason: MapEditReason.differentParents);
    final selected = c.childrenOf(parent, mapId: mapId).where((n) => ids.contains(n.cardId)).toList();
    final changed = summary.copyWith(fromId: selected.first.cardId, toId: selected.last.cardId);
    return MapEditResult(
      c.copyWith(summaries: [for (final s in c.summaries) s.id == summaryId ? changed : s]),
      value: changed,
    );
  }

  StudySetContent updateRelation(
    StudySetContent c,
    String id, {
    RelationArrow? arrow,
    bool? solid,
    RelationControlPoint? control1,
    RelationControlPoint? control2,
    bool resetControl1 = false,
    bool resetControl2 = false,
  }) => !c.relations.any((r) => r.mapId == mapId && r.id == id)
      ? c
      : c.copyWith(
          relations: [
            for (final r in c.relations)
              r.mapId == mapId && r.id == id
                  ? r.copyWith(
                      arrow: arrow,
                      solid: solid,
                      control1: control1,
                      control2: control2,
                      clearControl1: resetControl1,
                      clearControl2: resetControl2,
                    )
                  : r,
          ],
        );

  StudySetContent reverseRelation(StudySetContent c, String id) => c.copyWith(
    relations: [
      for (final r in c.relations)
        r.mapId == mapId && r.id == id
            ? r.copyWith(
                fromId: r.toId,
                toId: r.fromId,
                control1: r.control2,
                control2: r.control1,
                clearControl1: r.control2 == null,
                clearControl2: r.control1 == null,
              )
            : r,
    ],
  );
}
