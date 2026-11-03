import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

Matcher problem(SyncTransportProblem p) =>
    throwsA(isA<SyncTransportException>().having((e) => e.problem, 'problem', p));

class Remote implements SyncObjectTransport {
  Remote(this.objects, {String account = 'a', String library = 'lib'})
    : target = SyncTarget(service: 'test', account: account, location: 'server', libraryId: library);
  final Map<String, List<int>> objects;
  @override
  final SyncTarget target;
  SyncDelivery delivery = SyncDelivery.confirmed;
  bool manifestStaged = false;
  int calls = 0;
  Future<void> Function(String)? beforeCreate;
  @override
  Future<void> prepare() async {
    calls++;
  }

  @override
  Future<List<String>> listCommits() async {
    calls++;
    return objects.keys
        .where((k) => k.startsWith('commits/'))
        .map((k) => k.substring(8, k.length - 5))
        .toList()
        .reversed
        .toList();
  }

  @override
  Future<List<int>?> read(String key) async {
    calls++;
    return objects[key];
  }

  @override
  Future<SyncDelivery> create(String key, List<int> bytes) async {
    calls++;
    await beforeCreate?.call(key);
    if (objects.containsKey(key) && !sameSyncObject(objects[key]!, bytes)) {
      throw const SyncTransportException(SyncTransportProblem.collision);
    }
    objects[key] = bytes;
    return manifestStaged && key == 'library.json' ? SyncDelivery.staged : delivery;
  }
}

void main() {
  late Directory root;
  late FileSyncLedger la, lb;
  late FileLibraryStore a, b;
  late FileVocabularyStore va, vb;
  late FileSyncEngine x, y;
  late Remote ra, rb;
  late String id;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-engine-');
    la = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    lb = FileSyncLedger(Directory('${root.path}/b'), libraryId: 'lib', deviceId: 'b');
    a = FileLibraryStore(la.root, sync: la);
    b = FileLibraryStore(lb.root, sync: lb);
    va = FileVocabularyStore(la.root, sync: la);
    vb = FileVocabularyStore(lb.root, sync: lb);
    x = FileSyncEngine(la, FileSyncReceiver(a, va));
    y = FileSyncEngine(lb, FileSyncReceiver(b, vb));
    final objects = <String, List<int>>{};
    ra = Remote(objects);
    rb = Remote(objects);
    id = (await a.create(const NewStudySet(title: 'Private-first study', colorIndex: 0))).id;
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await va.dispose();
    await vb.dispose();
    await root.delete(recursive: true);
  });
  Future<void> start(FileSyncEngine e, Remote r) async {
    await e.bind(r);
    await e.resume();
  }

  Future<List<SyncCommit>> pending(FileSyncLedger l, Remote r) async =>
      (await l.pending(target: r.target.key)).where((c) => isSyncWireScope(c.scope)).toList();
  test('two repositories exchange real shared commits and recover delivery without echo or private files', () async {
    final now = DateTime.utc(2026);
    await va.save([
      VocabularyEntry(
        id: 'legacy-word',
        term: 'Word',
        language: 'en',
        kind: VocabularyKind.word,
        createdAt: now,
        updatedAt: now,
        forms: ['word'],
        note: 'All sources remain local-first',
      ),
    ]);
    await start(x, ra);
    await start(y, rb);
    expect((await x.run()).confirmed, greaterThan(0));
    expect(await pending(la, ra), isEmpty);
    expect(
      ra.objects.keys.every((k) => k == 'library.json' || RegExp(r'^commits/[a-f0-9]{64}\.json$').hasMatch(k)),
      isTrue,
    );
    for (final entry in ra.objects.entries.where((e) => e.key.startsWith('commits/'))) {
      final commit = SyncCommit.fromJson((jsonDecode(utf8.decode(entry.value)) as Map).cast());
      expect(commit.scope, isNot('library'));
      expect(commit.scope, isNot('vocabulary'));
      expect(commit.payload.containsKey('lastOpenedAt'), isFalse);
    }
    await y.run();
    expect((await vb.load()).single.note, 'All sources remain local-first');
    expect((await b.watchAll().first).single.title, 'Private-first study');
    await b.rename(id, 'Remote title');
    await y.run();
    await x.run();
    expect((await a.watchAll().first).single.title, 'Remote title');
    final restored = (await FileSyncLedger.restore(la.root))!;
    expect((await restored.transportConnection())!.target.key, ra.target.key);
    expect(await pending(restored, ra), isEmpty);
    final count = ra.objects.length;
    await x.run();
    expect(ra.objects.length, count);
    // An independently cleared target must be repaired or explicitly blocked,
    // never silently trusted merely because a local acknowledgement exists.
    final own = (await la.pending(
      target: ra.target.key,
      includeDelivered: true,
    )).firstWhere((c) => c.scope == 'sets/$id');
    ra.objects.remove('commits/${own.id}.json');
    await x.run();
    expect(ra.objects.containsKey('commits/${own.id}.json'), isTrue);
  });
  test('local iCloud-style staging and an unconfirmed manifest cannot acknowledge delivery', () async {
    ra.delivery = SyncDelivery.staged;
    await start(x, ra);
    final staged = await x.run();
    expect(staged.confirmed, 0);
    expect(staged.staged, greaterThan(0));
    expect(await pending(la, ra), isNotEmpty);
    ra.delivery = SyncDelivery.confirmed;
    ra.manifestStaged = true;
    expect((await x.run()).confirmed, 0);
    expect(await pending(la, ra), isNotEmpty);
    ra.manifestStaged = false;
    expect((await x.run()).confirmed, greaterThan(0));
    expect(await pending(la, ra), isEmpty);
  });
  test('pause interrupts the next request and late completion never acknowledges a new account', () async {
    await start(x, ra);
    final entered = Completer<void>(), release = Completer<void>();
    ra.beforeCreate = (key) async {
      if (key.startsWith('commits/') && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final run = x.run();
    expect(identical(x.run(), run), isTrue);
    final result = expectLater(run, problem(SyncTransportProblem.paused));
    await entered.future;
    await x.pause();
    final other = Remote({}, account: 'b');
    await x.bind(other);
    release.complete();
    await result;
    expect(await pending(la, ra), isNotEmpty);
    expect(await pending(la, other), isNotEmpty);
    expect((await la.transportConnection())!.paused, isTrue);
    await expectLater(x.run(), problem(SyncTransportProblem.paused));
    expect(other.calls, 0);
    await x.resume();
    await x.run();
    expect(await pending(la, other), isEmpty);
    expect(await pending(la, ra), isNotEmpty);
    final old = (await la.transportConnection())!;
    await x.pause();
    await expectLater(
      la.acknowledge([], target: other.target.key, connectionRevision: old.revision),
      problem(SyncTransportProblem.paused),
    );
    expect(
      ((await FileSyncLedger.restore(la.root))!.transportConnection()),
      completion(isA<SyncTransportConnection>().having((c) => c.paused, 'paused', true)),
    );
  });
  test('failed local confirmation retains the queue and retry verifies the existing remote object', () async {
    await start(x, ra);
    final blocker = Directory('${la.root.path}/.foliarc-sync/delivery-${syncDigest(ra.target.key)}.json.tmp');
    await blocker.create(recursive: true);
    await expectLater(x.run(), throwsA(isA<FileSystemException>()));
    expect(await pending(la, ra), isNotEmpty);
    expect(ra.objects.keys.any((k) => k.startsWith('commits/')), isTrue);
    await blocker.delete();
    await x.run();
    expect(await pending(la, ra), isEmpty);
    final other = Remote({}, account: 'quota');
    other.beforeCreate = (_) async => throw const SyncTransportException(SyncTransportProblem.quota);
    await start(x, other);
    await expectLater(x.run(), problem(SyncTransportProblem.quota));
    expect(await pending(la, other), isNotEmpty);
  });
  test('v1 history is rejected before network IO without rewriting or deleting it', () async {
    final legacy = SyncCommit.create(
      libraryId: 'lib',
      scope: 'sets/old',
      deviceId: 'old',
      sequence: 1,
      protocol: 1,
      payload: {},
    );
    await la.receive([legacy]);
    await start(x, ra);
    await expectLater(x.run(), problem(SyncTransportProblem.legacyProtocol));
    expect(ra.calls, 0);
    expect((await la.history())[legacy.id]!.protocol, 1);
  });
  test('wrong manifest, malformed commit and a new target missing received ancestors are not published', () async {
    await start(x, ra);
    ra.objects['library.json'] = syncLibraryManifest('other');
    await expectLater(x.run(), problem(SyncTransportProblem.wrongLibrary));
    expect(ra.objects.length, 1);
    ra.objects.clear();
    await x.run();
    await start(y, rb);
    await y.run();
    await b.rename(id, 'B contribution');
    final isolated = Remote({}, account: 'new-account');
    await y.bind(isolated);
    await y.resume();
    await expectLater(y.run(), problem(SyncTransportProblem.missingHistory));
    expect(isolated.objects.keys, ['library.json']);
    await y.bind(rb);
    await y.resume();
    await y.run();
    final badId = syncDigest('bad');
    ra.objects['commits/$badId.json'] = utf8.encode('{}');
    await expectLater(x.run(), problem(SyncTransportProblem.legacyProtocol));
    ra.objects['commits/$badId.json'] = utf8.encode('{"protocol":2}');
    await expectLater(x.run(), problem(SyncTransportProblem.invalidResponse));
    expect((await la.history()).containsKey(badId), isFalse);
  });
  test('drafts held before and during transmission do not publish intermediate content', () async {
    await start(x, ra);
    await a.beginContentTransaction(id);
    await a.rename(id, 'Unfinished');
    await x.run();
    expect(ra.objects.keys, ['library.json']);
    await a.endContentTransaction(id);
    await x.run();
    await start(y, rb);
    await y.run();
    expect((await b.watchAll().first).single.title, 'Unfinished');
  });
  test('binding rejects wrong library and the receiver cannot use a different ledger', () async {
    await expectLater(x.bind(Remote({}, library: 'other')), problem(SyncTransportProblem.wrongLibrary));
    await expectLater(x.resume(), problem(SyncTransportProblem.paused));
    await expectLater(la.resumeTransport('missing'), problem(SyncTransportProblem.accountChanged));
    final wrong = FileSyncEngine(la, FileSyncReceiver(b, vb));
    await start(wrong, ra);
    await expectLater(wrong.run(), throwsStateError);
    expect(ra.calls, 0);
  });
}
