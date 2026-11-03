import 'package:mm_core/mm_core.dart';

import 'commit.dart';
import 'projection.dart';

class SyncConflict {
  SyncConflict(List<String> path, Object? base, Object? left, Object? right)
    : path = List.unmodifiable(path),
      base = _freeze(base),
      left = _freeze(left),
      right = _freeze(right);
  final List<String> path;
  final Object? base, left, right;

  /// Stable under receiving the two branches in either order.
  String get id {
    final variants = [syncDigest(_wire(left)), syncDigest(_wire(right))]..sort();
    return syncDigest({'path': path, 'base': _wire(base), 'variants': variants});
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'path': path,
    'base': _wire(base),
    'left': _wire(left),
    'right': _wire(right),
  };

  factory SyncConflict.fromJson(Map<String, Object?> json) {
    const fields = {'version', 'id', 'path', 'base', 'left', 'right'};
    if (json['version'] != 1 || json.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('Unsupported conflict');
    }
    Object? read(Object? value) {
      if (value is! Map || value.length != 1) throw const FormatException('Invalid conflict value');
      if (value['missing'] == true) return contentMissing;
      if (value.containsKey('value')) return value['value'];
      throw const FormatException('Invalid conflict value');
    }

    try {
      final result = SyncConflict(
        (json['path'] as List).cast<String>(),
        read(json['base']),
        read(json['left']),
        read(json['right']),
      );
      if (result.id != json['id']) throw const FormatException('Conflict digest mismatch');
      return result;
    } on TypeError {
      throw const FormatException('Malformed conflict');
    }
  }
}

Object? _wire(Object? v) => v == contentMissing ? {'missing': true} : {'value': v};
Object? _freeze(Object? value) {
  if (value is Map) return Map<String, Object?>.unmodifiable(value.map((k, v) => MapEntry(k as String, _freeze(v))));
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

class ContentMergeResult {
  ContentMergeResult(this.content, Iterable<SyncConflict> conflicts) : conflicts = List.unmodifiable(conflicts);

  /// Null means structural validation failed. Never publish that transaction.
  final StudySetContent? content;
  final List<SyncConflict> conflicts;
  bool get clean => content != null && conflicts.isEmpty;
}

/// Pure three-way content merge. Conflicting values remain at the common base
/// in the preview; callers must persist the variants before publishing a preview.
ContentMergeResult mergeContent(StudySetContent base, StudySetContent left, StudySetContent right) {
  final conflicts = <SyncConflict>[];
  final merged = _merge(sharedContent(base), sharedContent(left), sharedContent(right), const [], conflicts) as Map;
  try {
    final content = contentFromDocument(merged.cast<String, Object?>());
    final errors = contentIntegrityErrors(content);
    if (errors.isNotEmpty) {
      for (final error in errors) {
        conflicts.add(SyncConflict(['integrity', error], null, sharedContent(left), sharedContent(right)));
      }
      return ContentMergeResult(null, conflicts);
    }
    return ContentMergeResult(content, conflicts);
  } on FormatException {
    conflicts.add(SyncConflict(['integrity', 'decode'], null, sharedContent(left), sharedContent(right)));
    return ContentMergeResult(null, conflicts);
  } on ArgumentError {
    conflicts.add(SyncConflict(['integrity', 'decode'], null, sharedContent(left), sharedContent(right)));
    return ContentMergeResult(null, conflicts);
  }
}

Object? _merge(Object? base, Object? left, Object? right, List<String> path, List<SyncConflict> conflicts) {
  if (contentValueEquals(left, right)) return left;
  if (contentValueEquals(left, base)) return right;
  if (contentValueEquals(right, base)) return left;
  // Metadata timestamps don't own edits. Keep the latest provenance without
  // letting it override text or imply causal ordering.
  if (path.isNotEmpty && {'updatedAt', 'organizedAt'}.contains(path.last) && left is String && right is String) {
    final a = DateTime.tryParse(left), b = DateTime.tryParse(right);
    if (a != null && b != null) return a.isAfter(b) ? left : right;
  }
  if (base is Map && left is Map && right is Map) {
    final result = <String, Object?>{};
    final keys = {...base.keys.cast<String>(), ...left.keys.cast<String>(), ...right.keys.cast<String>()}.toList()
      ..sort();
    for (final key in keys) {
      final value = _merge(
        base.containsKey(key) ? base[key] : contentMissing,
        left.containsKey(key) ? left[key] : contentMissing,
        right.containsKey(key) ? right[key] : contentMissing,
        [...path, key],
        conflicts,
      );
      if (value != contentMissing) result[key] = value;
    }
    return result;
  }
  if (path.isNotEmpty &&
      path.last == 'order' &&
      base is List &&
      left is List &&
      right is List &&
      [...base, ...left, ...right].every((v) => v is String)) {
    final order = _mergeOrder(base.cast<String>(), left.cast<String>(), right.cast<String>());
    if (order != null) return order;
  }
  conflicts.add(SyncConflict(path, base, left, right));
  return base;
}

/// Merge independent insertions while respecting each branch's explicit
/// adjacency constraints. Conflicting reorderings form a cycle and are kept
/// as conflicts. Removal vs edited item is still checked by the item merge.
List<String>? _mergeOrder(List<String> base, List<String> left, List<String> right) {
  final ids = {...left, ...right}
    ..removeWhere((id) => base.contains(id) && (!left.contains(id) || !right.contains(id)));
  final edges = {for (final id in ids) id: <String>{}};
  final incoming = {for (final id in ids) id: 0};
  for (final side in [left, right]) {
    final ordered = side.where(ids.contains).toList();
    for (var i = 1; i < ordered.length; i++) {
      if (edges[ordered[i - 1]]!.add(ordered[i])) incoming[ordered[i]] = incoming[ordered[i]]! + 1;
    }
  }
  final result = <String>[];
  final ready = ids.where((id) => incoming[id] == 0).toList()..sort();
  while (ready.isNotEmpty) {
    final id = ready.removeAt(0);
    result.add(id);
    for (final next in edges[id]!) {
      incoming[next] = incoming[next]! - 1;
      if (incoming[next] == 0) {
        ready.add(next);
        ready.sort();
      }
    }
  }
  return result.length == ids.length ? result : null;
}
