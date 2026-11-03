import 'dart:convert';

import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';
import 'sync_ledger_io.dart' if (dart.library.js_interop) 'sync_ledger_browser.dart';

import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:path/path.dart' as p;

/// One aggregate mutation. [local] is recovery data and never uploaded;
/// [shared] is the cloud projection. Null is an explicit deletion in both.
class SyncMutation {
  SyncMutation(this.scope, {required this.local, required this.shared, this.adopt, this.mergeParent});

  /// Adopt a received version, or create a merge with this additional parent.
  /// Both require the current head to remain an ancestor of the new version.
  final String? adopt, mergeParent;
  final String scope;
  final Map<String, Object?>? local, shared;
}

class LocalSyncSnapshot {
  LocalSyncSnapshot(this.scope, this.revision, this.value, this.commit);
  final String scope, revision;
  final Map<String, Object?>? value;
  final SyncCommit commit;
  bool get deleted => value == null;
}

class SyncRevisionChanged implements Exception {
  const SyncRevisionChanged(this.scope);
  final String scope;
  @override
  String toString() => 'Local sync revision changed: $scope';
}

/// A single-owner local write-ahead ledger, shared by library, vocabulary and
/// translation stores. Each atomic record contains local recovery snapshots AND
/// their newly generated cloud commits. There is no second outbox write.
///
/// Existing .mmset files remain projections. A projection failure after commit
/// is reported separately and must not make callers repeat a committed edit.
/// This ledger is local-only; transports consume [pending], never these files.
class FileSyncLedger {
  FileSyncLedger(this.root, {required this.libraryId, required this.deviceId});
  FileSyncLedger.browser({required String libraryId, required String deviceId})
    : this(browserRoot(), libraryId: libraryId, deviceId: deviceId);
  final Directory root;
  final String libraryId, deviceId;
  final _heads = <String, LocalSyncSnapshot>{};
  final _commits = <String, SyncCommit>{};
  final _outgoing = <String>{};
  final _issues = <String, Map<String, Object?>>{};
  final _projectionErrors = <String, Object>{};
  Map<String, Object> get projectionErrors => Map.unmodifiable(_projectionErrors);
  Future<void> _queue = Future.value();
  bool _loaded = false;
  int _sequence = 0;
  String? _last;

  Directory get _directory => Directory(p.join(root.path, '.foliarc-sync', 'local'));
  File get _identity => File(p.join(root.path, '.foliarc-sync', 'identity.json'));
  File get _delivered => File(p.join(root.path, '.foliarc-sync', 'delivered.json'));

  /// Reopening never invents a new library or device identity.
  static Future<FileSyncLedger?> restore(Directory root) async {
    final file = File(p.join(root.path, '.foliarc-sync', 'identity.json'));
    if (!await file.exists()) {
      if (await Directory(p.join(root.path, '.foliarc-sync', 'local')).exists()) {
        throw const FormatException('Missing sync identity for existing ledger');
      }
      return null;
    }
    final json = _map(jsonDecode(await file.readAsString()));
    if (json['version'] != 1 || json['libraryId'] is! String || json['deviceId'] is! String) {
      throw const FormatException('Unsupported sync identity');
    }
    return FileSyncLedger(root, libraryId: json['libraryId'] as String, deviceId: json['deviceId'] as String);
  }

  Future<T> _serial<T>(Future<T> Function() run) {
    final next = _queue.then((_) => run());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _load() async {
    final identity = {'version': 1, 'libraryId': libraryId, 'deviceId': deviceId};
    // Reuse the wire validator for bounded non-empty identities.
    SyncCommit.create(libraryId: libraryId, scope: 'identity', deviceId: deviceId, sequence: 1, payload: {});
    if (await _identity.exists()) {
      if (!contentValueEquals(jsonDecode(await _identity.readAsString()), identity)) {
        throw const FormatException('Sync library or device identity changed');
      }
    } else {
      if (await _directory.exists()) throw const FormatException('Missing sync identity for existing ledger');
      await _atomic(_identity, identity);
    }
    if (_loaded) return;
    final records = <Map<String, Object?>>[];
    if (await _directory.exists()) {
      await for (final file in _directory.list(followLinks: false)) {
        if (file is! File || file.path.endsWith('.tmp') || p.basename(file.path) == '.head') continue;
        final record = _map(jsonDecode(await file.readAsString()));
        final body = Map<String, Object?>.of(record)..remove('id');
        if (record['id'] != syncDigest(body) || p.basename(file.path) != '${record['id']}.json') {
          throw const FormatException('Local sync ledger digest mismatch');
        }
        if (!{1, 2}.contains(record['version']) ||
            record['sequence'] is! int ||
            record['changes'] is! List ||
            record['libraryId'] != libraryId ||
            record['deviceId'] != deviceId ||
            record.keys.any(
              (k) => !{
                'id',
                'version',
                'sequence',
                'previous',
                'libraryId',
                'deviceId',
                'changes',
                if (record['version'] == 2) ...['received', 'issues'],
              }.contains(k),
            )) {
          throw const FormatException('Unsupported local sync record');
        }
        records.add(record);
      }
    }
    records.sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
    final heads = <String, LocalSyncSnapshot>{}, commits = <String, SyncCommit>{};
    final outgoing = <String>{}, issues = <String, Map<String, Object?>>{};
    var sequence = 0;
    String? last;
    for (final record in records) {
      if (record['sequence'] != sequence + 1 || record['previous'] != last) {
        throw const FormatException('Incomplete or forked local sync history');
      }
      _replay(record, heads, commits, outgoing, issues);
      last = record['id'] as String;
      sequence++;
    }
    _heads
      ..clear()
      ..addAll(heads);
    _commits
      ..clear()
      ..addAll(commits);
    _outgoing
      ..clear()
      ..addAll(outgoing);
    _issues
      ..clear()
      ..addAll(issues);
    _sequence = sequence;
    _last = last;
    _loaded = true;
  }

  int _nextSequence(String scope, Map<String, SyncCommit> known) =>
      known.values
          .where((c) => c.scope == scope && c.deviceId == deviceId)
          .fold<int>(0, (n, c) => c.sequence > n ? c.sequence : n) +
      1;

  void _replay(
    Map<String, Object?> record,
    Map<String, LocalSyncSnapshot> heads,
    Map<String, SyncCommit> commits,
    Set<String> outgoing,
    Map<String, Map<String, Object?>> issues,
  ) {
    if (record['version'] == 2 && (record['received'] is! List || record['issues'] is! Map)) {
      throw const FormatException('Invalid receipt or diagnostic journal');
    }
    final received = record['version'] == 2 ? record['received'] as List : const [];
    final diagnostics = record['version'] == 2 ? _map(record['issues']) : <String, Object?>{};
    for (final raw in received) {
      final c = SyncCommit.fromJson(_map(raw));
      if (c.libraryId != libraryId || c.deviceId == deviceId && !commits.containsKey(c.id)) {
        throw const FormatException('Received commit belongs to another library or this installation');
      }
      commits[c.id] = c;
    }
    final changed = <String>{};
    for (final raw in record['changes'] as List) {
      final change = _map(raw);
      final scope = change['scope'];
      if (scope is! String ||
          !changed.add(scope) ||
          !change.containsKey('local') ||
          (change.containsKey('adopt') && change['adopt'] != true) ||
          change.keys.any((k) => !{'scope', 'local', 'commit', if (record['version'] == 2) 'adopt'}.contains(k))) {
        throw const FormatException('Invalid local sync mutation');
      }
      final previous = heads[scope]?.commit;
      final commit = change['commit'] == null ? previous : SyncCommit.fromJson(_map(change['commit']));
      if (commit == null ||
          commit.scope != scope ||
          commit.libraryId != libraryId ||
          (change['local'] == null) != commit.deleted) {
        throw const FormatException('Local snapshot/commit mismatch');
      }
      if (change['commit'] != null) {
        if (change['adopt'] == true) {
          if (!commits.containsKey(commit.id)) throw const FormatException('Adoption requires a receipt');
        } else {
          if (commit.deviceId != deviceId || commit.sequence != _nextSequence(scope, commits)) {
            throw const FormatException('Invalid local sync sequence');
          }
          if (record['version'] == 1 &&
              !contentValueEquals(commit.parents, previous == null ? <String>[] : [previous.id])) {
            throw const FormatException('Invalid local sync ancestry');
          }
          commits[commit.id] = commit;
          outgoing.add(commit.id);
        }
        // Quarantined received branches must not block local editing on the
        // already accepted lineage. Adoption still checks all known forks.
        late Map<String, SyncCommit> ancestry;
        try {
          ancestry = syncAncestry(commits, [commit.id], checkKnownForks: change['adopt'] == true);
        } on MissingSyncParents {
          throw const FormatException('Applied version is missing its ancestry');
        }
        if (previous != null && !ancestry.containsKey(previous.id)) {
          throw const FormatException('Applied version does not descend from the local head');
        }
      }
      heads[scope] = LocalSyncSnapshot(
        scope,
        record['id'] as String,
        change['local'] == null ? null : _freezeMap(_map(change['local'])),
        commit,
      );
    }
    for (final e in diagnostics.entries) {
      if (!commits.containsKey(e.key)) throw const FormatException('Unknown diagnostic input');
      if (e.value == null) {
        issues.remove(e.key);
      } else {
        issues[e.key] = _freezeMap(_map(e.value));
      }
    }
    if (changed.isEmpty && received.isEmpty && diagnostics.isEmpty) {
      throw const FormatException('Empty local sync transaction');
    }
  }

  /// Validate the whole transaction before its sole commit point. Receipt,
  /// materialization and clearing a resolved diagnostic can share one record.
  Future<void> _append(
    List<Map<String, Object?>> changes, {
    List<SyncCommit> received = const [],
    Map<String, Object?> issues = const {},
  }) async {
    final body = <String, Object?>{
      'version': 2,
      'libraryId': libraryId,
      'deviceId': deviceId,
      'sequence': _sequence + 1,
      'previous': _last,
      'changes': changes,
      'received': [for (final c in received) c.toJson()],
      'issues': issues,
    };
    final id = syncDigest(body), record = {'id': syncDigest(body), ...body};
    final heads = Map<String, LocalSyncSnapshot>.of(_heads), commits = Map<String, SyncCommit>.of(_commits);
    final outgoing = Set<String>.of(_outgoing), diagnostics = Map<String, Map<String, Object?>>.of(_issues);
    _replay(record, heads, commits, outgoing, diagnostics);
    await writeSyncLedgerRecord(p.join(_directory.path, '$id.json'), utf8.encode(jsonEncode(record)));
    _heads
      ..clear()
      ..addAll(heads);
    _commits
      ..clear()
      ..addAll(commits);
    _outgoing
      ..clear()
      ..addAll(outgoing);
    _issues
      ..clear()
      ..addAll(diagnostics);
    _sequence++;
    _last = id;
  }

  /// Receipt tolerates missing ancestors and keeps all branches, but does not
  /// materialize anything. Unknown commits using this device identity pause
  /// ingestion: an installation must never silently reuse another one's ID.
  Future<void> receive(Iterable<SyncCommit> incoming) {
    final inputs = incoming.toList();
    return _serial(() async {
      await _load();
      final added = <String, SyncCommit>{};
      for (final c in inputs) {
        if (c.libraryId != libraryId) throw const FormatException('Wrong sync library');
        if (!_commits.containsKey(c.id)) added[c.id] = c;
      }
      if (added.isNotEmpty) await _append([], received: added.values.toList());
    });
  }

  Future<Map<String, SyncCommit>> history() => _serial(() async {
    await _load();
    return Map.unmodifiable(_commits);
  });
  Future<Map<String, Map<String, Object?>>> issues() => _serial(() async {
    await _load();
    return Map.unmodifiable(_issues);
  });

  Future<void> recordIssue(SyncMergePlan plan, {required String scope, required String? expected}) => _serial(() async {
    await _load();
    if (_heads[scope]?.revision != expected) throw SyncRevisionChanged(scope);
    final value = plan.toJson();
    if (!contentValueEquals(_issues[plan.remote], value)) await _append([], issues: {plan.remote: value});
  });

  Future<Map<String, LocalSyncSnapshot>> snapshots() => _serial(() async {
    await _load();
    return Map.unmodifiable(_heads);
  });

  /// Preconditions and domain validation run in the same queue as the durable
  /// commit. A stale remote merge cannot overwrite a newer local revision.
  Future<Map<String, LocalSyncSnapshot>> commit(
    Iterable<SyncMutation> mutations, {
    Map<String, String?> expected = const {},
    void Function(Map<String, LocalSyncSnapshot>)? validate,
    bool Function(String scope)? tombstoneWhere,
    Iterable<String> resolved = const [],
  }) {
    // Freeze now, before waiting behind another asynchronous operation.
    final inputs = [
      for (final m in mutations)
        SyncMutation(
          m.scope,
          local: m.local == null ? null : _freezeMap(m.local!),
          shared: m.shared == null ? null : _freezeMap(m.shared!),
          adopt: m.adopt,
          mergeParent: m.mergeParent,
        ),
    ];
    final preconditions = Map<String, String?>.of(expected);
    final resolving = resolved.toSet();
    return _serial(() async {
      await _load();
      for (final entry in preconditions.entries) {
        if (_heads[entry.key]?.revision != entry.value) throw SyncRevisionChanged(entry.key);
      }
      validate?.call(Map.unmodifiable(_heads));
      final changes = <Map<String, Object?>>[];
      final scopes = <String>{};
      // Discover dependent scopes only after preceding writers have committed.
      // A caller-side snapshot would miss a child created while this waits.
      final mutations = [
        ...inputs,
        if (tombstoneWhere != null)
          for (final scope in _heads.keys)
            if (tombstoneWhere(scope)) SyncMutation(scope, local: null, shared: null),
      ];
      for (final input in mutations) {
        if (!scopes.add(input.scope) || (input.local == null) != (input.shared == null)) {
          throw const FormatException('Invalid sync mutation');
        }
        final previous = _heads[input.scope];
        final sharedChanged =
            input.adopt != null ||
            input.mergeParent != null ||
            previous == null ||
            previous.deleted != (input.shared == null) ||
            !contentValueEquals(previous.commit.payload, input.shared ?? <String, Object?>{});
        if (!sharedChanged && contentValueEquals(previous.value, input.local)) continue;
        if (input.adopt != null && input.mergeParent != null) throw const FormatException('Ambiguous sync advance');
        final adopted = input.adopt == null ? null : _commits[input.adopt];
        if (input.adopt != null &&
            (adopted == null ||
                adopted.deleted != (input.shared == null) ||
                !contentValueEquals(adopted.payload, input.shared ?? {}))) {
          throw const FormatException('Adopted payload mismatch');
        }
        final commit =
            adopted ??
            (sharedChanged
                ? SyncCommit.create(
                    libraryId: libraryId,
                    scope: input.scope,
                    deviceId: deviceId,
                    sequence: _nextSequence(input.scope, _commits),
                    parents: {
                      if (previous != null) previous.commit.id,
                      if (input.mergeParent != null) input.mergeParent!,
                    }.toList(),
                    payload: input.shared ?? {},
                    deleted: input.shared == null,
                  )
                : null);
        changes.add({
          'scope': input.scope,
          'local': input.local,
          'commit': commit?.toJson(),
          if (adopted != null) 'adopt': true,
        });
      }
      final cleared = <String, Object?>{
        for (final id in resolving)
          if (_issues.containsKey(id)) id: null,
      };
      if (changes.isNotEmpty || cleared.isNotEmpty) await _append(changes, issues: cleared);
      return Map.unmodifiable(_heads);
    });
  }

  /// Best-effort materialization is observable, but not the transaction result.
  Future<void> project(String key, Future<void> Function() write) async {
    try {
      await write();
      _projectionErrors.remove(key);
    } catch (error) {
      _projectionErrors[key] = error;
    }
  }

  Future<List<SyncCommit>> pending() => _serial(() async {
    await _load();
    final delivered = await _readDelivered();
    return List.unmodifiable(_commits.values.where((c) => _outgoing.contains(c.id) && !delivered.contains(c.id)));
  });

  Future<void> acknowledge(Iterable<String> ids) {
    final requested = ids.toSet();
    return _serial(() async {
      await _load();
      if (!requested.every(_outgoing.contains)) throw const FormatException('Unknown delivered commit');
      final delivered = await _readDelivered()
        ..addAll(requested);
      await _atomic(_delivered, {'version': 1, 'ids': delivered.toList()..sort()});
    });
  }

  Future<Set<String>> _readDelivered() async {
    if (!await _delivered.exists()) return {};
    final json = _map(jsonDecode(await _delivered.readAsString()));
    if (json['version'] != 1 || json['ids'] is! List || (json['ids'] as List).any((id) => !_outgoing.contains(id))) {
      throw const FormatException('Invalid sync delivery state');
    }
    return (json['ids'] as List).cast<String>().toSet();
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) throw const FormatException('Expected sync object');
    return value.cast<String, Object?>();
  }

  static Map<String, Object?> _freezeMap(Map<String, Object?> value) {
    Object? freeze(Object? v) {
      if (v is Map) return Map<String, Object?>.unmodifiable(v.map((k, value) => MapEntry(k as String, freeze(value))));
      if (v is List) return List<Object?>.unmodifiable(v.map(freeze));
      if (v == null || v is String || v is bool || v is num && v.isFinite) return v;
      throw const FormatException('Non-JSON recovery snapshot');
    }

    return freeze(value) as Map<String, Object?>;
  }

  static Future<void> _atomic(File file, Object json) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsBytes(utf8.encode(jsonEncode(json)), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        /* Original error wins. */
      }
      rethrow;
    }
  }
}
