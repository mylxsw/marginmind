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
    this.reviewLogs = const [],
    this.memoryStates = const [],
    this.relations = const [],
    this.summaries = const [],
    this.bookmarks = const [],
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

  /// Append-only rating history, including deleted cards.
  final List<ReviewLog> reviewLogs;
  final List<MemoryState> memoryStates;

  MemoryState? memoryOf(String cardId) => memoryStates.where((s) => s.cardId == cardId).firstOrNull;
  List<ReviewLog> reviewLogsOf(String cardId) => List.unmodifiable(reviewLogs.where((entry) => entry.cardId == cardId));

  /// Lines between cards and summaries of sibling ranges, per map.
  final List<MapRelation> relations;
  final List<MapSummary> summaries;

  /// The reader's page bookmarks, across documents.
  final List<Bookmark> bookmarks;

  /// Bookmarks of [documentId] in page order.
  List<Bookmark> bookmarksOn(String documentId) =>
      bookmarks.where((b) => b.documentId == documentId).toList()..sort((a, b) {
        final byPage = a.page.compareTo(b.page);
        return byPage != 0 ? byPage : a.createdAt.compareTo(b.createdAt);
      });

  Bookmark? bookmarkAt(String documentId, int page) =>
      bookmarks.where((b) => b.documentId == documentId && b.page == page).firstOrNull;

  /// Relations of [mapId] whose two cards are both placed in that map.
  List<MapRelation> relationsOf(String mapId) => [
    for (final r in relations)
      if (r.mapId == mapId && node(r.fromId, mapId: mapId) != null && node(r.toId, mapId: mapId) != null) r,
  ];

  /// Summaries of [mapId] whose range is intact, each with the children it
  /// covers in display order.
  List<(MapSummary, List<String>)> summariesOf(String mapId) => [
    for (final s in summaries)
      if (s.mapId == mapId)
        if (summaryRange(s) case final range?) (s, range),
  ];

  /// The children [s] covers, or null when either end is no longer a child
  /// of its parent.
  List<String>? summaryRange(MapSummary s) {
    final siblings = [for (final n in childrenOf(s.parentId, mapId: s.mapId)) n.cardId];
    final a = siblings.indexOf(s.fromId), b = siblings.indexOf(s.toId);
    if (a < 0 || b < 0) return null;
    return siblings.sublist(a < b ? a : b, (a < b ? b : a) + 1);
  }

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
  /// Suspended cards are never included. [mapId] limits it to one map;
  /// [branchId] to that card and everything below it (folded or not) on
  /// [mapId] (the main map when null); [tag] to cards carrying it (exact,
  /// case-insensitive). Filters apply before the new-card limit.
  List<Card> reviewQueue(DateTime now, {String? mapId, String? branchId, String? tag}) {
    final byId = {for (final r in reviews) r.cardId: r};
    final branch = branchId == null ? null : this.branch(branchId, mapId: mapId ?? MindMap.defaultId);
    final wanted = tag?.toLowerCase();
    final due = <Card>[];
    final fresh = <Card>[];
    for (final c in reviewableCards) {
      if (c.suspended) continue;
      if (mapId != null && node(c.id, mapId: mapId) == null) continue;
      if (branch != null && !branch.contains(c.id)) continue;
      if (wanted != null && !c.tags.any((t) => t.toLowerCase() == wanted)) continue;
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

  int dueCount(DateTime now, {String? mapId, String? branchId, String? tag}) =>
      reviewQueue(now, mapId: mapId, branchId: branchId, tag: tag).length;

  /// [cardId] and every card below it on [mapId], folded or not; empty when
  /// the card is not on that map.
  Set<String> branch(String cardId, {String mapId = MindMap.defaultId}) {
    if (node(cardId, mapId: mapId) == null) return const {};
    final children = <String, List<String>>{};
    for (final n in nodes) {
      if (n.mapId == mapId && n.parentId != null) children.putIfAbsent(n.parentId!, () => []).add(n.cardId);
    }
    final ids = <String>{};
    final pending = [cardId];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (ids.add(id)) pending.addAll(children[id] ?? const []);
    }
    return ids;
  }

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

  List<String> tags({String mapId = MindMap.defaultId}) {
    final names = <String, String>{};
    for (final c in cards) {
      if (node(c.id, mapId: mapId) == null) continue;
      for (final tag in c.tags) {
        names.putIfAbsent(tag.toLowerCase(), () => tag);
      }
    }
    return names.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Cards whose title, quote or tags contain [query] (case-insensitive),
  /// in map order. [tag] is an exact, case-insensitive filter; an empty
  /// query with a tag returns every card carrying that tag.
  List<Card> search(String query, {String mapId = MindMap.defaultId, String? tag}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty && tag == null) return const [];
    bool hit(String? s) => s != null && s.toLowerCase().contains(q);
    final result = <Card>[];
    void walk(String? parentId) {
      for (final n in childrenOf(parentId, mapId: mapId)) {
        final c = card(n.cardId);
        if (c == null) continue;
        final a = c.annotationId == null ? null : annotation(c.annotationId!);
        final tagged = tag == null || c.tags.any((t) => t.toLowerCase() == tag.toLowerCase());
        if (tagged && (q.isEmpty || hit(c.title) || hit(a?.quote) || c.tags.any(hit))) result.add(c);
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
    List<ReviewLog>? reviewLogs,
    List<MemoryState>? memoryStates,
    List<MapRelation>? relations,
    List<MapSummary>? summaries,
    List<Bookmark>? bookmarks,
  }) {
    return StudySetContent(
      documents: documents ?? this.documents,
      annotations: annotations ?? this.annotations,
      cards: cards ?? this.cards,
      nodes: nodes ?? this.nodes,
      maps: maps ?? this.maps,
      reviews: reviews ?? this.reviews,
      reviewLogs: reviewLogs ?? this.reviewLogs,
      memoryStates: memoryStates ?? this.memoryStates,
      relations: relations ?? this.relations,
      summaries: summaries ?? this.summaries,
      bookmarks: bookmarks ?? this.bookmarks,
    );
  }

  Map<String, Object?> toJson() => {
    'documents': [for (final d in documents) d.toJson()],
    'annotations': [for (final a in annotations) a.toJson()],
    'cards': [for (final c in cards) c.toJson()],
    'maps': [for (final m in maps) m.toJson()],
    'nodes': [for (final n in nodes) n.toJson()],
    'reviews': [for (final r in reviews) r.toJson()],
    'reviewLogs': [for (final r in reviewLogs) r.toJson()],
    'memoryStates': [for (final s in memoryStates) s.toJson()],
    'relations': [for (final r in relations) r.toJson()],
    'summaries': [for (final s in summaries) s.toJson()],
    'bookmarks': [for (final b in bookmarks) b.toJson()],
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
      reviewLogs: list('reviewLogs', ReviewLog.fromJson),
      memoryStates: list('memoryStates', MemoryState.fromJson),
      relations: list('relations', MapRelation.fromJson),
      summaries: list('summaries', MapSummary.fromJson),
      bookmarks: list('bookmarks', Bookmark.fromJson),
    );
  }
}
