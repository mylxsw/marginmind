import 'package:mm_core/mm_core.dart';

import 'commit.dart';
import 'device_reading.dart';
import 'reconciliation.dart';

/// Immutable paragraph writes, partitioned by document version. Human edits
/// (including explicit removal) remain authoritative over background AI results.
class TranslationRegister {
  TranslationRegister(this.writes, this.removed);
  factory TranslationRegister.empty() => TranslationRegister({}, {});
  final Map<String, Map<String, Object?>> writes;
  final Set<String> removed;

  Map<String, Map<String, Object?>> active(String version, String key) => {
    for (final e in writes.entries)
      if (!removed.contains(e.key) && e.value['documentVersion'] == version && e.value['key'] == key) e.key: e.value,
  };
  Map<String, Map<String, Object?>> choices(String version, String key) {
    final all = active(version, key);
    final human = all.entries.where(
      (e) => e.value['segment'] == null || (e.value['segment'] as Map)['origin'] == 'edited',
    );
    final selected = (human.isEmpty ? all.entries : human).toList()..sort((a, b) => a.key.compareTo(b.key));
    final distinct = <String, Map<String, Object?>>{};
    for (final e in selected) {
      // Provenance does not create a conflict when the text is identical.
      final text = (e.value['segment'] as Map?)?['text'];
      if (!distinct.values.any((v) => (v['segment'] as Map?)?['text'] == text)) distinct[e.key] = e.value;
    }
    return distinct;
  }

  String token(String version, String key) =>
      active(version, key).isEmpty ? 'absent:$version' : syncDigest([version, key, active(version, key)]);
  TranslationSnapshot snapshot(String version) {
    final keys = writes.values.where((v) => v['documentVersion'] == version).map((v) => v['key'] as String).toSet();
    final segments = <String, TranslationSegment>{}, conflicts = <String, List<TranslationChoice>>{};
    for (final key in keys) {
      final options = choices(version, key);
      if (options.isEmpty) continue;
      final first = options.values.first['segment'];
      if (first != null) segments[key] = TranslationSegment.fromJson((first as Map).cast());
      if (options.length > 1) {
        conflicts[key] = [
          for (final e in options.entries)
            TranslationChoice(
              e.key,
              e.value['segment'] == null ? null : TranslationSegment.fromJson((e.value['segment'] as Map).cast()),
            ),
        ];
      }
    }
    return TranslationSnapshot(
      documentVersion: version,
      segments: segments,
      tokens: {for (final key in keys) key: token(version, key)},
      conflicts: conflicts,
    );
  }

  TranslationRegister append(
    String version,
    TranslationSegment segment,
    String author,
    String operation, {
    bool observed = false,
    bool replaceEdited = false,
  }) {
    final next = TranslationRegister.fromJson(toJson());
    final candidates = active(version, segment.key);
    final shown = choices(version, segment.key).values.firstOrNull;
    for (final e in candidates.entries) {
      final old = e.value['segment'] as Map?;
      final human = old == null || old['origin'] == 'edited';
      if (!human ||
          (observed &&
              (segment.origin == TranslationOrigin.edited || replaceEdited) &&
              old?['text'] == (shown?['segment'] as Map?)?['text'])) {
        next.removed.add(e.key);
      }
    }
    final dot = '$author:${syncDigest(operation)}';
    if (next.writes.containsKey(dot)) throw const FormatException('Reused translation operation');
    next.writes[dot] = {'documentVersion': version, 'key': segment.key, 'segment': segment.toJson()};
    return TranslationRegister.fromJson(next.toJson());
  }

  TranslationRegister choose(String version, String key, String choice, String author, String operation) {
    final candidates = active(version, key);
    if (!candidates.containsKey(choice)) throw const FormatException('Stale translation choice');
    final next = TranslationRegister.fromJson(toJson());
    next.removed.addAll(candidates.keys);
    final dot = '$author:${syncDigest(operation)}';
    if (next.writes.containsKey(dot)) throw const FormatException('Reused translation operation');
    final selected = Map<String, Object?>.of(candidates[choice]!);
    if (selected['segment'] case final Map value) selected['segment'] = {...value, 'origin': 'edited'};
    next.writes[dot] = selected;
    return TranslationRegister.fromJson(next.toJson());
  }

  TranslationRegister clear(String version, String author, String operation) {
    final next = TranslationRegister.fromJson(toJson());
    final keys = writes.values.where((v) => v['documentVersion'] == version).map((v) => v['key'] as String).toSet();
    for (final key in keys) {
      next.removed.addAll(active(version, key).keys);
      next.writes['$author:${syncDigest([operation, key])}'] = {
        'documentVersion': version,
        'key': key,
        'segment': null,
      };
    }
    return TranslationRegister.fromJson(next.toJson());
  }

  TranslationRegister join(TranslationRegister other) {
    final next = TranslationRegister.fromJson(toJson());
    for (final e in other.writes.entries) {
      if (writes.containsKey(e.key) && !contentValueEquals(writes[e.key], e.value)) {
        throw const FormatException('Mutated translation');
      }
      next.writes[e.key] = e.value;
    }
    next.removed.addAll(other.removed);
    return TranslationRegister.fromJson(next.toJson());
  }

  void validateSuccessor(TranslationRegister next, String author) {
    if (!next.removed.containsAll(removed) || !writes.keys.toSet().containsAll(next.removed.difference(removed))) {
      throw const FormatException('Invalid translation removal');
    }
    for (final e in writes.entries) {
      if (!contentValueEquals(next.writes[e.key], e.value)) throw const FormatException('Mutated translation');
    }
    if (next.writes.keys.where((k) => !writes.containsKey(k)).any((k) => k.substring(0, k.length - 65) != author)) {
      throw const FormatException('Forged translation author');
    }
  }

  Map<String, Object?> toJson() => {
    'kind': 'translation-register',
    'version': 1,
    'writes': writes,
    'removed': removed.toList()..sort(),
  };
  factory TranslationRegister.fromJson(Map<String, Object?> json) {
    try {
      if (json.length != 4 || json['kind'] != 'translation-register' || json['version'] != 1) {
        throw const FormatException('Unknown translation protocol');
      }
      final writes = (json['writes'] as Map).map((k, v) => MapEntry(k as String, (v as Map).cast<String, Object?>()));
      final removed = (json['removed'] as List).cast<String>();
      if (removed.toSet().length != removed.length || !writes.keys.toSet().containsAll(removed)) {
        throw const FormatException('Invalid translation removals');
      }
      for (final e in writes.entries) {
        final v = e.value;
        if (!RegExp(r'^.+:[0-9a-f]{64}$').hasMatch(e.key) ||
            v.length != 3 ||
            v['documentVersion'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(v['documentVersion'] as String) ||
            v['key'] is! String ||
            (v['key'] as String).isEmpty ||
            !v.containsKey('segment')) {
          throw const FormatException('Invalid translation write');
        }
        if (v['segment'] != null) {
          final segment = TranslationSegment.fromJson((v['segment'] as Map).cast());
          if (segment.key != v['key'] || !contentValueEquals(segment.toJson(), v['segment'])) {
            throw const FormatException('Invalid translation segment');
          }
        }
      }
      return TranslationRegister(writes, removed.toSet());
    } on TypeError {
      throw const FormatException('Invalid translation register');
    } on ArgumentError {
      throw const FormatException('Invalid translation register');
    }
  }
}

SyncCommit translationBaseline(String library, String scope) => SyncCommit.create(
  libraryId: library,
  scope: scope,
  deviceId: 'translation-baseline-v1',
  sequence: 1,
  payload: TranslationRegister.empty().toJson(),
);

SyncMergePlan planTranslationMerge(
  Map<String, SyncCommit> known, {
  required String remote,
  String? local,
  required Set<String> acceptedContent,
}) {
  SyncMergePlan result(SyncMergeState state, String reason, {Map<String, Object?>? payload, bool adopt = false}) =>
      SyncMergePlan(remote: remote, local: local, state: state, reason: reason, payload: payload, adopt: adopt);
  try {
    final ancestry = syncAncestry(known, [remote, ?local]);
    final tip = known[remote]!, parts = tip.scope.split('/');
    if (parts.length != 4 ||
        parts.first != 'translated' ||
        parts.any((p) => p.isEmpty || p == '.' || p == '..' || RegExp(r'[/\\\x00-\x1f:]').hasMatch(p))) {
      throw const FormatException('Invalid translation scope');
    }
    final states = <String, TranslationRegister>{};
    for (final c in ancestry.values) {
      if (c.deleted || c.pending.isNotEmpty || c.resolves.isNotEmpty) {
        return result(SyncMergeState.conflict, 'deleteEdit');
      }
      states[c.id] = TranslationRegister.fromJson(c.payload);
    }
    for (final c in ancestry.values) {
      final state = states[c.id]!;
      if (c.parents.isEmpty) {
        if (c.id != translationBaseline(c.libraryId, c.scope).id) return result(SyncMergeState.conflict, 'noBase');
        continue;
      }
      final parent = c.parents.map((p) => states[p]!).reduce((a, b) => a.join(b));
      if (c.parents.length == 1) {
        parent.validateSuccessor(state, c.deviceId);
      } else if (!contentValueEquals(parent.toJson(), state.toJson())) {
        throw const FormatException('Invalid translation integration');
      }
      if (c.requires.length != 1 || !c.requires.containsKey('sets/${parts[1]}')) {
        throw const FormatException('Missing translation dependency');
      }
      final dependency = c.requires.values.single, source = known[dependency];
      if (source == null || !acceptedContent.contains(dependency)) {
        return result(SyncMergeState.waiting, 'missingContent');
      }
      if (source.scope != 'sets/${parts[1]}' || source.libraryId != tip.libraryId || source.deleted) {
        throw const FormatException('Invalid translation dependency');
      }
      final doc = contentFromDocument((source.payload['content'] as Map).cast()).document(parts[2]);
      if (doc == null) throw const FormatException('Missing translation document');
      final version = readingDocumentVersion(doc);
      if (state.writes.entries
          .where((e) => !parent.writes.containsKey(e.key))
          .any((e) => e.value['documentVersion'] != version)) {
        throw const FormatException('Invalid translation document version');
      }
    }
    final graph = SyncGraph(ancestry.values);
    if (local != null && graph.ancestors(local).contains(remote)) {
      return result(SyncMergeState.unchanged, 'alreadyApplied');
    }
    if (local == null || graph.ancestors(remote).contains(local)) {
      return result(SyncMergeState.ready, 'advance', payload: tip.payload, adopt: true);
    }
    final bases = graph.mergeBases(local, remote);
    if (bases.length != 1) return result(SyncMergeState.conflict, bases.isEmpty ? 'noBase' : 'multipleBases');
    return result(SyncMergeState.ready, 'merge', payload: states[local]!.join(states[remote]!).toJson());
  } on MissingSyncParents {
    return result(SyncMergeState.waiting, 'missingParents');
  } on FormatException {
    return result(SyncMergeState.conflict, 'invalidTranslation');
  } on ArgumentError {
    return result(SyncMergeState.conflict, 'invalidTranslation');
  } on TypeError {
    return result(SyncMergeState.conflict, 'invalidTranslation');
  }
}
