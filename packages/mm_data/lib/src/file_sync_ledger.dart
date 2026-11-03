import 'dart:convert';

import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';
import 'sync_ledger_io.dart' if (dart.library.js_interop) 'sync_ledger_browser.dart';

import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:path/path.dart' as p;

/// One aggregate mutation. [local] is recovery data and never uploaded;
/// [shared] is the cloud projection. Null is an explicit deletion in both.
class SyncMutation {
  SyncMutation(this.scope, {required this.local, required this.shared});
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
        if (record['version'] != 1 ||
            record['sequence'] is! int ||
            record['changes'] is! List ||
            record['libraryId'] != libraryId ||
            record['deviceId'] != deviceId ||
            record.keys.any(
              (k) => !{'id', 'version', 'sequence', 'previous', 'libraryId', 'deviceId', 'changes'}.contains(k),
            )) {
          throw const FormatException('Unsupported local sync record');
        }
        records.add(record);
      }
    }
    records.sort((a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int));
    final heads = <String, LocalSyncSnapshot>{}, commits = <String, SyncCommit>{};
    var sequence = 0;
    String? last;
    for (final record in records) {
      if (record['sequence'] != sequence + 1 || record['previous'] != last) {
        throw const FormatException('Incomplete or forked local sync history');
      }
      final changed = <String>{};
      for (final raw in record['changes'] as List) {
        final change = _map(raw);
        final scope = change['scope'];
        if (scope is! String ||
            !changed.add(scope) ||
            !change.containsKey('local') ||
            change.keys.any((k) => !{'scope', 'local', 'commit'}.contains(k))) {
          throw const FormatException('Invalid local sync mutation');
        }
        final previous = heads[scope]?.commit;
        final commit = change['commit'] == null ? previous : SyncCommit.fromJson(_map(change['commit']));
        if (commit == null ||
            commit.scope != scope ||
            commit.libraryId != libraryId ||
            commit.deviceId != deviceId ||
            (change['local'] == null) != commit.deleted) {
          throw const FormatException('Local snapshot/commit mismatch');
        }
        if (change['commit'] != null) {
          if (commit.sequence != (previous?.sequence ?? 0) + 1 ||
              !contentValueEquals(commit.parents, previous == null ? <String>[] : [previous.id])) {
            throw const FormatException('Invalid local sync ancestry');
          }
          commits[commit.id] = commit;
        }
        heads[scope] = LocalSyncSnapshot(
          scope,
          record['id'] as String,
          change['local'] == null ? null : _freezeMap(_map(change['local'])),
          commit,
        );
      }
      if (changed.isEmpty) throw const FormatException('Empty local sync transaction');
      last = record['id'] as String;
      sequence++;
    }
    _heads
      ..clear()
      ..addAll(heads);
    _commits
      ..clear()
      ..addAll(commits);
    _sequence = sequence;
    _last = last;
    _loaded = true;
  }

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
  }) {
    // Freeze now, before waiting behind another asynchronous operation.
    final inputs = [
      for (final m in mutations)
        SyncMutation(
          m.scope,
          local: m.local == null ? null : _freezeMap(m.local!),
          shared: m.shared == null ? null : _freezeMap(m.shared!),
        ),
    ];
    final preconditions = Map<String, String?>.of(expected);
    return _serial(() async {
      await _load();
      for (final entry in preconditions.entries) {
        if (_heads[entry.key]?.revision != entry.value) throw SyncRevisionChanged(entry.key);
      }
      validate?.call(Map.unmodifiable(_heads));
      final changes = <Map<String, Object?>>[], newCommits = <String, SyncCommit>{};
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
            previous == null ||
            previous.deleted != (input.shared == null) ||
            !contentValueEquals(previous.commit.payload, input.shared ?? <String, Object?>{});
        if (!sharedChanged && contentValueEquals(previous.value, input.local)) continue;
        final commit = sharedChanged
            ? SyncCommit.create(
                libraryId: libraryId,
                scope: input.scope,
                deviceId: deviceId,
                sequence: (previous?.commit.sequence ?? 0) + 1,
                parents: previous == null ? [] : [previous.commit.id],
                payload: input.shared ?? {},
                deleted: input.shared == null,
              )
            : null;
        if (commit != null) newCommits[commit.id] = commit;
        changes.add({'scope': input.scope, 'local': input.local, 'commit': commit?.toJson()});
      }
      if (changes.isEmpty) return Map.unmodifiable(_heads);
      final body = <String, Object?>{
        'version': 1,
        'libraryId': libraryId,
        'deviceId': deviceId,
        'sequence': _sequence + 1,
        'previous': _last,
        'changes': changes,
      };
      final id = syncDigest(body);
      await writeSyncLedgerRecord(p.join(_directory.path, '$id.json'), utf8.encode(jsonEncode({'id': id, ...body})));
      // Nothing after this point may turn a durable commit into an edit failure.
      for (final change in changes) {
        final scope = change['scope'] as String;
        final commit = change['commit'] == null ? _heads[scope]!.commit : newCommits[(change['commit'] as Map)['id']]!;
        _heads[scope] = LocalSyncSnapshot(scope, id, change['local'] as Map<String, Object?>?, commit);
      }
      _commits.addAll(newCommits);
      _sequence++;
      _last = id;
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
    return List.unmodifiable(_commits.values.where((c) => !delivered.contains(c.id)));
  });

  Future<void> acknowledge(Iterable<String> ids) {
    final requested = ids.toSet();
    return _serial(() async {
      await _load();
      if (!requested.every(_commits.containsKey)) throw const FormatException('Unknown delivered commit');
      final delivered = await _readDelivered()
        ..addAll(requested);
      await _atomic(_delivered, {'version': 1, 'ids': delivered.toList()..sort()});
    });
  }

  Future<Set<String>> _readDelivered() async {
    if (!await _delivered.exists()) return {};
    final json = _map(jsonDecode(await _delivered.readAsString()));
    if (json['version'] != 1 || json['ids'] is! List || (json['ids'] as List).any((id) => !_commits.containsKey(id))) {
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
