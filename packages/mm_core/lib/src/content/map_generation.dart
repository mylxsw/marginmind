import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';
import 'study_set_content.dart';

enum MapOrganization { chapter, topic, question }

class CardSource {
  CardSource({required this.documentId, required this.page}) {
    if (documentId.isEmpty || page < 1) throw ArgumentError('Invalid card source');
  }
  final String documentId;
  final int page;
  Map<String, Object?> toJson() => {'documentId': documentId, 'page': page};
  factory CardSource.fromJson(Map<String, Object?> j) =>
      CardSource(documentId: j['documentId'] as String, page: j['page'] as int);
}

class MapSource {
  MapSource({
    required this.documentId,
    List<String> chapters = const [],
    required this.fingerprint,
    required this.readThrough,
  }) : chapters = List.unmodifiable(chapters) {
    if (documentId.isEmpty || fingerprint.isEmpty || readThrough < 1) throw ArgumentError('Invalid map source');
  }
  final String documentId, fingerprint;
  final List<String> chapters;
  final int readThrough;
  Map<String, Object?> toJson() => {
    'documentId': documentId,
    'chapters': chapters,
    'fingerprint': fingerprint,
    'readThrough': readThrough,
  };
  factory MapSource.fromJson(Map<String, Object?> j) => MapSource(
    documentId: j['documentId'] as String,
    chapters: (j['chapters'] as List).cast<String>(),
    fingerprint: j['fingerprint'] as String,
    readThrough: j['readThrough'] as int,
  );
}

class MapGeneration {
  MapGeneration({
    required List<MapSource> sources,
    required this.organization,
    required this.depth,
    this.instructions,
    required this.generatedAt,
    Map<String, String> generated = const {},
  }) : sources = List.unmodifiable(sources),
       generated = Map.unmodifiable(generated) {
    if (sources.isEmpty ||
        sources.map((s) => s.documentId).toSet().length != sources.length ||
        depth < 2 ||
        depth > 4 ||
        (instructions?.runes.length ?? 0) > 500) {
      throw ArgumentError('Invalid map generation');
    }
  }
  final List<MapSource> sources;
  final MapOrganization organization;
  final int depth;
  final String? instructions;
  final DateTime generatedAt;

  /// Versioned hash of title AND placement; absent entries are user-owned.
  final Map<String, String> generated;
  MapGeneration withGenerated(Map<String, String> value) => MapGeneration(
    sources: sources,
    organization: organization,
    depth: depth,
    instructions: instructions,
    generatedAt: generatedAt,
    generated: value,
  );
  Map<String, Object?> toJson() => {
    'sources': [for (final s in sources) s.toJson()],
    'organization': organization.name,
    'depth': depth,
    if (instructions != null) 'instructions': instructions,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'generated': generated,
  };
  factory MapGeneration.fromJson(Map<String, Object?> j) => MapGeneration(
    sources: [for (final s in j['sources'] as List) MapSource.fromJson((s as Map).cast())],
    organization: MapOrganization.values.byName(j['organization'] as String),
    depth: j['depth'] as int,
    instructions: j['instructions'] as String?,
    generatedAt: DateTime.parse(j['generatedAt'] as String),
    generated: (j['generated'] as Map? ?? {}).cast<String, String>(),
  );
}

/// Canonical JSON (object keys sorted; array order meaningful), SHA-256 UTF-8.
String mapContentHash(Object? value) {
  Object? canonical(Object? v) {
    if (v is Map<String, Object?>) {
      final keys = v.keys.toList()..sort();
      return {for (final k in keys) k: canonical(v[k])};
    }
    if (v is List) return v.map(canonical).toList();
    return v;
  }

  return sha256.convert(utf8.encode(jsonEncode(canonical(value)))).toString();
}

String generatedNodeHash(Card card, MapNode node) => 'v1:${mapContentHash([card.title, node.parentId, node.order])}';

bool isMapNodeProtected(StudySetContent content, String mapId, String cardId) {
  final card = content.card(cardId), node = content.node(cardId, mapId: mapId);
  return card == null ||
      node == null ||
      card.kind != CardKind.topic ||
      content.map(mapId)?.generation?.generated[cardId] != generatedNodeHash(card, node);
}

String mapSourceFingerprint({
  required int pageCount,
  required String textHash,
  required Map<String, Object?> annotations,
  Map<String, Object?> notes = const {},
}) =>
    mapContentHash({'v': 1, 'pageCount': pageCount, 'textHash': textHash, 'annotations': annotations, 'notes': notes});

bool mapSourcesChanged(MapGeneration generation, List<MapSource> current) {
  if (generation.sources.length != current.length) return true;
  final byId = {for (final s in current) s.documentId: s};
  return generation.sources.any((old) {
    final next = byId[old.documentId];
    return next == null ||
        next.fingerprint != old.fingerprint ||
        next.readThrough > old.readThrough ||
        mapContentHash(next.chapters.toList()..sort()) != mapContentHash(old.chapters.toList()..sort());
  });
}

String mapDigestCacheKey({
  required MapSource source,
  required String chapterId,
  required String chapterFingerprint,
  required String model,
  required MapOrganization organization,
  String? instructions,
  int schemaVersion = 1,
}) => mapContentHash({
  'schema': schemaVersion,
  'documentId': source.documentId,
  'chapterFingerprint': chapterFingerprint,
  'chapter': chapterId,
  'model': model,
  'organization': organization.name,
  'instructions': instructions,
});
