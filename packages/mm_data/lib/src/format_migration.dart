import 'package:mm_core/mm_core.dart';

/// The only package version upgrade. Keeps metadata and unknown fields intact.
/// Missing/future versions are never interpreted as writable current data.
Map<String, Object?> migrateStudySet(Map<String, Object?> json) {
  if (json['format'] == 2) return json;
  if (json['format'] != 1) throw FormatException('Unsupported study set format: ${json['format']}');
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

Map<String, Object?> _annotation(Map<String, Object?> json) {
  final result = {...json};
  final page = result.remove('page');
  final rects = result.remove('rects');
  result['pages'] = [
    {'page': page, 'rects': rects},
  ];
  return result;
}
