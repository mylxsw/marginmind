import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/settings/sync_settings_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';

class Secrets implements SecretStore {
  final values = <String, String>{};
  bool fail = false, failDelete = false;
  @override
  Future<void> delete(String account) async {
    if (!failDelete) values.remove(account);
  }

  @override
  Future<String?> read(String account) async => values[account];
  @override
  Future<void> write(String account, String value) async {
    if (fail) throw StateError('private password must never appear in UI');
    values[account] = value;
  }
}

class TestRemote implements SyncObjectTransport {
  TestRemote(this.target, this.objects);
  @override
  final SyncTarget target;
  final Map<String, List<int>> objects;
  int reads = 0, creates = 0;
  Object? error;
  Completer<void>? gate;
  SyncDelivery delivery = SyncDelivery.confirmed;
  @override
  Future<void> prepare() async {}
  @override
  Future<List<String>> listCommits() async =>
      objects.keys.where((k) => k.startsWith('commits/')).map((k) => k.substring(8, k.length - 5)).toList();
  @override
  Future<List<int>?> read(String key) async {
    reads++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return objects[key];
  }

  @override
  Future<SyncDelivery> create(String key, List<int> value) async {
    creates++;
    objects[key] = value;
    return delivery;
  }
}

class TestCloud implements ICloudDrivePort, ICloudAccountEvents {
  final changes = StreamController<void>.broadcast();
  Completer<void>? gate, entered;
  @override
  Stream<void> get accountChanges => changes.stream;
  String? account = 'apple-local-id';
  @override
  String get containerIdentifier => 'iCloud.test';
  final objects = <String, List<int>>{};
  @override
  Future<String?> accountIdentity() async => account;
  @override
  Future<void> prepare(String directory, String expectedAccount) async {}
  @override
  Future<List<String>> list(String directory, String expectedAccount) async => [];
  @override
  Future<List<int>?> read(String path, String expectedAccount) async {
    if (entered != null && !entered!.isCompleted) entered!.complete();
    if (gate != null) await gate!.future;
    return objects[path];
  }

  @override
  Future<void> create(String path, List<int> bytes, String expectedAccount) async {
    objects[path] = bytes;
  }

  @override
  Future<bool> uploaded(String path, List<int> bytes, String expectedAccount) async => false;
}

class CancellableCloud extends TestCloud implements ICloudCancellablePort {
  final cancelled = Completer<void>();
  int cancellations = 0;
  bool failCancel = false;
  Object? error;
  @override
  Future<List<int>?> read(String path, String expectedAccount) async {
    if (error != null) throw error!;
    if (entered != null && !entered!.isCompleted) entered!.complete();
    if (gate != null) {
      await Future.any([gate!.future, cancelled.future]);
      if (cancelled.isCompleted) throw const SyncTransportException(SyncTransportProblem.paused);
    }
    return objects[path];
  }

  @override
  Future<void> cancelPending() async {
    cancellations++;
    if (failCancel) throw StateError('bridge unavailable');
    if (!cancelled.isCompleted) cancelled.complete();
  }
}

class BindingLedger extends FileSyncLedger {
  BindingLedger(super.root) : super(libraryId: 'library', deviceId: 'device');
  Future<void> Function()? afterBind;
  @override
  Future<void> bindTransport(SyncTarget target) async {
    await super.bindTransport(target);
    final action = afterBind;
    afterBind = null;
    await action?.call();
  }
}

void main() {
  late Directory root;
  late FileSyncLedger ledger;
  late FileLibraryStore library;
  late FileVocabularyStore vocabulary;
  late SyncSettingsController controller;
  late Secrets secrets;
  late TestRemote remote;
  late Map<String, List<int>> objects;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-settings-');
    ledger = BindingLedger(root);
    library = FileLibraryStore(root, sync: ledger);
    vocabulary = FileVocabularyStore(root, sync: ledger);
    await library.create(const NewStudySet(title: 'Private title', colorIndex: 0));
    secrets = Secrets();
    objects = {};
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      transport: (target, auth) {
        remote = TestRemote(target, objects);
        return remote;
      },
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await library.dispose();
    await vocabulary.dispose();
    await root.delete(recursive: true);
  });
  Future<void> connect({
    String account = 'alice',
    String password = 'private-password',
    String url = 'https://dav.test/folder',
  }) => controller.connectWebDav(directory: url, username: account, password: password);

  test('device setup registers once; explicit rename persists and rejects stale forms', () async {
    controller.setup = SyncSetup(libraryId: 'library', deviceId: 'device', deviceName: 'Initial', joining: false);
    await controller.renameDevice('My Mac', expectedRevision: null);
    expect(controller.failure, isNull);
    expect(controller.deviceName, 'My Mac');
    final observed = controller.devices.single.revision;
    await controller.renameDevice('Laptop', expectedRevision: observed);
    await controller.renameDevice('Stale', expectedRevision: observed);
    expect(controller.failure, SyncSettingsFailure.staleDevice);
    expect(controller.deviceName, 'Laptop');
    await controller.initialize();
    expect(controller.deviceName, 'Laptop');
  });

  test('disconnect verifies secret removal, retains histories, and survives restart', () async {
    await connect();
    await controller.syncOnce();
    final selected = controller.target!, before = (await ledger.history()).keys.toSet();
    secrets.failDelete = true;
    await controller.disconnect();
    expect(controller.failure, SyncSettingsFailure.storage);
    expect(controller.target!.key, selected.key);
    expect((await ledger.transportConnection())!.paused, true);
    secrets.failDelete = false;
    await controller.disconnect();
    expect(controller.failure, isNull);
    expect(controller.target, isNull);
    expect(secrets.values, isEmpty);
    expect(await ledger.transportConnection(), isNull);
    expect((await ledger.history()).keys.toSet(), before);
    expect((await ledger.pending(target: selected.key)).where((c) => isSyncWireScope(c.scope)), isEmpty);
    await controller.initialize();
    expect(controller.target, isNull);
    await connect(password: '');
    expect(controller.failure, SyncSettingsFailure.authentication);
    await connect();
    expect(controller.failure, isNull);
    expect(controller.pending, 0);
    await connect(account: 'bob');
    expect(controller.pending, greaterThan(0));
  });

  Future<void> useCloud(TestCloud cloud) async {
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      cloud: () async => cloud,
    );
    await controller.initialize();
  }

  test('pause finishes native waiting work without waiting for physical IO', () async {
    final cloud = CancellableCloud();
    await useCloud(cloud);
    await controller.connectICloud();
    cloud.gate = Completer<void>();
    cloud.entered = Completer<void>();
    final work = controller.syncOnce();
    await cloud.entered!.future;
    await controller.pause();
    await work;
    expect(cloud.gate!.isCompleted, false);
    expect(cloud.cancellations, 1);
    expect(controller.busy, false);
    expect(controller.failure, SyncSettingsFailure.paused);
    expect(controller.result, isNull);
    expect((await ledger.transportConnection())!.paused, true);
    expect(controller.pending, greaterThan(0));
    cloud.gate!.complete();
    expect(cloud.objects, isEmpty);
    await cloud.changes.close();
  });

  test('disposing settings cancels pending native probe and never binds its late result', () async {
    final cloud = CancellableCloud()
      ..gate = Completer<void>()
      ..entered = Completer<void>();
    await useCloud(cloud);
    final work = controller.connectICloud();
    await cloud.entered!.future;
    controller.dispose();
    await work;
    expect(cloud.cancellations, 1);
    expect(cloud.gate!.isCompleted, false);
    expect(cloud.changes.hasListener, false);
    expect(await ledger.transportConnection(), isNull);
    cloud.gate!.complete();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
    );
    await cloud.changes.close();
  });

  test('native timeout remains retryable and does not confirm pending content', () async {
    final cloud = CancellableCloud();
    await useCloud(cloud);
    await controller.connectICloud();
    cloud.error = const SyncTransportException(SyncTransportProblem.timedOut);
    await controller.syncOnce();
    expect(controller.busy, false);
    expect(controller.failure, SyncSettingsFailure.timedOut);
    expect(controller.result, isNull);
    expect((await ledger.transportConnection())!.paused, true);
    expect(controller.pending, greaterThan(0));
    cloud.error = null;
    await controller.syncOnce();
    expect(controller.failure, isNull);
    expect(controller.result!.staged, greaterThan(0));
    await cloud.changes.close();
  });

  test('account notification cancels native work but retains reconnect requirement', () async {
    final cloud = CancellableCloud();
    await useCloud(cloud);
    await controller.connectICloud();
    cloud.gate = Completer<void>();
    cloud.entered = Completer<void>();
    final work = controller.syncOnce();
    await cloud.entered!.future;
    cloud.changes.add(null);
    await work;
    expect(cloud.gate!.isCompleted, false);
    expect(controller.failure, SyncSettingsFailure.accountChanged);
    expect(controller.result, isNull);
    expect((await ledger.transportConnection())!.paused, true);
    await controller.syncOnce();
    expect(controller.failure, SyncSettingsFailure.accountChanged);
    cloud.gate!.complete();
    await cloud.changes.close();
  });

  test('failed native cancellation still persists pause and invalidates late result', () async {
    final cloud = CancellableCloud()..failCancel = true;
    await useCloud(cloud);
    await controller.connectICloud();
    cloud.gate = Completer<void>();
    cloud.entered = Completer<void>();
    final work = controller.syncOnce();
    await cloud.entered!.future;
    await controller.pause();
    expect(controller.failure, SyncSettingsFailure.service);
    expect((await ledger.transportConnection())!.paused, true);
    cloud.gate!.complete();
    await work;
    expect(controller.result, isNull);
    expect(cloud.objects, isEmpty);
    await cloud.changes.close();
  });

  test('pause during port discovery does not start an uncancelled account request', () async {
    final found = Completer<ICloudDrivePort?>(), entered = Completer<void>();
    final cloud = CancellableCloud();
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      cloud: () {
        entered.complete();
        return found.future;
      },
    );
    await controller.initialize();
    final work = controller.connectICloud();
    await entered.future;
    await controller.pause();
    found.complete(cloud);
    await work;
    expect(cloud.changes.hasListener, false);
    expect(controller.failure, SyncSettingsFailure.paused);
    expect(controller.target, isNull);
    await cloud.changes.close();
  });

  test('account notification invalidates waiting work and requires explicit reconnect', () async {
    final cloud = TestCloud();
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      cloud: () async => cloud,
    );
    await controller.initialize();
    await controller.connectICloud();
    cloud.gate = Completer<void>();
    cloud.entered = Completer<void>();
    final operation = controller.syncOnce();
    await cloud.entered!.future;
    cloud.changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.failure, SyncSettingsFailure.accountChanged);
    expect(controller.paused, true);
    expect((await ledger.transportConnection())!.paused, true);
    cloud.gate!.complete();
    await operation;
    expect(controller.result, isNull);
    expect(controller.failure, SyncSettingsFailure.accountChanged);
    expect(cloud.objects, isEmpty);
    await controller.syncOnce();
    expect(controller.failure, SyncSettingsFailure.accountChanged);
    await controller.connectICloud();
    expect(controller.failure, isNull);
    await controller.syncOnce();
    expect(controller.result!.staged, greaterThan(0));
    await controller.disconnect();
    expect(cloud.changes.hasListener, false);
    expect(controller.target, isNull);
    await cloud.changes.close();
  });

  test('notification while binding cannot restore a revoked connection result', () async {
    final cloud = TestCloud();
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      cloud: () async => cloud,
    );
    await controller.initialize();
    (ledger as BindingLedger).afterBind = () async {
      cloud.changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    };
    await controller.connectICloud();
    expect(controller.failure, SyncSettingsFailure.accountChanged);
    expect(controller.target, isNull);
    expect((await ledger.transportConnection())!.paused, true);
    expect(cloud.objects, isEmpty);
    await cloud.changes.close();
  });

  test('notification during initial iCloud probe prevents binding and stream errors pause', () async {
    final cloud = TestCloud()
      ..gate = Completer<void>()
      ..entered = Completer<void>();
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      cloud: () async => cloud,
    );
    await controller.initialize();
    final connect = controller.connectICloud();
    await cloud.entered!.future;
    cloud.changes.addError(StateError('notification unavailable'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cloud.gate!.complete();
    await connect;
    expect(controller.target, isNull);
    expect(controller.failure, SyncSettingsFailure.accountChanged);
    controller.dispose();
    expect(cloud.changes.hasListener, false);
    // Tear down owns a fresh controller rather than disposing the old one twice.
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
    );
    await cloud.changes.close();
  });

  test('connecting is read-only, manual cycle uploads metadata and persists paused', () async {
    expect(controller.initialized, isTrue);
    expect(controller.target, isNull);
    await connect();
    expect(controller.failure, isNull);
    expect(remote.reads, 1);
    expect(remote.creates, 0);
    expect(objects, isEmpty);
    expect(controller.target!.location, 'https://dav.test/folder/');
    expect(secrets.values.values.single, startsWith('Basic '));
    final connectionFile = File('${root.path}/.foliarc-sync/connection.json');
    expect(await connectionFile.readAsString(), isNot(contains('private-password')));
    expect((await ledger.transportConnection())!.paused, isTrue);
    expect(controller.pending, greaterThan(0));
    await controller.syncOnce();
    expect(controller.failure, isNull);
    expect(controller.result!.confirmed, greaterThan(0));
    expect(controller.pending, 0);
    expect(objects.keys, contains('library.json'));
    expect(objects.keys.every((key) => key == 'library.json' || key.startsWith('commits/')), isTrue);
    expect(controller.paused, isTrue);
    expect((await ledger.transportConnection())!.paused, isTrue);
  });

  test('explicit resource download refreshes availability and pauses even on failure', () async {
    final id = (await library.watchAll().first).single.id;
    await library.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'doc',
          title: 'Paper',
          fileName: 'documents/paper.pdf',
          pageCount: 1,
          importedAt: DateTime.utc(2026),
        ),
        files: {
          'documents/paper.pdf': [1, 2, 3],
        },
      ),
    );
    await connect();
    await controller.syncOnce();
    expect(controller.failure, isNull);
    expect(controller.resources.single.availability, SyncResourceAvailability.available);
    await File(library.resolveFile(id, 'documents/paper.pdf')).delete();
    await controller.refreshResources();
    expect(controller.resources.single.availability, SyncResourceAvailability.missing);
    await controller.downloadResource(controller.resources.single);
    expect(controller.failure, isNull);
    expect(controller.resources.single.availability, SyncResourceAvailability.available);
    expect((await ledger.transportConnection())!.paused, isTrue);
    await library.update(id, (c) => c.copyWith(documents: []));
    await controller.downloadResource(controller.resources.single);
    expect(controller.failure, isNotNull);
    expect(controller.resources, isEmpty);
    expect((await ledger.transportConnection())!.paused, isTrue);
  });

  test('restart retains binding but never resumes or reads secrets automatically', () async {
    await connect();
    await ledger.resumeTransport(controller.target!.key);
    final before = remote.reads;
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      transport: (target, auth) => TestRemote(target, objects),
    );
    await controller.initialize();
    expect(controller.target!.account, 'alice');
    expect((await ledger.transportConnection())!.paused, isTrue);
    expect(remote.reads, before);
    await controller.syncOnce();
    expect(controller.failure, isNull);
  });

  test('credential failure leaves old connection paused and no content uploaded', () async {
    await connect();
    final original = controller.target!.key;
    secrets.fail = true;
    await connect(account: 'bob');
    expect(controller.failure, SyncSettingsFailure.storage);
    expect(controller.target!.key, original);
    expect((await ledger.transportConnection())!.paused, isTrue);
    expect(objects, isEmpty);
    expect(controller.failure.toString(), isNot(contains('private password')));
  });

  test('blank password reuses only exact target credential', () async {
    await connect();
    await connect(password: '');
    expect(controller.failure, isNull);
    await connect(account: 'bob', password: '');
    expect(controller.failure, SyncSettingsFailure.authentication);
    expect(controller.target!.account, 'alice');
  });

  test('invalid credentials and locations do not change target or write secrets', () async {
    for (final account in ['', 'bad:user', 'line\nbreak']) {
      await connect(account: account);
      expect(controller.failure, SyncSettingsFailure.invalidInput);
    }
    for (final url in ['http://dav.test', 'https://user:pass@dav.test', 'https://dav.test/?query']) {
      await connect(url: url);
      expect(controller.failure, SyncSettingsFailure.invalidInput);
    }
    expect(controller.target, isNull);
    expect(secrets.values, isEmpty);
  });

  test('pause cancels a pending connection probe before credentials or binding', () async {
    final gate = Completer<void>();
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      transport: (target, auth) => TestRemote(target, objects)..gate = gate,
    );
    await controller.initialize();
    final operation = connect();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await controller.pause();
    gate.complete();
    await operation;
    expect(controller.failure, SyncSettingsFailure.paused);
    expect(controller.target, isNull);
    expect(secrets.values, isEmpty);
  });

  test('joining never creates a replacement for a missing remote library', () async {
    controller.setup = SyncSetup(libraryId: 'library', deviceId: 'device', deviceName: 'Mac', joining: true);
    await connect();
    expect(controller.failure, SyncSettingsFailure.missingLibrary);
    expect(objects, isEmpty);
    expect(controller.target, isNull);
    objects['library.json'] = syncLibraryManifest('library');
    await connect();
    expect(controller.failure, isNull);
    objects.clear();
    await controller.syncOnce();
    expect(controller.failure, SyncSettingsFailure.missingLibrary);
    expect(objects, isEmpty);
  });

  test('wrong manifest is rejected without storing credentials', () async {
    objects['library.json'] = syncLibraryManifest('other');
    await connect();
    expect(controller.failure, SyncSettingsFailure.service);
    expect(secrets.values, isEmpty);
  });

  test('iCloud staging is never reported as cloud confirmed and changed account pauses', () async {
    final cloud = TestCloud();
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      cloud: () async => cloud,
    );
    await controller.initialize();
    await controller.connectICloud();
    expect(controller.failure, isNull);
    expect(cloud.objects, isEmpty);
    await controller.syncOnce();
    expect(controller.result!.staged, greaterThan(0));
    expect(controller.result!.confirmed, 0);
    expect(controller.pending, greaterThan(0));
    cloud.account = 'another';
    await controller.syncOnce();
    expect(controller.failure, SyncSettingsFailure.accountChanged);
    expect((await ledger.transportConnection())!.paused, isTrue);
    expect(secrets.values, isEmpty);
  });

  test('unconfigured iCloud and unsupported credential storage are explicit', () async {
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: false,
      canStoreSecrets: false,
      cloud: () async => null,
    );
    await controller.initialize();
    await controller.connectICloud();
    expect(controller.failure, SyncSettingsFailure.unsupported);
    await connect();
    expect(controller.failure, SyncSettingsFailure.unsupported);
    await controller.activate(deviceName: 'Mac');
    expect(controller.failure, SyncSettingsFailure.unsupported);
  });

  test('startup mismatch does not construct a working receiver', () async {
    controller.dispose();
    final other = FileVocabularyStore(
      root,
      sync: FileSyncLedger(root, libraryId: 'library', deviceId: 'device'),
    );
    controller = SyncSettingsController(library, other, secrets: secrets, canActivate: true, canStoreSecrets: true);
    await controller.initialize();
    expect(controller.initialized, false);
    expect(controller.failure, SyncSettingsFailure.storage);
    await other.dispose();
  });

  test('unloaded packages block transfer without discarding readable sets', () async {
    controller.dispose();
    await library.dispose();
    final file = File('${root.path}/sets/broken.mmset/studyset.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{}');
    library = FileLibraryStore(root, sync: ledger);
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      transport: (t, a) => TestRemote(t, objects),
    );
    await controller.initialize();
    await connect();
    expect(controller.failure, SyncSettingsFailure.incompleteLibrary);
    expect((await library.watchAll().first).single.title, 'Private title');
    expect(objects, isEmpty);
  });

  test('new local library preparation stays local until next startup', () async {
    controller.dispose();
    await library.dispose();
    await vocabulary.dispose();
    final localRoot = Directory('${root.path}/local');
    library = FileLibraryStore(localRoot);
    vocabulary = FileVocabularyStore(localRoot);
    await library.create(const NewStudySet(title: 'Existing local', colorIndex: 0));
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
    );
    await controller.initialize();
    expect(controller.libraryId, isNull);
    await controller.activate(deviceName: 'Mac');
    expect(controller.restartRequired, true);
    expect(controller.failure, isNull);
    expect(await library.syncLedger, isNull);
    expect(await FileSyncLedger.restore(localRoot), isNull);
    expect((await library.watchAll().first).single.title, 'Existing local');
    await controller.cancelActivation();
    expect(controller.restartRequired, false);
    expect(await FileSyncSetup(localRoot).read(), isNull);
    await controller.activate(existingLibraryId: 'join-this', deviceName: 'Phone');
    expect(controller.libraryId, 'join-this');
    expect(controller.setup!.joining, true);
  });

  test('verified legacy identity can connect without replacing local history', () async {
    final old = SyncCommit.create(
      libraryId: ledger.libraryId,
      scope: 'library',
      deviceId: 'old',
      sequence: 1,
      protocol: 1,
      payload: {'oldNumeric': 1.0},
    );
    await ledger.receive([old]);
    await connect();
    expect(controller.failure, isNull);
    expect(controller.target, isNotNull);
    expect((await ledger.history())[old.id]!.id, old.id);
    expect(objects, isEmpty, reason: 'Connection probe never uploads historical data');
  });

  test('incomplete legacy graph is blocked before probing remote or storing credentials', () async {
    await ledger.receive([
      SyncCommit.create(
        libraryId: ledger.libraryId,
        scope: 'sets/old',
        deviceId: 'old',
        sequence: 1,
        protocol: 1,
        parents: [syncDigest('missing legacy ancestor')],
        payload: {},
      ),
    ]);
    await connect();
    expect(controller.failure, SyncSettingsFailure.legacyProtocol);
    expect(secrets.values, isEmpty);
    expect(objects, isEmpty);
    expect(controller.target, isNull);
  });

  test('pause invalidates an in-flight manual cycle and preserves its queue', () async {
    await connect();
    final selected = controller.target!, gate = Completer<void>();
    controller.dispose();
    controller = SyncSettingsController(
      library,
      vocabulary,
      secrets: secrets,
      canActivate: true,
      canStoreSecrets: true,
      transport: (target, auth) => TestRemote(target, objects)..gate = gate,
    );
    await controller.initialize();
    final run = controller.syncOnce();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await controller.pause();
    gate.complete();
    await run;
    expect(controller.failure, SyncSettingsFailure.paused);
    expect(controller.result, isNull);
    expect(controller.pending, greaterThan(0));
    expect((await ledger.transportConnection())!.target.key, selected.key);
    expect((await ledger.transportConnection())!.paused, true);
    expect(objects, isEmpty);
  });

  test('live queue status observes local writes', () async {
    await connect();
    await controller.syncOnce();
    expect(controller.pending, 0);
    await library.create(const NewStudySet(title: 'After sync', colorIndex: 0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.pending, greaterThan(0));
  });

  test('joining another device preserves its local set and publishes through real receivers', () async {
    await connect();
    await controller.syncOnce();
    final secondRoot = Directory('${root.path}/second');
    final original = FileLibraryStore(secondRoot);
    await original.create(const NewStudySet(title: 'Phone local content', colorIndex: 1));
    await original.dispose();
    final setup = FileSyncSetup(secondRoot);
    await setup.request(libraryId: ledger.libraryId, deviceName: 'Phone');
    final secondLedger = (await setup.openLedger())!;
    expect(secondLedger.deviceId, isNot(ledger.deviceId));
    final secondLibrary = FileLibraryStore(secondRoot, sync: secondLedger);
    final secondWords = FileVocabularyStore(secondRoot, sync: secondLedger);
    final second = SyncSettingsController(
      secondLibrary,
      secondWords,
      secrets: Secrets(),
      canActivate: true,
      canStoreSecrets: true,
      transport: (t, a) => TestRemote(t, objects),
    );
    try {
      await second.initialize();
      expect(second.deviceName, 'Phone');
      await second.connectWebDav(directory: 'https://dav.test/folder', username: 'alice', password: 'secret');
      expect(second.failure, isNull);
      await second.syncOnce();
      expect(second.failure, isNull);
      expect(
        (await secondLibrary.watchAll().first).map((s) => s.title),
        unorderedEquals(['Private title', 'Phone local content']),
      );
      await controller.syncOnce();
      expect(controller.failure, isNull);
      expect(controller.devices.single.name, 'Phone');
      expect(
        (await library.watchAll().first).map((s) => s.title),
        unorderedEquals(['Private title', 'Phone local content']),
      );
    } finally {
      second.dispose();
      await secondLibrary.dispose();
      await secondWords.dispose();
    }
  });
}
