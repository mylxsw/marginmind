import 'dart:async';
import 'dart:convert';

import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';

import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:path/path.dart' as p;

import 'file_sync_ledger.dart';

/// Application-wide vocabulary; saves are serialized and published only after
/// flush + rename. Unsupported or corrupt source files are never overwritten.
class FileVocabularyStore
    implements
        VocabularyRepository,
        AtomicVocabularyRepository,
        VocabularySyncRepository,
        VocabularyEditRepository,
        VocabularyIdentityRepository {
  // Public option for a private field that may be restored lazily.
  // ignore: prefer_initializing_formals
  FileVocabularyStore(this.root, {FileSyncLedger? sync}) : _sync = sync;
  FileVocabularyStore.browser({FileSyncLedger? sync}) : this(browserRoot(), sync: sync);
  final Directory root;
  FileSyncLedger? _sync;
  bool _syncChecked = false;
  String? _revision;
  Map<String, LocalSyncSnapshot> _heads = {};
  bool _disposed = false;
  final _leases = <_VocabularyLease>{};
  Object? _releaseError;
  bool _protected(String scope) => _leases.any((lease) => scope == 'words/${lease.entryId.substring(5)}');
  @override
  ContentEditLease protectVocabulary(String entryId) {
    if (!entryId.startsWith('word-')) return _VocabularyLease(this, entryId, Future.value());
    final lease = _VocabularyLease(
      this,
      entryId,
      _serial(() async {
        await _read();
      }),
    );
    _leases.add(lease);
    if (_entries != null) _changes.add(_entries!);
    return lease;
  }

  @override
  Future<String?> resolveVocabularyEntryId(String id) => _serial(() async {
    final entries = await _read();
    if (entries.any((e) => e.id == id)) return id;
    final matches = _heads.values
        .where((h) => h.scope.startsWith('words/'))
        .map((h) => VocabularyWord.fromJson(h.value!))
        .where((w) => w.alive && w.aliases.contains(id))
        .toList();
    return matches.length == 1 ? matches.single.entryId : null;
  });

  File get _file => File(p.join(root.path, 'vocabulary.json'));
  List<VocabularyEntry>? _entries;
  Future<void> _queue = Future.value();
  final _changes = StreamController<List<VocabularyEntry>>.broadcast();

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<List<VocabularyEntry>> _read() async {
    if (!_syncChecked) {
      _sync ??= await FileSyncLedger.restore(root);
      if (_sync != null && p.normalize(p.absolute(_sync!.root.path)) != p.normalize(p.absolute(root.path))) {
        throw ArgumentError('Sync ledger must belong to this library');
      }
      _syncChecked = true;
    }
    try {
      final snapshot = (await _sync?.snapshots())?['vocabulary'];
      if (snapshot?.deleted == true) throw const FormatException('Vocabulary aggregate cannot be deleted');
      final j =
          snapshot?.value ??
          (await _file.exists()
              ? jsonDecode(await _file.readAsString()) as Map
              : {'format': 1, 'entries': <Object?>[]});
      if (j['format'] is! int || j['format'] != 1) {
        throw const FormatException('Unsupported vocabulary format');
      }
      final entries = (j['entries'] as List).map((e) => VocabularyEntry.fromJson((e as Map).cast())).toList();
      _validate(entries, identities: _sync == null || j['syncWords'] == 1);
      if (_sync case final sync?) {
        _heads = await sync.snapshots();
        if (snapshot?.value?['syncWords'] != 1) {
          await _seed(entries);
        }
        final current = (await sync.snapshots())['vocabulary']!;
        _revision = current.revision;
        _heads = await sync.snapshots();
        await sync.project(_file.path, () => _write(current.value!));
        return _materialized(_heads);
      }
      return List.unmodifiable(entries);
    } on TypeError catch (error) {
      throw FormatException('Invalid vocabulary: $error');
    } on ArgumentError catch (error) {
      throw FormatException('Invalid vocabulary: $error');
    }
  }

  void _validate(List<VocabularyEntry> entries, {bool identities = true}) {
    final ids = <String>{}, keys = <(String, String)>{};
    for (final e in entries) {
      if (!ids.add(e.id) ||
          (identities && !keys.add((_sync == null ? e.language : vocabularyLanguage(e.language), e.key)))) {
        throw const FormatException('Duplicate vocabulary entry');
      }
    }
  }

  @override
  Future<List<VocabularyEntry>> load() => _serial(() async => _entries ??= await _read());
  @override
  Future<void> save(List<VocabularyEntry> entries) {
    final snapshot = List<VocabularyEntry>.unmodifiable(entries);
    return _serial(() async {
      final observed = _entries;
      final current = await _read();
      if (_sync != null &&
          !contentValueEquals(_json(current), _json(snapshot)) &&
          _heads.values
              .where((h) => h.scope.startsWith('words/'))
              .any((h) => VocabularyWord.fromJson(h.value!).writes.values.any((v) => v.isNotEmpty))) {
        throw StateError('Synced vocabulary edits require updateVocabulary');
      }
      if (_sync != null && observed != null && !contentValueEquals(_json(observed), _json(current))) {
        throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      }
      await _save(current, snapshot);
    });
  }

  @override
  Future<VocabularyMutation> updateVocabulary(
    List<VocabularyEntry> Function(List<VocabularyEntry>) edit, {
    Map<String, String> expected = const {},
  }) => _serial(() async {
    while (true) {
      final before = await _read();
      for (final e in expected.entries) {
        if (!e.key.startsWith('word-') || _heads['words/${e.key.substring(5)}']?.revision != e.value) {
          throw const ContentSyncActionException(ContentSyncActionFailure.stale);
        }
      }
      final after = edit(before);
      try {
        await _save(before, after);
        return VocabularyMutation(
          before,
          _entries!,
          versions: {
            for (final h in _heads.values.where((h) => h.scope.startsWith('words/')))
              'word-${h.scope.substring(6)}': h.revision,
          },
        );
      } on SyncRevisionChanged {
        continue;
      }
    }
  });

  List<Object?> _json(Iterable<VocabularyEntry> entries) => entries.map((e) => e.toJson()).toList();
  List<VocabularyEntry> _materialized(Map<String, LocalSyncSnapshot> heads) {
    final entries = <VocabularyEntry>[];
    for (final e in heads.entries.where((e) => e.key.startsWith('words/'))) {
      final word = VocabularyWord.fromJson(e.value.value!);
      if (word.entry case final entry?) entries.add(entry);
    }
    entries.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(entries);
  }

  Future<void> _baselines(Iterable<VocabularyEntry> entries) async {
    final sync = _sync!;
    for (final e in entries) {
      final base = vocabularyBaseline(sync.libraryId, e.language, e.term);
      if ((await sync.snapshots()).containsKey(base.scope)) continue;
      await sync.receive([base]);
      try {
        await sync.commit(
          [SyncMutation(base.scope, local: base.payload, shared: base.payload, adopt: base.id)],
          expected: {base.scope: null},
        );
      } on SyncRevisionChanged {
        /* Another writer installed the baseline. */
      }
    }
  }

  Future<void> _seed(List<VocabularyEntry> entries) async {
    await _baselines(entries);
    final heads = await _sync!.snapshots();
    final words = <String, VocabularyWord>{};
    final prepared = Map<String, LocalSyncSnapshot>.of(heads);
    for (final e in entries) {
      final scope = 'words/${vocabularyIdentity(e.language, e.term)}';
      final current = words[scope] ?? VocabularyWord.fromJson(heads[scope]!.value!);
      final imported = VocabularyWord.empty(
        e.language,
        e.term,
      ).edit(null, e, deviceId: _sync!.deviceId, operation: newId());
      words[scope] = current.join(imported);
    }
    final mutations = <SyncMutation>[];
    for (final e in words.entries) {
      mutations.add(SyncMutation(e.key, local: e.value.toJson(), shared: e.value.toJson()));
      final head = heads[e.key]!;
      prepared[e.key] = LocalSyncSnapshot(e.key, head.revision, e.value.toJson(), head.commit);
    }
    await _commit(mutations, prepared, heads);
  }

  Future<void> _commit(
    List<SyncMutation> mutations,
    Map<String, LocalSyncSnapshot> prepared,
    Map<String, LocalSyncSnapshot> observed, {
    Iterable<String> resolved = const [],
    String? remoteScope,
  }) async {
    final entries = _materialized(prepared);
    final local = <String, Object?>{'format': 1, 'syncWords': 1, 'entries': _json(entries)};
    final shared =
        observed['vocabulary']?.commit.payload ?? <String, Object?>{'kind': 'vocabulary-index', 'version': 1};
    final heads = await _sync!.commit(
      [...mutations, SyncMutation('vocabulary', local: local, shared: shared)],
      expected: {
        'vocabulary': observed['vocabulary']?.revision,
        for (final m in mutations) m.scope: observed[m.scope]?.revision,
      },
      resolved: resolved,
      validate: (_) {
        if (remoteScope != null && _protected(remoteScope)) throw const _VocabularyDeferred();
      },
    );
    _heads = heads;
    _revision = heads['vocabulary']!.revision;
    await _sync!.project(_file.path, () => _write(local));
    _entries = entries;
    if (!_disposed) _changes.add(entries);
  }

  Future<void> _save(List<VocabularyEntry> before, List<VocabularyEntry> after) async {
    _validate(after);
    if (_sync == null) {
      await _write({'format': 1, 'entries': _json(after)});
      _entries = List.unmodifiable(after);
      _changes.add(_entries!);
      return;
    }
    await _baselines(after);
    final heads = await _sync!.snapshots();
    // _read observed the index before the edit callback. Do not silently accept
    // an intervening remote publication while creating missing baselines.
    if (heads['vocabulary']?.revision != _revision) throw const SyncRevisionChanged('vocabulary');
    final old = {for (final e in before) vocabularyIdentity(e.language, e.term): e};
    final next = {for (final e in after) vocabularyIdentity(e.language, e.term): e};
    final prepared = Map<String, LocalSyncSnapshot>.of(heads), mutations = <SyncMutation>[];
    for (final key in {...old.keys, ...next.keys}) {
      if (contentValueEquals(old[key]?.toJson(), next[key]?.toJson())) continue;
      final scope = 'words/$key', head = heads['words/$key']!;
      final word = VocabularyWord.fromJson(head.value!)
          .edit(old[key], next[key], deviceId: _sync!.deviceId, operation: newId());
      mutations.add(SyncMutation(scope, local: word.toJson(), shared: word.toJson()));
      prepared[scope] = LocalSyncSnapshot(scope, head.revision, word.toJson(), head.commit);
    }
    await _commit(mutations, prepared, heads);
  }

  Future<FileSyncLedger?> get syncLedger async {
    await load();
    return _sync;
  }

  Future<void> receiveSync(Iterable<SyncCommit> incoming) async {
    await load();
    final sync = _sync;
    if (sync == null) throw StateError('Sync is not enabled');
    await sync.receive(incoming);
    await reconcileSync();
  }

  Future<void> reconcileSync() => _serial(() async {
    await _read();
    final sync = _sync;
    if (sync == null) return;
    final known = await sync.history();
    // Deterministic empty baselines contain no user data. Reconstruct only the
    // exact published baseline; never invent a baseline for unknown histories.
    for (final c in known.values.where((c) => c.scope.startsWith('words/'))) {
      try {
        final w = VocabularyWord.fromJson(c.payload);
        if (w.scope == c.scope) await sync.receive([vocabularyBaseline(sync.libraryId, w.language, w.key)]);
      } on FormatException {
        /* Retain and diagnose malformed input below. */
      }
    }
    final history = await sync.history();
    int depth(SyncCommit c) {
      try {
        return syncAncestry(history, [c.id]).length;
      } catch (_) {
        return history.length + 1;
      }
    }

    final inputs = history.values.where((c) => c.scope.startsWith('words/') && c.deviceId != sync.deviceId).toList()
      ..sort((a, b) {
        final n = depth(b).compareTo(depth(a));
        return n == 0 ? a.id.compareTo(b.id) : n;
      });
    for (final remote in inputs) {
      while (true) {
        final heads = await sync.snapshots(), head = heads[remote.scope];
        final graph = await sync.history();
        final plan = planVocabularyWord(graph, remote: remote.id, local: head?.commit.id);
        try {
          if (plan.state == SyncMergeState.unchanged) {
            await sync.commit([], expected: {remote.scope: head?.revision}, resolved: [remote.id]);
            break;
          }
          if (plan.state != SyncMergeState.ready) {
            await sync.recordIssue(plan, scope: remote.scope, expected: head?.revision);
            break;
          }
          if (_protected(remote.scope)) throw const _VocabularyDeferred();
          final prepared = Map<String, LocalSyncSnapshot>.of(heads);
          prepared[remote.scope] = LocalSyncSnapshot(remote.scope, head?.revision ?? '', plan.payload!, remote);
          await _commit(
            [
              SyncMutation(
                remote.scope,
                local: plan.payload,
                shared: plan.payload,
                adopt: plan.adopt ? remote.id : null,
                mergeParent: plan.adopt ? null : remote.id,
              ),
            ],
            prepared,
            heads,
            resolved: syncAncestry(graph, [remote.id]).keys,
            remoteScope: remote.scope,
          );
          break;
        } on SyncRevisionChanged {
          continue;
        } on _VocabularyDeferred {
          try {
            await sync.recordIssue(
              SyncMergePlan(
                remote: remote.id,
                local: head?.commit.id,
                state: SyncMergeState.waiting,
                reason: 'editing',
              ),
              scope: remote.scope,
              expected: head?.revision,
            );
          } on SyncRevisionChanged {
            continue;
          }
          break;
        }
      }
    }
    _entries = await _read();
    _releaseError = null;
    _changes.add(_entries!);
  });

  @override
  Future<VocabularySyncState> vocabularySyncState() => _serial(() async {
    await _read();
    final sync = _sync;
    if (sync == null) return VocabularySyncState();
    final conflicts = <VocabularySyncConflict>[];
    for (final head in _heads.values.where((h) => h.scope.startsWith('words/'))) {
      final word = VocabularyWord.fromJson(head.value!);
      for (final field in word.conflicts) {
        conflicts.add(
          VocabularySyncConflict(
            entryId: word.entryId,
            term: word.entry?.term ?? word.key,
            revision: head.revision,
            field: VocabularySyncField.values.byName(field),
            choices: [
              for (final e in word.alternatives(field).entries)
                VocabularySyncChoice(
                  e.key,
                  _describe(field, e.value),
                  deleted: field == 'alive' ? e.value == false : null,
                ),
            ],
          ),
        );
      }
    }
    final history = await sync.history(), problems = <ContentSyncProblem>{};
    for (final e in (await sync.issues()).entries) {
      if (history[e.key]?.scope.startsWith('words/') != true) continue;
      problems.add(switch (e.value['reason']) {
        'missingParents' => ContentSyncProblem.missingHistory,
        'editing' => ContentSyncProblem.editing,
        'noBase' => ContentSyncProblem.unrelatedHistory,
        'multipleBases' => ContentSyncProblem.ambiguousHistory,
        'differentScope' => ContentSyncProblem.unsupported,
        _ => ContentSyncProblem.invalidHistory,
      });
    }
    if (history.values.any(
      (c) => c.scope == 'vocabulary' && c.deviceId != sync.deviceId && c.payload['kind'] != 'vocabulary-index',
    )) {
      problems.add(ContentSyncProblem.unsupported);
    }
    return VocabularySyncState(
      enabled: true,
      conflicts: conflicts,
      editingEntries: _leases.map((l) => l.entryId),
      retryFailed: _releaseError != null,
      problems: problems,
      repairNeeded: sync.projectionErrors.containsKey(_file.path),
    );
  });

  String _describe(String field, Object? value) => switch (field) {
    'senses' => (value as List).map((v) => '${(v as Map)['partOfSpeech']} ${v['meaning']}').join('\n'),
    'forms' => (value as List).join(', '),
    _ => value?.toString() ?? '',
  };

  @override
  Stream<VocabularySyncState> watchVocabularySync() => watch().asyncMap((_) => vocabularySyncState());
  @override
  Future<void> retryVocabularySync() => reconcileSync();
  @override
  Future<void> chooseVocabulary(
    String entryId,
    VocabularySyncField field,
    String choice, {
    required String expectedRevision,
  }) => _serial(() async {
    await _read();
    final sync = _sync;
    if (sync == null || !entryId.startsWith('word-')) {
      throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    }
    final scope = 'words/${entryId.substring(5)}';
    if (_protected(scope)) throw const ContentSyncActionException(ContentSyncActionFailure.editing);
    final heads = await sync.snapshots(), head = heads[scope];
    if (head == null || head.revision != expectedRevision) {
      throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    }
    final word = VocabularyWord.fromJson(head.value!);
    if (!word.conflicts.contains(field.name)) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    final next = word.choose(field.name, choice, deviceId: sync.deviceId, operation: newId());
    final prepared = Map<String, LocalSyncSnapshot>.of(heads)
      ..[scope] = LocalSyncSnapshot(scope, head.revision, next.toJson(), head.commit);
    try {
      await _commit(
        [SyncMutation(scope, local: next.toJson(), shared: next.toJson())],
        prepared,
        heads,
        remoteScope: scope,
      );
    } on _VocabularyDeferred {
      throw const ContentSyncActionException(ContentSyncActionFailure.editing);
    } on SyncRevisionChanged {
      throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    }
  });

  Future<void> _write(Map value) async {
    final bytes = utf8.encode(jsonEncode(value));
    await root.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(_file.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        /* Preserve original failure. */
      }
      rethrow;
    }
  }

  @override
  Stream<List<VocabularyEntry>> watch() => Stream.multi((out) {
    StreamSubscription<List<VocabularyEntry>>? sub;
    var cancelled = false;
    out.onCancel = () async {
      cancelled = true;
      await sub?.cancel();
    };
    _serial(() async {
      try {
        final entries = _entries ??= await _read();
        if (cancelled) return;
        sub = _changes.stream.listen(out.add, onError: out.addError, onDone: out.close);
        out.add(entries);
      } catch (error, stack) {
        if (!cancelled) out.addError(error, stack);
      }
    });
  });

  /// Wait for all queued reads and writes.
  Future<void> flush() => _queue;

  /// Flush and release stream resources when the owning scope closes.
  Future<void> dispose() async {
    await flush();
    _disposed = true;
    await _changes.close();
  }
}

class _VocabularyDeferred implements Exception {
  const _VocabularyDeferred();
}

class _VocabularyLease implements ContentEditLease {
  _VocabularyLease(this.owner, this.entryId, this.ready);
  final FileVocabularyStore owner;
  final String entryId;
  @override
  final Future<void> ready;
  Future<void>? _closing;
  @override
  Future<void> release() => _closing ??= _release();
  Future<void> _release() async {
    await owner._serial(() async {
      owner._leases.remove(this);
    });
    if (owner._disposed) return;
    try {
      await owner.reconcileSync();
    } catch (error) {
      owner._releaseError = error;
      if (owner._entries != null) owner._changes.add(owner._entries!);
    }
  }
}
