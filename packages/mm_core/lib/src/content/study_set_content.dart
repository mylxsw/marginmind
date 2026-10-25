import 'package:meta/meta.dart';

import 'models.dart';

/// Everything inside one study set: documents, highlights, cards and the
/// main mind map. Immutable; edits produce a new value (see
/// [StudySetEditor]), which makes persistence and undo straightforward.
@immutable
class StudySetContent {
  const StudySetContent({
    this.documents = const [],
    this.annotations = const [],
    this.cards = const [],
    this.nodes = const [],
  });

  static const empty = StudySetContent();

  final List<Document> documents;
  final List<Annotation> annotations;
  final List<Card> cards;
  final List<MapNode> nodes;

  Document? document(String id) => documents.where((d) => d.id == id).firstOrNull;
  Annotation? annotation(String id) => annotations.where((a) => a.id == id).firstOrNull;
  Card? card(String id) => cards.where((c) => c.id == id).firstOrNull;
  MapNode? node(String cardId) => nodes.where((n) => n.cardId == cardId).firstOrNull;

  /// The excerpt card made from [annotationId], if any.
  Card? cardForAnnotation(String annotationId) => cards.where((c) => c.annotationId == annotationId).firstOrNull;

  /// Children of [parentId] (null = root) in display order.
  List<MapNode> childrenOf(String? parentId) =>
      nodes.where((n) => n.parentId == parentId).toList()..sort((a, b) => a.order.compareTo(b.order));

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

  StudySetContent copyWith({
    List<Document>? documents,
    List<Annotation>? annotations,
    List<Card>? cards,
    List<MapNode>? nodes,
  }) {
    return StudySetContent(
      documents: documents ?? this.documents,
      annotations: annotations ?? this.annotations,
      cards: cards ?? this.cards,
      nodes: nodes ?? this.nodes,
    );
  }

  Map<String, Object?> toJson() => {
    'documents': [for (final d in documents) d.toJson()],
    'annotations': [for (final a in annotations) a.toJson()],
    'cards': [for (final c in cards) c.toJson()],
    'nodes': [for (final n in nodes) n.toJson()],
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
    );
  }
}
