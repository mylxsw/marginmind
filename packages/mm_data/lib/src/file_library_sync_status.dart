part of 'file_library_store.dart';

extension _FileLibrarySyncStatus on FileLibraryStore {
  bool _isEditing(String id) => _contentTransactions.containsKey(id) || _editLeases.any((lease) => lease.id == id);

  bool _projectionFor(String id, String key) =>
      key == _libraryFile.path ||
      key == _packagePath(id) ||
      p.isWithin(_packagePath(id), key) ||
      key == 'translation-seed/$id' ||
      (key.startsWith('translations/$id/') || key.startsWith('translated/$id/'));

  Future<ContentSyncStatus> _contentSyncStatus(String id) async {
    await _ensureLoaded();
    final sync = _sync;
    if (sync == null) return ContentSyncStatus();
    final heads = await sync.snapshots();
    final head = heads[FileLibraryStore._scope(id)];
    final history = await sync.history();
    final conflicts = <ContentSyncConflict>[];
    for (final transaction in head?.commit.pending ?? const <String>[]) {
      final candidate = history[transaction]!;
      final before = history[candidate.parents.single]!.payload;
      var valid = true;
      try {
        _materializeSync(id, chooseSyncTransaction(before, candidate.payload, head!.commit.payload), head.value);
      } on FormatException {
        valid = false;
      } on ArgumentError {
        valid = false;
      } on TypeError {
        valid = false;
      }
      conflicts.add(
        ContentSyncConflict(
          id: transaction,
          canUseCandidate: valid,
          changes: contentSyncReview(before, candidate.payload, head!.commit.payload),
        ),
      );
    }
    final problems = <ContentSyncProblem>{};
    for (final entry in (await sync.issues()).entries) {
      final scope = history[entry.key]?.scope;
      if (!{FileLibraryStore._scope(id), 'reviews/$id'}.contains(scope) &&
          !(scope?.startsWith('reading/$id/') ?? false) &&
          !(scope?.startsWith('translated/$id/') ?? false)) {
        continue;
      }
      final issue = entry.value;
      problems.add(switch (issue['reason']) {
        'editing' => ContentSyncProblem.editing,
        'missingParents' || 'missingContent' => ContentSyncProblem.missingHistory,
        'noBase' => ContentSyncProblem.unrelatedHistory,
        'multipleBases' => ContentSyncProblem.ambiguousHistory,
        'concurrentResolutions' => ContentSyncProblem.concurrentChoices,
        'deleteEdit' => ContentSyncProblem.deletion,
        'differentScope' ||
        'unsupportedReviews' ||
        'unsupportedReading' ||
        'unsupportedDependencies' => ContentSyncProblem.unsupported,
        _ => ContentSyncProblem.invalidHistory,
      });
    }
    var translationConflicts = 0;
    if (head != null && !head.deleted) {
      final content = _SetRecord.fromJson(head.value!).content;
      for (final entry in heads.entries) {
        if (!entry.key.startsWith('translated/$id/') || entry.value.deleted) continue;
        final parts = entry.key.split('/');
        if (parts.length != 4) continue;
        final doc = content.document(parts[2]);
        if (doc != null) {
          translationConflicts += TranslationRegister.fromJson(entry.value.value!)
              .snapshot(readingDocumentVersion(doc))
              .conflicts
              .length;
        }
      }
    }
    final target = (await sync.transportConnection())?.target.key;
    final queued = (await sync.pending(target: target))
        .where((c) => isSyncWireScope(c.scope))
        .where(
          (c) =>
              c.scope == FileLibraryStore._scope(id) ||
              c.scope == 'reviews/$id' ||
              c.scope.startsWith('reading/$id/') ||
              (c.scope.startsWith('translations/$id/') || c.scope.startsWith('translated/$id/')),
        )
        .length;
    return ContentSyncStatus(
      enabled: true,
      revision: head?.revision,
      queued: queued,
      translationConflicts: translationConflicts,
      recoveryId: (await sync.recoveries())[FileLibraryStore._scope(id)],
      conflicts: conflicts,
      problems: problems,
      editing: _isEditing(id),
      retryFailed: _editSyncErrors.containsKey(id),
      repairNeeded:
          sync.projectionErrors.keys.any((key) => _projectionFor(id, key)) ||
          _packageLoadErrors.containsKey(_packagePath(id)) ||
          _researchSessionSyncErrors.keys.any((key) => p.isWithin(_packagePath(id), key)),
    );
  }

  Stream<ContentSyncStatus> _watchContentSync(String id) {
    late StreamController<ContentSyncStatus> out;
    final subscriptions = <StreamSubscription<void>>[];
    var cancelled = false;
    Future<void> refresh = Future.value();
    void changed([void _]) {
      refresh = refresh.then((_) async {
        if (cancelled) return;
        try {
          final status = await _contentSyncStatus(id);
          if (!cancelled) out.add(status);
        } catch (error, stack) {
          if (!cancelled) out.addError(error, stack);
        }
      });
    }

    out = StreamController<ContentSyncStatus>(
      onListen: () async {
        try {
          await _ensureLoaded();
          if (cancelled) return;
          subscriptions.add(
            _syncStatusChanges.stream.listen(
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
          // Subscribe before reading; changes during the asynchronous query are
          // queued instead of disappearing between initial read and subscription.
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

  Future<void> _chooseContentSync(
    String id,
    String transaction, {
    required String expectedRevision,
    required bool useCandidate,
  }) async {
    await _ensureLoaded();
    if (_isEditing(id)) throw const ContentSyncActionException(ContentSyncActionFailure.editing);
    try {
      await resolveSyncConflict(id, transaction, expectedRevision: expectedRevision, useCandidate: useCandidate);
    } on SyncRevisionChanged {
      throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    } on _EditingDeferred {
      throw const ContentSyncActionException(ContentSyncActionFailure.editing);
    } on FormatException {
      throw const ContentSyncActionException(ContentSyncActionFailure.invalidCandidate);
    } on StateError {
      if (_isEditing(id)) throw const ContentSyncActionException(ContentSyncActionFailure.editing);
      rethrow;
    }
  }

  Future<void> _acknowledgeContentRecovery(String id, String recoveryId) async {
    await _ensureLoaded();
    final sync = _sync;
    if (sync == null) return;
    try {
      await sync.acknowledgeRecovery(FileLibraryStore._scope(id), recoveryId);
    } on SyncRevisionChanged {
      throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    }
    _recoveredEditingDrafts.remove(id);
  }

  Future<void> _retryContentSync(String id) async {
    await _ensureLoaded();
    final sync = _sync;
    if (sync == null) return;
    try {
      await _queueWrite(id, () async {
        final snapshots = await sync.snapshots();
        final snapshot = snapshots[FileLibraryStore._scope(id)];
        final translations = FileTranslationStore(Directory(_packagePath(id)), sync: sync, studySetId: id);
        if (snapshot?.deleted == true) {
          await sync.project(_packagePath(id), () async {
            final file = File(p.join(_packagePath(id), 'studyset.json'));
            if (await file.exists()) await file.delete();
          });
        }
        if (snapshot?.value case final value?) {
          final record = _SetRecord.fromJson(value);
          if (snapshot!.draft && !_contentTransactions.containsKey(id)) {
            // A failed startup recovery still has its last saved draft. Retry
            // sealing it and recording the notice at the same commit point.
            await _saveRecord(record, finishDraft: true, recovered: snapshot.revision);
            _recoveredEditingDrafts.add(id);
          }
          await sync.project(_packagePath(id), () => _writeRecordFile(record));
          if (_packageLoadErrors.remove(_packagePath(id)) != null) {
            _sets[id] = record;
            _libraryChanges.add(null);
            _contentChanges.add(id);
          }
          await _syncResearchSessions(id, record.content);
          await sync.project(
            'translation-seed/$id',
            () => translations.seedExisting(record.content.documents.map((d) => d.id).toSet()),
          );
        }
        for (final scope in snapshots.keys.where(
          (s) => (s.startsWith('translations/$id/') || s.startsWith('translated/$id/')),
        )) {
          final parts = scope.split('/');
          await translations.compact(parts[2], parts[3]);
        }
        if (snapshots['library']?.value case final value?) {
          await sync.project(
            _libraryFile.path,
            () => FileLibraryStore._atomicWrite(_libraryFile, utf8.encode(jsonEncode(value))),
          );
        }
      });
      await reconcileSync();
      _editSyncErrors.remove(id);
    } catch (error) {
      _editSyncErrors[id] = error;
      rethrow;
    } finally {
      _syncStatusChanges.add(null);
    }
  }
}
