part of 'file_library_store.dart';

extension _FileLibraryReading on FileLibraryStore {
  Future<ReadingContinuations> _readingContinuations(String id) async {
    await _ensureLoaded();
    final sync = _sync;
    if (sync == null) return ReadingContinuations();
    final heads = await sync.snapshots(), history = await sync.history();
    final content = _sets[id]?.content;
    final items = <ReadingContinuation>[];
    final scopes = heads.keys.where((s) => s.startsWith('reading/$id/') && s != 'reading/$id/${sync.deviceId}').toList()
      ..sort();
    if (content != null) {
      for (final scope in scopes) {
        final head = heads[scope]!;
        if (head.deleted) continue;
        final reading = DeviceReading.fromJson(head.value!);
        final source = history[head.commit.requires[FileLibraryStore._scope(id)]];
        final original = source == null ? null : contentFromDocument((source.payload['content'] as Map).cast());
        for (final location in reading.locations) {
          final doc = content.document(location.documentId);
          final matches = doc != null && location.matches(doc);
          final available = matches && await _readingAvailable(id, doc);
          items.add(
            ReadingContinuation(
              deviceId: scope.substring('reading/$id/'.length),
              documentId: location.documentId,
              title: doc?.title ?? original?.document(location.documentId)?.title ?? '',
              remoteRevision: head.revision,
              localToken: doc == null ? '' : localReadingToken(doc),
              position: location.position,
              readAt: location.readAt,
              availability: !matches
                  ? ReadingContinuationAvailability.documentChanged
                  : available
                  ? ReadingContinuationAvailability.ready
                  : ReadingContinuationAvailability.unavailable,
            ),
          );
        }
      }
    }
    final status = await _contentSyncStatus(id);
    return ReadingContinuations(enabled: true, editing: _isEditing(id), items: items, problems: status.problems);
  }

  Future<bool> _readingAvailable(String id, Document doc) =>
      File(_resolvePath(id, doc.contentManifest ?? doc.fileName)).exists();

  Future<ReadingPosition> _prepareReadingContinuation(
    String id,
    String deviceId,
    String documentId, {
    required String remoteRevision,
    required String localToken,
  }) async {
    await _ensureLoaded();
    ReadingPosition? position;
    await _queueWrite(id, () async {
      final sync = _sync;
      if (sync == null || deviceId == sync.deviceId || deviceId.contains('/')) {
        throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      }
      final heads = await sync.snapshots(), scope = 'reading/$id/$deviceId';
      final remote = heads[scope], current = heads[FileLibraryStore._scope(id)];
      final doc = _sets[id]?.content.document(documentId);
      if (remote == null ||
          remote.deleted ||
          remote.revision != remoteRevision ||
          doc == null ||
          localReadingToken(doc) != localToken ||
          current?.deleted != false) {
        throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      }
      if (_isEditing(id)) throw const ContentSyncActionException(ContentSyncActionFailure.editing);
      final location = DeviceReading.fromJson(remote.value!).locations
          .where((l) => l.documentId == documentId)
          .firstOrNull;
      if (location == null || !location.matches(doc) || !await _readingAvailable(id, doc)) {
        throw const ContentSyncActionException(ContentSyncActionFailure.invalidCandidate);
      }
      final latest = await sync.snapshots();
      if (latest[scope]?.revision != remote.revision ||
          latest[FileLibraryStore._scope(id)]?.revision != current!.revision) {
        throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      }
      if (_isEditing(id)) throw const ContentSyncActionException(ContentSyncActionFailure.editing);
      position = location.position;
    });
    return position!;
  }

  Future<void> _reconcileReading() async {
    final sync = _sync!;
    final history = await sync.history();
    int depth(SyncCommit c) {
      try {
        return syncAncestry(history, [c.id]).length;
      } catch (_) {
        return history.length + 1;
      }
    }

    final inputs = history.values.where((c) => c.scope.startsWith('reading/') && c.deviceId != sync.deviceId).toList()
      ..sort((a, b) {
        final n = depth(b).compareTo(depth(a));
        return n == 0 ? a.id.compareTo(b.id) : n;
      });
    for (final remote in inputs) {
      final parts = remote.scope.split('/');
      // The protocol planner records malformed scope/author inputs too.
      final id = parts.length > 1 ? parts[1] : '';
      await _queueWrite(id, () async {
        while (true) {
          final heads = await sync.snapshots(),
              current = heads[remote.scope],
              content = heads[FileLibraryStore._scope(id)];
          final known = await sync.history();
          var plan = planDeviceReading(known, remote: remote.id, local: current?.commit.id);
          SyncMergePlan waiting(String reason) => SyncMergePlan(
            remote: remote.id,
            local: current?.commit.id,
            state: SyncMergeState.waiting,
            reason: reason,
          );
          try {
            if (plan.state == SyncMergeState.unchanged) {
              await sync.commit([], expected: {remote.scope: current?.revision}, resolved: [remote.id]);
              return;
            }
            if (plan.state == SyncMergeState.ready) {
              if (content == null) {
                plan = waiting('missingContent');
              } else if (content.deleted) {
                plan = waiting('deleteEdit');
              } else if (content.draft) {
                plan = waiting('editing');
              } else {
                final accepted = syncAncestry(known, [content.commit.id], checkKnownForks: false);
                for (final c in syncAncestry(known, [remote.id]).values) {
                  if (!c.deleted &&
                      c.payload['kind'] == 'device-reading' &&
                      !accepted.containsKey(c.requires[FileLibraryStore._scope(id)])) {
                    plan = waiting('missingContent');
                    break;
                  }
                }
              }
            }
            if (plan.state != SyncMergeState.ready) {
              await sync.recordIssue(plan, scope: remote.scope, expected: current?.revision);
              return;
            }
            _syncSnapshots = await sync.commit(
              [
                SyncMutation(
                  remote.scope,
                  local: remote.deleted ? null : remote.payload,
                  shared: remote.deleted ? null : remote.payload,
                  adopt: remote.id,
                ),
              ],
              expected: {remote.scope: current?.revision, FileLibraryStore._scope(id): content!.revision},
              resolved: syncAncestry(known, [remote.id]).keys,
              validate: (heads) {
                if (heads[FileLibraryStore._scope(id)]?.draft == true) throw const _EditingDeferred();
              },
            );
            // No study-set snapshot, active reader or local reading timer changes.
            return;
          } on SyncRevisionChanged {
            continue;
          } on _EditingDeferred {
            try {
              await sync.recordIssue(waiting('editing'), scope: remote.scope, expected: current?.revision);
            } on SyncRevisionChanged {
              continue;
            }
            return;
          }
        }
      });
    }
  }
}
