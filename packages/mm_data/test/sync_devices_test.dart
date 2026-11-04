import 'dart:io';

import 'package:mm_data/mm_data.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileSyncLedger a, b;
  late FileLibraryStore library;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-devices-');
    a = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    b = FileSyncLedger(Directory('${root.path}/b'), libraryId: 'lib', deviceId: 'b');
    library = FileLibraryStore(b.root, sync: b);
  });
  tearDown(() async {
    await library.dispose();
    await root.delete(recursive: true);
  });
  test('names survive out-of-order reception, restart and do not echo as local writes', () async {
    final devices = FileSyncDevices(a);
    await devices.rename('Mac', expectedRevision: null);
    final first = (await a.pending()).single;
    await devices.rename('Laptop', expectedRevision: (await devices.list()).single.revision);
    final last = (await a.pending()).last;
    await library.receiveSync([last]);
    expect(await FileSyncDevices(b).list(), isEmpty);
    expect(await b.issues(), isNotEmpty);
    await library.receiveSync([first]);
    expect((await FileSyncDevices(b).list()).single.name, 'Laptop');
    expect(await b.issues(), isEmpty);
    expect((await b.pending()).where((c) => c.scope.startsWith('devices/')), isEmpty);
    final restored = (await FileSyncLedger.restore(b.root))!;
    expect((await FileSyncDevices(restored).list()).single.name, 'Laptop');
    expect((await FileSyncDevices(restored).list()).single.local, false);
    await expectLater(devices.rename('Stale', expectedRevision: first.id), throwsA(isA<SyncRevisionChanged>()));
    expect((await devices.list()).single.name, 'Laptop');
  });
  test('device diagnostics do not block other devices or unrelated content', () async {
    await FileSyncDevices(a).rename('Mac', expectedRevision: null);
    final original = (await a.pending()).single;
    await library.receiveSync([original]);
    final bad = SyncCommit.create(
      libraryId: 'lib',
      scope: original.scope,
      deviceId: 'impostor',
      sequence: 1,
      parents: [original.id],
      payload: SyncDeviceProfile('Fake').toJson(),
    );
    await library.receiveSync([bad]);
    await FileSyncDevices(b).rename('Phone', expectedRevision: null);
    expect((await FileSyncDevices(b).list()).map((d) => d.name), ['Mac', 'Phone']);
    expect(await b.issues(), contains(bad.id));
    await library.create(const NewStudySet(title: 'Independent', colorIndex: 0));
    expect((await library.watchAll().first).single.title, 'Independent');
  });
  test('disconnect is durable, preserves queues, and old completion cannot confirm', () async {
    await FileSyncDevices(a).rename('Mac', expectedRevision: null);
    final target = SyncTarget(service: 'webdav', account: 'a', location: 'https://dav/', libraryId: 'lib');
    await a.bindTransport(target);
    await a.resumeTransport(target.key);
    final connection = (await a.transportConnection())!;
    final outgoing = await a.pending(target: target.key);
    await a.disconnectTransport(target.key);
    expect(await a.transportConnection(), isNull);
    expect(await (await FileSyncLedger.restore(a.root))!.transportConnection(), isNull);
    await expectLater(
      a.acknowledge(outgoing.map((c) => c.id), target: target.key, connectionRevision: connection.revision),
      throwsA(isA<SyncTransportException>()),
    );
    expect(await a.pending(target: target.key), hasLength(1));
    await a.bindTransport(target);
    await expectLater(a.disconnectTransport('wrong'), throwsA(isA<SyncTransportException>()));
    expect((await a.transportConnection())!.target.key, target.key);
  });
}
