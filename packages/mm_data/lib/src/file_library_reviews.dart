part of 'file_library_store.dart';

extension _FileLibraryReviews on FileLibraryStore {
  Map<String, Object?>? _prepareReviews(_SetRecord record) {
    final previous = _syncSnapshots[FileLibraryStore._scope(record.id)];
    final head = _syncSnapshots['reviews/${record.id}'];
    final next = reviewData(record.content);
    final before = previous?.value == null ? null : reviewData(_SetRecord.fromJson(previous!.value!).content);
    final changed = before == null || !contentValueEquals(normalizeReviewData(before), normalizeReviewData(next));
    if (_contentTransactions.containsKey(record.id) && changed) {
      throw const ReviewWriteUnavailable(ReviewSaveProblem.editing);
    }
    if (head == null || head.deleted) {
      if (previous != null) {
        if (changed) throw const ReviewWriteUnavailable(ReviewSaveProblem.awaitingBaseline);
        return null; // Content editing must not invent a competing empty baseline.
      }
      return ReviewTimeline.seed(next).toJson();
    }
    final timeline = head.value!['kind'] == 'review-events'
        ? ReviewTimeline.fromJson(head.value!)
        : ReviewTimeline.seed(head.value!);
    return timeline.append(next, deviceId: _sync!.deviceId).toJson();
  }

  Future<void> _reconcileReviews({bool Function(String)? canApply}) async {
    final sync = _sync!;
    final history = await sync.history();
    int depth(SyncCommit c) {
      try {
        return syncAncestry(history, [c.id]).length;
      } catch (_) {
        return history.length + 1;
      }
    }

    final inputs = history.values.where((c) => c.scope.startsWith('reviews/') && c.deviceId != sync.deviceId).toList()
      ..sort((a, b) {
        final order = depth(b).compareTo(depth(a));
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
    for (final remote in inputs) {
      final id = remote.scope.substring('reviews/'.length);
      await _queueWrite(id, () async {
        while (true) {
          final heads = await sync.snapshots();
          final current = heads[remote.scope], content = heads[FileLibraryStore._scope(id)];
          final known = await sync.history();
          var plan = planReviewMerge(known, remote: remote.id, local: current?.commit.id);
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
            if (content == null) {
              plan = waiting('missingContent');
            } else if (content.deleted || remote.deleted || current?.deleted == true) {
              // Content deletion owns the cascade. A late score never restores
              // a study set or erases its surviving local review history.
              plan = waiting('deleteEdit');
            } else if (plan.state == SyncMergeState.ready) {
              if (content.draft || canApply?.call(id) == false) {
                plan = waiting('editing');
              } else {
                final accepted = syncAncestry(known, [content.commit.id], checkKnownForks: false);
                for (final c in syncAncestry(known, [
                  remote.id,
                ]).values.where((c) => c.payload['kind'] == 'review-events')) {
                  if (c.requires.length != 1 || !c.requires.containsKey(FileLibraryStore._scope(id))) {
                    plan = waiting('invalidReviews');
                    break;
                  }
                  final dependency = c.requires[FileLibraryStore._scope(id)]!;
                  if (!accepted.containsKey(dependency) || accepted[dependency]!.deleted) {
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
            final timeline = ReviewTimeline.fromJson(plan.payload!);
            final record = _SetRecord.fromJson(content!.value!);
            final updated = record.copyWith(content: timeline.apply(record.content));
            final acceptedReviews = syncAncestry(known, [remote.id]).keys;
            _syncSnapshots = await sync.commit(
              [
                SyncMutation(FileLibraryStore._scope(id), local: updated.toJson(), shared: content.commit.payload),
                SyncMutation(
                  remote.scope,
                  local: plan.payload,
                  shared: plan.payload,
                  adopt: plan.adopt ? remote.id : null,
                  mergeParent: plan.adopt ? null : remote.id,
                  requireScopes: [FileLibraryStore._scope(id)],
                ),
              ],
              expected: {FileLibraryStore._scope(id): content.revision, remote.scope: current?.revision},
              resolved: acceptedReviews,
              validate: (heads) {
                if (heads[FileLibraryStore._scope(id)]?.draft == true || canApply?.call(id) == false) {
                  throw const _EditingDeferred();
                }
              },
            );
            _sets[id] = updated;
            await sync.project(_packagePath(id), () => _writeRecordFile(updated));
            _contentChanges.add(id);
            _libraryChanges.add(null);
            return;
          } on SyncRevisionChanged {
            continue; // Re-read and replay after an intervening local score.
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
