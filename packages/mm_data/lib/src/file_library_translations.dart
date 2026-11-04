part of 'file_library_store.dart';

extension _LibraryTranslations on FileLibraryStore {
  Future<void> _reconcileTranslations({bool Function(String)? canApply}) async {
    final sync = _sync!, known = await _sync!.history();
    for (final c in known.values.where((c) => c.scope.startsWith('translated/'))) {
      final parts = c.scope.split('/');
      if (parts.length == 4) await sync.receive([translationBaseline(sync.libraryId, c.scope)]);
    }
    final history = await sync.history();
    int depth(SyncCommit c) {
      try {
        return syncAncestry(history, [c.id]).length;
      } catch (_) {
        return history.length + 1;
      }
    }

    final inputs =
        history.values.where((c) => c.scope.startsWith('translated/') && c.deviceId != sync.deviceId).toList()
          ..sort((a, b) {
            final d = depth(b).compareTo(depth(a));
            return d == 0 ? a.id.compareTo(b.id) : d;
          });
    for (final remote in inputs) {
      final parts = remote.scope.split('/');
      if (parts.length != 4 ||
          parts.any((v) => v.isEmpty || v == '.' || v == '..' || RegExp(r'[/\\\x00-\x1f:]').hasMatch(v))) {
        final head = (await sync.snapshots())[remote.scope];
        await sync.recordIssue(
          SyncMergePlan(
            remote: remote.id,
            local: head?.commit.id,
            state: SyncMergeState.conflict,
            reason: 'invalidTranslation',
          ),
          scope: remote.scope,
          expected: head?.revision,
        );
        continue;
      }
      final id = parts[1], doc = parts[2], lang = parts[3];
      await _queueWrite(id, () async {
        while (true) {
          final heads = await sync.snapshots(), current = heads[remote.scope], content = heads['sets/$id'];
          final graph = await sync.history();
          SyncMergePlan waiting(String reason) => SyncMergePlan(
            remote: remote.id,
            local: current?.commit.id,
            state: SyncMergeState.waiting,
            reason: reason,
          );
          final accepted = content == null
              ? <String>{}
              : syncAncestry(graph, [content.commit.id], checkKnownForks: false).keys.toSet();
          var plan = planTranslationMerge(
            graph,
            remote: remote.id,
            local: current?.commit.id,
            acceptedContent: accepted,
          );
          try {
            if (plan.state == SyncMergeState.unchanged) {
              await sync.commit([], expected: {remote.scope: current?.revision}, resolved: [remote.id]);
              return;
            }
            if (content == null) {
              plan = waiting('missingContent');
            } else if (content.deleted ||
                current?.deleted == true ||
                _SetRecord.fromJson(content.value!).content.document(doc) == null) {
              plan = waiting('deleteEdit');
            } else if (content.draft || canApply?.call(id) == false) {
              plan = waiting('editing');
            }
            if (plan.state != SyncMergeState.ready) {
              await sync.recordIssue(plan, scope: remote.scope, expected: current?.revision);
              return;
            }
            _syncSnapshots = await sync.commit(
              [
                SyncMutation(
                  remote.scope,
                  local: plan.payload,
                  shared: plan.payload,
                  adopt: plan.adopt ? remote.id : null,
                  mergeParent: plan.adopt ? null : remote.id,
                  requireScopes: ['sets/$id'],
                ),
              ],
              expected: {remote.scope: current?.revision, 'sets/$id': content!.revision},
              resolved: syncAncestry(graph, [remote.id]).keys,
              validate: (h) {
                if (h['sets/$id']?.draft == true || canApply?.call(id) == false) throw const _EditingDeferred();
              },
            );
            final translations = FileTranslationStore(Directory(_packagePath(id)), sync: sync, studySetId: id);
            await translations.compact(doc, lang);
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
