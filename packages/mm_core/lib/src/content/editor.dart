import 'models.dart';
import 'review.dart';
import 'study_set_content.dart';

/// Every change to a study set's content, as pure functions. The UI calls
/// these through the repository; tests call them directly.
class StudySetEditor {
  StudySetEditor({required this.newId, required this.now});

  final String Function() newId;
  final DateTime Function() now;

  /// Where a new excerpt goes when [selectedCardId] is selected: under a
  /// selected topic, next to a selected excerpt/note (its parent), else the
  /// root. Returns a card id or null for the root.
  static String? excerptTarget(StudySetContent c, String? selectedCardId) {
    if (selectedCardId == null) return null;
    final card = c.card(selectedCardId);
    final node = c.node(selectedCardId);
    if (card == null || node == null) return null;
    return card.kind == CardKind.topic ? card.id : node.parentId;
  }

  double _nextOrder(StudySetContent c, String? parentId) {
    final siblings = c.childrenOf(parentId);
    return siblings.isEmpty ? 1 : siblings.last.order + 1;
  }

  /// Adds a document that has already been copied into the package.
  (StudySetContent, Document) addDocument(
    StudySetContent c, {
    required String title,
    required String fileName,
    required int pageCount,
  }) {
    final doc = Document(id: newId(), title: title, fileName: fileName, pageCount: pageCount, importedAt: now());
    return (c.copyWith(documents: [...c.documents, doc]), doc);
  }

  StudySetContent setLastPage(StudySetContent c, String documentId, int page) => c.copyWith(
    documents: [for (final d in c.documents) d.id == documentId ? d.copyWith(lastPage: page, lastReadAt: now()) : d],
  );

  /// Highlight only (no card).
  (StudySetContent, Annotation) highlight(
    StudySetContent c, {
    required String documentId,
    required int page,
    required List<PageRect> rects,
    required String quote,
    required int colorIndex,
  }) {
    final a = Annotation(
      id: newId(),
      documentId: documentId,
      page: page,
      rects: rects,
      quote: quote.trim(),
      colorIndex: colorIndex,
      createdAt: now(),
    );
    return (c.copyWith(annotations: [...c.annotations, a]), a);
  }

  /// Highlight + excerpt card + map node, in one step.
  (StudySetContent, Card) createExcerpt(
    StudySetContent c, {
    required String documentId,
    required int page,
    required List<PageRect> rects,
    required String quote,
    required int colorIndex,
    String? parentId,
  }) {
    final (withHighlight, a) = highlight(
      c,
      documentId: documentId,
      page: page,
      rects: rects,
      quote: quote,
      colorIndex: colorIndex,
    );
    return attachCard(withHighlight, a.id, parentId: parentId);
  }

  /// Turns an existing highlight into an excerpt card on the map.
  (StudySetContent, Card) attachCard(StudySetContent c, String annotationId, {String? parentId}) {
    final existing = c.cardForAnnotation(annotationId);
    if (existing != null) return (c, existing);
    final card = Card(id: newId(), kind: CardKind.excerpt, annotationId: annotationId, createdAt: now());
    return (_place(c, card, parentId), card);
  }

  (StudySetContent, Card) addTopic(StudySetContent c, {required String title, String? parentId}) =>
      _addCard(c, CardKind.topic, title, parentId);

  (StudySetContent, Card) addNote(StudySetContent c, {required String text, String? parentId}) =>
      _addCard(c, CardKind.note, text, parentId);

  (StudySetContent, Card) _addCard(StudySetContent c, CardKind kind, String title, String? parentId) {
    final card = Card(id: newId(), kind: kind, title: title.trim(), createdAt: now());
    return (_place(c, card, parentId), card);
  }

  /// Adds [card] as the last child of [parentId], expanding the parent so
  /// the new card is visible.
  StudySetContent _place(StudySetContent c, Card card, String? parentId) {
    final node = MapNode(cardId: card.id, parentId: parentId, order: _nextOrder(c, parentId));
    return c.copyWith(
      cards: [...c.cards, card],
      nodes: [for (final n in c.nodes) n.cardId == parentId && n.collapsed ? n.copyWith(collapsed: false) : n, node],
    );
  }

  StudySetContent rename(StudySetContent c, String cardId, String title) =>
      c.copyWith(cards: [for (final card in c.cards) card.id == cardId ? card.copyWith(title: title.trim()) : card]);

  StudySetContent recolor(StudySetContent c, String annotationId, int colorIndex) => c.copyWith(
    annotations: [for (final a in c.annotations) a.id == annotationId ? a.copyWith(colorIndex: colorIndex) : a],
  );

  /// Moves [cardId] under [newParentId] (null = root), at [index] among
  /// the new siblings (end when null). Refuses to move a node under itself
  /// or its own descendants.
  StudySetContent move(StudySetContent c, String cardId, String? newParentId, {int? index}) {
    if (c.node(cardId) == null) return c;
    if (newParentId != null && _subtree(c, cardId).contains(newParentId)) return c;
    final siblings = [
      for (final n in c.childrenOf(newParentId))
        if (n.cardId != cardId) n,
    ];
    final i = (index ?? siblings.length).clamp(0, siblings.length);
    final double order;
    if (siblings.isEmpty) {
      order = 1;
    } else if (i == 0) {
      order = siblings.first.order - 1;
    } else if (i == siblings.length) {
      order = siblings.last.order + 1;
    } else {
      order = (siblings[i - 1].order + siblings[i].order) / 2;
    }
    return c.copyWith(
      nodes: [
        for (final n in c.nodes)
          n.cardId == cardId ? n.copyWith(parentId: newParentId, toRoot: newParentId == null, order: order) : n,
      ],
    );
  }

  /// Moves a node one place up (-1) or down (+1) among its siblings.
  StudySetContent shift(StudySetContent c, String cardId, int delta) {
    final node = c.node(cardId);
    if (node == null) return c;
    final siblings = c.childrenOf(node.parentId);
    final i = siblings.indexWhere((n) => n.cardId == cardId);
    final target = i + delta;
    if (target < 0 || target >= siblings.length) return c;
    return move(c, cardId, node.parentId, index: target);
  }

  StudySetContent setCollapsed(StudySetContent c, String cardId, {required bool collapsed}) =>
      c.copyWith(nodes: [for (final n in c.nodes) n.cardId == cardId ? n.copyWith(collapsed: collapsed) : n]);

  /// Records a review of [cardId] rated [rating].
  StudySetContent rate(StudySetContent c, String cardId, Rating rating) {
    final next = ReviewScheduler.rate(cardId, c.reviewOf(cardId), rating, now());
    return c.copyWith(
      reviews: [
        for (final r in c.reviews)
          if (r.cardId != cardId) r,
        next,
      ],
    );
  }

  StudySetContent renameDocument(StudySetContent c, String documentId, String title) =>
      c.copyWith(documents: [for (final d in c.documents) d.id == documentId ? d.copyWith(title: title.trim()) : d]);

  /// Removes a document with its highlights and their excerpt cards
  /// (children of those cards go with them).
  StudySetContent removeDocument(StudySetContent c, String documentId) {
    var next = c;
    for (final a in c.annotationsOn(documentId)) {
      next = deleteAnnotation(next, a.id);
    }
    return next.copyWith(
      documents: [
        for (final d in next.documents)
          if (d.id != documentId) d,
      ],
    );
  }

  /// [snapshot] (an earlier state, for undo/redo) with the parts that are
  /// not undoable taken from [current]: review history and reading position.
  static StudySetContent restore(StudySetContent snapshot, StudySetContent current) => snapshot.copyWith(
    reviews: current.reviews,
    documents: [
      for (final d in snapshot.documents)
        if (current.document(d.id) case final now?)
          d.copyWith(lastPage: now.lastPage, lastReadAt: now.lastReadAt)
        else
          d,
    ],
  );

  /// Removes the card and its descendants from the map. Excerpt cards are
  /// deleted but their highlights stay in the source (as plain highlights).
  StudySetContent removeFromMap(StudySetContent c, String cardId) {
    final kill = _subtree(c, cardId);
    return c.copyWith(
      cards: [
        for (final card in c.cards)
          if (!kill.contains(card.id)) card,
      ],
      nodes: [
        for (final n in c.nodes)
          if (!kill.contains(n.cardId)) n,
      ],
    );
  }

  /// Deletes a highlight and, if it has one, its card subtree.
  StudySetContent deleteAnnotation(StudySetContent c, String annotationId) {
    final card = c.cardForAnnotation(annotationId);
    final without = card == null ? c : removeFromMap(c, card.id);
    return without.copyWith(
      annotations: [
        for (final a in without.annotations)
          if (a.id != annotationId) a,
      ],
    );
  }

  Set<String> _subtree(StudySetContent c, String cardId) {
    final result = {cardId};
    var frontier = [cardId];
    while (frontier.isNotEmpty) {
      final next = <String>[];
      for (final id in frontier) {
        for (final child in c.childrenOf(id)) {
          if (result.add(child.cardId)) next.add(child.cardId);
        }
      }
      frontier = next;
    }
    return result;
  }
}
