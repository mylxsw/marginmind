import 'package:meta/meta.dart';

/// A rectangle in PDF page coordinates (points, origin bottom-left, so
/// `top >= bottom`). Independent of zoom and screen size.
@immutable
class PageRect {
  const PageRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, Object?> toJson() => {'l': left, 't': top, 'r': right, 'b': bottom};

  factory PageRect.fromJson(Map<String, Object?> j) => PageRect(_d(j['l']), _d(j['t']), _d(j['r']), _d(j['b']));

  @override
  bool operator ==(Object other) =>
      other is PageRect && other.left == left && other.top == top && other.right == right && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

double _d(Object? v) => (v as num).toDouble();

/// A PDF inside a study set. The file lives in the set's package folder.
@immutable
class Document {
  const Document({
    required this.id,
    required this.title,
    required this.fileName,
    required this.pageCount,
    required this.importedAt,
    this.lastPage = 1,
    this.lastReadAt,
  });

  final String id;
  final String title;

  /// Path relative to the study set package, e.g. `documents/ab12.pdf`.
  final String fileName;
  final int pageCount;
  final int lastPage;
  final DateTime importedAt;

  /// When [lastPage] was last updated; drives "Continue Learning".
  final DateTime? lastReadAt;

  Document copyWith({String? title, int? lastPage, DateTime? lastReadAt}) => Document(
    id: id,
    title: title ?? this.title,
    fileName: fileName,
    pageCount: pageCount,
    importedAt: importedAt,
    lastPage: lastPage ?? this.lastPage,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'fileName': fileName,
    'pageCount': pageCount,
    'lastPage': lastPage,
    'importedAt': importedAt.toIso8601String(),
  };

  factory Document.fromJson(Map<String, Object?> j) => Document(
    id: j['id'] as String,
    title: j['title'] as String,
    fileName: j['fileName'] as String,
    pageCount: j['pageCount'] as int,
    lastPage: (j['lastPage'] as int?) ?? 1,
    importedAt: DateTime.parse(j['importedAt'] as String),
  );
}

/// A highlight on a document page. Keeps both geometry (to draw it) and
/// the quoted text (to show it, and to re-find it if the file changes).
@immutable
class Annotation {
  const Annotation({
    required this.id,
    required this.documentId,
    required this.page,
    required this.rects,
    required this.quote,
    required this.colorIndex,
    required this.createdAt,
  });

  final String id;
  final String documentId;

  /// 1-based page number.
  final int page;
  final List<PageRect> rects;
  final String quote;
  final int colorIndex;
  final DateTime createdAt;

  Annotation copyWith({int? colorIndex}) => Annotation(
    id: id,
    documentId: documentId,
    page: page,
    rects: rects,
    quote: quote,
    colorIndex: colorIndex ?? this.colorIndex,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'documentId': documentId,
    'page': page,
    'rects': [for (final r in rects) r.toJson()],
    'quote': quote,
    'colorIndex': colorIndex,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Annotation.fromJson(Map<String, Object?> j) => Annotation(
    id: j['id'] as String,
    documentId: j['documentId'] as String,
    page: j['page'] as int,
    rects: [for (final r in j['rects'] as List) PageRect.fromJson((r as Map).cast())],
    quote: j['quote'] as String,
    colorIndex: j['colorIndex'] as int,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

enum CardKind { topic, excerpt, note }

/// A node's content. Its place in the mind map is stored separately in
/// [MapNode], so one card could appear in several maps later.
@immutable
class Card {
  const Card({required this.id, required this.kind, this.title = '', this.annotationId, required this.createdAt});

  final String id;
  final CardKind kind;

  /// Topic name, note text, or an optional title for an excerpt.
  final String title;

  /// Set for excerpts.
  final String? annotationId;
  final DateTime createdAt;

  Card copyWith({String? title}) =>
      Card(id: id, kind: kind, title: title ?? this.title, annotationId: annotationId, createdAt: createdAt);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    if (annotationId != null) 'annotationId': annotationId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Card.fromJson(Map<String, Object?> j) => Card(
    id: j['id'] as String,
    kind: CardKind.values.byName(j['kind'] as String),
    title: (j['title'] as String?) ?? '',
    annotationId: j['annotationId'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

/// Placement of a card in the main mind map. `parentId == null` means a
/// child of the root (the study set itself).
@immutable
class MapNode {
  const MapNode({required this.cardId, this.parentId, required this.order});

  final String cardId;
  final String? parentId;

  /// Sibling order; fractional so inserts never renumber siblings.
  final double order;

  MapNode copyWith({String? parentId, bool toRoot = false, double? order}) =>
      MapNode(cardId: cardId, parentId: toRoot ? null : (parentId ?? this.parentId), order: order ?? this.order);

  Map<String, Object?> toJson() => {'cardId': cardId, if (parentId != null) 'parentId': parentId, 'order': order};

  factory MapNode.fromJson(Map<String, Object?> j) =>
      MapNode(cardId: j['cardId'] as String, parentId: j['parentId'] as String?, order: _d(j['order']));
}
