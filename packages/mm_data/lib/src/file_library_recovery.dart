part of 'file_library_store.dart';

extension _FileLibraryRecovery on FileLibraryStore {
  String _recoveryKey(String source, String version) => syncDigest({
    'kind': 'recovery-copy-v1',
    'library': _sync!.libraryId,
    'device': _sync!.deviceId,
    'source': source,
    'version': version,
  });

  Future<LibraryRecovery> _libraryRecovery() async {
    await _ensureLoaded();
    final sync = _sync;
    if (sync == null) return LibraryRecovery();
    final heads = await sync.snapshots(), history = await sync.history();
    final entries = <LibraryRecoveryEntry>[];
    for (final head in heads.values.where((h) => h.scope.startsWith('sets/'))) {
      // Only accepted ancestry is offered. Unrelated/unvalidated received
      // branches remain diagnostics; recovery must not imply their acceptance.
      final ancestry = syncAncestry(history, [head.commit.id], checkKnownForks: false);
      final graph = SyncGraph(ancestry.values);
      final id = head.scope.substring(5);
      final current = head.deleted ? null : _materializeSync(id, head.commit.payload, null);
      final live = <String, _SetRecord>{};
      for (final c in ancestry.values.where((c) => !c.deleted)) {
        final record = _materializeSync(id, c.payload, null);
        if (head.deleted || record.content.documents.any((d) => current!.content.document(d.id) == null)) {
          live[c.id] = record;
        }
      }
      // Keep the closest surviving snapshot for EACH missing document, not
      // just the latest set snapshot (which may already omit older deletions).
      final targets = <String?>{
        if (head.deleted) null,
        for (final r in live.values)
          for (final d in r.content.documents)
            if (head.deleted || current!.content.document(d.id) == null) d.id,
      };
      final versions = <String>{};
      final ancestors = <String, Set<String>>{};
      for (final doc in targets) {
        final candidates = live.keys.where((v) => doc == null || live[v]!.content.document(doc) != null).toList();
        for (final v in candidates) {
          if (!candidates.any(
            (other) => other != v && ancestors.putIfAbsent(other, () => graph.ancestors(other)).contains(v),
          )) {
            versions.add(v);
          }
        }
      }
      for (final v in versions.toList()..sort()) {
        final record = live[v]!;
        final receipt = heads['recoveryCopies/${_recoveryKey(id, v)}']?.value;
        entries.add(
          LibraryRecoveryEntry(
            studySetId: id,
            version: v,
            observedRevision: head.revision,
            title: record.title,
            deleted: head.deleted,
            documents: record.content.documents.map((d) => d.title),
            cards: record.content.cards.length,
            preview: record.content.cards.map((c) => c.title).where((t) => t.trim().isNotEmpty).take(8),
            hasUnresolvedChoices: ancestry[v]!.pending.isNotEmpty,
            copyId: receipt?['copy'] as String?,
          ),
        );
      }
    }
    return LibraryRecovery(enabled: true, entries: entries);
  }

  Future<String> _recoverLibraryCopy(LibraryRecoveryEntry selection, {required String title}) async {
    await _ensureLoaded();
    if (_sync == null || title.trim().isEmpty || title.trim().length > 256) {
      throw const ContentSyncActionException(ContentSyncActionFailure.invalidCandidate);
    }
    final sync = _sync!, source = selection.studySetId;
    final key = _recoveryKey(source, selection.version), copy = 'recovered-$key';
    final receiptScope = 'recoveryCopies/$key';
    try {
      await _queueWrite(source, () async {
        final heads = await sync.snapshots();
        final receipt = heads[receiptScope];
        if (receipt != null) {
          if (receipt.value?['copy'] != copy || heads[FileLibraryStore._scope(copy)]?.deleted != false) {
            throw const ContentSyncActionException(ContentSyncActionFailure.stale);
          }
          // A retry after a successful commit does not restore over later edits.
          return;
        }
        if (_isEditing(source) || heads[FileLibraryStore._scope(source)]?.revision != selection.observedRevision) {
          throw const ContentSyncActionException(ContentSyncActionFailure.stale);
        }
        final offered = await _libraryRecovery();
        if (!offered.entries.any(
          (e) =>
              e.studySetId == source &&
              e.version == selection.version &&
              e.observedRevision == selection.observedRevision,
        )) {
          throw const ContentSyncActionException(ContentSyncActionFailure.stale);
        }
        final commit = (await sync.history())[selection.version]!;
        final original = _materializeSync(source, commit.payload, null);
        final now = _clock();
        final record = _SetRecord(
          id: copy,
          title: title.trim(),
          colorIndex: original.colorIndex,
          folderId: null,
          starred: false,
          createdAt: now,
          lastOpenedAt: now,
          content: original.content,
          resources: original.resources,
        );
        await _queueWrite(copy, () async {
          Future<void> check() async {
            final current = await sync.snapshots();
            if (_isEditing(source) ||
                current[FileLibraryStore._scope(source)]?.revision != selection.observedRevision ||
                current[FileLibraryStore._scope(copy)] != null ||
                current[receiptScope] != null) {
              throw const ContentSyncActionException(ContentSyncActionFailure.stale);
            }
          }

          await check();
          await _copyRecoveryResources(source, record, check);
          // Source observation and receipt absence are checked in the SAME ledger
          // commit as the new set, so another tab cannot race the earlier reads.
          await _saveRecord(
            record,
            validate: (_) {
              if (_isEditing(source)) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
            },
            additional: [
              SyncMutation(
                receiptScope,
                local: {'source': source, 'version': selection.version, 'copy': copy},
                shared: {},
              ),
            ],
            observed: {
              FileLibraryStore._scope(source): selection.observedRevision,
              FileLibraryStore._scope(copy): null,
              'reviews/$copy': null,
              receiptScope: null,
            },
          );
          _sets[copy] = record;
          _libraryChanges.add(null);
          _contentChanges.add(copy);
        });
      });
    } on SyncRevisionChanged {
      throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    }
    return copy;
  }

  Future<void> _copyRecoveryResources(String source, _SetRecord record, Future<void> Function() check) async {
    final cache = ResourceCache(root);
    // Unmanifested historical paths have no byte provenance. Do not copy the
    // current bytes under an old document identity; the UI explains this limit.
    for (final capability in syncResourceGroups(record.content)) {
      final files = record.resources?.groups[capability.key];
      if (files == null) continue;
      Future<void> cacheSource(String path, SyncResourceFile descriptor) async {
        await check();
        final actual = await cache.inspect(_resolvePath(source, path));
        if (actual != null && contentValueEquals(actual.toJson(), descriptor.toJson())) {
          final cached = await cache.inspect(_resolvePath(source, path), cache: true);
          if (!contentValueEquals(cached?.toJson(), descriptor.toJson())) {
            throw const FormatException('Recovery resource changed');
          }
        }
      }

      // Validate the exact package closure before materializing any file.
      // Unknown dependency closure cannot authorize reading package files.
      final allowed = Set<String>.of(capability.roots);
      for (final path in [
        if (capability.bookBase != null) '${capability.bookBase}/manifest.json',
        if (capability.webBase != null) '${capability.webBase}/resources.json',
      ]) {
        final descriptor = files[path];
        if (descriptor == null || descriptor.length > syncObjectLimit) {
          throw const FormatException('Invalid recovery manifest');
        }
        await cacheSource(path, descriptor);
        final bytes = <int>[];
        for (final chunk in descriptor.chunks) {
          final data = await cache.readChunk(chunk);
          if (data == null) throw const FormatException('Recovery manifest unavailable');
          bytes.addAll(data);
        }
        if (bytes.length != descriptor.length || sha256.convert(bytes).toString() != descriptor.hash) {
          throw const FormatException('Corrupt recovery manifest');
        }
        final dependencies = syncResourceDependencies(
          capability,
          path,
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(),
        );
        allowed.addAll(dependencies.keys);
        if (dependencies.entries.any((e) => files[e.key]?.hash != e.value)) {
          throw const FormatException('Incomplete recovery manifest');
        }
      }
      if (files.keys.any((path) => !allowed.contains(path))) {
        throw const FormatException('Unexpected recovery resource');
      }
      for (final file in files.entries) {
        await cacheSource(file.key, file.value);
        var complete = true;
        for (final chunk in file.value.chunks) {
          if (await cache.readChunk(chunk) == null) {
            complete = false;
            break;
          }
        }
        if (complete) await cache.materialize(_resolvePath(record.id, file.key), file.value, check);
      }
    }
  }
}
