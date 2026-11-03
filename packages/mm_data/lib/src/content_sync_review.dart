import 'package:mm_core/mm_core.dart';

/// Review the original transaction's complete delta, including non-conflicting
/// companion edits. The choice applies that transaction atomically.
List<ContentSyncDifference> contentSyncReview(
  Map<String, Object?> before,
  Map<String, Object?> candidate,
  Map<String, Object?> current,
) {
  final result = <ContentSyncDifference>[];
  Object? at(Object? root, List<String> path) {
    for (final key in path) {
      if (root is! Map || !root.containsKey(key)) return contentMissing;
      root = root[key];
    }
    return root;
  }

  String name(Object? value) {
    if (value is! Map) return '';
    for (final key in ['title', 'name', 'label', 'text', 'quote', 'body']) {
      final text = value[key];
      if (text is String && text.trim().isNotEmpty) return text;
    }
    return '';
  }

  String reference(String id, Map<String, Object?> payload) {
    String find(Object? tree) {
      if (tree is! Map) return '';
      final entity = tree[id];
      if (entity is Map) {
        final label = name(entity);
        if (label.isNotEmpty) return label;
        final cards = (payload['content'] as Map?)?['cards'];
        if (cards is Map && entity['cardId'] is String) return name(cards[entity['cardId']]);
      }
      for (final child in tree.values.whereType<Map>()) {
        final label = find(child);
        if (label.isNotEmpty) return label;
      }
      return '';
    }

    return find(payload['content']);
  }

  String? describe(Object? value, List<String> path, Map<String, Object?> payload) {
    if (value == contentMissing || value == null) return null;
    if (value is Map) {
      final labels = <String>[];
      for (final key in ['title', 'name', 'label', 'text', 'quote', 'body']) {
        if (value[key] case final String text when text.isNotEmpty) labels.add(text);
      }
      for (final key in ['cardId', 'parentId', 'fromId', 'toId', 'documentId']) {
        if (value[key] case final String id) {
          final text = reference(id, payload);
          if (text.isNotEmpty) labels.add(text);
        }
      }
      for (final key in ['sections', 'blocks', 'items']) {
        if (value[key] case final Map children) {
          // Ordered collections carry an items map. Follow it without exposing
          // storage IDs; include nested note text when an entire note is added.
          final items = children['items'] is Map ? children['items'] as Map : children;
          for (final child in items.values.whereType<Map>()) {
            final text = describe(child, [...path, key], payload);
            if (text != null && text.isNotEmpty) labels.add(text);
          }
        }
      }
      return labels.toSet().join('\n');
    }
    if (value is List) return value.map((v) => describe(v, path, payload) ?? '').join('\n');
    if (value is String) {
      final key = path.last.toLowerCase();
      if (path.last.endsWith('Id') || path.last.endsWith('Ids') || key == 'id' || key == 'order') {
        return reference(value, payload);
      }
      if (key.contains('revision') ||
          key.endsWith('file') ||
          key.endsWith('filename') ||
          key.endsWith('manifest') ||
          key.endsWith('hash') ||
          key == 'fingerprint') {
        return '';
      }
      return value;
    }
    if (value is bool) return value ? '✓' : '—';
    return value is num ? '$value' : '';
  }

  void diff(Object? a, Object? b, List<String> path) {
    if (contentValueEquals(a, b)) return;
    if (path.isNotEmpty && {'updatedAt', 'createdAt'}.contains(path.last)) return;
    if (a is Map && b is Map || path.length == 2 && path.first == 'content' && (a is Map || b is Map)) {
      final left = a is Map ? a : const {}, right = b is Map ? b : const {};
      for (final key in {...left.keys.cast<String>(), ...right.keys.cast<String>()}) {
        diff(left.containsKey(key) ? left[key] : contentMissing, right.containsKey(key) ? right[key] : contentMissing, [
          ...path,
          key,
        ]);
      }
      return;
    }
    final collection = path.first == 'content' && path.length > 1 ? path[1] : '';
    final entity = switch (collection) {
      '' => ContentSyncEntity.studySet,
      'cards' || 'nodes' => ContentSyncEntity.card,
      'documents' => ContentSyncEntity.document,
      'studyNotes' => ContentSyncEntity.studyNote,
      'researchNotes' => ContentSyncEntity.researchNote,
      'annotations' => ContentSyncEntity.annotation,
      'marginNotes' => ContentSyncEntity.marginNote,
      'maps' => ContentSyncEntity.map,
      'relations' => ContentSyncEntity.relation,
      'summaries' => ContentSyncEntity.summary,
      'bookmarks' => ContentSyncEntity.bookmark,
      _ => ContentSyncEntity.other,
    };
    final key = path.last;
    final field = switch (key) {
      'title' || 'name' => ContentSyncField.title,
      'body' || 'text' || 'quote' || 'items' => ContentSyncField.text,
      'tags' => ContentSyncField.tags,
      'order' || 'sortIndex' => ContentSyncField.order,
      'organizedAt' => ContentSyncField.collectionBaseline,
      'parentId' || 'fromId' || 'toId' || 'folderId' => ContentSyncField.structure,
      'colorIndex' || 'width' || 'textFormat' => ContentSyncField.appearance,
      'documentId' || 'revision' || 'sourceId' => ContentSyncField.source,
      _ => a is Map || b is Map ? ContentSyncField.structure : ContentSyncField.other,
    };
    var title = '';
    if (path.length > 2 && path.first == 'content') {
      for (final payload in [current, candidate, before]) {
        title = name(at(payload, path.take(3).toList()));
        if (collection == 'nodes') {
          final node = at(payload, path.take(3).toList());
          if (node is Map && node['cardId'] is String) title = reference(node['cardId'] as String, payload);
        }
        if (title.isNotEmpty) break;
      }
    } else {
      title = current['title'] as String? ?? '';
    }
    result.add(
      ContentSyncDifference(
        entity: entity,
        title: title,
        field: field,
        current: describe(at(current, path), path, current),
        candidate: describe(b, path, candidate),
      ),
    );
  }

  diff(before, candidate, const []);
  return result;
}
