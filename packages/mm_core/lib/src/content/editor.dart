import 'models.dart';
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
    final node = MapNode(cardId: card.id, parentId: parentId, order: _nextOrder(c, parentId));
    return (c.copyWith(cards: [...c.cards, card], nodes: [...c.nodes, node]), card);
  }

  (StudySetContent, Card) addTopic(StudySetContent c, {required String title, String? parentId}) =>
      _addCard(c, CardKind.topic, title, parentId);

  (StudySetContent, Card) addNote(StudySetContent c, {required String text, String? parentId}) =>
      _addCard(c, CardKind.note, text, parentId);

  (StudySetContent, Card) _addCard(StudySetContent c, CardKind kind, String title, String? parentId) {
    final card = Card(id: newId(), kind: kind, title: title.trim(), createdAt: now());
    final node = MapNode(cardId: card.id, parentId: parentId, order: _nextOrder(c, parentId));
    return (c.copyWith(cards: [...c.cards, card], nodes: [...c.nodes, node]), card);
  }

  StudySetContent rename(StudySetContent c, String cardId, String title) =>
      c.copyWith(cards: [for (final card in c.cards) card.id == cardId ? card.copyWith(title: title.trim()) : card]);

  StudySetContent recolor(StudySetContent c, String annotationId, int colorIndex) => c.copyWith(
    annotations: [for (final a in c.annotations) a.id == annotationId ? a.copyWith(colorIndex: colorIndex) : a],
  );

  /// Moves [cardId] under [newParentId] (null = root), at the end. Refuses
  /// to move a node under itself or its own descendants.
  StudySetContent move(StudySetContent c, String cardId, String? newParentId) {
    if (newParentId != null && _subtree(c, cardId).contains(newParentId)) return c;
    final order = _nextOrder(c, newParentId);
    return c.copyWith(
      nodes: [
        for (final n in c.nodes)
          n.cardId == cardId ? n.copyWith(parentId: newParentId, toRoot: newParentId == null, order: order) : n,
      ],
    );
  }

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
