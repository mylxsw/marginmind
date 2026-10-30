import 'dart:convert';

import 'text_anchor.dart';
import 'study_note.dart';

import 'package:meta/meta.dart';

import 'models.dart';
import 'document_outline.dart';
import 'reading.dart';
import '../assistant/proposals.dart';
import 'note_format.dart';
import 'research.dart';
import 'review.dart';

/// Everything inside one study set: documents, highlights, cards and the
/// mind maps. Immutable; edits produce a new value (see
/// [StudySetEditor]), which makes persistence and undo straightforward.
@immutable
class StudySetContent {
  const StudySetContent({
    this.assistantReceipts = const [],
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
    this.researchNotes = const [],
    this.noteAttachments = const [],
    this.evidence = const [],
    this.researchSources = const [],
    this.inkStrokes = const [],
    this.marginNotes = const [],
    this.comparePairs = const [],
    this.translationCaches = const [],
    this.bookmarks = const [],
    this.documentOutlines = const [],
    this.studyNotes = const [],
    this.noteSourceArchive = const [],
  });

  static const empty = StudySetContent();

  final List<MapEditReceipt> assistantReceipts;
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

  final List<ResearchNote> researchNotes;
  final List<NoteAttachment> noteAttachments;
  final List<Evidence> evidence;
  final List<ResearchSource> researchSources;
  final List<InkStroke> inkStrokes;
  final List<MarginNote> marginNotes;
  final List<ComparePair> comparePairs;
  final List<TranslationCache> translationCaches;

  /// The reader's page bookmarks, across documents.
  final List<Bookmark> bookmarks;
  final List<DocumentOutline> documentOutlines;

  /// Written notes; missing in legacy study sets.
  final List<StudyNote> studyNotes;

  /// Deleted sources still referenced by a note.
  final List<NoteSourceArchive> noteSourceArchive;
  StudyNote? studyNote(String id) => studyNotes.where((n) => n.id == id).firstOrNull;

  DocumentOutline? outlineOn(String documentId) =>
      documentOutlines.where((o) => o.documentId == documentId).firstOrNull;

  /// Bookmarks in custom order, falling back to page order for legacy data.
  List<Bookmark> bookmarksOn(String documentId, {List<String> chapters = const []}) =>
      bookmarks.where((b) => b.documentId == documentId).toList()..sort((a, b) {
        if (a.order != null || b.order != null) {
          final byOrder = (a.order ?? 0x7fffffff).compareTo(b.order ?? 0x7fffffff);
          if (byOrder != 0) return byOrder;
        }
        final byPage = a.position is TextReadingPosition || b.position is TextReadingPosition
            ? (a.position == null || b.position == null
                  ? 0
                  : compareReadingPositions(a.position!, b.position!, chapters: chapters))
            : a.page.compareTo(b.page);
        return byPage != 0 ? byPage : a.createdAt.compareTo(b.createdAt);
      });

  Bookmark? bookmarkAt(String documentId, int page) => bookmarks
      .where((b) => b.documentId == documentId && b.position is! TextReadingPosition && b.page == page)
      .firstOrNull;

  Bookmark? bookmarkAtPosition(String documentId, ReadingPosition position) => bookmarks
      .where(
        (b) =>
            b.documentId == documentId &&
            b.position != null &&
            jsonEncode(b.position!.toJson()) == jsonEncode(position.toJson()),
      )
      .firstOrNull;

  /// Relations of [mapId] whose two cards are both placed in that map.
  List<MapRelation> relationsOf(String mapId) => [
    for (final r in relations)
      if (r.mapId == mapId && isPlaced(r.fromId, mapId: mapId) && isPlaced(r.toId, mapId: mapId)) r,
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

  ResearchNote? researchNote(String id) => researchNotes.where((n) => n.id == id).firstOrNull;

  Document? document(String id) => documents.where((d) => d.id == id).firstOrNull;
  Annotation? annotation(String id) => annotations.where((a) => a.id == id).firstOrNull;
  Card? card(String id) => cards.where((c) => c.id == id).firstOrNull;
  MapNode? node(String cardId, {String mapId = MindMap.defaultId}) =>
      nodes.where((n) => n.mapId == mapId && n.cardId == cardId).firstOrNull;

  bool containsCard(String cardId) => card(cardId) != null;

  /// Summary topic cards have a placement through their summary, not a MapNode.
  bool isPlaced(String cardId, {String mapId = MindMap.defaultId}) =>
      containsCard(cardId) &&
      (node(cardId, mapId: mapId) != null ||
          summaries.any((s) => s.mapId == mapId && s.cardId == cardId && summaryRange(s) != null));

  /// Effective ordered content, including legacy cards without stored segments.
  List<CardSegment> segmentsOf(Card card) {
    if (card.segments.isNotEmpty) return card.segments;
    final result = <CardSegment>[];
    if ((card.kind == CardKind.excerpt || card.kind == CardKind.image) && card.annotationId != null) {
      final source = annotation(card.annotationId!);
      result.add(CardSegment(text: source?.quote ?? '', annotationId: card.annotationId));
    }
    // An excerpt title is its review question, not another source segment.
    // Empty text cards still represent one segment for merge/split round trips.
    if (card.kind != CardKind.excerpt &&
        (card.title.isNotEmpty || card.kind == CardKind.topic || card.kind == CardKind.note)) {
      result.add(CardSegment(text: card.title));
    }
    if (card.body.isNotEmpty) result.add(CardSegment(text: card.body));
    return List.unmodifiable(result);
  }

  List<AnnotationSegmentMatch> segmentsForAnnotation(String annotationId, {String? mapId}) => [
    for (final card in cards)
      if (mapId == null || isPlaced(card.id, mapId: mapId))
        for (final (index, segment) in segmentsOf(card).indexed)
          if (segment.annotationId == annotationId) AnnotationSegmentMatch(card: card, segmentIndex: index),
  ];

  /// First card containing a segment linked to this annotation.
  Card? cardForAnnotation(String annotationId) => segmentsForAnnotation(annotationId).firstOrNull?.card;

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
  int get cardCount =>
      cards.where((c) => c.kind != CardKind.topic && c.id != researchReviewId(c.researchNoteId ?? '')).length;

  int get excerptCount => cards.where((c) => c.kind == CardKind.excerpt).length;

  ReviewState? reviewOf(String cardId) => reviews.where((r) => r.cardId == cardId).firstOrNull;

  /// A single persisted carrier per note; it has no map node or attachment.
  static String researchReviewId(String noteId) => 'research-review:$noteId';

  bool researchReviewEnabled(String noteId) => card(researchReviewId(noteId))?.suspended == false;

  /// Cards that can be reviewed: excerpts and non-empty notes on the map.
  Iterable<Card> get reviewableCards => cards.where(
    (c) =>
        (nodes.any((n) => n.cardId == c.id) ||
            (c.kind == CardKind.research && c.id == researchReviewId(c.researchNoteId ?? ''))) &&
        switch (c.kind) {
          CardKind.excerpt => segmentsOf(c).any((s) => s.annotationId != null && annotation(s.annotationId!) != null),
          CardKind.note => c.title.trim().isNotEmpty,
          CardKind.topic => false,
          CardKind.research =>
            c.id == researchReviewId(c.researchNoteId ?? '') && researchNote(c.researchNoteId ?? '') != null,
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
      final related = c.kind == CardKind.research
          ? cards.where((v) => v.researchNoteId == c.researchNoteId && v.id != c.id).toList()
          : [c];
      final mapped = related.where((v) => nodes.any((n) => n.cardId == v.id)).toList();
      // PDF-only notes participate in whole-map review, never an unrelated branch.
      if (mapId != null && mapped.isNotEmpty && !mapped.any((v) => node(v.id, mapId: mapId) != null)) continue;
      if (mapId != null && c.kind != CardKind.research && node(c.id, mapId: mapId) == null) continue;
      if (branch != null && !related.any((v) => branch.contains(v.id))) continue;
      if (wanted != null && !related.any((v) => v.tags.any((t) => t.toLowerCase() == wanted))) continue;
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

  /// Due times of scheduled, reviewable, not suspended cards.
  Iterable<DateTime> get scheduledDues sync* {
    final byId = {for (final r in reviews) r.cardId: r};
    for (final c in reviewableCards) {
      final r = byId[c.id];
      if (r != null && !c.suspended) yield r.due;
    }
  }

  int dueCount(DateTime now, {String? mapId, String? branchId, String? tag}) =>
      reviewQueue(now, mapId: mapId, branchId: branchId, tag: tag).length;

  /// [cardId] and every card below it on [mapId], folded or not; empty when
  /// the card is not on that map.
  Set<String> branch(String cardId, {String mapId = MindMap.defaultId}) {
    if (!isPlaced(cardId, mapId: mapId)) return const {};
    final children = <String, List<String>>{};
    for (final n in nodes) {
      if (n.mapId == mapId && n.parentId != null) children.putIfAbsent(n.parentId!, () => []).add(n.cardId);
    }
    // A summary belongs to the same branch as the siblings it summarizes.
    for (final summary in summaries) {
      if (summary.mapId != mapId || summary.cardId == null || summaryRange(summary) == null) continue;
      if (summary.parentId != null) children.putIfAbsent(summary.parentId!, () => []).add(summary.cardId!);
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
      titles.insert(0, notePlainText(card.title, card.textFormat));
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
        final tagged = tag == null || c.tags.any((t) => t.toLowerCase() == tag.toLowerCase());
        if (tagged &&
            (q.isEmpty ||
                hit(c.title) ||
                hit(c.body) ||
                segmentsOf(c).any((segment) => hit(segment.text)) ||
                c.tags.any(hit))) {
          result.add(c);
        }
        walk(c.id);
      }
    }

    walk(null);
    return result;
  }

  StudySetContent copyWith({
    List<MapEditReceipt>? assistantReceipts,
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
    List<ResearchNote>? researchNotes,
    List<NoteAttachment>? noteAttachments,
    List<Evidence>? evidence,
    List<ResearchSource>? researchSources,
    List<InkStroke>? inkStrokes,
    List<MarginNote>? marginNotes,
    List<ComparePair>? comparePairs,
    List<TranslationCache>? translationCaches,
    List<Bookmark>? bookmarks,
    List<DocumentOutline>? documentOutlines,
    List<StudyNote>? studyNotes,
    List<NoteSourceArchive>? noteSourceArchive,
  }) {
    return StudySetContent(
      assistantReceipts: assistantReceipts ?? this.assistantReceipts,
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
      researchNotes: researchNotes ?? this.researchNotes,
      noteAttachments: noteAttachments ?? this.noteAttachments,
      evidence: evidence ?? this.evidence,
      researchSources: researchSources ?? this.researchSources,
      inkStrokes: inkStrokes ?? this.inkStrokes,
      marginNotes: marginNotes ?? this.marginNotes,
      comparePairs: comparePairs ?? this.comparePairs,
      translationCaches: translationCaches ?? this.translationCaches,
      bookmarks: bookmarks ?? this.bookmarks,
      documentOutlines: documentOutlines ?? this.documentOutlines,
      studyNotes: studyNotes ?? this.studyNotes,
      noteSourceArchive: noteSourceArchive ?? this.noteSourceArchive,
    );
  }

  Map<String, Object?> toJson() => {
    'assistantReceipts': [for (final r in assistantReceipts) r.toJson()],
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
    'researchNotes': [for (final v in researchNotes) v.toJson()],
    'noteAttachments': [for (final v in noteAttachments) v.toJson()],
    'evidence': [for (final v in evidence) v.toJson()],
    'researchSources': [for (final v in researchSources) v.toJson()],
    'inkStrokes': [for (final v in inkStrokes) v.toJson()],
    'marginNotes': [for (final v in marginNotes) v.toJson()],
    'comparePairs': [for (final v in comparePairs) v.toJson()],
    'translationCaches': [for (final v in translationCaches) v.toJson()],
    'bookmarks': [for (final b in bookmarks) b.toJson()],
    'documentOutlines': [for (final o in documentOutlines) o.toJson()],
    if (studyNotes.isNotEmpty) 'studyNotes': [for (final n in studyNotes) n.toJson()],
    if (noteSourceArchive.isNotEmpty) 'noteSourceArchive': [for (final a in noteSourceArchive) a.toJson()],
  };

  factory StudySetContent.fromJson(Map<String, Object?> j) {
    List<T> list<T>(String key, T Function(Map<String, Object?>) f) => [
      for (final e in (j[key] as List?) ?? const []) f((e as Map).cast()),
    ];
    final cards = list('cards', Card.fromJson);
    final summaries = list('summaries', MapSummary.fromJson);
    final usedIds = cards.map((c) => c.id).toSet();
    final normalizedSummaries = <MapSummary>[];
    for (final summary in summaries) {
      if (summary.cardId != null && usedIds.contains(summary.cardId)) {
        normalizedSummaries.add(summary);
        continue;
      }
      final base = 'summary-topic:${summary.id}';
      var id = base;
      var suffix = 1;
      while (usedIds.contains(id)) {
        id = '$base:${suffix++}';
      }
      usedIds.add(id);
      cards.add(
        Card(
          id: id,
          kind: CardKind.topic,
          title: summary.label,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
      normalizedSummaries.add(summary.copyWith(cardId: id));
    }
    return StudySetContent(
      assistantReceipts: list('assistantReceipts', (j) => MapEditReceipt.fromJson(j.cast<String, dynamic>())),
      documents: list('documents', Document.fromJson),
      annotations: list('annotations', Annotation.fromJson),
      cards: cards,
      nodes: list('nodes', MapNode.fromJson),
      maps: j['maps'] == null ? const [MindMap.main] : list('maps', MindMap.fromJson),
      reviews: list('reviews', ReviewState.fromJson),
      reviewLogs: list('reviewLogs', ReviewLog.fromJson),
      memoryStates: list('memoryStates', MemoryState.fromJson),
      relations: list('relations', MapRelation.fromJson),
      summaries: normalizedSummaries,
      researchNotes: list('researchNotes', ResearchNote.fromJson),
      noteAttachments: list('noteAttachments', NoteAttachment.fromJson),
      evidence: list('evidence', Evidence.fromJson),
      researchSources: list('researchSources', ResearchSource.fromJson),
      inkStrokes: list('inkStrokes', InkStroke.fromJson),
      marginNotes: list('marginNotes', MarginNote.fromJson),
      comparePairs: list('comparePairs', ComparePair.fromJson),
      translationCaches: list('translationCaches', TranslationCache.fromJson),
      bookmarks: list('bookmarks', Bookmark.fromJson),
      documentOutlines: list('documentOutlines', DocumentOutline.fromJson),
      studyNotes: list('studyNotes', StudyNote.fromJson),
      noteSourceArchive: list('noteSourceArchive', NoteSourceArchive.fromJson),
    );
  }
}
