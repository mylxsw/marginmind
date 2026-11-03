part of 'file_library_store.dart';

extension _FileLibraryFolders on FileLibraryStore {
  static const _folderQueue = '@folders';

  Map<String, Object?> _folderIndex(Iterable<Folder> folders) => {
    'folders': [for (final folder in folders) sharedFolder(folder)],
  };

  String _folderRevision(Folder folder) => syncDigest(sharedFolder(folder));

  Future<LibraryOrganization> _organization() async {
    await _ensureLoaded();
    final sync = _sync;
    if (sync == null) {
      return LibraryOrganization(
        placements: {for (final record in _sets.values) record.id: record.folderId},
        entries: [
          for (final folder in _folders) FolderEntry(id: folder.id, revision: _folderRevision(folder), folder: folder),
        ],
      );
    }
    final heads = await sync.snapshots(), history = await sync.history();
    final problems = <String, Set<ContentSyncProblem>>{};
    for (final issue in (await sync.issues()).entries) {
      final scope = history[issue.key]?.scope;
      if (scope == null || !scope.startsWith('folders/')) continue;
      (problems[scope] ??= {}).add(switch (issue.value['reason']) {
        'missingParents' => ContentSyncProblem.missingHistory,
        'noBase' => ContentSyncProblem.unrelatedHistory,
        'multipleBases' => ContentSyncProblem.ambiguousHistory,
        'concurrentResolutions' => ContentSyncProblem.concurrentChoices,
        'deleteEdit' => ContentSyncProblem.deletion,
        _ => ContentSyncProblem.invalidHistory,
      });
    }
    return LibraryOrganization(
      placements: {for (final record in _sets.values) record.id: record.folderId},
      syncEnabled: true,
      queued: (await sync.pending()).where((c) => c.scope.startsWith('folders/')).length,
      repairNeeded: sync.projectionErrors.containsKey(_libraryFile.path),
      entries: [
        for (final scope in {...heads.keys.where((s) => s.startsWith('folders/')), ...problems.keys})
          if (heads[scope]?.deleted == false || problems.containsKey(scope))
            FolderEntry(
              id: scope.substring(8),
              revision: heads[scope]?.revision ?? '',
              folder: heads[scope]?.value == null ? null : folderFromSync(scope.substring(8), heads[scope]!.value!),
              choices: [
                for (final id in heads[scope]?.commit.pending ?? const <String>[])
                  FolderChoice(transaction: id, name: folderFromSync(scope.substring(8), history[id]!.payload).name),
              ],
              problems: problems[scope] ?? const {},
            ),
      ],
    );
  }

  Stream<LibraryOrganization> _watchOrganization() {
    late StreamController<LibraryOrganization> out;
    final subscriptions = <StreamSubscription<void>>[];
    var cancelled = false;
    Future<void> refresh = Future.value();
    void changed([void _]) {
      refresh = refresh.then((_) async {
        if (cancelled) return;
        try {
          final state = await _organization();
          if (!cancelled) out.add(state);
        } catch (error, stack) {
          if (!cancelled) out.addError(error, stack);
        }
      });
    }

    out = StreamController<LibraryOrganization>(
      onListen: () async {
        try {
          await _ensureLoaded();
          if (cancelled) return;
          subscriptions.add(
            _libraryChanges.stream.listen(
              changed,
              onDone: () {
                if (!cancelled) {
                  cancelled = true;
                  out.close();
                }
              },
            ),
          );
          if (_sync case final sync?) subscriptions.add(sync.changes.listen(changed));
          changed();
        } catch (error, stack) {
          if (!cancelled) out.addError(error, stack);
        }
      },
      onCancel: () async {
        cancelled = true;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return out.stream;
  }

  Future<Folder> _createFolder(String name) async {
    await _ensureLoaded();
    final id = _newId();
    final folder = folderFromSync(id, {'id': id, 'name': name.trim()});
    await _queueWrite(_folderQueue, () async {
      final heads = await _sync?.snapshots();
      if (_folders.any((f) => f.id == id) || heads?.containsKey('folders/$id') == true) {
        throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      }
      await _saveFolder(id, folder, heads: heads);
    });
    return folder;
  }

  Future<void> _changeFolder(String id, String? name, {required String expectedRevision}) async {
    await _ensureLoaded();
    await _queueWrite(_folderQueue, () async {
      final heads = await _sync?.snapshots();
      final old = _folders.where((f) => f.id == id).firstOrNull;
      final revision = heads == null ? (old == null ? null : _folderRevision(old)) : heads['folders/$id']?.revision;
      if (old == null || revision != expectedRevision) {
        throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      }
      if (name == null && (heads?['folders/$id']?.commit.pending.isNotEmpty ?? false)) {
        throw const ContentSyncActionException(ContentSyncActionFailure.invalidCandidate);
      }
      final folder = name == null ? null : folderFromSync(id, {'id': id, 'name': name.trim()});
      await _saveFolder(id, folder, heads: heads);
    });
  }

  /// Both the folder decision and its local index are one recovery record.
  /// The legacy library stream remains immutable; only per-folder streams sync.
  Future<void> _saveFolder(
    String id,
    Folder? folder, {
    Map<String, LocalSyncSnapshot>? heads,
    SyncMergePlan? plan,
    Iterable<String> resolved = const [],
    List<String> resolves = const [],
  }) async {
    final folders = [
      for (final old in _folders)
        if (old.id != id) old,
      ?folder,
    ]..sort((a, b) => a.id.compareTo(b.id));
    final value = _folderIndex(folders);
    final sync = _sync;
    if (sync == null) {
      await FileLibraryStore._atomicWrite(_libraryFile, utf8.encode(jsonEncode(value)));
    } else {
      final scope = 'folders/$id';
      _syncSnapshots = await sync.commit(
        [
          SyncMutation(
            scope,
            local: folder == null ? null : sharedFolder(folder),
            shared: folder == null ? null : sharedFolder(folder),
            adopt: plan?.adopt == true ? plan!.remote : null,
            mergeParent: plan != null && !plan.adopt ? plan.remote : null,
            pending: plan?.pending,
            resolves: resolves,
          ),
          SyncMutation('library', local: value, shared: heads!['library']!.commit.payload),
        ],
        expected: {scope: heads[scope]?.revision, 'library': heads['library']!.revision},
        resolved: resolved,
      );
      await sync.project(
        _libraryFile.path,
        () => FileLibraryStore._atomicWrite(_libraryFile, utf8.encode(jsonEncode(value))),
      );
    }
    _folders = folders;
    _libraryChanges.add(null);
  }

  Future<void> _moveStudySet(String id, String? folderId, {required String? expectedFolderId}) async {
    await _ensureLoaded();
    // Lock the folder registry before the set: a deletion cannot slip between
    // destination validation and the set commit. Inbound uses the same queue.
    await _queueWrite(
      _folderQueue,
      () => _queueWrite(id, () async {
        final record = _require(id);
        if (record.folderId != expectedFolderId) {
          throw const ContentSyncActionException(ContentSyncActionFailure.stale);
        }
        if (folderId != null && !_folders.any((f) => f.id == folderId)) {
          throw const ContentSyncActionException(ContentSyncActionFailure.stale);
        }
        final next = record.copyWith(folderId: folderId, clearFolder: folderId == null);
        await _saveRecord(next);
        _sets[id] = next;
        _libraryChanges.add(null);
      }),
    );
  }

  Future<void> _chooseFolderName(
    String id,
    String transaction, {
    required String expectedRevision,
    required bool useCandidate,
  }) async {
    await _ensureLoaded();
    final sync = _sync;
    if (sync == null) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    await _queueWrite(_folderQueue, () async {
      final heads = await sync.snapshots(), current = heads['folders/$id'];
      if (current?.revision != expectedRevision || current == null || !current.commit.pending.contains(transaction)) {
        throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      }
      final history = await sync.history(), candidate = history[transaction]!;
      final payload = useCandidate
          ? chooseSyncTransaction(history[candidate.parents.single]!.payload, candidate.payload, current.commit.payload)
          : current.commit.payload;
      await _saveFolder(id, folderFromSync(id, payload), heads: heads, resolves: [transaction]);
    });
  }

  Future<void> _reconcileFolders() async {
    final sync = _sync!;
    final history = await sync.history();
    int depth(SyncCommit c) {
      try {
        return syncAncestry(history, [c.id]).length;
      } catch (_) {
        return history.length + 1;
      }
    }

    final inputs = history.values.where((c) => c.scope.startsWith('folders/') && c.deviceId != sync.deviceId).toList()
      ..sort((a, b) {
        final n = depth(b).compareTo(depth(a));
        return n == 0 ? a.id.compareTo(b.id) : n;
      });
    for (final remote in inputs) {
      await _queueWrite(_folderQueue, () async {
        while (true) {
          final heads = await sync.snapshots(), current = heads[remote.scope];
          final known = await sync.history(), id = remote.scope.substring(8);
          var plan = planSyncMerge(
            known,
            remote: remote.id,
            local: current?.commit.id,
            validateTransaction: (value) => folderFromSync(id, value),
          );
          try {
            if (plan.state == SyncMergeState.unchanged) {
              await sync.commit([], expected: {remote.scope: current?.revision}, resolved: [remote.id]);
              return;
            }
            Folder? folder;
            if (plan.state == SyncMergeState.ready) {
              try {
                // Validate roots and single-parent versions too, including IDs
                // on tombstones. Folder streams have no external dependencies.
                folderFromSync(id, {'id': id, 'name': 'validation'});
                for (final c in syncAncestry(known, [remote.id]).values) {
                  if (c.requires.isNotEmpty) throw const FormatException('Folder dependency');
                  if (!c.deleted) folderFromSync(id, c.payload);
                }
                folder = plan.deleted ? null : folderFromSync(id, plan.payload!);
              } on FormatException {
                plan = SyncMergePlan(
                  remote: remote.id,
                  local: current?.commit.id,
                  state: SyncMergeState.conflict,
                  reason: 'invalidFolder',
                );
              }
            }
            if (plan.state != SyncMergeState.ready) {
              await sync.recordIssue(plan, scope: remote.scope, expected: current?.revision);
              return;
            }
            await _saveFolder(
              id,
              folder,
              heads: heads,
              plan: plan,
              resolved: syncAncestry(known, [remote.id, if (current != null) current.commit.id]).keys,
            );
            return;
          } on SyncRevisionChanged {
            continue;
          }
        }
      });
    }
  }

  Future<void> _retryOrganization() async {
    await _ensureLoaded();
    if (_sync case final sync?) {
      await _reconcileFolders();
      await _queueWrite(_folderQueue, () async {
        final value = (await sync.snapshots())['library']!.value;
        await sync.project(
          _libraryFile.path,
          () => FileLibraryStore._atomicWrite(_libraryFile, utf8.encode(jsonEncode(value))),
        );
      });
    }
  }
}
