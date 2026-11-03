import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';

const syncProtocolVersion = 2;

/// Only for reading the unpublished v1 candidate and its local journal. Its
/// JSON-number encoding was runtime dependent; never use for new wire IDs.
String legacySyncDigest(Object? value) => sha256.convert(utf8.encode(canonicalContentJson(value))).toString();

/// Tagged canonical tree, with finite JSON numbers encoded as IEEE-754 bytes.
/// JSON's 1/1.0 and exponent spellings differ between Dart VM and JavaScript.
/// Explicit tags distinguish numbers from strings and user-authored maps.
String syncDigest(Object? value) {
  Object encode(Object? value) {
    if (value == null) return ['null'];
    if (value is bool) return ['bool', value];
    if (value is String) return ['string', value];
    if (value is num) {
      if (!value.isFinite || value.abs() > 9007199254740991) {
        throw const FormatException('Sync numbers must be finite and within the exact JSON integer range');
      }
      final bytes = ByteData(8)..setFloat64(0, value == 0 ? 0 : value.toDouble(), Endian.big);
      return [
        'number',
        [for (var i = 0; i < 8; i++) bytes.getUint8(i).toRadixString(16).padLeft(2, '0')].join(),
      ];
    }
    if (value is List) return ['array', value.map(encode).toList()];
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return [
        'object',
        [
          for (final key in keys) [key, encode(value[key])],
        ],
      ];
    }
    throw const FormatException('Not a JSON sync value');
  }

  return sha256.convert(utf8.encode(jsonEncode(encode(value)))).toString();
}

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
    this.pending,
    this.resolves,
    this.requires,
    this.protocol,
    this.legacyCanonical,
  );

  factory SyncCommit.create({
    required String libraryId,
    required String scope,
    required String deviceId,
    required int sequence,
    List<String> parents = const [],
    required Map<String, Object?> payload,
    bool deleted = false,
    List<String> pending = const [],
    List<String> resolves = const [],
    Map<String, String> requires = const {},
    int protocol = syncProtocolVersion,
  }) {
    if (protocol != 1 && protocol != syncProtocolVersion) throw const FormatException('Unsupported sync commit');
    if ([libraryId, scope, deviceId].any((s) => s.isEmpty || s.length > 256) || sequence < 1) {
      throw const FormatException('Invalid sync identity');
    }
    final sorted = parents.toSet().toList()..sort();
    if (sorted.length != parents.length || sorted.any((s) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(s))) {
      throw const FormatException('Invalid commit parents');
    }
    if (deleted && payload.isNotEmpty) throw const FormatException('Tombstones cannot contain live content');
    List<String> references(List<String> values) {
      final sorted = values.toSet().toList()..sort();
      if (sorted.length != values.length || sorted.any((s) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(s))) {
        throw const FormatException('Invalid transaction references');
      }
      return List.unmodifiable(sorted);
    }

    if (deleted && (pending.isNotEmpty || resolves.isNotEmpty)) {
      throw const FormatException('Resolve pending transactions before deletion');
    }
    if (requires.entries.any(
          (e) => e.key.isEmpty || e.key.length > 256 || e.key == scope || !RegExp(r'^[0-9a-f]{64}$').hasMatch(e.value),
        ) ||
        deleted && requires.isNotEmpty) {
      throw const FormatException('Invalid domain dependencies');
    }
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
      references(pending),
      references(resolves),
      Map.unmodifiable(requires),
      protocol,
      null,
    );
    return SyncCommit._(
      protocol == 1 ? legacySyncDigest(candidate._body()) : syncDigest(candidate._body()),
      libraryId,
      scope,
      deviceId,
      sequence,
      candidate.parents,
      frozen,
      deleted,
      candidate.pending,
      candidate.resolves,
      candidate.requires,
      protocol,
      protocol == 1 ? canonicalContentJson(candidate._body()) : null,
    );
  }

  final String id, libraryId, scope, deviceId;
  final int sequence, protocol;

  /// Exact bytes originally hashed by the unpublished v1 implementation.
  /// This is an integrity witness, not a signature or a new commit identity.
  /// Keeping it as text preserves VM double spelling across JavaScript parsing.
  final String? legacyCanonical;

  bool get portable {
    if (protocol == syncProtocolVersion) return true;
    if (legacyCanonical == null) return false;
    try {
      syncDigest(_body()); // Reject numbers that cannot survive JSON runtimes.
      return true;
    } on FormatException {
      return false;
    }
  }

  final List<String> parents;
  final Map<String, Object?> payload;
  final bool deleted;

  /// Unresolved atomic transactions remain in the causal ancestry. Carrying
  /// their IDs acknowledges receipt, never a choice of their final value.
  final List<String> pending, resolves;

  /// Other domains that must be accepted before applying this version.
  final Map<String, String> requires;

  Map<String, Object?> _body() => {
    'protocol': protocol,
    'libraryId': libraryId,
    'scope': scope,
    'deviceId': deviceId,
    'sequence': sequence,
    'parents': parents,
    'deleted': deleted,
    'payload': payload,
    if (pending.isNotEmpty) 'pending': pending,
    if (resolves.isNotEmpty) 'resolves': resolves,
    if (requires.isNotEmpty) 'requires': requires,
  };
  Map<String, Object?> toJson() => {
    'id': id,
    ..._body(),
    if (legacyCanonical != null && portable) 'legacyCanonical': legacyCanonical,
  };

  factory SyncCommit.fromJson(Map<String, Object?> json) {
    const fields = {
      'id',
      'protocol',
      'libraryId',
      'scope',
      'deviceId',
      'sequence',
      'parents',
      'deleted',
      'payload',
      'pending',
      'resolves',
      'requires',
      'legacyCanonical',
    };
    if (!{1, syncProtocolVersion}.contains(json['protocol']) || json.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('Unsupported sync commit');
    }
    try {
      final result = SyncCommit.create(
        protocol: json['protocol'] as int,
        libraryId: json['libraryId'] as String,
        scope: json['scope'] as String,
        deviceId: json['deviceId'] as String,
        sequence: json['sequence'] as int,
        parents: (json['parents'] as List).cast<String>(),
        payload: (json['payload'] as Map).cast<String, Object?>(),
        deleted: json['deleted'] as bool,
        pending: ((json['pending'] ?? const []) as List).cast<String>(),
        resolves: ((json['resolves'] ?? const []) as List).cast<String>(),
        requires: ((json['requires'] ?? const {}) as Map).cast<String, String>(),
      );
      if (json.containsKey('legacyCanonical')) {
        final witness = json['legacyCanonical'] as String;
        if (result.protocol != 1 ||
            sha256.convert(utf8.encode(witness)).toString() != json['id'] ||
            !contentValueEquals(jsonDecode(witness), result._body())) {
          throw const FormatException('Invalid legacy commit witness');
        }
        // Numeric semantics must be portable even when the old spelling differs.
        syncDigest(result._body());
        return SyncCommit._(
          json['id'] as String,
          result.libraryId,
          result.scope,
          result.deviceId,
          result.sequence,
          result.parents,
          result.payload,
          result.deleted,
          result.pending,
          result.resolves,
          result.requires,
          result.protocol,
          witness,
        );
      }
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
    for (final c in _commits.values) {
      final history = ancestors(c.id)..remove(c.id);
      if (!history.containsAll([...c.pending, ...c.resolves]) ||
          c.pending.any((id) => _commits[id]?.parents.length != 1) ||
          (c.deleted && c.parents.any((id) => _commits[id]!.pending.isNotEmpty)) ||
          (c.parents.length == 1 &&
              !contentValueEquals(
                _commits[c.parents.single]!.pending.where((id) => !c.resolves.contains(id)).toList(),
                c.pending,
              )) ||
          c.pending.any(c.resolves.contains) ||
          (c.resolves.isNotEmpty &&
              (c.parents.length != 1 || !c.resolves.every(_commits[c.parents.single]!.pending.contains)))) {
        throw const FormatException('Invalid unresolved transaction ancestry');
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
