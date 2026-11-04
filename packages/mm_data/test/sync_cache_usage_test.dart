import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/resource_cache.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileSyncLedger ledger;
  late ResourceCache cache;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-cache-');
    ledger = FileSyncLedger(root, libraryId: 'lib', deviceId: 'local');
    cache = ResourceCache(root);
  });
  tearDown(() => root.delete(recursive: true));
  Future<String> chunk(int value) async {
    final bytes = [value, value];
    final hash = sha256.convert(bytes).toString();
    await cache.storeChunk(hash, bytes);
    return hash;
  }

  Map<String, Object?> payload(String hash) => {
    'resources': SyncResources({
      'document/d/revision': {
        'documents/a.pdf': SyncResourceFile(hash: hash, length: 2, chunks: [hash]),
      },
    }).toJson(),
  };

  test('empty cache does not scan package files or create a blob directory', () async {
    final original = File('${root.path}/document.pdf');
    await original.writeAsBytes([1, 2]);
    final usage = await ledger.resourceCacheUsage(reclaim: true);
    expect(usage.bytes, 0);
    expect(usage.chunks, 0);
    expect(usage.canReclaim, true);
    expect(await Directory('${root.path}/.foliarc-sync/blobs').exists(), false);
    expect(await original.readAsBytes(), [1, 2]);
  });

  test('all historical, received and private draft references survive collection and restart', () async {
    final historical = await chunk(1), received = await chunk(2), draft = await chunk(3), orphan = await chunk(4);
    await ledger.commit([SyncMutation('sets/a', local: payload(historical), shared: payload(historical))]);
    await ledger.commit([SyncMutation('sets/a', local: null, shared: null)]);
    // Received but unaccepted input must still pin its resources.
    await ledger.receive([
      SyncCommit.create(
        libraryId: 'lib',
        scope: 'sets/remote',
        deviceId: 'remote',
        sequence: 1,
        payload: payload(received),
      ),
    ]);
    await ledger.commit([SyncMutation('sets/draft', local: {}, shared: {})]);
    await ledger.commit([SyncMutation('sets/draft', local: payload(draft), shared: {}, deferShared: true)]);
    await ledger.acknowledge((await ledger.pending()).map((c) => c.id));
    final before = await ledger.history();
    final privateFiles = await Directory('${root.path}/.foliarc-sync/local')
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    final privateBytes = {for (final f in privateFiles) f.path: await f.readAsBytes()};
    final preview = await ledger.resourceCacheUsage();
    expect(preview.bytes, 8);
    expect(preview.reclaimableBytes, 2);
    final result = await ledger.resourceCacheUsage(reclaim: true);
    expect(result.reclaimedBytes, 2);
    expect(result.bytes, 6);
    expect(result.reclaimableChunks, 0);
    expect(await cache.readChunk(orphan), isNull);
    for (final hash in [historical, received, draft]) {
      expect(await cache.readChunk(hash), isNotNull);
    }
    for (final f in privateFiles) {
      expect(await f.readAsBytes(), privateBytes[f.path]);
    }
    final reopened = (await FileSyncLedger.restore(root))!;
    expect((await reopened.history()).keys, before.keys);
    expect((await reopened.resourceCacheUsage(reclaim: true)).reclaimedBytes, 0);
  });

  test('displayed unused count is not deletion authority after new receipt', () async {
    final hash = await chunk(5);
    expect((await ledger.resourceCacheUsage()).reclaimableChunks, 1);
    await ledger.receive([
      SyncCommit.create(libraryId: 'lib', scope: 'sets/a', deviceId: 'r', sequence: 1, payload: payload(hash)),
    ]);
    expect((await ledger.resourceCacheUsage(reclaim: true)).reclaimedBytes, 0);
    expect(await cache.readChunk(hash), isNotNull);
  });

  test('missing ancestors prevent collection until their references become known', () async {
    final hash = await chunk(10);
    final ancestor = SyncCommit.create(
      libraryId: 'lib',
      scope: 'sets/a',
      deviceId: 'r',
      sequence: 1,
      payload: payload(hash),
    );
    final child = SyncCommit.create(
      libraryId: 'lib',
      scope: 'sets/a',
      deviceId: 'r',
      sequence: 2,
      parents: [ancestor.id],
      payload: {},
    );
    await ledger.receive([child]);
    final blocked = await ledger.resourceCacheUsage(reclaim: true);
    expect(blocked.incompleteHistory, true);
    expect(blocked.canReclaim, false);
    expect(await cache.readChunk(hash), isNotNull);
    await ledger.receive([ancestor]);
    final complete = await ledger.resourceCacheUsage(reclaim: true);
    expect(complete.incompleteHistory, false);
    expect(complete.canReclaim, true);
    expect(complete.reclaimedBytes, 0);
  });

  test('staged blocks cannot be collected before their manifest commits', () async {
    final entered = Completer<String>(), finish = Completer<void>();
    final operation = ledger.stageResources(() async {
      final hash = await chunk(6);
      entered.complete(hash);
      await finish.future;
      await ledger.commit([SyncMutation('sets/a', local: payload(hash), shared: payload(hash))]);
    });
    final hash = await entered.future;
    try {
      final blocked = await ledger.resourceCacheUsage(reclaim: true);
      expect(blocked.staging, true);
      expect(blocked.canReclaim, false);
      expect(blocked.reclaimedBytes, 0);
      expect(await cache.readChunk(hash), isNotNull);
    } finally {
      finish.complete();
      await operation;
    }
    expect((await ledger.resourceCacheUsage(reclaim: true)).reclaimedBytes, 0);
  });

  test('failed staging releases its lease and orphan removal is retryable', () async {
    await expectLater(
      ledger.stageResources(() async {
        await chunk(7);
        throw StateError('failed before commit');
      }),
      throwsStateError,
    );
    final result = await ledger.resourceCacheUsage(reclaim: true);
    expect(result.canReclaim, true);
    expect(result.reclaimedBytes, 2);
    expect((await ledger.resourceCacheUsage(reclaim: true)).reclaimedBytes, 0);
  });

  test('real manifest preparation excludes reclamation until its atomic commit', () async {
    final probe = _StagingProbeLedger(root);
    final library = FileLibraryStore(root, sync: probe);
    addTearDown(library.dispose);
    final id = (await library.create(const NewStudySet(title: 'Source', colorIndex: 0))).id;
    await library.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'doc',
          title: 'PDF',
          fileName: 'documents/a.pdf',
          pageCount: 1,
          importedAt: DateTime.utc(2026),
        ),
        files: {
          'documents/a.pdf': [1, 2, 3],
        },
      ),
    );
    await library.prepareSyncResources();
    expect(probe.probes, 1);
    final usage = await probe.resourceCacheUsage(reclaim: true);
    expect(usage.staging, false);
    expect(usage.bytes, 3);
    expect(usage.reclaimedBytes, 0);
  });

  test('batch histories deduplicate pins and reclaim only the unreferenced half', () async {
    final commits = <SyncCommit>[];
    for (var i = 0; i < 512; i++) {
      final bytes = [i ~/ 256, i % 256];
      final hash = sha256.convert(bytes).toString();
      await cache.storeChunk(hash, bytes);
      if (i.isEven) {
        commits.add(
          SyncCommit.create(
            libraryId: 'lib',
            scope: 'sets/$i',
            deviceId: 'remote',
            sequence: 1,
            payload: payload(hash),
          ),
        );
      }
    }
    await ledger.receive(commits);
    final usage = await ledger.resourceCacheUsage(reclaim: true);
    expect(usage.chunks, 256);
    expect(usage.bytes, 512);
    expect(usage.reclaimedBytes, 512);
    expect((await ledger.history()).length, 256);
  });

  test('unknown manifest fails closed before any chunk is removed', () async {
    final hash = await chunk(8);
    await ledger.receive([
      SyncCommit.create(
        libraryId: 'lib',
        scope: 'sets/a',
        deviceId: 'r',
        sequence: 1,
        payload: {
          'resources': {'version': 999},
        },
      ),
    ]);
    await expectLater(ledger.resourceCacheUsage(reclaim: true), throwsFormatException);
    expect(await cache.readChunk(hash), isNotNull);
  });

  test('only direct fixed-name chunk files are counted and symlink directories are rejected', () async {
    await chunk(9);
    final directory = '${root.path}/.foliarc-sync/blobs';
    final tmp = File('$directory/uncommitted.tmp');
    await tmp.writeAsBytes([4, 5, 6]);
    final nested = File('$directory/nested/${syncDigest('nested')}');
    await nested.parent.create();
    await nested.writeAsBytes([7]);
    final outside = File('${root.path}/private');
    await outside.writeAsBytes([8]);
    final link = Link('$directory/${syncDigest('link')}');
    await link.create(outside.path);
    expect((await ledger.resourceCacheUsage(reclaim: true)).reclaimedBytes, 2);
    expect(await tmp.exists(), true);
    expect(await nested.exists(), true);
    expect(await link.exists(), true);
    expect(await outside.readAsBytes(), [8]);
    await Directory(directory).rename('$directory.saved');
    await Link(directory).create('$directory.saved');
    await expectLater(ledger.resourceCacheUsage(reclaim: true), throwsFormatException);
  });
}

class _StagingProbeLedger extends FileSyncLedger {
  _StagingProbeLedger(super.root) : super(libraryId: 'lib', deviceId: 'local');
  int probes = 0;
  @override
  Future<Map<String, LocalSyncSnapshot>> commit(
    Iterable<SyncMutation> mutations, {
    Map<String, String?> expected = const {},
    void Function(Map<String, LocalSyncSnapshot>)? validate,
    bool Function(String scope)? tombstoneWhere,
    Iterable<String> resolved = const [],
    Map<String, String> recovered = const {},
  }) async {
    final inputs = mutations.toList();
    if (inputs.any((m) => m.shared?.containsKey('resources') ?? false)) {
      probes++;
      final usage = await resourceCacheUsage(reclaim: true);
      expect(usage.staging, true);
      expect(usage.canReclaim, false);
      expect(usage.reclaimedBytes, 0);
      expect(usage.bytes, 3);
    }
    return super.commit(
      inputs,
      expected: expected,
      validate: validate,
      tombstoneWhere: tombstoneWhere,
      resolved: resolved,
      recovered: recovered,
    );
  }
}
