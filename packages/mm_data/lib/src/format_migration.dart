import 'package:mm_core/mm_core.dart';

/// The format [migrateStudySet] produces and the store writes.
const currentStudySetFormat = 4;

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

Map<String, Object?> _annotation(Map<String, Object?> json) {
  final result = {...json};
  final page = result.remove('page');
  final rects = result.remove('rects');
  result['pages'] = [
    {'page': page, 'rects': rects},
  ];
  return result;
}
