import 'package:meta/meta.dart';

import 'models.dart';
import 'review.dart';

/// Everything inside one study set: documents, highlights, cards and the
/// mind maps. Immutable; edits produce a new value (see
/// [StudySetEditor]), which makes persistence and undo straightforward.
@immutable
class StudySetContent {
  const StudySetContent({
    this.documents = const [],
    this.annotations = const [],
    this.cards = const [],
    this.nodes = const [],
    this.maps = const [MindMap.main],
    this.reviews = const [],
  });

  static const empty = StudySetContent();

  final List<Document> documents;
  final List<Annotation> annotations;
  final List<Card> cards;
  final List<MapNode> nodes;
  final List<MindMap> maps;
  MindMap? map(String id) => maps.where((m) => m.id == id).firstOrNull;

  /// Review history per card. Entries of deleted cards are kept (and
  /// ignored) so undoing a delete brings the card back with its schedule.
  final List<ReviewState> reviews;

  Document? document(String id) => documents.where((d) => d.id == id).firstOrNull;
  Annotation? annotation(String id) => annotations.where((a) => a.id == id).firstOrNull;
  Card? card(String id) => cards.where((c) => c.id == id).firstOrNull;
  MapNode? node(String cardId, {String mapId = MindMap.defaultId}) =>
      nodes.where((n) => n.mapId == mapId && n.cardId == cardId).firstOrNull;

  /// The excerpt card made from [annotationId], if any.
  Card? cardForAnnotation(String annotationId) => cards.where((c) => c.annotationId == annotationId).firstOrNull;

  /// Children of [parentId] (null = root) in display order.
  List<MapNode> childrenOf(String? parentId, {String mapId = MindMap.defaultId}) =>
      nodes.where((n) => n.mapId == mapId && n.parentId == parentId).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  List<Annotation> annotationsOn(String documentId) => annotations.where((a) => a.documentId == documentId).toList();

  /// The document read most recently, for "Continue Learning".
  Document? get lastRead {
    final read = documents.where((d) => d.lastReadAt != null).toList()
      ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    return read.firstOrNull ?? documents.firstOrNull;
  }

  /// Excerpts and notes (topics are structure, not cards to review).
  int get cardCount => cards.where((c) => c.kind != CardKind.topic).length;

  int get excerptCount => cards.where((c) => c.kind == CardKind.excerpt).length;

  ReviewState? reviewOf(String cardId) => reviews.where((r) => r.cardId == cardId).firstOrNull;

  /// Cards that can be reviewed: excerpts and non-empty notes on the map.
  Iterable<Card> get reviewableCards => cards.where(
    (c) =>
        nodes.any((n) => n.cardId == c.id) &&
        switch (c.kind) {
          CardKind.excerpt => annotation(c.annotationId ?? '') != null,
          CardKind.note => c.title.trim().isNotEmpty,
          CardKind.topic => false,
          CardKind.image => c.imageFileName != null,
        },
  );

  /// What a review session at [now] covers: due cards (most overdue first),
  /// then up to [ReviewScheduler.newPerSession] new cards in creation order.
  List<Card> reviewQueue(DateTime now, {String? mapId}) {
    final byId = {for (final r in reviews) r.cardId: r};
    final due = <Card>[];
    final fresh = <Card>[];
    for (final c in reviewableCards) {
      if (mapId != null && node(c.id, mapId: mapId) == null) continue;
      final r = byId[c.id];
      if (r == null) {
        fresh.add(c);
      } else if (!r.due.isAfter(now)) {
        due.add(c);
      }
    }
    due.sort((a, b) => byId[a.id]!.due.compareTo(byId[b.id]!.due));
    fresh.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [...due, ...fresh.take(ReviewScheduler.newPerSession)];
  }

  int dueCount(DateTime now, {String? mapId}) => reviewQueue(now, mapId: mapId).length;

  /// Titles of the topics/cards above [cardId], root first.
  List<String> pathOf(String cardId, {String mapId = MindMap.defaultId}) {
    final titles = <String>[];
    var parent = node(cardId, mapId: mapId)?.parentId;
    final seen = <String>{};
    while (parent != null && seen.add(parent)) {
      final card = this.card(parent);
      if (card == null) break;
      titles.insert(0, card.title);
      parent = node(parent, mapId: mapId)?.parentId;
    }
    return titles;
  }

  /// Cards whose title or quote contains [query]
  /// (case-insensitive), in map order.
  List<Card> search(String query, {String mapId = MindMap.defaultId}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    bool hit(String? s) => s != null && s.toLowerCase().contains(q);
    final result = <Card>[];
    void walk(String? parentId) {
      for (final n in childrenOf(parentId, mapId: mapId)) {
        final c = card(n.cardId);
        if (c == null) continue;
        final a = c.annotationId == null ? null : annotation(c.annotationId!);
        if (hit(c.title) || hit(a?.quote)) result.add(c);
        walk(c.id);
      }
    }

    walk(null);
    return result;
  }

  StudySetContent copyWith({
    List<Document>? documents,
    List<Annotation>? annotations,
    List<Card>? cards,
    List<MapNode>? nodes,
    List<MindMap>? maps,
    List<ReviewState>? reviews,
  }) {
    return StudySetContent(
      documents: documents ?? this.documents,
      annotations: annotations ?? this.annotations,
      cards: cards ?? this.cards,
      nodes: nodes ?? this.nodes,
      maps: maps ?? this.maps,
      reviews: reviews ?? this.reviews,
    );
  }

  Map<String, Object?> toJson() => {
    'documents': [for (final d in documents) d.toJson()],
    'annotations': [for (final a in annotations) a.toJson()],
    'cards': [for (final c in cards) c.toJson()],
    'maps': [for (final m in maps) m.toJson()],
    'nodes': [for (final n in nodes) n.toJson()],
    'reviews': [for (final r in reviews) r.toJson()],
  };

  factory StudySetContent.fromJson(Map<String, Object?> j) {
    List<T> list<T>(String key, T Function(Map<String, Object?>) f) => [
      for (final e in (j[key] as List?) ?? const []) f((e as Map).cast()),
    ];
    return StudySetContent(
      documents: list('documents', Document.fromJson),
      annotations: list('annotations', Annotation.fromJson),
      cards: list('cards', Card.fromJson),
      nodes: list('nodes', MapNode.fromJson),
      maps: j['maps'] == null ? const [MindMap.main] : list('maps', MindMap.fromJson),
      reviews: list('reviews', ReviewState.fromJson),
    );
  }
}
