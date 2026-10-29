import 'package:mm_core/mm_core.dart';

/// The format [migrateStudySet] produces and the store writes.
const currentStudySetFormat = 8;

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
  return result;
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
