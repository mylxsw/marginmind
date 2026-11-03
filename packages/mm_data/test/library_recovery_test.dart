import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late RecoveryLedger ledger;
  late FileLibraryStore store;
  late String id;
  final now = DateTime.utc(2026);
  final editor = StudySetEditor(newId: () => 'card', now: () => now);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('recovery-');
    ledger = RecoveryLedger(root);
    store = FileLibraryStore(root, sync: ledger, clock: () => now);
    id = (await store.create(const NewStudySet(title: 'Original', colorIndex: 2))).id;
    await store.update(id, (c) => editor.addNote(c, text: 'Kept content').$1);
  });
  tearDown(() async {
    await store.dispose();
    await root.delete(recursive: true);
  });
  Future<void> pdf([String doc = 'doc']) => store.importDocumentPackage(
    id,
    DocumentPackage(
      document: Document(id: doc, title: 'Paper $doc', fileName: 'documents/$doc.pdf', pageCount: 3, importedAt: now),
      files: {
        'documents/$doc.pdf': [1, 2, 3],
      },
    ),
  );

  test('deleted set copies content/resources, keeps tombstone and receipt, retry survives restart', () async {
    await pdf();
    await store.prepareSyncResources();
    await File('${root.path}/sets/$id.mmset/documents/private.pdf').writeAsString('PRIVATE');
    await store.delete(id);
    expect(await store.libraryRecoveryEnabled, true);
    final selected = (await store.libraryRecovery()).entries.single;
    final old = (await ledger.snapshots())['sets/$id']!.revision;
    final copy = await store.recoverLibraryCopy(selected, title: 'Recovered');
    expect(copy, isNot(id));
    expect((await store.load(copy)).card('card')!.title, 'Kept content');
    expect(await File(store.resolveFile(copy, 'documents/doc.pdf')).readAsBytes(), [1, 2, 3]);
    expect(await File(store.resolveFile(copy, 'documents/private.pdf')).exists(), false);
    expect((await ledger.snapshots())['sets/$id']!.revision, old);
    final head = (await ledger.snapshots())['sets/$copy']!.commit;
    expect(head.parents, isEmpty);
    expect(
      (await ledger.pending()).where((c) => isSyncWireScope(c.scope)).any((c) => c.scope.startsWith('recoveryCopies/')),
      false,
    );
    expect((await store.libraryRecovery()).entries.single.copyId, copy);
    await store.dispose();
    store = FileLibraryStore(root);
    expect(await store.recoverLibraryCopy(selected, title: 'Ignored retry'), copy);
    expect((await store.watchAll().first).single.title, 'Recovered');
    await store.rename(copy, 'Edited copy');
    expect(await store.recoverLibraryCopy(selected, title: 'Do not replace'), copy);
    expect((await store.watchAll().first).single.title, 'Edited copy');
    await store.delete(copy);
    await expectLater(
      store.recoverLibraryCopy(selected, title: 'No resurrection'),
      throwsA(isA<ContentSyncActionException>()),
    );
  });

  test('successive document deletions each retain a version, including after set deletion', () async {
    await pdf('one');
    await pdf('two');
    await store.update(id, (c) => editor.removeDocument(c, 'one'));
    await store.update(id, (c) => editor.removeDocument(c, 'two'));
    var entries = (await store.libraryRecovery()).entries;
    expect(entries, hasLength(2));
    final selected = entries.firstWhere((e) => e.documents.contains('Paper one'));
    final copy = await store.recoverLibraryCopy(selected, title: 'Docs');
    expect((await store.load(copy)).documents, hasLength(2));
    expect((await store.load(id)).documents, isEmpty);
    // No historic manifest: retained same-path bytes are deliberately not copied.
    expect(await File(store.resolveFile(copy, 'documents/one.pdf')).exists(), false);
    await store.delete(id);
    entries = (await store.libraryRecovery()).entries.where((e) => e.studySetId == id).toList();
    expect(entries, hasLength(3));
    expect(entries.any((e) => e.documents.contains('Paper one')), true);
  });

  test('stale observations, invalid titles and editing leases cannot create copies', () async {
    await pdf();
    await store.update(id, (c) => editor.removeDocument(c, 'doc'));
    final selected = (await store.libraryRecovery()).entries.single;
    await expectLater(store.recoverLibraryCopy(selected, title: ' '), throwsA(isA<ContentSyncActionException>()));
    final lease = store.protectContent(id, [
      ['cards', 'card'],
    ]);
    await lease.ready;
    await expectLater(store.recoverLibraryCopy(selected, title: 'Locked'), throwsA(isA<ContentSyncActionException>()));
    await lease.release();
    await store.rename(id, 'Changed');
    await expectLater(store.recoverLibraryCopy(selected, title: 'Stale'), throwsA(isA<ContentSyncActionException>()));
    expect(await store.watchAll().first, hasLength(1));
  });

  test('fresh device recovers accepted deletion history without resurrecting source or echoing receipts', () async {
    await pdf();
    await store.prepareSyncResources();
    await store.delete(id);
    final otherRoot = Directory('${root.path}/other');
    final otherLedger = FileSyncLedger(otherRoot, libraryId: 'lib', deviceId: 'b');
    final other = FileLibraryStore(otherRoot, sync: otherLedger);
    try {
      await other.receiveSync((await ledger.pending()).reversed.toList());
      final selected = (await other.libraryRecovery()).entries.single;
      final copy = await other.recoverLibraryCopy(selected, title: 'Remote recovery');
      expect(await other.watchAll().first, hasLength(1));
      expect((await other.load(copy)).documents.single.id, 'doc');
      expect(await other.watchDocumentResources(copy, 'doc').first, DocumentResourceAvailability.missing);
      await store.receiveSync(await otherLedger.pending());
      expect((await store.watchAll().first).single.id, copy);
      expect((await ledger.snapshots())['sets/$id']!.deleted, true);
    } finally {
      await other.dispose();
    }
  });

  test('changed original bytes are not copied, verified cached bytes are used', () async {
    await pdf();
    await store.prepareSyncResources();
    await store.delete(id);
    await File('${root.path}/sets/$id.mmset/documents/doc.pdf').writeAsBytes([9]);
    final copy = await store.recoverLibraryCopy((await store.libraryRecovery()).entries.single, title: 'Cached');
    expect(await File(store.resolveFile(copy, 'documents/doc.pdf')).readAsBytes(), [1, 2, 3]);
    expect(await File('${root.path}/sets/$id.mmset/documents/doc.pdf').readAsBytes(), [9]);
  });

  test('projection failure commits once, reopening repairs the copy', () async {
    await store.delete(id);
    final selected = (await store.libraryRecovery()).entries.single;
    final key = syncDigest({
      'kind': 'recovery-copy-v1',
      'library': 'lib',
      'device': 'a',
      'source': id,
      'version': selected.version,
    });
    final blocker = Directory('${root.path}/sets/recovered-$key.mmset/studyset.json.tmp');
    await blocker.create(recursive: true);
    final copy = await store.recoverLibraryCopy(selected, title: 'Copy');
    expect(store.syncProjectionErrors, isNotEmpty);
    final heads = await ledger.snapshots();
    expect(heads['sets/$copy']!.revision, heads['recoveryCopies/$key']!.revision);
    await blocker.delete();
    await store.dispose();
    store = FileLibraryStore(root);
    expect(await store.recoverLibraryCopy(selected, title: 'Retry'), copy);
    expect((await store.watchAll().first).single.title, 'Copy');
  });

  test('CAS rejects a source changed at commit time; no receipt or copy survives', () async {
    await store.delete(id);
    final selected = (await store.libraryRecovery()).entries.single;
    ledger.beforeRecovery = () async {
      // Same tombstone, new private revision, simulating another writer.
      await ledger.commit([
        SyncMutation('sets/$id', local: null, shared: null),
        SyncMutation('test-race', local: {'changed': true}, shared: {}),
      ]);
      // An unchanged set may not get a new revision: change the observed local
      // tombstone by advancing its shared branch with another valid tombstone.
      final old = (await ledger.snapshots())['sets/$id']!;
      final next = SyncCommit.create(
        libraryId: 'lib',
        scope: 'sets/$id',
        deviceId: 'remote',
        sequence: 1,
        parents: [old.commit.id],
        payload: {},
        deleted: true,
      );
      await ledger.receive([next]);
      await ledger.commit([SyncMutation('sets/$id', local: null, shared: null, adopt: next.id)]);
    };
    await expectLater(store.recoverLibraryCopy(selected, title: 'Stale'), throwsA(isA<ContentSyncActionException>()));
    expect((await ledger.snapshots()).keys.where((k) => k.startsWith('recoveryCopies/')), isEmpty);
    expect(await store.watchAll().first, isEmpty);
  });

  test('failed atomic commit retries without duplicate copies or lost original history', () async {
    await store.delete(id);
    final selected = (await store.libraryRecovery()).entries.single;
    ledger.beforeRecovery = () async => throw const FileSystemException('disk full');
    await expectLater(store.recoverLibraryCopy(selected, title: 'Retry me'), throwsA(isA<FileSystemException>()));
    expect((await ledger.snapshots()).keys.where((k) => k.startsWith('recoveryCopies/')), isEmpty);
    final results = await Future.wait([
      store.recoverLibraryCopy(selected, title: 'Retry me'),
      store.recoverLibraryCopy(selected, title: 'Duplicate'),
    ]);
    expect(results[0], results[1]);
    expect((await store.watchAll().first).single.title, 'Retry me');
  });

  test('book recovery follows verified manifest closure; missing manifest refuses publication', () async {
    final chapter = utf8.encode('chapter'), hash = sha256.convert(utf8.encode('chapter')).toString();
    const base = 'books/book/version';
    final chapterPath = '$base/chapters/$hash.json';
    final manifest = utf8.encode(
      jsonEncode({
        'spine': [
          {'path': chapterPath, 'sha256': hash},
        ],
        'resources': [],
      }),
    );
    await store.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'book',
          title: 'Book',
          fileName: '$base/manifest.json',
          contentManifest: '$base/manifest.json',
          pageCount: 0,
          importedAt: now,
          layout: DocumentLayout.reflow,
          revision: 'version',
        ),
        files: {'$base/manifest.json': manifest, chapterPath: chapter},
      ),
    );
    await store.prepareSyncResources();
    await store.delete(id);
    final selected = (await store.libraryRecovery()).entries.single;
    final manifestFile = File('${root.path}/sets/$id.mmset/$base/manifest.json');
    await manifestFile.delete();
    final cacheFile = File('${root.path}/.foliarc-sync/blobs/${sha256.convert(manifest)}');
    // The cache is content addressed, and a missing dependency proof prevents
    // both metadata publication and arbitrary reads from the old package.
    expect(await cacheFile.exists(), true);
    await cacheFile.delete();
    await expectLater(store.recoverLibraryCopy(selected, title: 'Book copy'), throwsFormatException);
    expect(await store.watchAll().first, isEmpty);
    await manifestFile.writeAsBytes(manifest);
    final copy = await store.recoverLibraryCopy(selected, title: 'Book copy');
    expect(await File(store.resolveFile(copy, chapterPath)).readAsBytes(), chapter);
    expect(await File(store.resolveFile(copy, '$base/manifest.json')).readAsBytes(), manifest);
  });

  test('library recovery stream sees deletion and receipt, then releases its listener', () async {
    final initial = Completer<void>(), deleted = Completer<LibraryRecoveryEntry>(), recovered = Completer<void>();
    final sub = store.watchLibraryRecovery().listen((state) {
      if (!initial.isCompleted) initial.complete();
      if (state.entries.isNotEmpty && !deleted.isCompleted) deleted.complete(state.entries.first);
      if (state.entries.any((e) => e.copyId != null) && !recovered.isCompleted) recovered.complete();
    });
    try {
      await initial.future.timeout(const Duration(seconds: 5));
      await store.delete(id);
      final selected = await deleted.future.timeout(const Duration(seconds: 5));
      await store.recoverLibraryCopy(selected, title: 'Watched');
      await recovered.future.timeout(const Duration(seconds: 5));
    } finally {
      await sub.cancel();
    }
  });

  test('local-only mode stays disabled and never creates a ledger for recovery', () async {
    final local = FileLibraryStore(Directory('${root.path}/local'));
    try {
      expect(await local.libraryRecoveryEnabled, false);
      expect((await local.libraryRecovery()).enabled, false);
      expect(await local.syncLedger, isNull);
    } finally {
      await local.dispose();
    }
  });
}

class RecoveryLedger extends FileSyncLedger {
  RecoveryLedger(super.root) : super(libraryId: 'lib', deviceId: 'a');
  Future<void> Function()? beforeRecovery;
  @override
  Future<Map<String, LocalSyncSnapshot>> commit(
    Iterable<SyncMutation> mutations, {
    Map<String, String?> expected = const {},
    void Function(Map<String, LocalSyncSnapshot>)? validate,
    bool Function(String)? tombstoneWhere,
    Iterable<String> resolved = const [],
    Map<String, String> recovered = const {},
  }) async {
    final inputs = mutations.toList();
    if (inputs.any((m) => m.scope.startsWith('recoveryCopies/'))) {
      final action = beforeRecovery;
      beforeRecovery = null;
      await action?.call();
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
