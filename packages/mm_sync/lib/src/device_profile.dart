import 'commit.dart';
import 'reconciliation.dart';

/// A name is presentation data, never an account identity or authorization.
class SyncDeviceProfile {
  SyncDeviceProfile(String name) : name = name.trim() {
    if (this.name.isEmpty ||
        this.name.length > 100 ||
        this.name.contains(RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'))) {
      throw const FormatException('Invalid device name');
    }
  }
  final String name;
  Map<String, Object?> toJson() => {'kind': 'device-profile', 'version': 1, 'name': name};
  factory SyncDeviceProfile.fromJson(Map<String, Object?> json) {
    if (json.length != 3 || json['kind'] != 'device-profile' || json['version'] != 1 || json['name'] is! String) {
      throw const FormatException('Unsupported device profile');
    }
    final result = SyncDeviceProfile(json['name'] as String);
    if (result.name != json['name']) throw const FormatException('Noncanonical device name');
    return result;
  }
}

/// A device may rename itself along one causal chain. No clock-based winner,
/// merged identities, or arbitrary root substitution when a device is cloned.
SyncMergePlan planDeviceProfile(Map<String, SyncCommit> known, {required String remote, String? local}) {
  final plan = planSyncMerge(known, remote: remote, local: local);
  if (plan.state != SyncMergeState.ready && plan.state != SyncMergeState.unchanged) return plan;
  SyncMergePlan invalid() =>
      SyncMergePlan(remote: remote, local: local, state: SyncMergeState.conflict, reason: 'invalidDevice');
  if (plan.state == SyncMergeState.ready && !plan.adopt) return invalid();
  final tip = known[remote]!, parts = tip.scope.split('/');
  if (parts.length != 2 || parts.first != 'devices' || parts.last.isEmpty) return invalid();
  try {
    for (final c in syncAncestry(known, [remote, ?local]).values) {
      if (c.scope != tip.scope ||
          c.deviceId != parts.last ||
          c.deleted ||
          c.parents.length > 1 ||
          c.pending.isNotEmpty ||
          c.resolves.isNotEmpty ||
          c.requires.isNotEmpty) {
        return invalid();
      }
      SyncDeviceProfile.fromJson(c.payload);
    }
  } on FormatException {
    return invalid();
  }
  return plan;
}
