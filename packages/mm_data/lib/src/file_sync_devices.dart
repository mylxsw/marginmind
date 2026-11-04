import 'package:mm_sync/mm_sync.dart';

import 'file_sync_ledger.dart';

class SyncDeviceInfo {
  const SyncDeviceInfo(this.id, this.name, this.revision, {required this.local});
  final String id, name, revision;
  final bool local;
}

/// Device registration uses the same durable version/outbox as other domains.
/// Receipt adoption emits ledger changes, including for open reading pickers.
class FileSyncDevices {
  const FileSyncDevices(this.ledger);
  final FileSyncLedger ledger;

  Future<List<SyncDeviceInfo>> list() async => [
    for (final entry in (await ledger.snapshots()).entries)
      if (entry.key.startsWith('devices/') && !entry.value.deleted)
        SyncDeviceInfo(
          entry.key.substring(8),
          SyncDeviceProfile.fromJson(entry.value.value!).name,
          entry.value.revision,
          local: entry.key == 'devices/${ledger.deviceId}',
        ),
  ]..sort((a, b) => a.id.compareTo(b.id));

  Future<void> rename(String name, {required String? expectedRevision}) async {
    final value = SyncDeviceProfile(name).toJson(), scope = 'devices/${ledger.deviceId}';
    await ledger.commit(
      [SyncMutation(scope, local: value, shared: value)],
      expected: {scope: expectedRevision},
    );
  }

  Future<void> reconcile() async {
    final history = await ledger.history();
    int depth(SyncCommit c) {
      try {
        return syncAncestry(history, [c.id]).length;
      } on MissingSyncParents {
        return history.length + 1;
      } on FormatException {
        return history.length + 1;
      }
    }

    final inputs = history.values.where((c) => c.scope.startsWith('devices/') && c.deviceId != ledger.deviceId).toList()
      ..sort((a, b) => depth(b).compareTo(depth(a)));
    for (final remote in inputs) {
      while (true) {
        final current = (await ledger.snapshots())[remote.scope];
        final plan = planDeviceProfile(history, remote: remote.id, local: current?.commit.id);
        if (plan.state == SyncMergeState.unchanged) {
          await ledger.commit(const [], resolved: [remote.id]);
          break;
        }
        if (plan.state != SyncMergeState.ready) {
          try {
            await ledger.recordIssue(plan, scope: remote.scope, expected: current?.revision);
          } on SyncRevisionChanged {
            continue;
          }
          break;
        }
        try {
          await ledger.commit(
            [SyncMutation(remote.scope, local: remote.payload, shared: remote.payload, adopt: remote.id)],
            expected: {remote.scope: current?.revision},
            resolved: syncAncestry(history, [remote.id]).keys,
          );
          break;
        } on SyncRevisionChanged {
          continue;
        }
      }
    }
  }
}
