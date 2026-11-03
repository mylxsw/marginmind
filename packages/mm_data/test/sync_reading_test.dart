import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileSyncLedger left, right;
  late FileLibraryStore a, b;
  late String id;
  final time = DateTime.utc(2026);
  final editor = StudySetEditor(newId: () => 'x', now: () => time);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-reading-');
    left = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'library', deviceId: 'a');
    right = ReadingRacingLedger(Directory('${root.path}/b'));
    a = FileLibraryStore(left.root, sync: left);
    b = FileLibraryStore(right.root, sync: right);
    id = (await a.create(const NewStudySet(title: 'Study', colorIndex: 0))).id;
    await a.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(id: 'doc', title: 'Book', fileName: 'documents/book.pdf', pageCount: 20, importedAt: time),
        files: {
          'documents/book.pdf': [1, 2, 3],
        },
      ),
    );
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await root.delete(recursive: true);
  });
  Future<void> send() async => b.receiveSync(await left.pending());
  Future<void> asset() async {
    final file = File('${right.root.path}/sets/$id.mmset/documents/book.pdf');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1, 2, 3]);
  }

  Future<ReadingPosition> prepare(ReadingContinuation c) => b.prepareReadingContinuation(
    id,
    c.deviceId,
    c.documentId,
    remoteRevision: c.remoteRevision,
    localToken: c.localToken,
  );

  test('received progress is separate from local reading, resource gated, explicit and restart safe', () async {
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 12));
    await send();
    expect((await b.load(id)).document('doc')!.lastPage, 1);
    var c = (await b.readingContinuations(id)).items.single;
    expect(c.title, 'Book');
    expect(c.position, isA<PdfPosition>().having((p) => p.page, 'page', 12));
    expect(c.availability, ReadingContinuationAvailability.unavailable);
    await expectLater(prepare(c), throwsA(isA<ContentSyncActionException>()));
    await asset();
    c = (await b.readingContinuations(id)).items.single;
    final pending = (await right.pending()).map((c) => c.id).toList();
    expect(c.availability, ReadingContinuationAvailability.ready);
    expect(await prepare(c), isA<PdfPosition>());
    expect((await b.load(id)).document('doc')!.lastPage, 1);
    expect((await right.pending()).map((c) => c.id), pending);
    await b.update(id, (c) => editor.setLastPage(c, 'doc', 3));
    await expectLater(prepare(c), throwsA(isA<ContentSyncActionException>()));
    await b.dispose();
    b = FileLibraryStore(right.root);
    c = (await b.readingContinuations(id)).items.single;
    expect((c.position as PdfPosition).page, 12);
    expect((await b.load(id)).document('doc')!.lastPage, 3);
    await send();
    expect((await b.readingContinuations(id)).items, hasLength(1));
  });

  test('draft changes never leak reading references; cancellation publishes only valid final locations', () async {
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 2));
    final original = await a.load(id);
    final before = (await left.history()).values.where((c) => c.scope.startsWith('reading/')).length;
    await a.beginContentTransaction(id);
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 7));
    expect((await left.history()).values.where((c) => c.scope.startsWith('reading/')), hasLength(before));
    expect((await left.pending()).where((c) => c.scope.startsWith('reading/')), isEmpty);
    await a.update(id, (_) => original);
    await a.endContentTransaction(id);
    expect((await left.history()).values.where((c) => c.scope.startsWith('reading/')), hasLength(before));
    await send();
    expect(((await b.readingContinuations(id)).items.single.position as PdfPosition).page, 2);
    await b.beginContentTransaction(id);
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 9));
    await send();
    expect(((await b.readingContinuations(id)).items.single.position as PdfPosition).page, 2);
    expect((await b.contentSyncStatus(id)).problems, contains(ContentSyncProblem.editing));
    await b.endContentTransaction(id);
    expect(((await b.readingContinuations(id)).items.single.position as PdfPosition).page, 9);
  });

  test('reading waits for missing content dependencies and rejects spoofed device authors', () async {
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 8));
    final commits = await left.pending();
    await b.receiveSync(commits.where((c) => c.scope.startsWith('reading/')));
    expect((await b.readingContinuations(id)).items, isEmpty);
    expect((await b.contentSyncStatus(id)).problems, contains(ContentSyncProblem.missingHistory));
    await b.receiveSync(commits.where((c) => !c.scope.startsWith('reading/')));
    expect((await b.readingContinuations(id)).items, hasLength(1));
    final tip = (await left.snapshots())['reading/$id/a']!.commit;
    final forged = SyncCommit.create(
      libraryId: 'library',
      scope: tip.scope,
      deviceId: 'impostor',
      sequence: 1,
      parents: [tip.id],
      payload: tip.payload,
      requires: tip.requires,
    );
    await b.receiveSync([forged]);
    expect((await b.contentSyncStatus(id)).problems, contains(ContentSyncProblem.invalidHistory));
    expect(((await b.readingContinuations(id)).items.single.position as PdfPosition).page, 8);
  });

  test('removed and replaced documents do not reuse an old reading position', () async {
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 8));
    await send();
    await asset();
    final observed = (await b.readingContinuations(id)).items.single;
    await b.update(id, (c) => c.copyWith(documents: [c.document('doc')!.copyWith(fileName: 'documents/new.pdf')]));
    expect(
      (await b.readingContinuations(id)).items.single.availability,
      ReadingContinuationAvailability.documentChanged,
    );
    await expectLater(prepare(observed), throwsA(isA<ContentSyncActionException>()));
    await b.update(id, (c) => editor.removeDocument(c, 'doc'));
    expect(
      (await b.readingContinuations(id)).items.single.availability,
      ReadingContinuationAvailability.documentChanged,
    );
    await b.delete(id);
    await send();
    expect((await b.readingContinuations(id)).items, isEmpty);
    expect((await right.pending()).where((c) => c.scope == 'reading/$id/a'), isEmpty);
    expect(await b.watchAll().first, isEmpty);
  });

  test('new source positions invalidate an open choice and editing blocks explicit continuation', () async {
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 5));
    await send();
    await asset();
    final old = (await b.readingContinuations(id)).items.single;
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 6));
    await send();
    await expectLater(prepare(old), throwsA(isA<ContentSyncActionException>()));
    final next = (await b.readingContinuations(id)).items.single;
    await b.beginContentTransaction(id);
    await expectLater(
      prepare(next),
      throwsA(isA<ContentSyncActionException>().having((e) => e.reason, 'reason', ContentSyncActionFailure.editing)),
    );
    await b.endContentTransaction(id);
    await prepare((await b.readingContinuations(id)).items.single);
  });

  test(
    'out-of-order reading waits and state subscribers observe accepted progress without local content changes',
    () async {
      await a.update(id, (c) => editor.setLastPage(c, 'doc', 5));
      final old = (await left.snapshots())['reading/$id/a']!.commit;
      await a.update(id, (c) => editor.setLastPage(c, 'doc', 9));
      final next = (await left.snapshots())['reading/$id/a']!.commit;
      final events = <ReadingContinuations>[];
      final sub = b.watchReadingContinuations(id).listen(events.add);
      await b.receiveSync((await left.pending()).where((c) => c.id != old.id));
      expect((await b.readingContinuations(id)).items, isEmpty);
      await b.receiveSync([old]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((events.last.items.single.position as PdfPosition).page, 9);
      expect((await b.load(id)).document('doc')!.lastPage, 1);
      expect((await right.snapshots())[next.scope]!.commit.id, next.id);
      await sub.cancel();
      await a.update(id, (c) => editor.setLastPage(c, 'doc', 10));
      await send();
    },
  );

  test('saved draft reading is sealed with its content dependency after restart', () async {
    await a.beginContentTransaction(id);
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 11));
    await a.dispose();
    a = FileLibraryStore(left.root);
    await a.load(id);
    final recovered = (await a.syncLedger)!;
    final commits = await recovered.pending();
    await b.receiveSync(commits);
    expect(((await b.readingContinuations(id)).items.single.position as PdfPosition).page, 11);
    expect(
      (await recovered.snapshots())['reading/$id/a']!.commit.requires['sets/$id'],
      (await recovered.snapshots())['sets/$id']!.commit.id,
    );
  });

  test('device identities cannot generate ambiguous reading scopes', () async {
    final invalid = FileSyncLedger(Directory('${root.path}/invalid'), libraryId: 'library', deviceId: 'a/b');
    await expectLater(invalid.snapshots(), throwsFormatException);
    expect(await Directory('${root.path}/invalid/.foliarc-sync/local').exists(), isFalse);
  });

  test('failed adoption remains received and retry handles a changed revision before publishing', () async {
    await a.update(id, (c) => editor.setLastPage(c, 'doc', 7));
    final ledger = right as ReadingRacingLedger;
    ledger.beforeAdvance = () async => throw const FileSystemException('disk unavailable');
    await expectLater(send(), throwsA(isA<FileSystemException>()));
    expect((await right.history()).values.where((c) => c.scope == 'reading/$id/a'), isNotEmpty);
    expect((await b.readingContinuations(id)).items, isEmpty);
    ledger.beforeAdvance = () async {
      final remote = (await left.snapshots())['reading/$id/a']!.commit;
      await right.commit([SyncMutation(remote.scope, local: remote.payload, shared: remote.payload, adopt: remote.id)]);
    };
    await b.reconcileSync();
    expect(((await b.readingContinuations(id)).items.single.position as PdfPosition).page, 7);
    expect((await b.load(id)).document('doc')!.lastPage, 1);
    expect(await right.issues(), isEmpty);
  });

  test('each device retains its own text location and a third device receives both without echo', () async {
    final doc = Document(
      id: 'text',
      title: 'Text',
      fileName: 'books/text/source.epub',
      contentManifest: 'books/text/manifest.json',
      revision: 'revision',
      layout: DocumentLayout.reflow,
      pageCount: 0,
      importedAt: time,
    );
    final position = TextReadingPosition(revision: 'revision', chapterId: 'chapter', offset: 42);
    await a.importDocumentPackage(
      id,
      DocumentPackage(
        document: doc,
        files: {
          'books/text/manifest.json': [123, 125],
          'books/text/source.epub': [1, 2, 3],
        },
      ),
    );
    await a.update(
      id,
      (c) => c.copyWith(
        documents: [
          ...c.documents.where((d) => d.id != 'text'),
          doc.copyWith(readingPosition: position, lastReadAt: time),
        ],
      ),
    );
    await send();
    await b.update(id, (c) => editor.setLastPage(c, 'doc', 4));
    final thirdLedger = FileSyncLedger(Directory('${root.path}/third'), libraryId: 'library', deviceId: 'third');
    final third = FileLibraryStore(thirdLedger.root, sync: thirdLedger);
    try {
      await third.receiveSync([...await left.pending(), ...await right.pending()]);
      final offered = (await third.readingContinuations(id)).items;
      expect(offered.map((c) => c.deviceId).toSet(), {'a', 'b'});
      expect(offered.singleWhere((c) => c.deviceId == 'a').position.toJson(), position.toJson());
      expect((offered.singleWhere((c) => c.deviceId == 'b').position as PdfPosition).page, 4);
      expect((await third.load(id)).document('text')!.readingPosition, isNull);
      expect(
        (await thirdLedger.pending()).where((c) => c.scope == 'reading/$id/a' || c.scope == 'reading/$id/b'),
        isEmpty,
      );
    } finally {
      await third.dispose();
    }
  });
}

class ReadingRacingLedger extends FileSyncLedger {
  ReadingRacingLedger(super.root) : super(libraryId: 'library', deviceId: 'b');
  Future<void> Function()? beforeAdvance;
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
    if (inputs.any((m) => m.scope.startsWith('reading/') && m.adopt != null)) {
      final action = beforeAdvance;
      beforeAdvance = null;
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
