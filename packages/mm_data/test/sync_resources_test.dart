import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/resource_cache.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

class ResourceRemote implements SyncObjectTransport {
  final objects = <String, List<int>>{};
  Future<void> Function(String)? onRead;
  bool stageBlobs = false;
  int blobCreates = 0;
  @override
  final target = SyncTarget(service: 'test', account: 'a', location: 'server', libraryId: 'lib');
  @override
  Future<void> prepare() async {}
  @override
  Future<List<String>> listCommits() async =>
      objects.keys.where((k) => k.startsWith('commits/')).map((k) => k.substring(8, 72)).toList();
  @override
  Future<List<int>?> read(String key) async {
    await onRead?.call(key);
    return objects[key];
  }

  @override
  Future<SyncDelivery> create(String key, List<int> bytes) async {
    checkSyncObjectData(key, bytes);
    if (key.startsWith('blobs/')) blobCreates++;
    if (objects[key] != null && !sameSyncStoredObject(key, objects[key]!, bytes)) throw StateError('collision');
    objects[key] = List.of(bytes);
    return stageBlobs && key.startsWith('blobs/') ? SyncDelivery.staged : SyncDelivery.confirmed;
  }
}

void main() {
  late Directory root;
  late FileSyncLedger la, lb;
  late FileLibraryStore a, b;
  late FileVocabularyStore va, vb;
  late FileSyncEngine x, y;
  late ResourceRemote remote;
  late String id;
  final now = DateTime.utc(2026);
  final bytes = List<int>.generate(syncResourceChunkSize + 37, (i) => i % 251);
  DocumentPackage pdf([List<int>? data]) => DocumentPackage(
    document: Document(id: 'doc', title: 'Paper', fileName: 'documents/paper.pdf', pageCount: 2, importedAt: now),
    files: {'documents/paper.pdf': data ?? bytes},
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('resources-');
    la = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    lb = FileSyncLedger(Directory('${root.path}/b'), libraryId: 'lib', deviceId: 'b');
    a = FileLibraryStore(la.root, sync: la);
    b = FileLibraryStore(lb.root, sync: lb);
    va = FileVocabularyStore(la.root, sync: la);
    vb = FileVocabularyStore(lb.root, sync: lb);
    x = FileSyncEngine(la, FileSyncReceiver(a, va));
    y = FileSyncEngine(lb, FileSyncReceiver(b, vb));
    remote = ResourceRemote();
    id = (await a.create(const NewStudySet(title: 'Set', colorIndex: 0))).id;
    await x.bind(remote);
    await x.resume();
    await y.bind(remote);
    await y.resume();
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await va.dispose();
    await vb.dispose();
    await root.delete(recursive: true);
  });
  Future<SyncResourceStatus> transfer() async {
    await a.importDocumentPackage(id, pdf());
    await x.run();
    await y.run();
    return (await b.syncResources()).single;
  }

  test(
    'two devices exchange metadata, then verified chunks on demand; private/unreferenced files never leave',
    () async {
      await a.importDocumentPackage(id, pdf());
      await File('${la.root.path}/sets/$id.mmset/documents/private.pdf').writeAsString('SECRET');
      expect((await a.syncResources()).single.availability, SyncResourceAvailability.unverified);
      await x.run();
      await y.run();
      expect(remote.objects.keys.where((k) => k.startsWith('blobs/')), hasLength(2));
      expect(remote.objects.values.any((v) => utf8.decode(v, allowMalformed: true).contains('SECRET')), isFalse);
      final missing = (await b.syncResources()).single;
      expect(missing.availability, SyncResourceAvailability.missing);
      expect(await b.watchDocumentResources(id, 'doc').first, DocumentResourceAvailability.missing);
      expect(await File(b.resolveFile(id, 'documents/paper.pdf')).exists(), isFalse);
      final becomesAvailable = b
          .watchDocumentResources(id, 'doc')
          .firstWhere((value) => value == DocumentResourceAvailability.ready);
      await y.download(missing);
      expect(await becomesAvailable.timeout(const Duration(seconds: 5)), DocumentResourceAvailability.ready);
      expect(await File(b.resolveFile(id, 'documents/paper.pdf')).readAsBytes(), bytes);
      expect(await b.watchDocumentResources(id, 'doc').first, DocumentResourceAvailability.ready);
      expect((await b.syncResources()).single.availability, SyncResourceAvailability.available);
      final restored = FileLibraryStore(lb.root);
      expect((await restored.syncResources()).single.availability, SyncResourceAvailability.available);
      await restored.dispose();
      await y.download(missing); // Already present is idempotent.
      await a.rename(id, 'Renamed');
      final before = remote.blobCreates;
      await x.run();
      expect(
        remote.blobCreates - before,
        2,
        reason: 'A chunk is verified once per cycle, not once per historical snapshot',
      );
    },
  );
  test('staged chunks keep the referencing commit unconfirmed until cloud confirmation', () async {
    await a.importDocumentPackage(id, pdf([1, 2, 3]));
    remote.stageBlobs = true;
    expect((await x.run()).staged, greaterThan(0));
    expect((await la.pending(target: remote.target.key)).any((c) => c.payload['resources'] != null), isTrue);
    remote.stageBlobs = false;
    await x.run();
    expect((await la.pending(target: remote.target.key)).where((c) => isSyncWireScope(c.scope)), isEmpty);
  });
  test('partial download caches verified chunks and resumes after restart without publishing partial files', () async {
    final missing = await transfer();
    final keys = remote.objects.keys.where((k) => k.startsWith('blobs/')).toList();
    final removed = remote.objects.remove(keys.last)!;
    await expectLater(y.download(missing), throwsA(isA<SyncTransportException>()));
    expect(await File(b.resolveFile(id, 'documents/paper.pdf')).exists(), isFalse);
    remote.objects[keys.last] = removed;
    remote.objects.remove(keys.first); // Only the durable local chunk can satisfy this.
    await b.dispose();
    b = FileLibraryStore(lb.root, sync: lb);
    y = FileSyncEngine(lb, FileSyncReceiver(b, vb));
    await y.bind(remote);
    await y.resume();
    await y.download((await b.syncResources()).single);
    expect((await b.syncResources()).single.availability, SyncResourceAvailability.available);
  });
  test('corrupt remote bytes and local replacements never become verified or overwritten', () async {
    final missing = await transfer();
    final key = remote.objects.keys.firstWhere((k) => k.startsWith('blobs/'));
    final correct = remote.objects[key]!;
    remote.objects[key] = List.filled(correct.length, 0);
    await expectLater(y.download(missing), throwsFormatException);
    remote.objects[key] = correct;
    final local = File(b.resolveFile(id, 'documents/paper.pdf'));
    await local.parent.create(recursive: true);
    await local.writeAsString('keep me');
    await expectLater(y.download(missing), throwsFormatException);
    expect(await local.readAsString(), 'keep me');
    expect(await b.watchDocumentResources(id, 'doc').first, DocumentResourceAvailability.changed);
    await expectLater(b.readDocumentFile(id, 'documents/paper.pdf'), throwsFormatException);
    expect((await b.syncResources()).single.availability, SyncResourceAvailability.changed);
    final count = remote.objects.length;
    await expectLater(y.run(), throwsFormatException);
    expect(remote.objects.length, count);
  });
  test('pause and document deletion invalidate an in-flight download', () async {
    final missing = await transfer();
    remote.onRead = (key) async {
      if (key.startsWith('blobs/')) await y.pause();
    };
    await expectLater(y.download(missing), throwsA(isA<SyncTransportException>()));
    expect(await File(b.resolveFile(id, 'documents/paper.pdf')).exists(), isFalse);
    await y.resume();
    remote.onRead = (key) async {
      if (key.startsWith('blobs/')) {
        remote.onRead = null;
        await b.update(id, (c) => c.copyWith(documents: []));
      }
    };
    await expectLater(y.download(missing), throwsStateError);
    expect(await File(b.resolveFile(id, 'documents/paper.pdf')).exists(), isFalse);
  });
  test('draft and symlink files cannot publish a resource list', () async {
    await a.importDocumentPackage(id, pdf([1]));
    await a.beginContentTransaction(id);
    await a.prepareSyncResources();
    expect((await a.syncResources()).single.availability, SyncResourceAvailability.unverified);
    await a.endContentTransaction(id);
    final file = File(a.resolveFile(id, 'documents/paper.pdf'));
    await file.delete();
    final private = File('${root.path}/secret');
    await private.writeAsString('PRIVATE');
    await Link(file.path).create(private.path);
    await expectLater(a.prepareSyncResources(), throwsFormatException);
    expect((await la.history()).values.any((c) => c.payload['resources'] != null), isFalse);
  });
  test('manifest closure transfers book chapters, web images and original bytes, but not siblings', () async {
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
    await a.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'book',
          title: 'Book',
          fileName: '$base/manifest.json',
          contentManifest: '$base/manifest.json',
          sourceFileName: 'documents/original.md',
          pageCount: 0,
          importedAt: now,
          revision: 'version',
          layout: DocumentLayout.reflow,
          origin: DocumentOrigin(url: 'https://example.com', capturedAt: now, snapshotFile: '$web/snapshot.html'),
        ),
        files: files,
      ),
    );
    await x.run();
    await y.run();
    await y.download((await b.syncResources()).single);
    for (final file in files.entries) {
      expect(await File(b.resolveFile(id, file.key)).readAsBytes(), file.value);
    }
  });
  test('image cards and research snapshots follow only their explicit references', () async {
    final image = await a.importImageBytes(id, [137, 80, 78, 71, 13, 10, 26, 10]);
    final snapshot = await a.writeResearchSnapshot(id, '# Evidence');
    await a.update(
      id,
      (c) => c.copyWith(
        cards: [
          ...c.cards,
          Card(id: 'image', kind: CardKind.note, title: 'Diagram', imageFileName: image, createdAt: now),
        ],
        researchSources: [
          ResearchSource(
            id: 'source',
            url: 'https://example.com',
            canonicalUrl: 'https://example.com',
            kind: 'web',
            title: 'Evidence',
            fetchedAt: now,
            versions: [
              SourceVersion(
                version: 1,
                snapshotFile: snapshot,
                hash: sha256.convert(utf8.encode('# Evidence')).toString(),
              ),
            ],
          ),
        ],
      ),
    );
    await x.run();
    await y.run();
    final missing = await b.syncResources();
    expect(missing, hasLength(2));
    expect(missing.map((r) => r.title), containsAll(['Set · Diagram', 'Set · Evidence']));
    for (final resource in missing) {
      await y.download(resource);
    }
    expect((await b.syncResources()).every((r) => r.availability == SyncResourceAvailability.available), isTrue);
    expect(await File(b.resolveFile(id, image)).readAsBytes(), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(await b.readResearchSnapshot(id, snapshot), '# Evidence');
    expect(utf8.decode((await b.watchReferencedResource(id, snapshot).first).bytes!), '# Evidence');
  });

  test('standalone resources verify exact bytes, refuse private paths and follow removal', () async {
    final image = await a.importImageBytes(id, [137, 80, 78, 71, 13, 10, 26, 10]);
    await a.update(
      id,
      (c) => c.copyWith(
        cards: [Card(id: 'picture', kind: CardKind.note, title: 'Picture', imageFileName: image, createdAt: now)],
      ),
    );
    await x.run();
    await y.run();
    final states = StreamIterator(b.watchReferencedResource(id, image));
    expect(await states.moveNext(), isTrue);
    expect(states.current.availability, DocumentResourceAvailability.missing);
    await y.download((await b.syncResources()).single);
    expect(await states.moveNext(), isTrue);
    expect(states.current.availability, DocumentResourceAvailability.ready);
    expect(states.current.bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(() => states.current.bytes![0] = 0, throwsUnsupportedError);
    await File(b.resolveFile(id, image)).writeAsBytes([1, 2]);
    final changed = await b.watchReferencedResource(id, image).first;
    expect(changed.availability, DocumentResourceAvailability.changed);
    expect(changed.bytes, isNull);
    await b.update(id, (c) => c.copyWith(cards: []));
    expect(await states.moveNext(), isTrue);
    expect(states.current.availability, DocumentResourceAvailability.missing);
    expect(states.current.bytes, isNull);
    expect(await File(b.resolveFile(id, image)).exists(), isTrue);
    await states.cancel();
    for (final path in ['../.foliarc-sync/local', '.foliarc-sync/identity.json', 'images/unreferenced.png']) {
      expect((await b.watchReferencedResource(id, path).first).bytes, isNull);
    }
  });

  test('local images validate content-addressed names without enabling sync', () async {
    final local = FileLibraryStore(Directory('${root.path}/local'));
    final set = await local.create(const NewStudySet(title: 'Local', colorIndex: 0));
    final image = await local.importImageBytes(set.id, [137, 80, 78, 71, 13, 10, 26, 10]);
    await local.update(
      set.id,
      (c) => c.copyWith(
        cards: [Card(id: 'picture', kind: CardKind.note, title: '', imageFileName: image, createdAt: now)],
      ),
    );
    expect((await local.watchReferencedResource(set.id, image).first).availability, DocumentResourceAvailability.ready);
    expect(await local.syncLedger, isNull);
    await File(local.resolveFile(set.id, image)).writeAsBytes([4]);
    expect(
      (await local.watchReferencedResource(set.id, image).first).availability,
      DocumentResourceAvailability.changed,
    );
    await File(local.resolveFile(set.id, image)).delete();
    expect(
      (await local.watchReferencedResource(set.id, image).first).availability,
      DocumentResourceAvailability.missing,
    );
    final outside = File('${root.path}/private-image')..writeAsBytesSync([137, 80, 78, 71, 13, 10, 26, 10]);
    await Link(local.resolveFile(set.id, image)).create(outside.path);
    expect(
      (await local.watchReferencedResource(set.id, image).first).availability,
      DocumentResourceAvailability.changed,
    );
    await local.dispose();
  });

  test('metadata rename rejects a remote revision even when the visible name returns', () async {
    await a.importDocumentPackage(id, pdf([1]));
    await x.run();
    await y.run();
    final observed = await b.titleForEditing(id);
    await a.rename(id, 'Remote');
    await a.rename(id, observed.title);
    await x.run();
    await y.run();
    await expectLater(
      b.renameObserved(id, 'Stale', expectedRevision: observed.revision),
      throwsA(isA<ContentSyncActionException>()),
    );
    final latest = await b.titleForEditing(id);
    await b.renameObserved(id, 'Chosen', expectedRevision: latest.revision);
    expect((await b.titleForEditing(id)).title, 'Chosen');
    await b.delete(id);
    await expectLater(b.renameObserved(id, 'Restore', expectedRevision: latest.revision), throwsStateError);
  });

  test('cache validates zero files, tampered chunks, descriptors and private symlinks', () async {
    final cache = ResourceCache(la.root), file = File('${la.root.path}/empty');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([]);
    final descriptor = (await cache.inspect(file.path, cache: true))!;
    expect(descriptor.chunks, isEmpty);
    await cache.materialize('${la.root.path}/restored', descriptor, () async {});
    expect(await File('${la.root.path}/restored').length(), 0);
    await expectLater(cache.storeChunk('bad', [1]), throwsFormatException);
    final hash = sha256.convert([1]).toString();
    await cache.storeChunk(hash, [1]);
    await File('${la.root.path}/.foliarc-sync/blobs/$hash').writeAsBytes([2]);
    expect(await cache.readChunk(hash), isNull);
    await cache.storeChunk(hash, [1]);
    expect(await cache.readChunk(hash), [1]);
  });
}
