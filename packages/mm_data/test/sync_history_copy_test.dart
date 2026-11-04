import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:mm_data/src/resource_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'sync_engine_test.dart' show Remote, problem;

class BlockingRemote extends Remote {
  BlockingRemote() : super({});
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<List<int>?> read(String key) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.read(key);
  }
}

void main() {
  late Directory root;
  late FileSyncLedger ledger, other;
  late FileLibraryStore library, peer;
  late FileVocabularyStore words, peerWords;
  late FileSyncEngine engine;
  late String id;
  late Remote destination;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('history-copy-');
    ledger = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    other = FileSyncLedger(Directory('${root.path}/b'), libraryId: 'lib', deviceId: 'b');
    library = FileLibraryStore(ledger.root, sync: ledger);
    peer = FileLibraryStore(other.root, sync: other);
    words = FileVocabularyStore(ledger.root, sync: ledger);
    peerWords = FileVocabularyStore(other.root, sync: other);
    engine = FileSyncEngine(ledger, FileSyncReceiver(library, words));
    id = (await library.create(const NewStudySet(title: 'Origin', colorIndex: 0))).id;
    await peer.receiveSync((await ledger.pending()).where((c) => isSyncWireScope(c.scope)));
    await peer.rename(id, 'Contribution from another device');
    await library.receiveSync((await other.pending()).where((c) => isSyncWireScope(c.scope)));
    await FileSyncReceiver(library, words).validateLedger(ledger);
    destination = Remote({}, account: 'destination');
    await engine.bind(destination);
  });
  tearDown(() async {
    await library.dispose();
    await peer.dispose();
    await words.dispose();
    await peerWords.dispose();
    await root.delete(recursive: true);
  });

  test('explicit preview copies accepted remote ancestry and restarts without changing ordinary pending', () async {
    await words.save([
      VocabularyEntry(
        id: 'word',
        term: 'Word',
        language: 'en',
        kind: VocabularyKind.word,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        forms: ['word'],
      ),
    ]);
    final source = await ledger.historyCopySource();
    final own = (await ledger.pending(includeDelivered: true))
        .where((c) => isSyncWireScope(c.scope))
        .map((c) => c.id)
        .toSet();
    final plan = await engine.previewHistoryCopy();
    expect(destination.objects, isEmpty);
    expect(plan.otherDeviceCommits, source.commits.values.where((c) => c.deviceId == 'b').length);
    expect(plan.otherDeviceCommits, greaterThan(0));
    expect(plan.commits, source.commits.length);
    final result = await engine.copyHistory(plan);
    expect(result.confirmed, plan.commits);
    expect(result.staged, 0);
    expect(
      (await ledger.pending(includeDelivered: true)).where((c) => isSyncWireScope(c.scope)).map((c) => c.id).toSet(),
      own,
    );
    for (final id in source.commits.keys) {
      expect(destination.objects.containsKey('commits/$id.json'), true);
    }
    expect(destination.objects.keys.every((k) => k == 'library.json' || k.startsWith('commits/')), true);
    await expectLater(engine.copyHistory(plan), problem(SyncTransportProblem.paused));
    final newLedger = FileSyncLedger(Directory('${root.path}/c'), libraryId: 'lib', deviceId: 'c');
    final target = FileLibraryStore(newLedger.root, sync: newLedger);
    final targetWords = FileVocabularyStore(newLedger.root, sync: newLedger);
    try {
      final targetEngine = FileSyncEngine(newLedger, FileSyncReceiver(target, targetWords));
      await targetEngine.bind(destination);
      await targetEngine.resume();
      await targetEngine.run();
      expect((await target.watchAll().first).single.title, 'Contribution from another device');
      expect((await (await FileSyncLedger.restore(newLedger.root))!.history()).keys, containsAll(source.commits.keys));
    } finally {
      await target.dispose();
      await targetWords.dispose();
    }
  });

  test('unaccepted receipts are reported and excluded, while accepted deleted ancestry remains', () async {
    final stranger = SyncCommit.create(
      libraryId: 'lib',
      scope: 'sets/unknown',
      deviceId: 'unknown',
      sequence: 1,
      payload: {'privateProbe': 'UNACCEPTED INPUT'},
    );
    await ledger.receive([stranger]);
    await library.delete(id);
    final plan = await engine.previewHistoryCopy();
    expect(plan.excluded, 1);
    await engine.copyHistory(plan);
    expect(destination.objects.containsKey('commits/${stranger.id}.json'), false);
    expect(destination.objects.values.any((b) => utf8.decode(b).contains('UNACCEPTED INPUT')), false);
    final all = destination.objects.entries
        .where((e) => e.key.startsWith('commits/'))
        .map((e) => SyncCommit.fromJson((jsonDecode(utf8.decode(e.value)) as Map).cast()));
    expect(all.any((c) => c.scope == 'sets/$id' && c.deleted), true);
    expect(all.any((c) => c.payload['title'] == 'Origin'), true);
  });

  test('changed content, a draft and resource staging invalidate consent without writing destination', () async {
    final plan = await engine.previewHistoryCopy();
    await library.rename(id, 'Newer');
    await expectLater(engine.copyHistory(plan), throwsA(isA<SyncRevisionChanged>()));
    expect(destination.objects, isEmpty);
    await library.beginContentTransaction(id);
    await expectLater(engine.previewHistoryCopy(), throwsA(isA<SyncRevisionChanged>()));
    await library.endContentTransaction(id);
    await ledger.stageResources(() async {
      await expectLater(engine.previewHistoryCopy(), throwsA(isA<SyncRevisionChanged>()));
    });
    expect(destination.objects, isEmpty);
    await engine.copyHistory(await engine.previewHistoryCopy());
  });

  test('another owner pausing the binding rejects reviewed connection even for the same target', () async {
    final plan = await engine.previewHistoryCopy();
    await ledger.pauseTransport();
    await expectLater(engine.copyHistory(plan), problem(SyncTransportProblem.paused));
    expect(destination.objects, isEmpty);
    final fresh = await engine.previewHistoryCopy();
    await engine.pause();
    await expectLater(engine.copyHistory(fresh), problem(SyncTransportProblem.paused));
  });

  test('pause or rebinding during a copy prevents late confirmation and following requests', () async {
    final plan = await engine.previewHistoryCopy();
    final entered = Completer<void>(), release = Completer<void>();
    destination.beforeCreate = (key) async {
      if (key.startsWith('commits/') && !entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    };
    final copying = engine.copyHistory(plan);
    final rejected = expectLater(copying, problem(SyncTransportProblem.paused));
    await entered.future;
    await expectLater(engine.copyHistory(plan), problem(SyncTransportProblem.unavailable));
    final another = Remote({}, account: 'different');
    await engine.bind(another);
    release.complete();
    await rejected;
    expect(another.calls, 0);
    expect(await ledger.pending(target: destination.target.key), isNotEmpty);
    expect(destination.objects.keys.where((k) => k.startsWith('commits/')).length, 1);
    await engine.bind(destination);
    destination.beforeCreate = null;
    await engine.copyHistory(await engine.previewHistoryCopy());
    expect((await ledger.pending(target: destination.target.key)).where((c) => isSyncWireScope(c.scope)), isEmpty);
  });

  test('staged delivery never acknowledges local outbox; repeat preview verifies and confirms', () async {
    destination.delivery = SyncDelivery.staged;
    final plan = await engine.previewHistoryCopy();
    final result = await engine.copyHistory(plan);
    expect(result.confirmed, 0);
    expect(result.staged, plan.commits);
    expect(await ledger.pending(target: destination.target.key), isNotEmpty);
    destination.delivery = SyncDelivery.confirmed;
    final count = destination.objects.length;
    await engine.copyHistory(await engine.previewHistoryCopy());
    expect(destination.objects.length, count);
    expect((await ledger.pending(target: destination.target.key)).where((c) => isSyncWireScope(c.scope)), isEmpty);
  });

  test('wrong target manifests fail before publication', () async {
    destination.objects['library.json'] = syncLibraryManifest('wrong');
    await expectLater(engine.previewHistoryCopy(), problem(SyncTransportProblem.wrongLibrary));
    expect(destination.objects.length, 1);
    destination.objects.clear();
    await engine.copyHistory(await engine.previewHistoryCopy());
  });
  test('historical chunks preflight before writes and an interrupted copy resumes after restart', () async {
    final data = List<int>.generate(512, (i) => i % 251);
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
        files: {'documents/paper.pdf': data},
      ),
    );
    await library.prepareSyncResources();
    final hash = sha256.convert(data).toString();
    final chunk = File('${ledger.root.path}/.foliarc-sync/blobs/$hash');
    await chunk.delete();
    await expectLater(engine.previewHistoryCopy(), problem(SyncTransportProblem.unavailable));
    expect(destination.objects, isEmpty);
    // Explicitly restore a verified chunk. Preview never scans package files.
    await ResourceCache(ledger.root).storeChunk(hash, data);
    final plan = await engine.previewHistoryCopy();
    expect(plan.chunks, 1);
    var count = 0;
    destination.beforeCreate = (key) async {
      if (key.startsWith('commits/') && count++ == 1) throw const SyncTransportException(SyncTransportProblem.quota);
    };
    await expectLater(engine.copyHistory(plan), problem(SyncTransportProblem.quota));
    expect(destination.objects['blobs/$hash.bin'], data);
    final restored = (await FileSyncLedger.restore(ledger.root))!;
    final reopened = FileLibraryStore(ledger.root, sync: restored);
    final vocabulary = FileVocabularyStore(ledger.root, sync: restored);
    try {
      final retry = FileSyncEngine(restored, FileSyncReceiver(reopened, vocabulary));
      destination.beforeCreate = null;
      await retry.bind(destination);
      // Re-read verified destination chunks when the local cache is absent.
      await chunk.delete();
      final retried = await retry.previewHistoryCopy();
      expect((await retry.copyHistory(retried)).staged, 0);
      expect(retried.commits, plan.commits);
    } finally {
      await reopened.dispose();
      await vocabulary.dispose();
    }
  });

  test('changed history while publishing leaves all acknowledgements pending', () async {
    final plan = await engine.previewHistoryCopy();
    destination.beforeCreate = (key) async {
      if (key.startsWith('commits/')) await library.rename(id, 'Changed during copy');
    };
    await expectLater(engine.copyHistory(plan), throwsA(isA<SyncRevisionChanged>()));
    expect((await ledger.pending(target: destination.target.key)).where((c) => isSyncWireScope(c.scope)), isNotEmpty);
  });

  test('inspection and confirmation require a bound target and an engine-issued current plan', () async {
    final unbound = FileSyncEngine(ledger, FileSyncReceiver(library, words));
    await expectLater(unbound.previewHistoryCopy(), problem(SyncTransportProblem.paused));
    final plan = await engine.previewHistoryCopy();
    await expectLater(unbound.copyHistory(plan), problem(SyncTransportProblem.paused));
    await engine.bind(Remote({}, account: 'new'));
    await expectLater(engine.copyHistory(plan), problem(SyncTransportProblem.paused));
  });
  test('copy verifies complete book and web package closures before publishing chunks', () async {
    final chapter = utf8.encode('{"text":"hello"}'), image = [1, 2, 3], snapshot = utf8.encode('<p>hi</p>');
    final hash = sha256.convert(chapter).toString(), imageHash = sha256.convert(image).toString();
    const base = 'books/book/version', web = 'web/book/capture';
    final chapterPath = '$base/chapters/$hash.json', imagePath = '$base/resources/$imageHash.png';
    final files = <String, List<int>>{
      '$base/manifest.json': utf8.encode(
        jsonEncode({
          'spine': [
            {'path': chapterPath, 'sha256': hash},
          ],
          'resources': [
            {'path': imagePath, 'sha256': imageHash},
          ],
        }),
      ),
      chapterPath: chapter,
      imagePath: image,
      '$web/snapshot.html': snapshot,
      '$web/resources.json': utf8.encode(
        jsonEncode({
          'snapshotSha256': sha256.convert(snapshot).toString(),
          'resources': {'resources/image-1.png': imageHash},
        }),
      ),
      '$web/resources/image-1.png': image,
      'documents/original.md': utf8.encode('original'),
    };
    await library.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'book',
          title: 'Book',
          fileName: '$base/manifest.json',
          contentManifest: '$base/manifest.json',
          sourceFileName: 'documents/original.md',
          pageCount: 0,
          importedAt: DateTime.utc(2026),
          revision: 'version',
          layout: DocumentLayout.reflow,
          origin: DocumentOrigin(
            url: 'https://example.com',
            capturedAt: DateTime.utc(2026),
            snapshotFile: '$web/snapshot.html',
          ),
        ),
        files: files,
      ),
    );
    await library.prepareSyncResources();
    final plan = await engine.previewHistoryCopy();
    expect(destination.objects, isEmpty);
    await engine.copyHistory(plan);
    for (final bytes in files.values) {
      expect(destination.objects['blobs/${sha256.convert(bytes)}.bin'], bytes);
    }
  });

  test('frozen private prerequisites cannot be forwarded even by an explicit copy', () async {
    await ledger.commit([
      SyncMutation('private/input', local: {'secret': 'private'}, shared: {}),
      SyncMutation(
        'folders/invalid',
        local: {'id': 'invalid', 'name': 'Folder'},
        shared: {'id': 'invalid', 'name': 'Folder'},
        requireScopes: ['private/input'],
      ),
    ]);
    await expectLater(engine.previewHistoryCopy(), problem(SyncTransportProblem.missingHistory));
    expect(destination.calls, 0);
  });
  test('preview reserves engine work and discards results after a pause', () async {
    final blocked = BlockingRemote();
    await engine.bind(blocked);
    final preview = engine.previewHistoryCopy();
    final rejected = expectLater(preview, problem(SyncTransportProblem.paused));
    await blocked.entered.future;
    await expectLater(engine.previewHistoryCopy(), problem(SyncTransportProblem.unavailable));
    await expectLater(engine.run(), problem(SyncTransportProblem.unavailable));
    await engine.pause();
    blocked.release.complete();
    await rejected;
    expect(engine.running, false);
    expect(blocked.objects, isEmpty);
  });
  test('unresolved accepted candidates stay pending through copy and a third device', () async {
    await library.rename(id, 'Candidate A');
    await peer.rename(id, 'Candidate B');
    await library.receiveSync((await other.pending()).where((c) => isSyncWireScope(c.scope)));
    final accepted = (await ledger.snapshots())['sets/$id']!.commit;
    expect(accepted.pending, isNotEmpty);
    await engine.copyHistory(await engine.previewHistoryCopy());
    final thirdLedger = FileSyncLedger(Directory('${root.path}/third'), libraryId: 'lib', deviceId: 'third');
    final third = FileLibraryStore(thirdLedger.root, sync: thirdLedger);
    final thirdWords = FileVocabularyStore(thirdLedger.root, sync: thirdLedger);
    try {
      await FileSyncReceiver(third, thirdWords).receive(
        destination.objects.entries
            .where((e) => e.key.startsWith('commits/'))
            .map((e) => SyncCommit.fromJson((jsonDecode(utf8.decode(e.value)) as Map).cast())),
      );
      final received = (await thirdLedger.snapshots())['sets/$id']!.commit;
      expect(received.id, accepted.id);
      expect(received.pending, accepted.pending);
      expect((await third.contentSyncStatus(id)).conflicts, isNotEmpty);
      final reopened = (await FileSyncLedger.restore(thirdLedger.root))!;
      expect((await reopened.snapshots())['sets/$id']!.commit.pending, accepted.pending);
    } finally {
      await third.dispose();
      await thirdWords.dispose();
    }
  });
}
