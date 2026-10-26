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
    lastReadAt: lastReadAt ?? this.lastReadAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'fileName': fileName,
    'pageCount': pageCount,
    'lastPage': lastPage,
    'importedAt': importedAt.toIso8601String(),
    if (lastReadAt != null) 'lastReadAt': lastReadAt!.toIso8601String(),
  };

  factory Document.fromJson(Map<String, Object?> j) => Document(
    id: j['id'] as String,
    title: j['title'] as String,
    fileName: j['fileName'] as String,
    pageCount: j['pageCount'] as int,
    lastPage: (j['lastPage'] as int?) ?? 1,
    importedAt: DateTime.parse(j['importedAt'] as String),
    lastReadAt: j['lastReadAt'] == null ? null : DateTime.parse(j['lastReadAt'] as String),
  );
}

/// A reader's own bookmark on one page of a document. An empty [title]
/// means "unnamed": the UI shows the page number instead.
@immutable
class Bookmark {
  const Bookmark({
    required this.id,
    required this.documentId,
    required this.page,
    required this.createdAt,
    this.title = '',
  });

  final String id;
  final String documentId;

  /// 1-based page.
  final int page;
  final DateTime createdAt;
  final String title;

  Bookmark copyWith({String? title}) =>
      Bookmark(id: id, documentId: documentId, page: page, createdAt: createdAt, title: title ?? this.title);

  Map<String, Object?> toJson() => {
    'id': id,
    'documentId': documentId,
    'page': page,
    'createdAt': createdAt.toIso8601String(),
    if (title.isNotEmpty) 'title': title,
  };

  factory Bookmark.fromJson(Map<String, Object?> j) => Bookmark(
    id: j['id'] as String,
    documentId: j['documentId'] as String,
    page: j['page'] as int,
    createdAt: DateTime.parse(j['createdAt'] as String),
    title: (j['title'] as String?) ?? '',
  );
}

/// Rectangles belonging to one 1-based PDF page.
@immutable
class AnnotationPage {
  const AnnotationPage({required this.page, required this.rects});
  final int page;
  final List<PageRect> rects;
  Map<String, Object?> toJson() => {
    'page': page,
    'rects': [for (final r in rects) r.toJson()],
  };
  factory AnnotationPage.fromJson(Map<String, Object?> j) => AnnotationPage(
    page: j['page'] as int,
    rects: [for (final r in j['rects'] as List) PageRect.fromJson((r as Map).cast())],
  );
}

/// A highlight spanning one or more pages, in reading order.
@immutable
class Annotation {
  const Annotation({
    required this.id,
    required this.documentId,
    int? page,
    List<PageRect>? rects,
    List<AnnotationPage>? pages,
    required this.quote,
    required this.colorIndex,
    required this.createdAt,
  }) : assert(pages != null || (page != null && rects != null)),
       _pages = pages,
       _page = page,
       _rects = rects;

  final String id;
  final String documentId;
  final List<AnnotationPage>? _pages;
  final int? _page;
  final List<PageRect>? _rects;
  List<AnnotationPage> get pages => _pages ?? [AnnotationPage(page: _page!, rects: _rects!)];

  /// First-page compatibility accessors for the existing reader.
  int get page => pages.first.page;
  List<PageRect> get rects => pages.first.rects;
  final String quote;
  final int colorIndex;
  final DateTime createdAt;

  Annotation copyWith({int? colorIndex}) => Annotation(
    id: id,
    documentId: documentId,
    pages: pages,
    quote: quote,
    colorIndex: colorIndex ?? this.colorIndex,
    createdAt: createdAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'documentId': documentId,
    'pages': [for (final p in pages) p.toJson()],
    'quote': quote,
    'colorIndex': colorIndex,
    'createdAt': createdAt.toIso8601String(),
  };
  factory Annotation.fromJson(Map<String, Object?> j) => Annotation(
    id: j['id'] as String,
    documentId: j['documentId'] as String,
    pages: j['pages'] == null
        ? [AnnotationPage.fromJson(j)]
        : [for (final p in j['pages'] as List) AnnotationPage.fromJson((p as Map).cast())],
    quote: j['quote'] as String,
    colorIndex: j['colorIndex'] as int,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

enum CardKind { topic, excerpt, note, image }

/// A node's content. Its place in the mind map is stored separately in
/// [MapNode], so one card could appear in several maps later.
@immutable
class Card {
  const Card({
    required this.id,
    required this.kind,
    this.title = '',
    this.annotationId,
    this.imageFileName,
    this.tags = const [],
    this.suspended = false,
    required this.createdAt,
  });

  final String id;
  final CardKind kind;

  /// Topic name, note text, or an optional title for an excerpt.
  final String title;

  /// Set for excerpts.
  final String? annotationId;

  /// Content-addressed image path relative to the package.
  final String? imageFileName;
  final DateTime createdAt;

  final List<String> tags;

  /// Shared across maps; a suspended card stays out of every review queue.
  final bool suspended;

  Card copyWith({String? title, List<String>? tags, bool? suspended}) => Card(
    id: id,
    kind: kind,
    title: title ?? this.title,
    tags: tags == null ? this.tags : List.unmodifiable(tags),
    suspended: suspended ?? this.suspended,
    annotationId: annotationId,
    imageFileName: imageFileName,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    if (annotationId != null) 'annotationId': annotationId,
    if (imageFileName != null) 'imageFileName': imageFileName,
    if (tags.isNotEmpty) 'tags': tags,
    if (suspended) 'suspended': true,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Card.fromJson(Map<String, Object?> j) => Card(
    id: j['id'] as String,
    kind: CardKind.values.byName(j['kind'] as String),
    title: (j['title'] as String?) ?? '',
    annotationId: j['annotationId'] as String?,
    imageFileName: j['imageFileName'] as String?,
    tags: List.unmodifiable(((j['tags'] as List?) ?? const []).cast<String>()),
    suspended: (j['suspended'] as bool?) ?? false,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

/// A named map. The stable default id keeps format 1 placements unchanged.
@immutable
class MindMap {
  const MindMap({required this.id, required this.title});
  static const defaultId = 'main';
  static const main = MindMap(id: defaultId, title: '');
  final String id;
  final String title;
  MindMap copyWith({String? title}) => MindMap(id: id, title: title ?? this.title);
  Map<String, Object?> toJson() => {'id': id, 'title': title};
  factory MindMap.fromJson(Map<String, Object?> j) => MindMap(id: j['id'] as String, title: j['title'] as String);
}

/// Placement of a card in the main mind map. `parentId == null` means a
/// child of the root (the study set itself).
@immutable
class MapNode {
  const MapNode({
    required this.cardId,
    this.mapId = MindMap.defaultId,
    this.parentId,
    required this.order,
    this.collapsed = false,
  });

  final String cardId;
  final String mapId;
  final String? parentId;

  /// Sibling order; fractional so inserts never renumber siblings.
  final double order;

  /// Children are hidden in the map view.
  final bool collapsed;

  MapNode copyWith({String? parentId, bool toRoot = false, double? order, bool? collapsed}) => MapNode(
    cardId: cardId,
    mapId: mapId,
    parentId: toRoot ? null : (parentId ?? this.parentId),
    order: order ?? this.order,
    collapsed: collapsed ?? this.collapsed,
  );

  Map<String, Object?> toJson() => {
    'cardId': cardId,
    'mapId': mapId,
    if (parentId != null) 'parentId': parentId,
    'order': order,
    if (collapsed) 'collapsed': true,
  };

  factory MapNode.fromJson(Map<String, Object?> j) => MapNode(
    cardId: j['cardId'] as String,
    mapId: (j['mapId'] as String?) ?? MindMap.defaultId,
    parentId: j['parentId'] as String?,
    order: _d(j['order']),
    collapsed: (j['collapsed'] as bool?) ?? false,
  );
}

/// A labeled line between two cards of one map, drawn from [fromId] to
/// [toId]. It belongs to the map, not to either card.
@immutable
class MapRelation {
  const MapRelation({
    required this.id,
    this.mapId = MindMap.defaultId,
    required this.fromId,
    required this.toId,
    this.label = '',
  });

  final String id;
  final String mapId;
  final String fromId;
  final String toId;
  final String label;

  MapRelation copyWith({String? label}) =>
      MapRelation(id: id, mapId: mapId, fromId: fromId, toId: toId, label: label ?? this.label);

  Map<String, Object?> toJson() => {
    'id': id,
    'mapId': mapId,
    'fromId': fromId,
    'toId': toId,
    if (label.isNotEmpty) 'label': label,
  };

  factory MapRelation.fromJson(Map<String, Object?> j) => MapRelation(
    id: j['id'] as String,
    mapId: (j['mapId'] as String?) ?? MindMap.defaultId,
    fromId: j['fromId'] as String,
    toId: j['toId'] as String,
    label: (j['label'] as String?) ?? '',
  );
}

/// A label summing up consecutive children of [parentId] (null = root),
/// from [fromId] to [toId] inclusive. The range follows the siblings'
/// current order, so reordering inside it keeps the summary.
@immutable
class MapSummary {
  const MapSummary({
    required this.id,
    this.mapId = MindMap.defaultId,
    this.parentId,
    required this.fromId,
    required this.toId,
    this.label = '',
  });

  final String id;
  final String mapId;
  final String? parentId;
  final String fromId;
  final String toId;
  final String label;

  MapSummary copyWith({String? label, String? fromId, String? toId}) => MapSummary(
    id: id,
    mapId: mapId,
    parentId: parentId,
    fromId: fromId ?? this.fromId,
    toId: toId ?? this.toId,
    label: label ?? this.label,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'mapId': mapId,
    if (parentId != null) 'parentId': parentId,
    'fromId': fromId,
    'toId': toId,
    if (label.isNotEmpty) 'label': label,
  };

  factory MapSummary.fromJson(Map<String, Object?> j) => MapSummary(
    id: j['id'] as String,
    mapId: (j['mapId'] as String?) ?? MindMap.defaultId,
    parentId: j['parentId'] as String?,
    fromId: j['fromId'] as String,
    toId: j['toId'] as String,
    label: (j['label'] as String?) ?? '',
  );
}
