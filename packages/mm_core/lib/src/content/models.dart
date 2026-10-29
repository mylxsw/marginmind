import 'package:meta/meta.dart';

import 'research.dart';
import 'reading.dart';

const _keepCrop = Object();
const _keepValue = Object();

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
    this.crop,
    this.cropSuggestionDismissed = false,
  });

  final String id;
  final String title;

  /// Path relative to the study set package, e.g. `documents/ab12.pdf`.
  final String fileName;
  final int pageCount;
  final DocumentCrop? crop;
  final bool cropSuggestionDismissed;
  final int lastPage;
  final DateTime importedAt;

  /// When [lastPage] was last updated; drives "Continue Learning".
  final DateTime? lastReadAt;

  Document copyWith({
    String? title,
    int? lastPage,
    DateTime? lastReadAt,
    Object? crop = _keepCrop,
    bool? cropSuggestionDismissed,
  }) => Document(
    id: id,
    title: title ?? this.title,
    fileName: fileName,
    pageCount: pageCount,
    importedAt: importedAt,
    lastPage: lastPage ?? this.lastPage,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    crop: identical(crop, _keepCrop) ? this.crop : crop as DocumentCrop?,
    cropSuggestionDismissed: cropSuggestionDismissed ?? this.cropSuggestionDismissed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'fileName': fileName,
    'pageCount': pageCount,
    'lastPage': lastPage,
    'importedAt': importedAt.toIso8601String(),
    if (lastReadAt != null) 'lastReadAt': lastReadAt!.toIso8601String(),
    if (crop != null) 'crop': crop!.toJson(),
    if (cropSuggestionDismissed) 'cropSuggestionDismissed': true,
  };

  factory Document.fromJson(Map<String, Object?> j) => Document(
    crop: j['crop'] == null ? null : DocumentCrop.fromJson((j['crop'] as Map).cast()),
    cropSuggestionDismissed: j['cropSuggestionDismissed'] as bool? ?? false,
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
    this.order,
  });

  final String id;
  final String documentId;

  /// 1-based page.
  final int page;
  final DateTime createdAt;
  final String title;

  /// Custom position within this document; null retains legacy page sorting.
  final int? order;

  Bookmark copyWith({String? title, int? page, int? order}) => Bookmark(
    id: id,
    documentId: documentId,
    page: page ?? this.page,
    createdAt: createdAt,
    title: title ?? this.title,
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'documentId': documentId,
    'page': page,
    'createdAt': createdAt.toIso8601String(),
    if (title.isNotEmpty) 'title': title,
    if (order != null) 'order': order,
  };

  factory Bookmark.fromJson(Map<String, Object?> j) => Bookmark(
    id: j['id'] as String,
    documentId: j['documentId'] as String,
    page: j['page'] as int,
    createdAt: DateTime.parse(j['createdAt'] as String),
    title: (j['title'] as String?) ?? '',
    order: j['order'] as int?,
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

enum AnnotationKind { highlight, underline }

enum AnnotationLineStyle { solid, dashed, dotted, wavy }

/// A text mark spanning one or more pages, in reading order.
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
    this.kind = AnnotationKind.highlight,
    this.lineStyle = AnnotationLineStyle.solid,
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

  /// Preset ID 0–5, or 0x01000000 | RGB for an exact custom color.
  final int colorIndex;
  final DateTime createdAt;

  final AnnotationKind kind;
  final AnnotationLineStyle lineStyle;

  Annotation copyWith({int? colorIndex, AnnotationKind? kind, AnnotationLineStyle? lineStyle}) => Annotation(
    id: id,
    documentId: documentId,
    pages: pages,
    quote: quote,
    colorIndex: colorIndex ?? this.colorIndex,
    kind: kind ?? this.kind,
    lineStyle: lineStyle ?? this.lineStyle,
    createdAt: createdAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'documentId': documentId,
    'pages': [for (final p in pages) p.toJson()],
    'quote': quote,
    'colorIndex': colorIndex,
    if (kind != AnnotationKind.highlight) 'kind': kind.name,
    if (lineStyle != AnnotationLineStyle.solid) 'lineStyle': lineStyle.name,
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
    kind: AnnotationKind.values.where((v) => v.name == j['kind']).firstOrNull ?? AnnotationKind.highlight,
    lineStyle:
        AnnotationLineStyle.values.where((v) => v.name == j['lineStyle']).firstOrNull ?? AnnotationLineStyle.solid,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

@immutable
class CardSegment {
  const CardSegment({required this.text, this.annotationId});
  final String text;
  final String? annotationId;

  CardSegment copyWith({String? text, Object? annotationId = _keepValue}) => CardSegment(
    text: text ?? this.text,
    annotationId: identical(annotationId, _keepValue) ? this.annotationId : annotationId as String?,
  );

  Map<String, Object?> toJson() => {'text': text, if (annotationId != null) 'annotationId': annotationId};

  factory CardSegment.fromJson(Map<String, Object?> j) =>
      CardSegment(text: j['text'] as String? ?? '', annotationId: j['annotationId'] as String?);
}

@immutable
class AnnotationSegmentMatch {
  const AnnotationSegmentMatch({required this.card, required this.segmentIndex});
  final Card card;
  final int segmentIndex;
}

enum CardKind { topic, excerpt, note, image, research }

/// A node's content. Its place in the mind map is stored separately in
/// [MapNode], so one card could appear in several maps later.
@immutable
class Card {
  const Card({
    required this.id,
    required this.kind,
    this.title = '',
    this.body = '',
    this.segments = const [],
    this.annotationId,
    this.imageFileName,
    this.researchNoteId,
    this.textFormat = TextFormat.plain,
    this.imageOrigin,
    this.tags = const [],
    this.suspended = false,
    required this.createdAt,
  });

  final String id;
  final CardKind kind;

  /// Topic name, note text, or an optional title for an excerpt.
  final String title;

  /// Optional note body; when set, review uses title as question and body as answer.
  final String body;
  final List<CardSegment> segments;

  /// Set for excerpts.
  final String? annotationId;

  /// Content-addressed image path relative to the package.
  final String? imageFileName;
  final String? researchNoteId;
  final TextFormat textFormat;
  final String? imageOrigin;
  final DateTime createdAt;

  final List<String> tags;

  /// Shared across maps; a suspended card stays out of every review queue.
  final bool suspended;

  Card copyWith({
    String? title,
    String? body,
    CardKind? kind,
    List<CardSegment>? segments,
    Object? annotationId = _keepValue,
    bool clearAnnotationId = false,
    List<String>? tags,
    bool? suspended,
    TextFormat? textFormat,
  }) => Card(
    id: id,
    kind: kind ?? this.kind,
    segments: segments == null ? this.segments : List.unmodifiable(segments),
    title: title ?? this.title,
    body: body ?? this.body,
    tags: tags == null ? this.tags : List.unmodifiable(tags),
    suspended: suspended ?? this.suspended,
    annotationId: clearAnnotationId
        ? null
        : (identical(annotationId, _keepValue) ? this.annotationId : annotationId as String?),
    imageFileName: imageFileName,
    researchNoteId: researchNoteId,
    textFormat: textFormat ?? this.textFormat,
    imageOrigin: imageOrigin,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    if (body.isNotEmpty) 'body': body,
    if (segments.isNotEmpty) 'segments': [for (final segment in segments) segment.toJson()],
    if (annotationId != null) 'annotationId': annotationId,
    if (imageFileName != null) 'imageFileName': imageFileName,
    if (researchNoteId != null) 'researchNoteId': researchNoteId,
    'textFormat': textFormat.name,
    if (imageOrigin != null) 'imageOrigin': imageOrigin,
    if (tags.isNotEmpty) 'tags': tags,
    if (suspended) 'suspended': true,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Card.fromJson(Map<String, Object?> j) => Card(
    id: j['id'] as String,
    kind: CardKind.values.byName(j['kind'] as String),
    title: (j['title'] as String?) ?? '',
    body: j['body'] as String? ?? '',
    segments: List.unmodifiable([
      for (final v in (j['segments'] as List?) ?? const []) CardSegment.fromJson((v as Map).cast()),
    ]),
    annotationId: j['annotationId'] as String?,
    imageFileName: j['imageFileName'] as String?,
    researchNoteId: j['researchNoteId'] as String?,
    textFormat: TextFormat.values.byName(j['textFormat'] as String? ?? 'plain'),
    imageOrigin: j['imageOrigin'] as String?,
    tags: List.unmodifiable(((j['tags'] as List?) ?? const []).cast<String>()),
    suspended: (j['suspended'] as bool?) ?? false,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

enum MapStructure { mind, logic, brace, tree }

enum MapPalette { system, rainbow, fresh, warm, morandi, ink }

/// A named map. The stable default id keeps format 1 placements unchanged.
@immutable
class MindMap {
  const MindMap({
    required this.id,
    required this.title,
    this.density = MapDensity.full,
    this.structure = MapStructure.mind,
    this.palette = MapPalette.system,
  });
  static const defaultId = 'main';
  static const main = MindMap(id: defaultId, title: '');
  final String id;
  final String title;
  final MapDensity density;
  final MapStructure structure;
  final MapPalette palette;
  MindMap copyWith({String? title, MapDensity? density, MapStructure? structure, MapPalette? palette}) => MindMap(
    id: id,
    title: title ?? this.title,
    density: density ?? this.density,
    structure: structure ?? this.structure,
    palette: palette ?? this.palette,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'density': density.name,
    'structure': structure.name,
    'palette': palette.name,
  };
  factory MindMap.fromJson(Map<String, Object?> j) => MindMap(
    id: j['id'] as String,
    title: j['title'] as String,
    density: MapDensity.values.byName(j['density'] as String? ?? 'full'),
    structure: MapStructure.values.byName(j['structure'] as String? ?? 'mind'),
    palette: MapPalette.values.byName(j['palette'] as String? ?? 'system'),
  );
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
    this.width,
  });

  final String cardId;
  final String mapId;
  final String? parentId;

  /// Sibling order; fractional so inserts never renumber siblings.
  final double order;

  /// Children are hidden in the map view.
  final bool collapsed;

  /// The card's width in this map (P2-C06); null is the default width.
  final double? width;

  /// The range a card can be resized to.
  static const minWidth = 200.0;
  static const maxWidth = 480.0;

  MapNode copyWith({
    String? parentId,
    bool toRoot = false,
    double? order,
    bool? collapsed,
    double? width,
    bool resetWidth = false,
  }) => MapNode(
    cardId: cardId,
    mapId: mapId,
    parentId: toRoot ? null : (parentId ?? this.parentId),
    order: order ?? this.order,
    collapsed: collapsed ?? this.collapsed,
    width: resetWidth ? null : (width ?? this.width),
  );

  Map<String, Object?> toJson() => {
    'cardId': cardId,
    'mapId': mapId,
    if (parentId != null) 'parentId': parentId,
    'order': order,
    if (collapsed) 'collapsed': true,
    if (width != null) 'width': width,
  };

  factory MapNode.fromJson(Map<String, Object?> j) => MapNode(
    cardId: j['cardId'] as String,
    mapId: (j['mapId'] as String?) ?? MindMap.defaultId,
    parentId: j['parentId'] as String?,
    order: _d(j['order']),
    collapsed: (j['collapsed'] as bool?) ?? false,
    width: (j['width'] as num?)?.toDouble(),
  );
}

enum RelationArrow { end, both, none }

@immutable
class RelationControlPoint {
  const RelationControlPoint(this.dx, this.dy);
  final double dx;
  final double dy;
  Map<String, Object?> toJson() => {'dx': dx, 'dy': dy};
  factory RelationControlPoint.fromJson(Map<String, Object?> j) => RelationControlPoint(_d(j['dx']), _d(j['dy']));
  @override
  bool operator ==(Object other) => other is RelationControlPoint && dx == other.dx && dy == other.dy;
  @override
  int get hashCode => Object.hash(dx, dy);
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
    this.arrow = RelationArrow.end,
    this.solid = false,
    this.control1,
    this.control2,
  });

  final String id;
  final String mapId;
  final String fromId;
  final String toId;
  final String label;

  final RelationArrow arrow;
  final bool solid;
  final RelationControlPoint? control1;
  final RelationControlPoint? control2;

  MapRelation copyWith({
    String? label,
    String? fromId,
    String? toId,
    RelationArrow? arrow,
    bool? solid,
    RelationControlPoint? control1,
    RelationControlPoint? control2,
    bool clearControl1 = false,
    bool clearControl2 = false,
  }) => MapRelation(
    id: id,
    mapId: mapId,
    fromId: fromId ?? this.fromId,
    toId: toId ?? this.toId,
    label: label ?? this.label,
    arrow: arrow ?? this.arrow,
    solid: solid ?? this.solid,
    control1: clearControl1 ? null : control1 ?? this.control1,
    control2: clearControl2 ? null : control2 ?? this.control2,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'mapId': mapId,
    'fromId': fromId,
    'toId': toId,
    'arrow': arrow.name,
    'solid': solid,
    if (control1 != null) 'control1': control1!.toJson(),
    if (control2 != null) 'control2': control2!.toJson(),
    if (label.isNotEmpty) 'label': label,
  };

  factory MapRelation.fromJson(Map<String, Object?> j) => MapRelation(
    id: j['id'] as String,
    mapId: (j['mapId'] as String?) ?? MindMap.defaultId,
    fromId: j['fromId'] as String,
    toId: j['toId'] as String,
    label: (j['label'] as String?) ?? '',
    arrow: RelationArrow.values.byName(j['arrow'] as String? ?? 'end'),
    solid: j['solid'] as bool? ?? false,
    control1: j['control1'] == null ? null : RelationControlPoint.fromJson((j['control1'] as Map).cast()),
    control2: j['control2'] == null ? null : RelationControlPoint.fromJson((j['control2'] as Map).cast()),
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
    this.cardId,
    required this.fromId,
    required this.toId,
    this.label = '',
  });

  final String id;
  final String mapId;
  final String? parentId;
  final String? cardId;
  final String fromId;
  final String toId;
  final String label;

  MapSummary copyWith({
    String? label,
    String? fromId,
    String? toId,
    String? cardId,
    String? parentId,
    bool toRoot = false,
  }) => MapSummary(
    id: id,
    mapId: mapId,
    parentId: toRoot ? null : parentId ?? this.parentId,
    cardId: cardId ?? this.cardId,
    fromId: fromId ?? this.fromId,
    toId: toId ?? this.toId,
    label: label ?? this.label,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'mapId': mapId,
    if (cardId != null) 'cardId': cardId,
    if (parentId != null) 'parentId': parentId,
    'fromId': fromId,
    'toId': toId,
    if (label.isNotEmpty) 'label': label,
  };

  factory MapSummary.fromJson(Map<String, Object?> j) => MapSummary(
    id: j['id'] as String,
    mapId: (j['mapId'] as String?) ?? MindMap.defaultId,
    parentId: j['parentId'] as String?,
    cardId: j['cardId'] as String?,
    fromId: j['fromId'] as String,
    toId: j['toId'] as String,
    label: (j['label'] as String?) ?? '',
  );
}
