import 'package:mm_core/mm_core.dart';

/// The format [migrateStudySet] produces and the store writes.
const currentStudySetFormat = 11;

/// Upgrades a package step by step to [currentStudySetFormat]. Keeps
/// metadata and unknown fields intact. Missing/future versions are never
/// interpreted as writable current data.
Map<String, Object?> migrateStudySet(Map<String, Object?> json) {
  final format = json['format'];
  if (format is! int || format < 1 || format > currentStudySetFormat) {
    throw FormatException('Unsupported study set format: $format');
  }
  var result = json;
  if (format < 2) result = _toFormat2(result);
  if (format < 3) result = _toFormat3(result);
  if (format < 4) result = _toFormat4(result);
  if (format < 5) result = _toFormat5(result);
  if (format < 6) result = _toFormat6(result);
  if (format < 7) result = _toFormat7(result);
  if (format < 8) result = _toFormat8(result);
  if (format < 9) result = _toFormat9(result);
  if (format < 10) result = _toFormat10(result);
  if (format < 11) result = {...result, 'format': 11};
  return result;
}

/// Format 10: summaries own topic cards. Preserve raw fields (including the old
/// label) while giving every legacy summary a stable, collision-free card id.
Map<String, Object?> _toFormat10(Map<String, Object?> json) {
  final content = ((json['content'] as Map?) ?? const {}).cast<String, Object?>();
  final summaries = (content['summaries'] as List?) ?? const [];
  if (summaries.isEmpty) return {...json, 'format': 10};
  final cards = [...(content['cards'] as List?) ?? const []];
  final usedIds = {
    for (final card in cards) (card as Map)['id'],
    for (final summary in summaries) (summary as Map)['cardId'],
  };
  final upgraded = <Map<String, Object?>>[];
  for (final raw in summaries) {
    final summary = (raw as Map).cast<String, Object?>();
    if (summary['cardId'] != null) {
      upgraded.add(summary);
      continue;
    }
    final base = 'summary-topic:${summary['id']}';
    var cardId = base;
    for (var suffix = 1; usedIds.contains(cardId); suffix++) {
      cardId = '$base:$suffix';
    }
    usedIds.add(cardId);
    cards.add({
      'id': cardId,
      'kind': 'topic',
      'title': summary['label'] ?? '',
      'createdAt': '1970-01-01T00:00:00.000Z',
    });
    upgraded.add({...summary, 'cardId': cardId});
  }
  return {
    ...json,
    'format': 10,
    'content': {...content, 'cards': cards, 'summaries': upgraded},
  };
}

/// Format 2: multi-page highlights and named maps.
Map<String, Object?> _toFormat2(Map<String, Object?> json) {
  final content = ((json['content'] as Map?) ?? const {}).cast<String, Object?>();
  return {
    ...json,
    'format': 2,
    'content': {
      ...content,
      'maps': [MindMap.main.toJson()],
      'annotations': [
        for (final raw in (content['annotations'] as List?) ?? const []) _annotation((raw as Map).cast()),
      ],
      'nodes': [
        for (final raw in (content['nodes'] as List?) ?? const [])
          {...(raw as Map).cast<String, Object?>(), 'mapId': MindMap.defaultId},
      ],
    },
  };
}

/// Format 3: card tags. Cards without `tags` read as untagged.
Map<String, Object?> _toFormat3(Map<String, Object?> json) => {...json, 'format': 3};

/// Format 4: relations and summaries. Older apps would drop them on save,
/// so the version keeps those apps from opening the package.
Map<String, Object?> _toFormat4(Map<String, Object?> json) {
  final content = ((json['content'] as Map?) ?? const {}).cast<String, Object?>();
  return {
    ...json,
    'format': 4,
    'content': {...content, 'relations': const [], 'summaries': const []},
  };
}

/// Format 5: reader bookmarks. Older apps would drop them on save.
Map<String, Object?> _toFormat5(Map<String, Object?> json) {
  final content = ((json['content'] as Map?) ?? const {}).cast<String, Object?>();
  return {
    ...json,
    'format': 5,
    'content': {...content, 'bookmarks': const []},
  };
}

Map<String, Object?> _annotation(Map<String, Object?> json) {
  final result = {...json};
  final page = result.remove('page');
  final rects = result.remove('rects');
  result['pages'] = [
    {'page': page, 'rects': rects},
  ];
  return result;
}

/// Format 6: rating history, optional FSRS state and card suspension.
/// Old schedules stay byte-for-byte equivalent; absent suspension reads false.
Map<String, Object?> _toFormat6(Map<String, Object?> json) {
  final content = ((json['content'] as Map?) ?? const {}).cast<String, Object?>();
  return {
    ...json,
    'format': 6,
    'content': {...content, 'reviewLogs': const [], 'memoryStates': const []},
  };
}

/// Format 7 adds only empty collections and defaults; schedules are untouched.
Map<String, Object?> _toFormat7(Map<String, Object?> json) {
  final content = ((json['content'] as Map?) ?? const {}).cast<String, Object?>();
  return {
    ...json,
    'format': 7,
    'content': {
      ...content,
      for (final key in ['researchNotes', 'noteAttachments', 'evidence', 'researchSources', 'inkStrokes'])
        key: const [],
    },
  };
}

/// Format 8: reading enhancements. Never rewrite existing document coordinates.
Map<String, Object?> _toFormat8(Map<String, Object?> json) {
  final content = ((json['content'] as Map?) ?? const {}).cast<String, Object?>();
  return {
    ...json,
    'format': 8,
    'content': {
      ...content,
      for (final key in ['marginNotes', 'comparePairs', 'translationCaches'])
        if (!content.containsKey(key)) key: const [],
    },
  };
}

/// Format 9: editable PDF outlines and persistent bookmark ordering.
Map<String, Object?> _toFormat9(Map<String, Object?> json) {
  final content = ((json['content'] as Map?) ?? const {}).cast<String, Object?>();
  return {
    ...json,
    'format': 9,
    'content': {...content, 'documentOutlines': content['documentOutlines'] ?? const []},
  };
}
