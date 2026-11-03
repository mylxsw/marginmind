import 'package:mm_core/mm_core.dart';

import 'commit.dart';
import 'reconciliation.dart';

/// A word has one library-wide identity regardless of the device's old UUID.
String vocabularyIdentity(String language, String term) =>
    syncDigest([vocabularyLanguage(language), vocabularyKey(term)]);

const vocabularyFields = {
  'term',
  'kind',
  'forms',
  'ukPhonetic',
  'usPhonetic',
  'senses',
  'gloss',
  'note',
  'status',
  'createdAt',
  'updatedAt',
  'alive',
};
const _presentationFields = {'term', 'createdAt', 'updatedAt'};

/// Observed-remove multi-value registers. Writes are immutable and removals
/// name observed writes, so a concurrent edit stays visible as a choice.
/// Sources use the same rule independently of dictionary-field conflicts.
class VocabularyWord {
  VocabularyWord._(this.language, this.key, this.writes, this.removed);
  factory VocabularyWord.empty(String language, String term) => VocabularyWord._(
    vocabularyLanguage(language),
    vocabularyKey(term),
    {
      for (final field in {...vocabularyFields, 'contexts', 'aliases'}) field: {},
    },
    {
      for (final field in {...vocabularyFields, 'contexts', 'aliases'}) field: <String>{},
    },
  );
  final String language, key;
  final Map<String, Map<String, Object?>> writes;
  final Map<String, Set<String>> removed;
  String get identity => vocabularyIdentity(language, key);
  String get scope => 'words/$identity';
  String get entryId => 'word-$identity';
  Set<String> get aliases => active('aliases').values.cast<String>().toSet();

  Map<String, Object?> active(String field) => {
    for (final e in writes[field]!.entries)
      if (!removed[field]!.contains(e.key)) e.key: e.value,
  };
  Map<String, Object?> alternatives(String field) {
    final distinct = <String, Object?>{};
    final entries = active(field).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (final e in entries) {
      if (!distinct.values.any((v) => contentValueEquals(v, e.value))) distinct[e.key] = e.value;
    }
    return distinct;
  }

  Set<String> get conflicts => !alive
      ? {}
      : {
          for (final field in vocabularyFields.difference(_presentationFields))
            if (alternatives(field).length > 1) field,
        };
  bool get alive => active('alive').values.contains(true);

  Object? _display(String field, Object? fallback) {
    final choices = alternatives(field).values.toList();
    if (choices.isEmpty) return fallback;
    if (_presentationFields.contains(field)) {
      choices.sort((a, b) => (a as String).compareTo(b as String));
      return field == 'updatedAt' ? choices.last : choices.first;
    }
    return choices.first;
  }

  VocabularyEntry? get entry {
    if (!alive) return null;
    final contexts = active('contexts').entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return VocabularyEntry.fromJson({
      'id': entryId,
      'term': _display('term', key),
      'key': key,
      'language': language,
      'kind': _display('kind', 'word'),
      'forms': _display('forms', [key]),
      'ukPhonetic': _display('ukPhonetic', null),
      'usPhonetic': _display('usPhonetic', null),
      'senses': _display('senses', []),
      'gloss': _display('gloss', ''),
      'note': _display('note', ''),
      'status': _display('status', 'learning'),
      'createdAt': _display('createdAt', DateTime.utc(1970).toIso8601String()),
      'updatedAt': _display('updatedAt', DateTime.utc(1970).toIso8601String()),
      'contexts': {
        for (final e in contexts)
          syncDigest(e.value): {...(e.value as Map).cast<String, Object?>(), 'id': syncDigest(e.value)},
      }.values.toList(),
    });
  }

  Map<String, Object?> toJson() => {
    'kind': 'vocabulary-word',
    'version': 1,
    'language': language,
    'key': key,
    'writes': writes,
    'removed': {for (final e in removed.entries) e.key: e.value.toList()..sort()},
  };
  factory VocabularyWord.fromJson(Map<String, Object?> json) {
    try {
      if (json.length != 6 || json['kind'] != 'vocabulary-word' || json['version'] != 1) {
        throw const FormatException('Unknown word protocol');
      }
      final result = VocabularyWord.empty(json['language'] as String, json['key'] as String);
      if (result.language.isEmpty ||
          result.key.isEmpty ||
          result.language != json['language'] ||
          result.key != json['key']) {
        throw const FormatException('Noncanonical word identity');
      }
      final writes = (json['writes'] as Map).cast<String, Object?>(),
          removed = (json['removed'] as Map).cast<String, Object?>();
      if (!contentValueEquals(writes.keys.toList()..sort(), result.writes.keys.toList()..sort()) ||
          !contentValueEquals(removed.keys.toList()..sort(), result.removed.keys.toList()..sort())) {
        throw const FormatException('Invalid word fields');
      }
      for (final field in result.writes.keys) {
        result.writes[field]!.addAll((writes[field] as Map).cast<String, Object?>());
        final tombstones = (removed[field] as List).cast<String>();
        result.removed[field]!.addAll(tombstones);
        if (tombstones.length != result.removed[field]!.length ||
            !result.writes[field]!.keys.toSet().containsAll(tombstones)) {
          throw const FormatException('Unknown removed word value');
        }
        if (field == 'aliases' && tombstones.isNotEmpty) {
          throw const FormatException('Removed vocabulary alias');
        }
        for (final e in result.writes[field]!.entries) {
          if (field == 'contexts') {
            final c = VocabularyContext.fromJson((e.value as Map).cast());
            if (!RegExp(r'^.+:[0-9a-f]{64}$').hasMatch(e.key) || !contentValueEquals(_context(c), e.value)) {
              throw const FormatException('Invalid source snapshot');
            }
          } else {
            if (!RegExp(r'^.+:[0-9a-f]{64}$').hasMatch(e.key)) {
              throw const FormatException('Invalid word edit identity');
            }
            if (field == 'aliases') {
              if (e.value is! String || (e.value as String).isEmpty) {
                throw const FormatException('Invalid vocabulary alias');
              }
            } else {
              _validateField(field, e.value, result.key);
            }
          }
        }
      }
      for (final field in vocabularyFields) {
        if (result.writes[field]!.isNotEmpty && result.active(field).isEmpty) {
          throw const FormatException('Empty word register');
        }
      }
      result.entry; // Enforce the materialized domain constraints as well.
      return result;
    } on TypeError {
      throw const FormatException('Invalid vocabulary word');
    } on ArgumentError {
      throw const FormatException('Invalid vocabulary word');
    }
  }

  static Map<String, Object?> _context(VocabularyContext c) => {
    ...c.toJson(),
    'id': 'source',
    'addedAt': c.addedAt.toUtc().toIso8601String(),
  };
  static String _contextId(VocabularyContext c) => syncDigest(_context(c));
  static void _validateField(String field, Object? value, String key) {
    final template = VocabularyEntry(
      id: 'validate',
      term: key,
      language: 'en',
      kind: VocabularyKind.word,
      createdAt: DateTime.utc(1970),
      updatedAt: DateTime.utc(1970),
      forms: [key],
    ).toJson();
    if (field == 'alive') {
      if (value is! bool) throw const FormatException('Invalid word life state');
      return;
    }
    final candidate = VocabularyEntry.fromJson({...template, field: value});
    if (field == 'term' && candidate.key != key) throw const FormatException('Word identity changed');
    if ((field == 'createdAt' || field == 'updatedAt') &&
        (value is! String || DateTime.parse(value).toUtc().toIso8601String() != value)) {
      throw const FormatException('Noncanonical word time');
    }
    if (!contentValueEquals(candidate.toJson()[field], value)) throw const FormatException('Invalid word field');
  }

  VocabularyWord edit(
    VocabularyEntry? before,
    VocabularyEntry? after, {
    required String deviceId,
    required String operation,
  }) {
    final next = VocabularyWord.fromJson(toJson());
    if (after != null && vocabularyIdentity(after.language, after.term) != identity) {
      throw const FormatException('Word identity changed');
    }
    final previous = before?.toJson(), value = after?.toJson();
    final dot = '$deviceId:${syncDigest(operation)}';
    void write(String field, Object? value) {
      _validateField(field, value, key);
      // An ordinary edit observes the displayed value, not every competing
      // candidate. Only explicit choose() may dismiss those other candidates.
      final observed = field == 'alive' ? true : previous?[field];
      next.removed[field]!.addAll(
        active(field).entries
            .where(
              (e) =>
                  before == null ||
                  after == null ||
                  _presentationFields.contains(field) ||
                  contentValueEquals(e.value, observed),
            )
            .map((e) => e.key),
      );
      if (next.writes[field]!.containsKey(dot)) throw const FormatException('Reused word operation');
      next.writes[field]![dot] = value;
    }

    if (!contentValueEquals(before?.toJson(), after?.toJson())) write('alive', after != null);
    if (after != null) {
      if (after.id != entryId && !aliases.contains(after.id)) {
        next.writes['aliases']![dot] = after.id;
      }
      for (final field in vocabularyFields.where((f) => f != 'alive')) {
        final a = previous?[field], b = value![field];
        if (before == null || !contentValueEquals(a, b)) {
          write(
            field,
            (field == 'createdAt'
                ? after.createdAt.toUtc().toIso8601String()
                : field == 'updatedAt'
                ? after.updatedAt.toUtc().toIso8601String()
                : b),
          );
        }
      }
      final old = {for (final c in before?.contexts ?? const <VocabularyContext>[]) _contextId(c): c};
      final sources = {for (final c in after.contexts) _contextId(c): c};
      next.removed['contexts']!.addAll(
        active('contexts').entries
            .where((e) => old.containsKey(syncDigest(e.value)) && !sources.containsKey(syncDigest(e.value)))
            .map((e) => e.key),
      );
      for (final e in sources.entries) {
        if (!old.containsKey(e.key)) {
          next.writes['contexts']!['$deviceId:${syncDigest([operation, e.key])}'] = _context(e.value);
        }
      }
    }
    return VocabularyWord.fromJson(next.toJson());
  }

  VocabularyWord choose(String field, String choice, {required String deviceId, required String operation}) {
    if (!vocabularyFields.contains(field) || !active(field).containsKey(choice)) {
      throw const FormatException('Stale word choice');
    }
    final next = VocabularyWord.fromJson(toJson());
    next.removed[field]!.addAll(active(field).keys);
    final dot = '$deviceId:${syncDigest(operation)}';
    if (next.writes[field]!.containsKey(dot)) throw const FormatException('Reused word operation');
    next.writes[field]![dot] = writes[field]![choice];
    return VocabularyWord.fromJson(next.toJson());
  }

  VocabularyWord join(VocabularyWord other) {
    if (identity != other.identity) throw const FormatException('Different words');
    final next = VocabularyWord.fromJson(toJson());
    for (final field in writes.keys) {
      for (final e in other.writes[field]!.entries) {
        if (next.writes[field]!.containsKey(e.key) && !contentValueEquals(next.writes[field]![e.key], e.value)) {
          throw const FormatException('Mutated word operation');
        }
        next.writes[field]![e.key] = e.value;
      }
      next.removed[field]!.addAll(other.removed[field]!);
    }
    return VocabularyWord.fromJson(next.toJson());
  }

  void validateSuccessor(VocabularyWord next, String author) {
    if (identity != next.identity) throw const FormatException('Word identity changed');
    for (final field in writes.keys) {
      if (!next.removed[field]!.containsAll(removed[field]!)) throw const FormatException('Forgotten removal');
      for (final e in writes[field]!.entries) {
        if (!next.writes[field]!.containsKey(e.key) || !contentValueEquals(e.value, next.writes[field]![e.key])) {
          throw const FormatException('Mutated word history');
        }
      }
      if (!writes[field]!.keys.toSet().containsAll(next.removed[field]!.difference(removed[field]!))) {
        throw const FormatException('Unobserved removal');
      }
      if (next.writes[field]!.keys
          .where((id) => !writes[field]!.containsKey(id))
          .any((id) => id.substring(0, id.length - 65) != author)) {
        throw const FormatException('Forged word author');
      }
    }
  }
}

/// The explicit empty word is a mathematical domain baseline, shared by all
/// devices. It contains no user data and does not select between unknown roots.
SyncCommit vocabularyBaseline(String libraryId, String language, String key) {
  final word = VocabularyWord.empty(language, key);
  return SyncCommit.create(
    libraryId: libraryId,
    scope: word.scope,
    deviceId: 'vocabulary-baseline-v1',
    sequence: 1,
    payload: word.toJson(),
  );
}

SyncMergePlan planVocabularyWord(Map<String, SyncCommit> known, {required String remote, String? local}) {
  SyncMergePlan result(SyncMergeState state, String reason, {Map<String, Object?>? payload, bool adopt = false}) =>
      SyncMergePlan(remote: remote, local: local, state: state, reason: reason, payload: payload, adopt: adopt);
  try {
    final ancestry = syncAncestry(known, [remote, ?local]);
    if (local != null &&
        (known[local]!.libraryId != known[remote]!.libraryId || known[local]!.scope != known[remote]!.scope)) {
      return result(SyncMergeState.conflict, 'differentScope');
    }
    final states = <String, VocabularyWord>{};
    for (final c in ancestry.values) {
      if (c.deleted || c.pending.isNotEmpty || c.resolves.isNotEmpty || c.requires.isNotEmpty) {
        throw const FormatException('Invalid word commit');
      }
      final state = VocabularyWord.fromJson(c.payload);
      if (state.scope != c.scope) throw const FormatException('Invalid word scope');
      states[c.id] = state;
    }
    for (final c in ancestry.values) {
      final state = states[c.id]!;
      if (c.parents.isEmpty) {
        if (c.id != vocabularyBaseline(c.libraryId, state.language, state.key).id) {
          return result(SyncMergeState.conflict, 'noBase');
        }
      } else if (c.parents.length == 1) {
        states[c.parents.single]!.validateSuccessor(state, c.deviceId);
      } else {
        final merged = c.parents.map((p) => states[p]!).reduce((a, b) => a.join(b));
        if (!contentValueEquals(merged.toJson(), state.toJson())) {
          throw const FormatException('Invalid word integration');
        }
      }
    }
    final graph = SyncGraph(ancestry.values);
    if (local != null && graph.ancestors(local).contains(remote)) {
      return result(SyncMergeState.unchanged, 'alreadyApplied');
    }
    if (local == null || graph.ancestors(remote).contains(local)) {
      return result(SyncMergeState.ready, 'advance', payload: known[remote]!.payload, adopt: true);
    }
    final bases = graph.mergeBases(local, remote);
    if (bases.length != 1) return result(SyncMergeState.conflict, bases.isEmpty ? 'noBase' : 'multipleBases');
    final merged = states[local]!.join(states[remote]!);
    return result(SyncMergeState.ready, 'merge', payload: merged.toJson());
  } on MissingSyncParents {
    return result(SyncMergeState.waiting, 'missingParents');
  } on FormatException {
    return result(SyncMergeState.conflict, 'invalidVocabulary');
  } on ArgumentError {
    return result(SyncMergeState.conflict, 'invalidVocabulary');
  } on TypeError {
    return result(SyncMergeState.conflict, 'invalidVocabulary');
  }
}
