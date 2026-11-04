import 'dart:convert';

import 'editor.dart';
import 'research.dart';
import 'study_note.dart';
import 'study_set_content.dart';

/// A conditional change to editable content. Reading/review state is not owned
/// by the undo stack. Paths identify entities, never array offsets.
class ContentChange {
  ContentChange._(this.before, this.after, this._changes, [this._empty]);

  factory ContentChange.between(StudySetContent before, StudySetContent after) {
    final a = contentDocument(StudySetEditor.restore(before, after));
    final b = contentDocument(after);
    // Receipts follow the edit that produced them (including undo/redo).
    a['assistantReceipts'] = contentDocument(before)['assistantReceipts'];
    final changes = <ContentFieldChange>[];
    _diff(a, b, const [], changes);
    return ContentChange._(before, after, List.unmodifiable(changes), changes.isEmpty);
  }

  final StudySetContent before, after;
  final List<ContentFieldChange> _changes;
  bool? _empty;
  bool get isEmpty => _empty ??= _computeEmpty();

  bool _computeEmpty() {
    if (_changes.isEmpty) return true;
    final original = contentDocument(before), candidate = contentDocument(before);
    try {
      for (final change in _changes) {
        // A transaction that observed an intervening edit is not a no-op even
        // when its final text happens to equal its original text.
        if (!_matches(change.path, _at(candidate, change.path), change.before)) return false;
        _set(candidate, change.path, change.after);
      }
      return contentValueEquals(original, candidate);
    } on ContentChangeConflict {
      return false;
    }
  }

  List<ContentFieldChange> get fields => _changes;

  ContentChange get reversed => ContentChange._(
    after,
    before,
    List.unmodifiable(_changes.reversed.map((c) => ContentFieldChange(c.path, c.after, c.before))),
    _empty,
  );

  /// All changes are staged and checked before publishing the candidate. A failed
  /// inverse never partially undoes an excerpt or other compound operation.
  StudySetContent apply(StudySetContent current) {
    final json = contentDocument(current);
    for (final change in _changes) {
      if (!_matches(change.path, _at(json, change.path), change.before)) {
        throw ContentChangeConflict(change.path);
      }
      _set(json, change.path, change.after);
    }
    // Modification time is provenance: restore it only when the whole note
    // still matches the observed version, preserving later writers. organizedAt
    // is different: it is the material-collection baseline and participates in
    // the conditional delta just like authored content.
    final touchedNotes = <(String, String)>{
      for (final field in _changes)
        if (field.path.length > 2 && {'studyNotes', 'researchNotes'}.contains(field.path.first))
          (field.path[0], field.path[1]),
    };
    if (touchedNotes.isNotEmpty) {
      final beforeDocument = contentDocument(before),
          afterDocument = contentDocument(after),
          observed = contentDocument(current);
      for (final (collection, id) in touchedNotes) {
        final previous = (beforeDocument[collection] as Map)[id];
        final desired = (afterDocument[collection] as Map)[id];
        final actual = (json[collection] as Map)[id];
        if (previous is Map &&
            desired is Map &&
            actual is Map &&
            contentValueEquals((observed[collection] as Map)[id], previous)) {
          actual['updatedAt'] = desired['updatedAt'];
        }
      }
    }
    late StudySetContent next;
    try {
      next = contentFromDocument(json, order: after, additionalOrder: current);
    } on FormatException {
      throw ContentChangeConflict(['integrity', 'decode']);
    } on ArgumentError {
      throw ContentChangeConflict(['integrity', 'decode']);
    }
    // Existing invalid legacy relationships are tolerated, but an inverse must
    // not introduce a new dangling reference or a cycle involving remote work.
    final oldErrors = {...contentIntegrityErrors(current), ...contentIntegrityErrors(after)};
    final introduced = contentIntegrityErrors(next).where((e) => !oldErrors.contains(e));
    if (introduced.isNotEmpty) throw ContentChangeConflict(['integrity', introduced.first]);
    return StudySetEditor.restore(next, current).copyWith(assistantReceipts: next.assistantReceipts);
  }

  /// Compose successive local edits without capturing unrelated intervening
  /// repository updates as part of the transaction's undo history.
  ContentChange followedBy(ContentChange next) {
    final fields = [..._changes];
    for (final change in next._changes) {
      if (fields.isNotEmpty &&
          contentValueEquals(fields.last.path, change.path) &&
          contentValueEquals(fields.last.after, change.before)) {
        final previous = fields.removeLast();
        if (!contentValueEquals(previous.before, change.after)) {
          fields.add(ContentFieldChange(change.path, previous.before, change.after));
        }
      } else {
        fields.add(change);
      }
    }
    return ContentChange._(before, next.after, List.unmodifiable(fields));
  }
}

class ContentChangeConflict implements Exception {
  ContentChangeConflict(List<String> path) : path = List.unmodifiable(path);
  final List<String> path;
  @override
  String toString() => 'Content changed since edit: ${path.join('/')}';
}

/// Missing is distinct from a present JSON null (e.g. a root node's parent).
const contentMissing = _Missing();

class _Missing {
  const _Missing();
}

class ContentFieldChange {
  ContentFieldChange(List<String> path, Object? before, Object? after)
    : path = List.unmodifiable(path),
      before = _freeze(before),
      after = _freeze(after);
  final List<String> path;
  final Object? before, after;
}

Object? _freeze(Object? value) {
  if (value is Map) return Map<String, Object?>.unmodifiable(value.map((k, v) => MapEntry(k as String, _freeze(v))));
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

bool _matches(List<String> path, Object? actual, Object? expected) {
  if (path.length == 2 && path.first == 'documents' && actual is Map && expected is Map) {
    Map<String, Object?> editable(Map value) => Map<String, Object?>.from(value)
      ..remove('lastPage')
      ..remove('lastReadAt')
      ..remove('readingPosition')
      ..remove('cropSuggestionDismissed');
    return contentValueEquals(editable(actual), editable(expected));
  }
  if (path.length == 2 && {'studyNotes', 'researchNotes'}.contains(path.first) && actual is Map && expected is Map) {
    Map<String, Object?> editable(Map value) => Map<String, Object?>.from(value)..remove('updatedAt');
    return contentValueEquals(editable(actual), editable(expected));
  }
  return contentValueEquals(actual, expected);
}

String canonicalContentJson(Object? value) => jsonEncode(_canonical(value));
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

bool contentValueEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == contentMissing || b == contentMissing) return false;
  // JSON numbers have one semantic value across native and browser decoders.
  if (a is num && b is num) return a.isFinite && b.isFinite && a == b;
  if (a is List && b is List) {
    return a.length == b.length && Iterable<int>.generate(a.length).every((i) => contentValueEquals(a[i], b[i]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((k) => b.containsKey(k) && contentValueEquals(a[k], b[k]));
  }
  return a == b;
}

/// Stable entity identities for the complete current StudySetContent schema.
/// Unknown collections fail closed so a format addition cannot silently vanish.
String _identity(String collection, Map<String, Object?> item) => switch (collection) {
  'nodes' => jsonEncode([item['mapId'] ?? 'main', item['cardId']]),
  'reviews' || 'memoryStates' => item['cardId'] as String,
  'documentOutlines' => item['documentId'] as String,
  'translationCaches' => jsonEncode([item['documentId'], item['targetLang']]),
  'noteSourceArchive' => (item['annotation'] as Map)['id'] as String,
  'assistantReceipts' => item['proposalId'] as String,
  'documents' ||
  'annotations' ||
  'cards' ||
  'maps' ||
  'reviewLogs' ||
  'relations' ||
  'summaries' ||
  'researchNotes' ||
  'noteAttachments' ||
  'evidence' ||
  'researchSources' ||
  'inkStrokes' ||
  'marginNotes' ||
  'comparePairs' ||
  'bookmarks' ||
  'studyNotes' => item['id'] as String,
  _ => throw FormatException('Unknown content collection: $collection'),
};

const _collections = {
  'nodes',
  'reviews',
  'memoryStates',
  'documentOutlines',
  'translationCaches',
  'noteSourceArchive',
  'assistantReceipts',
  'documents',
  'annotations',
  'cards',
  'maps',
  'reviewLogs',
  'relations',
  'summaries',
  'researchNotes',
  'noteAttachments',
  'evidence',
  'researchSources',
  'inkStrokes',
  'marginNotes',
  'comparePairs',
  'bookmarks',
  'studyNotes',
};

Map<String, Object?> contentDocument(StudySetContent content) {
  final document = <String, Object?>{};
  for (final entry in content.toJson().entries) {
    final items = <String, Object?>{};
    for (final value in entry.value! as List) {
      final item = Map<String, Object?>.from(value as Map);
      final id = _identity(entry.key, item);
      if (items.containsKey(id)) throw FormatException('Duplicate ${entry.key} identity');
      if (entry.key == 'studyNotes') item['sections'] = _ordered(item['sections'] as List, blocks: true);
      items[id] = item;
    }
    document[entry.key] = items;
  }
  // Optional collections have a stable empty representation.
  document.putIfAbsent('studyNotes', () => <String, Object?>{});
  document.putIfAbsent('noteSourceArchive', () => <String, Object?>{});
  return document;
}

Map<String, Object?> _ordered(List values, {bool blocks = false}) {
  final items = <String, Object?>{};
  for (final value in values) {
    final item = Map<String, Object?>.from(value as Map);
    final id = item['id'] as String;
    if (items.containsKey(id)) throw const FormatException('Duplicate note identity');
    if (blocks) item['blocks'] = _ordered(item['blocks'] as List);
    items[id] = item;
  }
  return {'order': items.keys.toList(), 'items': items};
}

List<Object?> _unordered(Map value, {bool blocks = false}) {
  final items = value['items'] as Map;
  final order = (value['order'] as List).cast<String>();
  if (order.toSet().length != order.length || order.length != items.length || !order.every(items.containsKey)) {
    throw const FormatException('Invalid note order');
  }
  if (items.entries.any((entry) => (entry.value as Map)['id'] != entry.key)) {
    throw const FormatException('Note identity mismatch');
  }
  return [
    for (final id in order)
      {
        ...Map<String, Object?>.from(items[id] as Map),
        if (blocks) 'blocks': _unordered((items[id] as Map)['blocks'] as Map),
      },
  ];
}

StudySetContent contentFromDocument(
  Map<String, Object?> document, {
  StudySetContent? order,
  StudySetContent? additionalOrder,
}) {
  final preferred = order?.toJson() ?? const <String, Object?>{};
  final additional = additionalOrder?.toJson() ?? const <String, Object?>{};
  final json = <String, Object?>{};
  for (final entry in document.entries) {
    if (!_collections.contains(entry.key)) throw FormatException('Unknown collection: ${entry.key}');
    final values = (entry.value as Map).cast<String, Object?>();
    for (final item in values.entries) {
      if (_identity(entry.key, Map<String, Object?>.from(item.value as Map)) != item.key) {
        throw const FormatException('Content identity mismatch');
      }
    }
    final ids = <String>{};
    for (final source in [preferred, additional]) {
      for (final item in (source[entry.key] as List?) ?? const []) {
        final id = _identity(entry.key, Map<String, Object?>.from(item as Map));
        if (values.containsKey(id)) ids.add(id);
      }
    }
    ids.addAll(values.keys.toList()..sort());
    json[entry.key] = [
      for (final id in ids)
        {
          ...Map<String, Object?>.from(values[id] as Map),
          if (entry.key == 'studyNotes') 'sections': _unordered((values[id] as Map)['sections'] as Map, blocks: true),
        },
    ];
  }
  // Legacy import repairs must not manufacture records while applying a merge
  // or an inverse. Preserve the exact candidate for integrity validation.
  return StudySetContent.fromJson(json, migrateSummaries: false);
}

void _diff(Object? before, Object? after, List<String> path, List<ContentFieldChange> changes) {
  if (path.length == 3 && {'studyNotes', 'researchNotes'}.contains(path.first) && path.last == 'updatedAt') {
    return;
  }
  if (contentValueEquals(before, after)) return;
  if (before is Map && after is Map) {
    for (final key in {...before.keys.cast<String>(), ...after.keys.cast<String>()}) {
      _diff(
        before.containsKey(key) ? before[key] : contentMissing,
        after.containsKey(key) ? after[key] : contentMissing,
        [...path, key],
        changes,
      );
    }
  } else {
    changes.add(ContentFieldChange(path, before, after));
  }
}

Object? _at(Map<String, Object?> document, List<String> path) {
  Object? cursor = document;
  for (final key in path) {
    if (cursor is! Map || !cursor.containsKey(key)) return contentMissing;
    cursor = cursor[key];
  }
  return cursor;
}

void _set(Map<String, Object?> document, List<String> path, Object? value) {
  var cursor = document;
  for (final (depth, key) in path.take(path.length - 1).indexed) {
    if (cursor[key] is! Map) throw ContentChangeConflict(path);
    // contentDocument owns its collection and entity maps. Deeper toJson
    // values may still belong to immutable model objects (e.g. generated
    // fingerprints). Copy only the traversed nested maps before staging edits.
    if (depth >= 2) cursor[key] = Map<String, Object?>.from(cursor[key] as Map);
    cursor = (cursor[key] as Map).cast<String, Object?>();
  }
  if (value == contentMissing) {
    cursor.remove(path.last);
  } else {
    cursor[path.last] = jsonDecode(jsonEncode(value));
  }
}

/// Domain constraints required before publishing merged or inverse content.
List<String> contentIntegrityErrors(StudySetContent c) {
  final errors = <String>[];
  final cards = c.cards.map((v) => v.id).toSet();
  final maps = c.maps.map((v) => v.id).toSet();
  final docs = c.documents.map((v) => v.id).toSet();
  final annotations = c.annotations.map((v) => v.id).toSet();
  final parents = {for (final n in c.nodes) (n.mapId, n.cardId): n.parentId};
  for (final s in c.summaries) {
    if (s.cardId != null && c.summaryRange(s) != null) {
      if (parents.containsKey((s.mapId, s.cardId))) errors.add('summaries/${s.id}/placement');
      parents[(s.mapId, s.cardId!)] = s.parentId;
    }
  }
  void checkParents(String mapId, String cardId, String key) {
    final visited = <String>{cardId};
    var parent = parents[(mapId, cardId)];
    while (parent != null) {
      if (!visited.add(parent)) {
        errors.add('$key/cycle');
        break;
      }
      if (!parents.containsKey((mapId, parent))) {
        errors.add('$key/parent');
        break;
      }
      parent = parents[(mapId, parent)];
    }
  }

  if (maps.isEmpty) errors.add('maps/empty');
  for (final n in c.nodes) {
    final key = '${n.mapId}/${n.cardId}';
    if (!cards.contains(n.cardId) || !maps.contains(n.mapId)) errors.add('nodes/$key/reference');
    checkParents(n.mapId, n.cardId, 'nodes/$key');
  }
  for (final a in c.annotations) {
    if (!docs.contains(a.documentId)) errors.add('annotations/${a.id}/document');
    final revision = c.document(a.documentId)?.revision;
    if (a.textAnchors.any((anchor) => anchor.revision != revision)) errors.add('annotations/${a.id}/revision');
  }
  for (final card in c.cards) {
    if (card.annotationId != null && !annotations.contains(card.annotationId)) {
      errors.add('cards/${card.id}/annotation');
    }
    if (card.researchNoteId != null && !c.researchNotes.any((n) => n.id == card.researchNoteId)) {
      errors.add('cards/${card.id}/researchNote');
    }
  }
  for (final r in c.relations) {
    if (!c.isPlaced(r.fromId, mapId: r.mapId) || !c.isPlaced(r.toId, mapId: r.mapId)) {
      errors.add('relations/${r.id}/endpoint');
    }
  }
  for (final s in c.summaries) {
    if (c.summaryRange(s) == null) errors.add('summaries/${s.id}/range');
    if (s.cardId != null && !cards.contains(s.cardId)) errors.add('summaries/${s.id}/card');
    if (!maps.contains(s.mapId)) errors.add('summaries/${s.id}/map');
    if (s.cardId != null) checkParents(s.mapId, s.cardId!, 'summaries/${s.id}');
  }
  for (final b in c.bookmarks) {
    if (!docs.contains(b.documentId)) errors.add('bookmarks/${b.id}/document');
  }
  for (final outline in c.documentOutlines) {
    if (!docs.contains(outline.documentId)) errors.add('outlines/${outline.documentId}/document');
  }
  final notes = c.researchNotes.map((n) => n.id).toSet();
  for (final attachment in c.noteAttachments) {
    if (!notes.contains(attachment.noteId)) errors.add('attachments/${attachment.id}/note');
    final valid = switch (attachment.target) {
      CardTarget(:final cardId) => cards.contains(cardId),
      PdfTarget(:final documentId) || TextTarget(:final documentId) => docs.contains(documentId),
    };
    if (!valid) errors.add('attachments/${attachment.id}/target');
  }
  for (final stroke in c.inkStrokes) {
    if (!docs.contains(stroke.documentId)) errors.add('ink/${stroke.id}/document');
  }
  for (final note in c.marginNotes) {
    if (!docs.contains(note.documentId)) errors.add('marginNotes/${note.id}/document');
    if (note.nodeId != null && !parents.containsKey((note.mapId ?? 'main', note.nodeId))) {
      errors.add('marginNotes/${note.id}/node');
    }
  }
  final sources = {...annotations, ...c.noteSourceArchive.map((a) => a.annotation.id)};
  final margins = c.marginNotes.map((n) => n.id).toSet();
  for (final note in c.studyNotes) {
    final sections = note.sections.map((s) => s.id).toSet();
    for (final section in note.sections) {
      for (final block in section.blocks) {
        final valid = switch (block) {
          QuoteBlock() => sources.contains(block.annotationId),
          OwnBlock() => switch (block.source) {
            OwnSource.card || OwnSource.image => cards.contains(block.sourceId),
            OwnSource.marginNote => margins.contains(block.sourceId),
            OwnSource.researchNote => notes.contains(block.sourceId),
          },
          XrefBlock() => sections.contains(block.toSectionId),
          _ => true,
        };
        if (!valid) errors.add('studyNotes/${note.id}/${section.id}/${block.id}/source');
      }
    }
  }
  return errors;
}
