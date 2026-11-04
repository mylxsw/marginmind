part of 'file_translation_store.dart';

extension _TranslationSync on FileTranslationStore {
  String _syncScope(String id, String lang) =>
      'translated/${_component(studySetId!)}/${_component(id)}/${_component(lang)}';
  Document _parentDocument(Map<String, LocalSyncSnapshot> heads, String id, {bool writing = false}) {
    _requireLiveParent(heads, id);
    final parent = heads['sets/$studySetId']!;
    if (writing && parent.draft) throw const ContentSyncActionException(ContentSyncActionFailure.editing);
    return StudySetContent.fromJson((parent.value!['content'] as Map).cast()).document(id)!;
  }

  Future<LocalSyncSnapshot> _ensureStream(String id, String lang) async {
    final ledger = sync!, scope = _syncScope(id, lang);
    while (true) {
      final heads = await ledger.snapshots(), parent = heads['sets/$studySetId'];
      if (heads[scope] case final existing?) {
        if (existing.deleted) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
        return existing;
      }
      final doc = _parentDocument(heads, id, writing: true);
      final old = await _readLegacy(id, lang);
      final base = translationBaseline(ledger.libraryId, scope);
      await ledger.receive([base]);
      try {
        var value = TranslationRegister.empty();
        for (final segment in old.segments.values) {
          value = value.append(readingDocumentVersion(doc), segment, ledger.deviceId, newId());
        }
        await ledger.commit(
          [
            SyncMutation(
              scope,
              local: value.toJson(),
              shared: value.toJson(),
              adopt: old.segments.isEmpty ? base.id : null,
              mergeParent: old.segments.isEmpty ? null : base.id,
              requireScopes: old.segments.isEmpty ? [] : ['sets/$studySetId'],
            ),
          ],
          expected: {scope: null, 'sets/$studySetId': parent!.revision},
          validate: (h) => _parentDocument(h, id, writing: true),
        );
        return (await ledger.snapshots())[scope]!;
      } on SyncRevisionChanged {
        continue;
      }
    }
  }

  Future<TranslationSnapshot> _loadSynced(String id, String lang) async {
    final heads = await sync!.snapshots(), parent = heads['sets/$studySetId'];
    if (parent == null || parent.deleted) return TranslationSnapshot();
    final doc = StudySetContent.fromJson((parent.value!['content'] as Map).cast()).document(id);
    if (doc == null) return TranslationSnapshot();
    final existing = heads[_syncScope(id, lang)];
    if (existing?.deleted == true) return TranslationSnapshot(documentVersion: readingDocumentVersion(doc));
    if (existing == null && parent.draft) return _readLegacy(id, lang);
    final head = existing ?? await _ensureStream(id, lang);
    return TranslationRegister.fromJson(head.value!).snapshot(readingDocumentVersion(doc));
  }

  Future<TranslationSnapshot> _appendSynced(
    String id,
    String lang,
    TranslationSegment segment, {
    String? expectedToken,
    bool guarded = false,
    bool replaceEdited = false,
  }) async {
    final ledger = sync!, scope = _syncScope(id, lang);
    await _ensureStream(id, lang);
    while (true) {
      final heads = await ledger.snapshots(), head = heads[scope]!;
      final version = readingDocumentVersion(_parentDocument(heads, id, writing: true));
      if (head.deleted) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      final before = TranslationRegister.fromJson(head.value!);
      if (guarded && before.token(version, segment.key) != expectedToken) {
        throw const ContentSyncActionException(ContentSyncActionFailure.stale);
      }
      final next = before.append(
        version,
        segment,
        ledger.deviceId,
        newId(),
        observed: guarded,
        replaceEdited: replaceEdited,
      );
      try {
        await ledger.commit(
          [
            SyncMutation(scope, local: next.toJson(), shared: next.toJson(), requireScopes: ['sets/$studySetId']),
          ],
          expected: {scope: head.revision, 'sets/$studySetId': heads['sets/$studySetId']!.revision},
          validate: (h) => _parentDocument(h, id, writing: true),
        );
        final snapshot = next.snapshot(version);
        await ledger.project(scope, () => _writeSegments(id, lang, snapshot.segments.values));
        return snapshot;
      } on SyncRevisionChanged {
        continue;
      }
    }
  }

  Future<void> _chooseSynced(String id, String lang, String key, String choice, String expected) async {
    final ledger = sync;
    if (ledger == null) throw StateError('Sync not enabled');
    final heads = await ledger.snapshots(), scope = _syncScope(id, lang), head = heads[_syncScope(id, lang)];
    final version = readingDocumentVersion(_parentDocument(heads, id, writing: true));
    if (head == null || head.deleted) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    final before = TranslationRegister.fromJson(head.value!);
    if (before.token(version, key) != expected) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    final next = before.choose(version, key, choice, ledger.deviceId, newId());
    try {
      await ledger.commit(
        [
          SyncMutation(scope, local: next.toJson(), shared: next.toJson(), requireScopes: ['sets/$studySetId']),
        ],
        expected: {scope: head.revision, 'sets/$studySetId': heads['sets/$studySetId']!.revision},
        validate: (h) => _parentDocument(h, id, writing: true),
      );
    } on SyncRevisionChanged {
      throw const ContentSyncActionException(ContentSyncActionFailure.stale);
    }
    await ledger.project(scope, () => _writeSegments(id, lang, next.snapshot(version).segments.values));
  }

  Future<void> _clearSynced(String id, String lang) async {
    final ledger = sync!, scope = _syncScope(id, lang);
    await _ensureStream(id, lang);
    while (true) {
      final heads = await ledger.snapshots(), head = heads[scope]!;
      final version = readingDocumentVersion(_parentDocument(heads, id, writing: true));
      final next = TranslationRegister.fromJson(head.value!).clear(version, ledger.deviceId, newId());
      try {
        await ledger.commit(
          [
            SyncMutation(scope, local: next.toJson(), shared: next.toJson(), requireScopes: ['sets/$studySetId']),
          ],
          expected: {scope: head.revision, 'sets/$studySetId': heads['sets/$studySetId']!.revision},
          validate: (h) => _parentDocument(h, id, writing: true),
        );
        await ledger.project(scope, () => _removePair(id, lang));
        return;
      } on SyncRevisionChanged {
        continue;
      }
    }
  }
}
