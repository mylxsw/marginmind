import 'package:meta/meta.dart';

import 'models.dart';

enum TextFormat { plain, markdown }

enum NoteOrigin { user, ai, excerpt, mixed }

enum MapDensity { full, compact, titleOnly }

enum InkTool { pen, highlighter, ellipse }

/// Stable page coordinates; shared by attachments and research starting points.
sealed class NoteTarget {
  const NoteTarget();
  Map<String, Object?> toJson();
  factory NoteTarget.fromJson(Map<String, Object?> j) => switch (j['type']) {
    'pdf' => PdfTarget.fromJson(j),
    'card' => CardTarget.fromJson(j),
    _ => throw const FormatException('Unknown note target'),
  };
}

@immutable
class PdfTarget extends NoteTarget {
  PdfTarget({required this.documentId, required List<AnnotationPage> pages, this.quote = '', this.context = ''})
    : pages = List.unmodifiable([
        for (final p in pages) AnnotationPage(page: p.page, rects: List.unmodifiable(p.rects)),
      ]);
  final String documentId;
  final List<AnnotationPage> pages;
  final String quote;
  final String context;
  @override
  Map<String, Object?> toJson() => {
    'type': 'pdf',
    'documentId': documentId,
    'pages': [for (final p in pages) p.toJson()],
    'quote': quote,
    'context': context,
  };
  factory PdfTarget.fromJson(Map<String, Object?> j) => PdfTarget(
    documentId: j['documentId'] as String,
    pages: [for (final p in j['pages'] as List) AnnotationPage.fromJson((p as Map).cast())],
    quote: j['quote'] as String? ?? '',
    context: j['context'] as String? ?? '',
  );
}

@immutable
class CardTarget extends NoteTarget {
  const CardTarget({required this.cardId});
  final String cardId;
  @override
  Map<String, Object?> toJson() => {'type': 'card', 'cardId': cardId};
  factory CardTarget.fromJson(Map<String, Object?> j) => CardTarget(cardId: j['cardId'] as String);
}

/// A PDF anchor or a card anchor with its map. Deleted anchors remain historical.
@immutable
class SourceAnchor {
  const SourceAnchor({required this.target, this.mapId});
  final NoteTarget target;
  final String? mapId;
  bool canLocate(Iterable<Document> documents, Iterable<MapNode> nodes) => switch (target) {
    PdfTarget(:final documentId) => documents.any((d) => d.id == documentId),
    CardTarget(:final cardId) => nodes.any((n) => n.cardId == cardId && n.mapId == mapId),
  };
  Map<String, Object?> toJson() => {'target': target.toJson(), if (mapId != null) 'mapId': mapId};
  factory SourceAnchor.fromJson(Map<String, Object?> j) =>
      SourceAnchor(target: NoteTarget.fromJson((j['target'] as Map).cast()), mapId: j['mapId'] as String?);
}

@immutable
class NoteAttachment {
  const NoteAttachment({required this.id, required this.noteId, required this.target});
  final String id;
  final String noteId;
  final NoteTarget target;
  Map<String, Object?> toJson() => {'id': id, 'noteId': noteId, 'target': target.toJson()};
  factory NoteAttachment.fromJson(Map<String, Object?> j) => NoteAttachment(
    id: j['id'] as String,
    noteId: j['noteId'] as String,
    target: NoteTarget.fromJson((j['target'] as Map).cast()),
  );
}

@immutable
class EvidenceRef {
  const EvidenceRef(this.evidenceId);
  final String evidenceId;
  Map<String, Object?> toJson() => {'evidenceId': evidenceId};
  factory EvidenceRef.fromJson(Map<String, Object?> j) => EvidenceRef(j['evidenceId'] as String);
}

/// Exactly one locator: paragraph, PDF page, or a video time range in seconds.
@immutable
class EvidenceLocator {
  const EvidenceLocator.paragraph(String id) : paragraphId = id, page = null, start = null, end = null;
  const EvidenceLocator.page(int value) : page = value, paragraphId = null, start = null, end = null;
  const EvidenceLocator.timeRange(double from, double to) : start = from, end = to, page = null, paragraphId = null;
  final String? paragraphId;
  final int? page;
  final double? start;
  final double? end;
  Map<String, Object?> toJson() => {
    if (paragraphId != null) 'paragraphId': paragraphId,
    if (page != null) 'page': page,
    if (start != null) 'timeRange': [start, end],
  };
  factory EvidenceLocator.fromJson(Map<String, Object?> j) {
    if (j['paragraphId'] case final String id) return EvidenceLocator.paragraph(id);
    if (j['page'] case final int page) return EvidenceLocator.page(page);
    if (j['timeRange'] case final List range when range.length == 2) {
      return EvidenceLocator.timeRange((range[0] as num).toDouble(), (range[1] as num).toDouble());
    }
    throw const FormatException('Invalid evidence locator');
  }
}

enum EvidenceAcquisition { auto, userPaste }

@immutable
class Evidence {
  const Evidence({
    required this.id,
    required this.sourceId,
    required this.sourceVersion,
    required this.quote,
    required this.locator,
    required this.acquisition,
    required this.capturedAt,
  });
  final String id;
  final String sourceId;
  final int sourceVersion;
  final String quote;
  final EvidenceLocator locator;
  final EvidenceAcquisition acquisition;
  final DateTime capturedAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'sourceVersion': sourceVersion,
    'quote': quote,
    'locator': locator.toJson(),
    'acquisition': acquisition.name,
    'capturedAt': capturedAt.toIso8601String(),
  };
  factory Evidence.fromJson(Map<String, Object?> j) => Evidence(
    id: j['id'] as String,
    sourceId: j['sourceId'] as String,
    sourceVersion: j['sourceVersion'] as int,
    quote: j['quote'] as String,
    locator: EvidenceLocator.fromJson((j['locator'] as Map).cast()),
    acquisition: EvidenceAcquisition.values.byName(j['acquisition'] as String),
    capturedAt: DateTime.parse(j['capturedAt'] as String),
  );
}

@immutable
class SourceVersion {
  const SourceVersion({required this.version, required this.snapshotFile, required this.hash});
  final int version;
  final String snapshotFile;
  final String hash;
  Map<String, Object?> toJson() => {'version': version, 'snapshotFile': snapshotFile, 'hash': hash};
  factory SourceVersion.fromJson(Map<String, Object?> j) =>
      SourceVersion(version: j['version'] as int, snapshotFile: j['snapshotFile'] as String, hash: j['hash'] as String);
}

@immutable
class ResearchSource {
  ResearchSource({
    required this.id,
    required this.url,
    required this.canonicalUrl,
    required this.kind,
    required this.title,
    List<String> authors = const [],
    this.publishedAt,
    this.doi,
    this.videoId,
    this.readState = 'unread',
    required this.fetchedAt,
    List<SourceVersion> versions = const [],
  }) : authors = List.unmodifiable(authors),
       versions = List.unmodifiable(versions);
  final String id;
  final String url;
  final String canonicalUrl;
  final String kind;
  final String title;
  final List<String> authors;
  final DateTime? publishedAt;
  final String? doi;
  final String? videoId;
  final String readState;
  final DateTime fetchedAt;
  final List<SourceVersion> versions;
  Map<String, Object?> toJson() => {
    'id': id,
    'url': url,
    'canonicalUrl': canonicalUrl,
    'kind': kind,
    'title': title,
    'authors': authors,
    if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
    if (doi != null) 'doi': doi,
    if (videoId != null) 'videoId': videoId,
    'readState': readState,
    'fetchedAt': fetchedAt.toIso8601String(),
    'versions': [for (final v in versions) v.toJson()],
  };
  factory ResearchSource.fromJson(Map<String, Object?> j) => ResearchSource(
    id: j['id'] as String,
    url: j['url'] as String,
    canonicalUrl: j['canonicalUrl'] as String,
    kind: j['kind'] as String,
    title: j['title'] as String,
    authors: (j['authors'] as List).cast<String>(),
    publishedAt: j['publishedAt'] == null ? null : DateTime.parse(j['publishedAt'] as String),
    doi: j['doi'] as String?,
    videoId: j['videoId'] as String?,
    readState: j['readState'] as String,
    fetchedAt: DateTime.parse(j['fetchedAt'] as String),
    versions: [for (final v in j['versions'] as List) SourceVersion.fromJson((v as Map).cast())],
  );
}

@immutable
class ResearchNote {
  ResearchNote({
    required this.id,
    required this.title,
    required this.body,
    this.textFormat = TextFormat.plain,
    this.question = '',
    this.sessionId,
    List<EvidenceRef> citations = const [],
    this.origin = NoteOrigin.user,
    this.edited = false,
    required this.createdAt,
    required this.updatedAt,
    this.sourceLocationMissing = false,
  }) : citations = List.unmodifiable(citations);
  final String id;
  final String title;
  final String body;
  final TextFormat textFormat;
  final String question;
  final String? sessionId;
  final List<EvidenceRef> citations;
  final NoteOrigin origin;
  final bool edited;

  /// A copied PDF anchor was unavailable in the receiving study set.
  final bool sourceLocationMissing;
  final DateTime createdAt;
  final DateTime updatedAt;
  ResearchNote copyWith({String? title, String? body, TextFormat? textFormat, DateTime? updatedAt}) => ResearchNote(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    textFormat: textFormat ?? this.textFormat,
    question: question,
    sessionId: sessionId,
    citations: citations,
    origin: origin,
    edited: true,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sourceLocationMissing: sourceLocationMissing,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'textFormat': textFormat.name,
    'question': question,
    if (sessionId != null) 'sessionId': sessionId,
    'citations': [for (final c in citations) c.toJson()],
    'origin': origin.name,
    'edited': edited,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (sourceLocationMissing) 'sourceLocationMissing': true,
  };
  factory ResearchNote.fromJson(Map<String, Object?> j) => ResearchNote(
    id: j['id'] as String,
    title: j['title'] as String,
    body: j['body'] as String,
    textFormat: TextFormat.values.byName(j['textFormat'] as String? ?? 'plain'),
    question: j['question'] as String? ?? '',
    sessionId: j['sessionId'] as String?,
    citations: [for (final c in j['citations'] as List? ?? []) EvidenceRef.fromJson((c as Map).cast())],
    origin: NoteOrigin.values.byName(j['origin'] as String),
    edited: j['edited'] as bool? ?? false,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    sourceLocationMissing: j['sourceLocationMissing'] as bool? ?? false,
  );
}

@immutable
class InkPoint {
  const InkPoint(this.x, this.y);
  final double x;
  final double y;
  Map<String, Object?> toJson() => {'x': x, 'y': y};
  factory InkPoint.fromJson(Map<String, Object?> j) => InkPoint((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
}

@immutable
class InkStroke {
  InkStroke({
    required this.id,
    required this.documentId,
    required this.page,
    required this.tool,
    required this.colorIndex,
    required this.width,
    List<InkPoint> points = const [],
    this.ellipse,
  }) : points = List.unmodifiable(points);
  static const maxPoints = 10000;
  final String id;
  final String documentId;
  final int page;
  final InkTool tool;
  final int colorIndex;
  final double width;
  final List<InkPoint> points;
  final PageRect? ellipse;
  Map<String, Object?> toJson() => {
    'id': id,
    'documentId': documentId,
    'page': page,
    'tool': tool.name,
    'colorIndex': colorIndex,
    'width': width,
    'points': [for (final p in points) p.toJson()],
    if (ellipse != null) 'ellipse': ellipse!.toJson(),
  };
  factory InkStroke.fromJson(Map<String, Object?> j) => InkStroke(
    id: j['id'] as String,
    documentId: j['documentId'] as String,
    page: j['page'] as int,
    tool: InkTool.values.byName(j['tool'] as String),
    colorIndex: j['colorIndex'] as int,
    width: (j['width'] as num).toDouble(),
    points: [for (final p in j['points'] as List? ?? []) InkPoint.fromJson((p as Map).cast())],
    ellipse: j['ellipse'] == null ? null : PageRect.fromJson((j['ellipse'] as Map).cast()),
  );
}
