import 'package:meta/meta.dart';

import 'models.dart';

const _keep = Object();
double _number(Object? value) => (value as num).toDouble();
void _check(bool valid, String message) {
  if (!valid) throw ArgumentError(message);
}

enum CropMode { auto, manual }

enum CropScope { all, oddEven, page }

/// Distances from the original page edges, in PDF points.
@immutable
class CropInsets {
  CropInsets({this.left = 0, this.top = 0, this.right = 0, this.bottom = 0}) {
    _check([left, top, right, bottom].every((v) => v.isFinite && v >= 0), 'Invalid crop insets');
  }
  final double left, top, right, bottom;
  void validateSize(double width, double height) =>
      _check(width.isFinite && height.isFinite && width > left + right && height > top + bottom, 'Crop removes page');
  CropInsets copyWith({double? left, double? top, double? right, double? bottom}) => CropInsets(
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
  );
  Map<String, Object?> toJson() => {'left': left, 'top': top, 'right': right, 'bottom': bottom};
  factory CropInsets.fromJson(Map<String, Object?> j) => CropInsets(
    left: _number(j['left']),
    top: _number(j['top']),
    right: _number(j['right']),
    bottom: _number(j['bottom']),
  );
}

@immutable
class DocumentCrop {
  DocumentCrop({
    this.enabled = true,
    this.mode = CropMode.auto,
    this.scope = CropScope.all,
    required this.all,
    this.odd,
    Map<int, CropInsets> pages = const {},
  }) : pages = Map.unmodifiable(pages) {
    _check(pages.keys.every((page) => page > 0), 'Page numbers start at one');
  }
  final bool enabled;
  final CropMode mode;
  final CropScope scope;
  final CropInsets all;
  final CropInsets? odd;
  final Map<int, CropInsets> pages;
  CropInsets forPage(int page) {
    _check(page > 0, 'Page numbers start at one');
    if (!enabled) return CropInsets();
    return switch (scope) {
      CropScope.all => all,
      CropScope.oddEven => page.isOdd ? odd ?? all : all,
      CropScope.page => pages[page] ?? CropInsets(),
    };
  }

  DocumentCrop copyWith({
    bool? enabled,
    CropMode? mode,
    CropScope? scope,
    CropInsets? all,
    Object? odd = _keep,
    Map<int, CropInsets>? pages,
  }) => DocumentCrop(
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    scope: scope ?? this.scope,
    all: all ?? this.all,
    odd: identical(odd, _keep) ? this.odd : odd as CropInsets?,
    pages: pages ?? this.pages,
  );
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'scope': scope.name,
    'all': all.toJson(),
    if (odd != null) 'odd': odd!.toJson(),
    'pages': {for (final e in pages.entries) '${e.key}': e.value.toJson()},
  };
  factory DocumentCrop.fromJson(Map<String, Object?> j) => DocumentCrop(
    enabled: j['enabled'] as bool,
    mode: CropMode.values.byName(j['mode'] as String),
    scope: CropScope.values.byName(j['scope'] as String),
    all: CropInsets.fromJson((j['all'] as Map).cast()),
    odd: j['odd'] == null ? null : CropInsets.fromJson((j['odd'] as Map).cast()),
    pages: {
      for (final e in (j['pages'] as Map? ?? {}).entries)
        int.parse(e.key as String): CropInsets.fromJson((e.value as Map).cast()),
    },
  );
}

/// A captured quote, independent of any highlight's lifetime.
@immutable
class AnnotationAnchor {
  AnnotationAnchor({required List<AnnotationPage> pages, required this.quote})
    : pages = List.unmodifiable([
        for (final p in pages) AnnotationPage(page: p.page, rects: List.unmodifiable(p.rects)),
      ]) {
    _check(
      pages.isNotEmpty &&
          pages.every(
            (p) =>
                p.page > 0 &&
                p.rects.isNotEmpty &&
                p.rects.every(
                  (r) =>
                      [r.left, r.top, r.right, r.bottom].every((v) => v.isFinite) &&
                      r.left >= 0 &&
                      r.bottom >= 0 &&
                      r.right > r.left &&
                      r.top > r.bottom,
                ),
          ),
      'Invalid annotation anchor',
    );
  }
  final List<AnnotationPage> pages;
  final String quote;
  AnnotationAnchor copyWith({List<AnnotationPage>? pages, String? quote}) =>
      AnnotationAnchor(pages: pages ?? this.pages, quote: quote ?? this.quote);
  Map<String, Object?> toJson() => {
    'pages': [for (final p in pages) p.toJson()],
    'quote': quote,
  };
  factory AnnotationAnchor.fromJson(Map<String, Object?> j) => AnnotationAnchor(
    pages: [for (final p in j['pages'] as List) AnnotationPage.fromJson((p as Map).cast())],
    quote: j['quote'] as String,
  );
}

@immutable
class MarginNote {
  MarginNote({
    required this.id,
    required this.documentId,
    required this.page,
    this.anchor,
    this.lineY,
    required this.text,
    required this.colorIndex,
    this.nodeId,
    this.mapId,
    required this.createdAt,
    required this.updatedAt,
  }) {
    _check(
      id.isNotEmpty && documentId.isNotEmpty && page > 0 && colorIndex >= 0 && colorIndex < 6,
      'Invalid margin note',
    );
    _check((anchor == null) != (lineY == null), 'Exactly one anchor or lineY is required');
    _check(lineY == null || (lineY!.isFinite && lineY! >= 0), 'Invalid lineY');
    _check(anchor == null || anchor!.pages.first.page == page, 'Anchor page mismatch');
    _check(mapId == null || nodeId != null, 'mapId requires nodeId');
  }
  final String id, documentId, text;
  final int page, colorIndex;
  final AnnotationAnchor? anchor;
  final double? lineY;

  /// The associated cardId, scoped to [mapId] (main when absent).
  final String? nodeId, mapId;
  final DateTime createdAt, updatedAt;
  MarginNote copyWith({
    int? page,
    Object? anchor = _keep,
    Object? lineY = _keep,
    String? text,
    int? colorIndex,
    Object? nodeId = _keep,
    Object? mapId = _keep,
    DateTime? updatedAt,
  }) => MarginNote(
    id: id,
    documentId: documentId,
    page: page ?? this.page,
    anchor: identical(anchor, _keep) ? this.anchor : anchor as AnnotationAnchor?,
    lineY: identical(lineY, _keep) ? this.lineY : lineY as double?,
    text: text ?? this.text,
    colorIndex: colorIndex ?? this.colorIndex,
    nodeId: identical(nodeId, _keep) ? this.nodeId : nodeId as String?,
    mapId: identical(mapId, _keep) ? this.mapId : mapId as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'documentId': documentId,
    'page': page,
    if (anchor != null) 'anchor': anchor!.toJson(),
    if (lineY != null) 'lineY': lineY,
    'text': text,
    'colorIndex': colorIndex,
    if (nodeId != null) 'nodeId': nodeId,
    if (mapId != null) 'mapId': mapId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory MarginNote.fromJson(Map<String, Object?> j) => MarginNote(
    id: j['id'] as String,
    documentId: j['documentId'] as String,
    page: j['page'] as int,
    anchor: j['anchor'] == null ? null : AnnotationAnchor.fromJson((j['anchor'] as Map).cast()),
    lineY: j['lineY'] == null ? null : _number(j['lineY']),
    text: j['text'] as String,
    colorIndex: j['colorIndex'] as int,
    nodeId: j['nodeId'] as String?,
    mapId: j['mapId'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}

@immutable
sealed class CompareTarget {
  const CompareTarget();
  Map<String, Object?> toJson();
  factory CompareTarget.fromJson(Map<String, Object?> j) => switch (j['kind']) {
    'pdf' => PdfCompareTarget(j['documentId'] as String),
    'ai' => AiCompareTarget(j['targetLang'] as String),
    _ => throw FormatException('Unknown comparison target'),
  };
}

final class PdfCompareTarget extends CompareTarget {
  PdfCompareTarget(this.documentId) {
    _check(documentId.isNotEmpty, 'Empty documentId');
  }
  final String documentId;
  PdfCompareTarget copyWith({String? documentId}) => PdfCompareTarget(documentId ?? this.documentId);
  @override
  Map<String, Object?> toJson() => {'kind': 'pdf', 'documentId': documentId};
}

final class AiCompareTarget extends CompareTarget {
  AiCompareTarget(this.targetLang) {
    _check(targetLang.trim().isNotEmpty, 'Empty target language');
  }
  final String targetLang;
  AiCompareTarget copyWith({String? targetLang}) => AiCompareTarget(targetLang ?? this.targetLang);
  @override
  Map<String, Object?> toJson() => {'kind': 'ai', 'targetLang': targetLang};
}

/// 1-based page and original PDF y (bottom-left origin), independent of crop.
@immutable
class PdfReadingPosition {
  PdfReadingPosition({required this.page, required this.y}) {
    _check(page > 0 && y.isFinite && y >= 0, 'Invalid reading position');
  }
  final int page;
  final double y;
  PdfReadingPosition copyWith({int? page, double? y}) => PdfReadingPosition(page: page ?? this.page, y: y ?? this.y);
  Map<String, Object?> toJson() => {'page': page, 'y': y};
  factory PdfReadingPosition.fromJson(Map<String, Object?> j) =>
      PdfReadingPosition(page: j['page'] as int, y: _number(j['y']));
}

@immutable
class AlignPoint {
  const AlignPoint({required this.left, required this.right});
  final PdfReadingPosition left, right;
  AlignPoint copyWith({PdfReadingPosition? left, PdfReadingPosition? right}) =>
      AlignPoint(left: left ?? this.left, right: right ?? this.right);
  Map<String, Object?> toJson() => {'left': left.toJson(), 'right': right.toJson()};
  factory AlignPoint.fromJson(Map<String, Object?> j) => AlignPoint(
    left: PdfReadingPosition.fromJson((j['left'] as Map).cast()),
    right: PdfReadingPosition.fromJson((j['right'] as Map).cast()),
  );
}

@immutable
class ComparePair {
  ComparePair({
    required this.id,
    required this.leftDocumentId,
    required this.right,
    List<AlignPoint> alignPoints = const [],
    this.sync = true,
  }) : alignPoints = List.unmodifiable(alignPoints) {
    _check(id.isNotEmpty && leftDocumentId.isNotEmpty, 'Invalid compare pair');
    _check(
      right is! PdfCompareTarget || (right as PdfCompareTarget).documentId != leftDocumentId,
      'Cannot compare a document to itself',
    );
    _check(right is! AiCompareTarget || alignPoints.isEmpty, 'AI uses paragraph alignment');
  }
  final String id, leftDocumentId;
  final CompareTarget right;
  final List<AlignPoint> alignPoints;
  final bool sync;
  ComparePair copyWith({String? leftDocumentId, CompareTarget? right, List<AlignPoint>? alignPoints, bool? sync}) =>
      ComparePair(
        id: id,
        leftDocumentId: leftDocumentId ?? this.leftDocumentId,
        right: right ?? this.right,
        alignPoints: alignPoints ?? this.alignPoints,
        sync: sync ?? this.sync,
      );
  Map<String, Object?> toJson() => {
    'id': id,
    'leftDocumentId': leftDocumentId,
    'right': right.toJson(),
    'alignPoints': [for (final p in alignPoints) p.toJson()],
    'sync': sync,
  };
  factory ComparePair.fromJson(Map<String, Object?> j) => ComparePair(
    id: j['id'] as String,
    leftDocumentId: j['leftDocumentId'] as String,
    right: CompareTarget.fromJson((j['right'] as Map).cast()),
    alignPoints: [for (final p in j['alignPoints'] as List? ?? []) AlignPoint.fromJson((p as Map).cast())],
    sync: j['sync'] as bool? ?? true,
  );
}

@immutable
class TranslationCache {
  TranslationCache({
    required this.documentId,
    required this.targetLang,
    Map<String, String> paragraphs = const {},
    required this.model,
    required this.createdAt,
  }) : paragraphs = Map.unmodifiable(paragraphs) {
    _check(documentId.isNotEmpty && targetLang.trim().isNotEmpty && model.isNotEmpty, 'Invalid translation cache');
    _check(
      paragraphs.entries.every((e) => e.key.isNotEmpty && e.value.trim().isNotEmpty),
      'Only complete non-empty translations can be cached',
    );
  }
  final String documentId, targetLang, model;
  final Map<String, String> paragraphs;
  final DateTime createdAt;
  TranslationCache copyWith({Map<String, String>? paragraphs, String? model}) => TranslationCache(
    documentId: documentId,
    targetLang: targetLang,
    paragraphs: paragraphs ?? this.paragraphs,
    model: model ?? this.model,
    createdAt: createdAt,
  );
  Map<String, Object?> toJson() => {
    'documentId': documentId,
    'targetLang': targetLang,
    'paragraphs': paragraphs,
    'model': model,
    'createdAt': createdAt.toIso8601String(),
  };
  factory TranslationCache.fromJson(Map<String, Object?> j) => TranslationCache(
    documentId: j['documentId'] as String,
    targetLang: j['targetLang'] as String,
    paragraphs: (j['paragraphs'] as Map).cast(),
    model: j['model'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}
