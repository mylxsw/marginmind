import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';

const syncProtocolVersion = 1;
String syncDigest(Object? value) => sha256.convert(utf8.encode(canonicalContentJson(value))).toString();

/// Immutable, content-addressed commit. Account credentials never belong here.
/// Parent identities establish causality; wall clocks are not ordering keys.
class SyncCommit {
  SyncCommit._(
    this.id,
    this.libraryId,
    this.scope,
    this.deviceId,
    this.sequence,
    this.parents,
    this.payload,
    this.deleted,
  );

  factory SyncCommit.create({
    required String libraryId,
    required String scope,
    required String deviceId,
    required int sequence,
    List<String> parents = const [],
    required Map<String, Object?> payload,
    bool deleted = false,
  }) {
    if ([libraryId, scope, deviceId].any((s) => s.isEmpty || s.length > 256) || sequence < 1) {
      throw const FormatException('Invalid sync identity');
    }
    final sorted = parents.toSet().toList()..sort();
    if (sorted.length != parents.length || sorted.any((s) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(s))) {
      throw const FormatException('Invalid commit parents');
    }
    if (deleted && payload.isNotEmpty) throw const FormatException('Tombstones cannot contain live content');
    final frozen = _freeze(payload) as Map<String, Object?>;
    final candidate = SyncCommit._(
      '',
      libraryId,
      scope,
      deviceId,
      sequence,
      List.unmodifiable(sorted),
      frozen,
      deleted,
    );
    return SyncCommit._(
      syncDigest(candidate._body()),
      libraryId,
      scope,
      deviceId,
      sequence,
      candidate.parents,
      frozen,
      deleted,
    );
  }

  final String id, libraryId, scope, deviceId;
  final int sequence;
  final List<String> parents;
  final Map<String, Object?> payload;
  final bool deleted;

  Map<String, Object?> _body() => {
    'protocol': syncProtocolVersion,
    'libraryId': libraryId,
    'scope': scope,
    'deviceId': deviceId,
    'sequence': sequence,
    'parents': parents,
    'deleted': deleted,
    'payload': payload,
  };
  Map<String, Object?> toJson() => {'id': id, ..._body()};

  factory SyncCommit.fromJson(Map<String, Object?> json) {
    const fields = {'id', 'protocol', 'libraryId', 'scope', 'deviceId', 'sequence', 'parents', 'deleted', 'payload'};
    if (json['protocol'] != syncProtocolVersion || json.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('Unsupported sync commit');
    }
    try {
      final result = SyncCommit.create(
        libraryId: json['libraryId'] as String,
        scope: json['scope'] as String,
        deviceId: json['deviceId'] as String,
        sequence: json['sequence'] as int,
        parents: (json['parents'] as List).cast<String>(),
        payload: (json['payload'] as Map).cast<String, Object?>(),
        deleted: json['deleted'] as bool,
      );
      if (result.id != json['id']) throw const FormatException('Commit digest mismatch');
      return result;
    } on TypeError {
      throw const FormatException('Malformed sync commit');
    }
  }
}

Object? _freeze(Object? value) {
  if (value is Map) return Map<String, Object?>.unmodifiable(value.map((k, v) => MapEntry(k as String, _freeze(v))));
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || value is num && value.isFinite) return value;
  throw const FormatException('Non-JSON sync payload');
}

/// Validated causal graph. Missing parents are pending input, never an excuse
/// to guess a merge base. Duplicate device sequence numbers indicate a forked
/// installation identity and must not silently overwrite each other.
class SyncGraph {
  SyncGraph(Iterable<SyncCommit> commits) {
    final sequences = <(String, String, String, int), String>{};
    for (final c in commits) {
      final key = (c.libraryId, c.scope, c.deviceId, c.sequence);
      if (sequences.containsKey(key) && sequences[key] != c.id) throw const FormatException('Device sequence fork');
      sequences[key] = c.id;
      _commits[c.id] = c;
    }
    for (final c in _commits.values) {
      for (final id in c.parents) {
        final parent = _commits[id];
        if (parent == null) throw const FormatException('Missing commit parent');
        if (parent.libraryId != c.libraryId || parent.scope != c.scope) {
          throw const FormatException('Cross-scope parent');
        }
        if (parent.deviceId == c.deviceId && parent.sequence >= c.sequence) {
          throw const FormatException('Invalid causal sequence');
        }
      }
    }
    final devices = <(String, String, String), List<SyncCommit>>{};
    for (final c in _commits.values) {
      devices.putIfAbsent((c.libraryId, c.scope, c.deviceId), () => []).add(c);
    }
    for (final history in devices.values) {
      history.sort((a, b) => a.sequence.compareTo(b.sequence));
      for (var i = 1; i < history.length; i++) {
        if (!_descendsFrom(history[i].id, history[i - 1].id)) {
          throw const FormatException('Device history fork');
        }
      }
    }
  }
  final _commits = <String, SyncCommit>{};

  bool _descendsFrom(String id, String ancestor) {
    final visited = <String>{}, pending = <String>[id];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current == ancestor) return true;
      if (visited.add(current)) pending.addAll(_commits[current]!.parents);
    }
    return false;
  }

  Set<String> ancestors(String id) {
    if (!_commits.containsKey(id)) throw const FormatException('Unknown commit');
    final result = <String>{}, pending = <String>[id];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (result.add(current)) pending.addAll(_commits[current]!.parents);
    }
    return result;
  }

  /// May return multiple bases (criss-cross history). The caller must preserve
  /// the branches in that case rather than arbitrarily choosing a base.
  Set<String> mergeBases(String left, String right) {
    final common = ancestors(left).intersection(ancestors(right));
    // The common set is ancestor-closed. Every non-tip common ancestor is a
    // direct parent of another member, so one pass finds all maximal bases.
    return common.difference({for (final id in common) ..._commits[id]!.parents});
  }
}
