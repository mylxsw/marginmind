@TestOn('browser')
library;

import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/library_browser_io.dart';
import 'package:mm_data/src/resource_cache.dart';
import 'package:mm_data/src/sync_ledger_browser.dart' as ledger_io;
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  late FileLibraryStore store;
  late String database;
  final editor = StudySetEditor(newId: newId, now: () => DateTime.utc(2026));
  setUp(() async {
    database = 'mm-test-${newId()}';
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
  });
  tearDown(() async {
    await store.dispose();
    BrowserFiles.close();
    web.window.indexedDB.deleteDatabase(database);
  });

  test('deleted browser content restores as a new identity once across restart', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser');
    store = FileLibraryStore.browser(sync: ledger);
    final set = await store.create(const NewStudySet(title: 'Deleted', colorIndex: 0));
    await store.update(set.id, (c) => editor.addNote(c, text: 'Kept').$1);
    await store.delete(set.id);
    final selected = (await store.libraryRecovery()).entries.single;
    final copy = await store.recoverLibraryCopy(selected, title: 'Recovered');
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect(await store.recoverLibraryCopy(selected, title: 'Do not duplicate'), copy);
    expect((await store.watchAll().first).single.id, copy);
    expect((await store.load(copy)).cards.single.title, 'Kept');
    expect((await (await store.syncLedger)!.snapshots())['sets/${set.id}']!.deleted, true);
  });

  test('standalone image bytes and observed titles retain browser guards', () async {
    final set = await store.create(const NewStudySet(title: 'Original', colorIndex: 0));
    final image = await store.importImageBytes(set.id, [137, 80, 78, 71, 13, 10, 26, 10]);
    await store.update(
      set.id,
      (c) => c.copyWith(
        cards: [
          Card(id: 'picture', kind: CardKind.note, title: '', imageFileName: image, createdAt: DateTime.utc(2026)),
        ],
      ),
    );
    final read = await store.watchReferencedResource(set.id, image).first;
    expect(read.availability, DocumentResourceAvailability.ready);
    expect(read.bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    final title = await store.titleForEditing(set.id);
    await store.rename(set.id, 'Newer');
    await expectLater(
      store.renameObserved(set.id, 'Stale', expectedRevision: title.revision),
      throwsA(isA<ContentSyncActionException>()),
    );
    await store.update(set.id, (c) => c.copyWith(cards: []));
    expect(
      (await store.watchReferencedResource(set.id, image).first).availability,
      DocumentResourceAvailability.missing,
    );
  });

  test('device names and disconnected bindings recover without clearing delivery history', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser');
    store = FileLibraryStore.browser(sync: ledger);
    await FileSyncDevices(ledger).rename('Browser', expectedRevision: null);
    final remote = SyncCommit.create(
      libraryId: 'library',
      scope: 'devices/phone',
      deviceId: 'phone',
      sequence: 1,
      payload: SyncDeviceProfile('Phone').toJson(),
    );
    await store.receiveSync([remote]);
    final target = SyncTarget(service: 'webdav', account: 'alice', location: 'https://dav/', libraryId: 'library');
    await ledger.bindTransport(target);
    await ledger.resumeTransport(target.key);
    final connection = (await ledger.transportConnection())!;
    final outgoing = await ledger.pending(target: target.key);
    await ledger.disconnectTransport(target.key);
    await expectLater(
      ledger.acknowledge(outgoing.map((c) => c.id), target: target.key, connectionRevision: connection.revision),
      throwsA(isA<SyncTransportException>()),
    );
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    final restored = (await store.syncLedger)!;
    expect(await restored.transportConnection(), isNull);
    expect((await FileSyncDevices(restored).list()).map((d) => d.name), ['Browser', 'Phone']);
    expect((await restored.pending()).where((c) => c.scope == 'devices/phone'), isEmpty);
  });

  test('resource manifest and chunk cache survive IndexedDB restart and restore on demand', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser');
    store = FileLibraryStore.browser(sync: ledger);
    final id = (await store.create(const NewStudySet(title: 'Files', colorIndex: 0))).id;
    await store.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'doc',
          title: 'PDF',
          fileName: 'documents/file.pdf',
          pageCount: 1,
          importedAt: DateTime.utc(2026),
        ),
        files: {
          'documents/file.pdf': [0, 255, 128],
        },
      ),
    );
    await store.prepareSyncResources();
    expect((await store.syncResources()).single.availability, SyncResourceAvailability.available);
    final snapshot = (await ledger.snapshots())['sets/$id']!;
    final manifest = SyncResources.fromJson((snapshot.commit.payload['resources'] as Map).cast<String, Object?>());
    final descriptor = manifest.groups.values.single.values.single;
    final path = '${store.root.path}/sets/$id.mmset/documents/file.pdf';
    await File(path).delete();
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await store.syncResources()).single.availability, SyncResourceAvailability.missing);
    await ResourceCache(store.root).materialize(path, descriptor, () async {});
    expect((await store.syncResources()).single.availability, SyncResourceAvailability.available);
    expect(await store.readDocumentFile(id, 'documents/file.pdf'), [0, 255, 128]);
  });

  test('remote device reading survives browser restart without changing local progress', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser');
    store = FileLibraryStore.browser(sync: ledger);
    final id = (await store.create(const NewStudySet(title: 'Reading', colorIndex: 0))).id;
    await store.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'doc',
          title: 'Book',
          fileName: 'documents/book.pdf',
          pageCount: 20,
          importedAt: DateTime.utc(2026),
        ),
        files: {
          'documents/book.pdf': [1, 2, 3],
        },
      ),
    );
    final source = (await ledger.snapshots())['sets/$id']!.commit;
    final content = editor.setLastPage(await store.load(id), 'doc', 13);
    final remote = SyncCommit.create(
      libraryId: 'library',
      scope: 'reading/$id/remote',
      deviceId: 'remote',
      sequence: 1,
      payload: DeviceReading.fromContent(content).toJson(),
      requires: {source.scope: source.id},
    );
    await store.receiveSync([remote]);
    expect((await store.load(id)).document('doc')!.lastPage, 1);
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    final c = (await store.watchReadingContinuations(id).first).items.single;
    expect(c.availability, ReadingContinuationAvailability.ready);
    expect(
      (await store.prepareReadingContinuation(
        id,
        c.deviceId,
        c.documentId,
        remoteRevision: c.remoteRevision,
        localToken: c.localToken,
      ) as PdfPosition).page,
      13,
    );
    expect((await store.load(id)).document('doc')!.lastPage, 1);
    await store.update(id, (c) => editor.setLastPage(c, 'doc', 13));
    final pending = await (await store.syncLedger)!.pending();
    expect(pending.where((c) => c.scope == remote.scope), isEmpty);
    expect(pending.where((c) => c.scope == 'reading/$id/browser').last.requires[source.scope], source.id);
  });

  test('folder choices, membership and deletion survive browser restart', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser');
    store = FileLibraryStore.browser(sync: ledger);
    final folder = await store.createFolder('Initial');
    final base = (await ledger.snapshots())['folders/${folder.id}']!;
    final id = (await store.create(const NewStudySet(title: 'Study', colorIndex: 0))).id;
    await store.moveStudySet(id, folder.id, expectedFolderId: null);
    await store.renameFolder(folder.id, 'Local', expectedRevision: base.revision);
    final remote = SyncCommit.create(
      libraryId: 'library',
      scope: base.scope,
      deviceId: 'remote',
      sequence: 1,
      parents: [base.commit.id],
      payload: {'id': folder.id, 'name': 'Remote'},
    );
    await store.receiveSync([remote]);
    expect((await store.watchOrganization().first).entries.single.choices, hasLength(1));
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    var entry = (await store.watchOrganization().first).entries.single;
    await store.chooseFolderName(
      folder.id,
      entry.choices.single.transaction,
      expectedRevision: entry.revision,
      useCandidate: true,
    );
    entry = (await store.watchOrganization().first).entries.single;
    expect(entry.choices, isEmpty);
    await store.deleteFolder(folder.id, expectedRevision: entry.revision);
    expect((await store.watchAll().first).single.folderId, isNull);
    expect((await (await store.syncLedger)!.snapshots())['sets/$id']!.value!['folderId'], folder.id);
  });

  test('versioned review replay, pending commits and failed rating retry survive IndexedDB reopen', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser');
    store = FileLibraryStore.browser(sync: ledger);
    final id = (await store.create(const NewStudySet(title: 'Review', colorIndex: 0))).id;
    await store.update(id, (c) => editor.addNote(c, text: 'Question').$1);
    final card = (await store.load(id)).cards.single.id;
    final heads = await ledger.snapshots();
    final base = heads['reviews/$id']!.commit, set = heads['sets/$id']!.commit;
    final remoteTimeline = ReviewTimeline.fromJson(base.payload)
        .append(reviewData(editor.rate(await store.load(id), card, Rating.easy)), deviceId: 'remote');
    final remote = SyncCommit.create(
      libraryId: 'library',
      scope: base.scope,
      deviceId: 'remote',
      sequence: 1,
      parents: [base.id],
      payload: remoteTimeline.toJson(),
      requires: {set.scope: set.id},
    );
    await store.update(id, (c) => editor.rate(c, card, Rating.good));
    await store.receiveSync([remote]);
    expect((await store.load(id)).reviewLogs, hasLength(2));
    final pending = (await ledger.pending()).map((c) => c.id).toList();
    BrowserFiles.close();
    await expectLater(store.update(id, (c) => editor.rate(c, card, Rating.good)), throwsStateError);
    expect((await store.load(id)).reviewLogs, hasLength(2));
    await store.dispose();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await store.load(id)).reviewLogs, hasLength(2));
    final reopened = (await store.syncLedger)!;
    expect((await reopened.pending()).map((c) => c.id), pending);
    await store.receiveSync([remote]);
    expect((await store.load(id)).reviewLogs, hasLength(2));
    await store.update(id, (c) => editor.rate(c, card, Rating.good));
    expect((await store.load(id)).reviewLogs, hasLength(3));
  });

  test('saved draft recovery and explicit acknowledgement survive IndexedDB reopen', () async {
    await store.dispose();
    store = FileLibraryStore.browser(
      sync: FileSyncLedger.browser(libraryId: 'lib', deviceId: 'device'),
    );
    final id = (await store.create(const NewStudySet(title: 'Set', colorIndex: 0))).id;
    await store.beginContentTransaction(id);
    await store.update(id, (c) => editor.addNote(c, text: 'Saved before crash').$1);
    Future<void> reopen() async {
      await store.dispose();
      BrowserFiles.close();
      await BrowserFiles.open(name: database);
      store = FileLibraryStore.browser();
    }

    await reopen();
    final recovered = (await store.contentSyncStatus(id)).recoveryId!;
    expect((await store.load(id)).cards.single.title, 'Saved before crash');
    await reopen();
    expect((await store.contentSyncStatus(id)).recoveryId, recovered);
    await store.acknowledgeContentRecovery(id, recovered);
    await reopen();
    expect((await store.contentSyncStatus(id)).recoveryId, isNull);
    expect((await store.load(id)).cards.single.title, 'Saved before crash');
  });

  test('received versions and applied state survive IndexedDB reopen without echo uploads', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser');
    store = FileLibraryStore.browser(sync: ledger);
    final set = await store.create(const NewStudySet(title: 'Local', colorIndex: 0));
    final base = (await ledger.snapshots())['sets/${set.id}']!.commit;
    final remote = SyncCommit.create(
      libraryId: 'library',
      deviceId: 'remote',
      scope: base.scope,
      sequence: 1,
      parents: [base.id],
      payload: {...base.payload, 'title': 'Received'},
    );
    await store.receiveSync([remote]);
    expect((await store.watchAll().first).single.title, 'Received');
    expect((await ledger.pending()).any((c) => c.id == remote.id), isFalse);
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await store.watchAll().first).single.title, 'Received');
    final reopened = (await store.syncLedger)!;
    expect((await reopened.history())[remote.id]!.payload['title'], 'Received');
    expect((await reopened.snapshots())[base.scope]!.commit.id, remote.id);
    expect(await reopened.issues(), isEmpty);
    await store.receiveSync([remote]);
    expect((await reopened.snapshots())[base.scope]!.commit.id, remote.id);
  });

  test('document package stores source, book IR and snapshots using the same browser keys', () async {
    final set = await store.create(const NewStudySet(title: 'Books', colorIndex: 0));
    final manifest = 'books/book/v1/manifest.json';
    final document = Document(
      id: 'book',
      title: 'Book',
      fileName: manifest,
      contentManifest: manifest,
      sourceFileName: 'documents/source.epub',
      pageCount: 0,
      format: DocumentFormat.epub,
      layout: DocumentLayout.reflow,
      importedAt: DateTime.utc(2026),
      revision: 'v1',
    );
    final package = DocumentPackage(
      document: document,
      files: {
        manifest: utf8.encode('{}'),
        'documents/source.epub': [1, 2, 3],
        'books/book/v1/chapters/one.json': utf8.encode('{"text":"Hello"}'),
      },
    );
    await store.importDocumentPackage(set.id, package);
    await expectLater(store.importDocumentPackage(set.id, package, cancelled: () => true), throwsStateError);
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await store.load(set.id)).documents.single.revision, 'v1');
    expect(await store.readDocumentFile(set.id, 'documents/source.epub'), [1, 2, 3]);
  });

  test('reading v8 extensions persist across IndexedDB reopen', () async {
    final set = await store.create(const NewStudySet(title: 'Reading', colorIndex: 0));
    final date = DateTime.utc(2026);
    await store.update(
      set.id,
      (c) => c.copyWith(
        documents: [Document(id: 'a', title: 'A', fileName: 'a.pdf', pageCount: 2, importedAt: date)],
      ),
    );
    await store.setDocumentCrop(set.id, 'a', DocumentCrop(all: CropInsets(left: 24)));
    await store.upsertMarginNote(
      set.id,
      MarginNote(
        id: 'n',
        documentId: 'a',
        page: 1,
        lineY: 500,
        text: 'Note',
        colorIndex: 1,
        createdAt: date,
        updatedAt: date,
      ),
    );
    await store.upsertComparePair(set.id, ComparePair(id: 'p', leftDocumentId: 'a', right: AiCompareTarget('zh')));
    await Future.wait([
      for (final fp in ['one', 'two'])
        store.mergeTranslationParagraphs(
          set.id,
          TranslationCache(documentId: 'a', targetLang: 'zh', paragraphs: {fp: '译文'}, model: 'm', createdAt: date),
        ),
    ]);
    final saved = await store.load(set.id);
    expect(saved.translationCaches.single.paragraphs.length, 2);
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await store.load(set.id)).toJson(), saved.toJson());
    await store.removeMarginNote(set.id, 'n');
    await store.removeComparePair(set.id, 'p');
    await store.removeTranslationCache(set.id, 'a', 'zh');
    await store.setDocumentCrop(set.id, 'a', null);
    final cleared = await store.load(set.id);
    expect(cleared.marginNotes, isEmpty);
    expect(cleared.comparePairs, isEmpty);
    expect(cleared.translationCaches, isEmpty);
    expect(cleared.document('a')!.crop, isNull);
  });

  test('PDF, image, map and metadata survive closing and reopening IndexedDB', () async {
    final set = await store.create(const NewStudySet(title: 'Browser study', colorIndex: 2));
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 sample'));
    final url = web.URL.createObjectURL(web.Blob([pdf.toJS].toJS));
    final name = await store.importFile(set.id, url);
    expect(await store.importFile(set.id, url), name);
    web.URL.revokeObjectURL(url);
    final image = await store.importImageBytes(set.id, [137, 80, 78, 71, 13, 10, 26, 10]);
    await store.update(set.id, (c) {
      final withPdf = editor.addDocument(c, title: 'PDF', fileName: name, pageCount: 1).$1;
      return editor.addTopic(withPdf, title: 'Persisted node').$1;
    });
    await store.setStarred(set.id, starred: true);
    await store.rename(set.id, 'Saved study');
    await store.setColor(set.id, 3);
    await store.markOpened(set.id);
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    final summary = (await store.watchAll().first).single;
    expect(summary.title, 'Saved study');
    expect(summary.starred, isTrue);
    expect(summary.colorIndex, 3);
    final content = await store.load(set.id);
    expect(content.cards.single.title, 'Persisted node');
    expect(content.documents.single.fileName, name);
    expect(await File(store.resolveFile(set.id, name)).readAsBytes(), pdf);
    expect(await File(store.resolveFile(set.id, image)).readAsBytes(), [137, 80, 78, 71, 13, 10, 26, 10]);
    final raw = jsonDecode(await File('/Library/sets/${set.id}.mmset/studyset.json').readAsString()) as Map;
    expect(raw['content'], content.toJson());
    expect(raw['format'], isA<int>());
  });

  test('serialized concurrent updates and deletion leave no orphan package', () async {
    final set = await store.create(const NewStudySet(title: 'Concurrent', colorIndex: 0));
    await Future.wait([
      for (var i = 0; i < 12; i++) store.update(set.id, (c) => editor.addTopic(c, title: 'Node $i').$1),
    ]);
    expect((await store.load(set.id)).cards, hasLength(12));
    await store.delete(set.id);
    expect(await store.watchAll().first, isEmpty);
    expect(await Directory('/Library/sets/${set.id}.mmset').exists(), isFalse);
  });

  test('a failed transaction never publishes edited content', () async {
    final set = await store.create(const NewStudySet(title: 'Failure', colorIndex: 0));
    BrowserFiles.close();
    await expectLater(store.update(set.id, (c) => editor.addTopic(c, title: 'Lost').$1), throwsStateError);
    expect((await store.load(set.id)).cards, isEmpty);
    await BrowserFiles.open(name: database);
    await store.update(set.id, (c) => editor.addTopic(c, title: 'Retry').$1);
    expect((await store.load(set.id)).cards.single.title, 'Retry');
  });

  test('corrupt packages are isolated and non-image bytes rejected', () async {
    await File('/Library/sets/bad.mmset/studyset.json').writeAsBytes(utf8.encode('{bad'));
    await store.watchAll().first;
    expect(store.packageLoadErrors, hasLength(1));
    final set = await store.create(const NewStudySet(title: 'Healthy', colorIndex: 0));
    await expectLater(store.importImageBytes(set.id, [1, 2]), throwsFormatException);
    await expectLater(store.importFile(set.id, '/missing.pdf'), throwsA(isA<FileSystemException>()));
  });

  test('a stale tab cannot overwrite another tab’s committed package', () async {
    final set = await store.create(const NewStudySet(title: 'Original', colorIndex: 0));
    final opened = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(database);
    request.onsuccess = ((web.Event _) => opened.complete(request.result as web.IDBDatabase)).toJS;
    final other = await opened.future;
    final tx = other.transaction('files'.toJS, 'readwrite');
    final done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx
        .objectStore('files')
        .put(Uint8List.fromList(utf8.encode('other tab')).toJS, '/Library/sets/${set.id}.mmset/studyset.json'.toJS);
    await done.future;
    other.close();
    await expectLater(
      store.update(set.id, (c) => editor.addTopic(c, title: 'Stale edit').$1),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.load(set.id)).cards, isEmpty);
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    expect(await File('/Library/sets/${set.id}.mmset/studyset.json').readAsString(), 'other tab');
  });

  test('research snapshots retain canonical names and validate their hash', () async {
    final set = await store.create(const NewStudySet(title: 'Research', colorIndex: 0));
    final name = await store.writeResearchSnapshot(set.id, '# Saved');
    expect(await store.writeResearchSnapshot(set.id, '# Saved'), name);
    expect(await store.readResearchSnapshot(set.id, name), '# Saved');
    await File('/Library/sets/${set.id}.mmset/$name').writeAsBytes([1]);
    await expectLater(store.readResearchSnapshot(set.id, name), throwsFormatException);
  });

  test('sync commit and outbox recover together after IndexedDB reopen', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser-device');
    store = FileLibraryStore.browser(sync: ledger);
    final set = await store.create(const NewStudySet(title: 'Synced', colorIndex: 0));
    await store.update(set.id, (c) => editor.addTopic(c, title: 'Durable').$1);
    final pending = (await ledger.pending()).map((c) => c.id).toList();
    BrowserFiles.close();
    await expectLater(store.update(set.id, (c) => editor.addTopic(c, title: 'Not committed').$1), throwsStateError);
    expect((await store.load(set.id)).cards, hasLength(1));
    await store.dispose();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await store.load(set.id)).cards.single.title, 'Durable');
    expect((await (await store.syncLedger)!.pending()).map((c) => c.id), pending);
  });

  test('unresolved transactions and independent successors recover in IndexedDB', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser-device');
    store = FileLibraryStore.browser(sync: ledger);
    final set = await store.create(const NewStudySet(title: 'Base', colorIndex: 0));
    final base = (await ledger.snapshots())['sets/${set.id}']!.commit;
    final remote = SyncCommit.create(
      libraryId: 'library',
      scope: base.scope,
      deviceId: 'remote',
      sequence: 1,
      parents: [base.id],
      payload: {...base.payload, 'title': 'Remote'},
    );
    final later = SyncCommit.create(
      libraryId: 'library',
      scope: base.scope,
      deviceId: 'remote',
      sequence: 2,
      parents: [remote.id],
      payload: {...remote.payload, 'colorIndex': 2},
    );
    await store.rename(set.id, 'Local');
    await store.receiveSync([later, remote]);
    expect((await store.watchAll().first).single.colorIndex, 2);
    var head = (await ledger.snapshots())[base.scope]!;
    final pending = head.commit.pending.single;
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await store.syncConflicts(set.id)).single.transaction, pending);
    final reopened = (await store.syncLedger)!;
    head = (await reopened.snapshots())[base.scope]!;
    await store.resolveSyncConflict(set.id, pending, expectedRevision: head.revision, useCandidate: true);
    expect(await store.syncConflicts(set.id), isEmpty);
    expect((await store.watchAll().first).single.colorIndex, 2);
    expect((await reopened.snapshots())[base.scope]!.commit.resolves, [pending]);
  });

  test('concurrent human choices survive IndexedDB reopen and settle as one guarded review', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser-device');
    store = FileLibraryStore.browser(sync: ledger);
    final set = await store.create(const NewStudySet(title: 'Base', colorIndex: 0));
    final scope = 'sets/${set.id}';
    final base = (await ledger.snapshots())[scope]!.commit;
    final remote = SyncCommit.create(
      libraryId: 'library',
      scope: scope,
      deviceId: 'remote',
      sequence: 1,
      parents: [base.id],
      payload: {...base.payload, 'title': 'Remote'},
    );
    await store.rename(set.id, 'Local');
    await store.receiveSync([remote]);
    final merged = (await ledger.snapshots())[scope]!;
    final pending = merged.commit.pending.single;
    await store.resolveSyncConflict(set.id, pending, expectedRevision: merged.revision, useCandidate: false);
    final keep = (await ledger.snapshots())[scope]!.commit;
    final use = SyncCommit.create(
      libraryId: 'library',
      scope: scope,
      deviceId: 'remote',
      sequence: 2,
      parents: [merged.commit.id],
      resolves: [pending],
      payload: chooseSyncCandidate(await ledger.history(), pending, merged.commit.payload),
    );
    await store.receiveSync([use]);
    final status = await store.contentSyncStatus(set.id);
    expect(status.conflicts, hasLength(2));
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    final restored = await store.contentSyncStatus(set.id);
    expect(restored.conflicts.every((c) => c.concurrentChoices == 2), isTrue);
    await store.chooseContentSync(set.id, keep.id, expectedRevision: restored.revision!, useCandidate: true);
    expect((await store.contentSyncStatus(set.id)).conflicts, isEmpty);
    expect((await store.watchAll().first).single.title, keep.payload['title']);
    expect((await (await store.syncLedger)!.snapshots())[scope]!.commit.resolves.toSet(), {keep.id, use.id});
  });

  test('local editing drafts survive IndexedDB failure and reopen as one shared transaction', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser-device');
    store = FileLibraryStore.browser(sync: ledger);
    final set = await store.create(const NewStudySet(title: 'Base', colorIndex: 0));
    final before = (await ledger.history()).values.where((c) => c.scope == 'sets/${set.id}').length;
    await store.beginContentTransaction(set.id);
    await store.update(set.id, (c) => editor.addTopic(c, title: 'First').$1);
    await store.rename(set.id, 'Saved draft');
    expect((await ledger.pending()).where((c) => c.scope == 'sets/${set.id}'), isEmpty);
    BrowserFiles.close();
    await expectLater(store.endContentTransaction(set.id), throwsStateError);
    await store.dispose();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await store.watchAll().first).single.title, 'Saved draft');
    expect(store.recoveredEditingDrafts, {set.id});
    final restored = (await store.syncLedger)!;
    expect((await restored.snapshots())['sets/${set.id}']!.draft, isFalse);
    expect((await restored.history()).values.where((c) => c.scope == 'sets/${set.id}'), hasLength(before + 1));
  });

  test('transport bindings persist per target and another tab pause is read from IndexedDB', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser-device');
    store = FileLibraryStore.browser(sync: ledger);
    final set = await store.create(const NewStudySet(title: 'Synced', colorIndex: 0));
    final target = SyncTarget(
      service: 'webdav',
      account: 'alice',
      location: 'https://dav.example/',
      libraryId: 'library',
    );
    await ledger.bindTransport(target);
    expect((await ledger.transportConnection())!.paused, isTrue);
    await ledger.resumeTransport(target.key);
    final connection = (await ledger.transportConnection())!;
    final commit = (await ledger.pending()).firstWhere((c) => c.scope == 'sets/${set.id}');
    await ledger.acknowledge([commit.id], target: target.key, connectionRevision: connection.revision);
    expect((await ledger.pending(target: target.key)).any((c) => c.id == commit.id), isFalse);
    expect((await ledger.pending(target: 'another-target')).any((c) => c.id == commit.id), isTrue);
    final opened = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(database);
    request.onsuccess = ((web.Event _) => opened.complete(request.result as web.IDBDatabase)).toJS;
    final other = await opened.future;
    final tx = other.transaction('files'.toJS, 'readwrite');
    final done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx
        .objectStore('files')
        .put(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'version': 1,
                'deviceId': 'browser-device',
                'target': target.toJson(),
                'revision': 'another-tab',
                'paused': true,
              }),
            ),
          ).toJS,
          '/Library/.foliarc-sync/connection.json'.toJS,
        );
    await done.future;
    other.close();
    expect((await ledger.transportConnection())!.paused, isTrue);
    await expectLater(
      ledger_io.replaceSyncConnection('/Library/.foliarc-sync/connection.json', [123, 125], connection.revision),
      throwsA(isA<SyncTransportException>()),
    );
    expect((await ledger.transportConnection())!.revision, 'another-tab');
    final oldBinding = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'deviceId': 'browser-device',
          'target': target.toJson(),
          'revision': connection.revision,
          'paused': false,
        }),
      ),
    );
    await expectLater(
      BrowserFiles.commit(
        {
          '/should-not-confirm': Uint8List.fromList([1]),
        },
        [],
        guards: {'/Library/.foliarc-sync/connection.json': oldBinding},
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File('/should-not-confirm').exists(), isFalse);
    await expectLater(
      ledger.acknowledge([commit.id], target: target.key, connectionRevision: connection.revision),
      throwsA(isA<SyncTransportException>()),
    );
    await expectLater(ledger.resumeTransport(target.key), throwsA(isA<FileSystemException>()));
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileLibraryStore.browser();
    expect((await (await store.syncLedger)!.transportConnection())!.revision, 'another-tab');
  });

  test('sync record and head compare-and-swap prevent stale tabs from creating forks', () async {
    await store.dispose();
    final ledger = FileSyncLedger.browser(libraryId: 'library', deviceId: 'browser-device');
    store = FileLibraryStore.browser(sync: ledger);
    final set = await store.create(const NewStudySet(title: 'Synced', colorIndex: 0));
    final pending = (await ledger.pending()).length;
    final opened = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(database);
    request.onsuccess = ((web.Event _) => opened.complete(request.result as web.IDBDatabase)).toJS;
    final other = await opened.future;
    final tx = other.transaction('files'.toJS, 'readwrite');
    final done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx
        .objectStore('files')
        .put(Uint8List.fromList(utf8.encode('another head')).toJS, '/Library/.foliarc-sync/local/.head'.toJS);
    await done.future;
    other.close();
    await expectLater(
      store.update(set.id, (c) => editor.addTopic(c, title: 'Stale').$1),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.load(set.id)).cards, isEmpty);
    expect(await ledger.pending(), hasLength(pending));
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    final records = await Directory('/Library/.foliarc-sync/local')
        .list()
        .where((f) => f is File && f.path.endsWith('.json'))
        .toList();
    expect(records, hasLength(2)); // library baseline, then study-set transaction
  });
}
