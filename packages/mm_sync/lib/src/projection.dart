import 'package:mm_core/mm_core.dart';

/// Shared learning content, separated from device state and review history.
/// Local format 11 remains a materialized view; it is not the wire protocol.
Map<String, Object?> sharedContent(StudySetContent content) {
  final value = contentDocument(content);
  for (final field in ['reviews', 'reviewLogs', 'memoryStates', 'assistantReceipts', 'comparePairs']) {
    value.remove(field);
  }
  for (final entry in (value['documents'] as Map).values.cast<Map>()) {
    for (final field in ['lastPage', 'lastReadAt', 'readingPosition', 'cropSuggestionDismissed']) {
      entry.remove(field);
    }
  }
  for (final entry in (value['nodes'] as Map).values.cast<Map>()) {
    entry.remove('collapsed');
  }
  return value;
}

/// Preserve this device's presentation and separately managed learning state.
StudySetContent materializeShared(Map<String, Object?> shared, StudySetContent local) {
  final combined = contentDocument(local)..addAll(shared);
  final next = contentFromDocument(combined);
  return StudySetEditor.restore(next, local).copyWith(
    nodes: [
      for (final node in next.nodes)
        node.copyWith(collapsed: local.node(node.cardId, mapId: node.mapId)?.collapsed ?? false),
    ],
  );
}
