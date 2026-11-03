import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  SyncCommit c(
    String name, {
    String device = 'a',
    String scope = 'devices/a',
    List<String> parents = const [],
    int sequence = 1,
    bool deleted = false,
    Map<String, String> requires = const {},
    List<String> pending = const [],
  }) => SyncCommit.create(
    libraryId: 'lib',
    scope: scope,
    deviceId: device,
    sequence: sequence,
    payload: deleted ? {} : SyncDeviceProfile(name).toJson(),
    parents: parents,
    deleted: deleted,
    requires: requires,
    pending: pending,
  );
  test('bounded canonical display names never become identities', () {
    expect(SyncDeviceProfile('  我的 Mac  ').name, '我的 Mac');
    expect(SyncDeviceProfile.fromJson(SyncDeviceProfile('Phone').toJson()).name, 'Phone');
    for (final name in ['', ' ', 'a' * 101, 'a\nb', '\u202efake', '\u2066fake']) {
      expect(() => SyncDeviceProfile(name), throwsFormatException);
    }
    for (final json in <Map<String, Object?>>[
      {},
      {'kind': 'device-profile', 'version': 1, 'name': ' raw '},
      {'kind': 'device-profile', 'version': 2, 'name': 'A'},
    ]) {
      expect(() => SyncDeviceProfile.fromJson(json), throwsFormatException);
    }
    expect(isSyncWireScope('devices/a'), true);
  });
  test('single author rename fast forwards, ancestors stay unchanged and missing parents wait', () {
    final a = c('Mac'), b = c('Laptop', parents: [a.id], sequence: 2);
    final history = {a.id: a, b.id: b};
    expect(planDeviceProfile({b.id: b}, remote: b.id).state, SyncMergeState.waiting);
    expect(planDeviceProfile(history, remote: b.id, local: a.id).adopt, true);
    expect(planDeviceProfile(history, remote: a.id, local: b.id).state, SyncMergeState.unchanged);
  });
  test('spoofed authors, malformed scopes, deletion and content dependencies are retained as problems', () {
    final a = c('Mac');
    for (final bad in [
      c('Bad', device: 'impostor'),
      c('Bad', scope: 'devices/a/extra'),
      c('Bad', deleted: true),
      c('Bad', requires: {'sets/x': a.id}),
      c('Bad', pending: [a.id]),
    ]) {
      expect(planDeviceProfile({bad.id: bad}, remote: bad.id).state, SyncMergeState.conflict);
    }
  });
  test('a device fork is never merged even if its two names match', () {
    final a = c('Mac'), b = c('Phone', parents: [a.id], sequence: 2), d = c('Phone', parents: [a.id], sequence: 3);
    final history = {a.id: a, b.id: b, d.id: d};
    expect(planDeviceProfile(history, remote: d.id, local: b.id).state, SyncMergeState.conflict);
    final checkpoint = c('Phone', parents: [b.id, d.id], sequence: 4);
    expect(
      planDeviceProfile({...history, checkpoint.id: checkpoint}, remote: checkpoint.id).state,
      SyncMergeState.conflict,
    );
    final otherRoot = c('Other', sequence: 5);
    expect(
      planDeviceProfile({...history, otherRoot.id: otherRoot}, remote: otherRoot.id, local: b.id).reason,
      'invalidHistory',
    );
  });
}
