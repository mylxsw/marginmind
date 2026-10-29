import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileLibraryStore store;
  late String setId;
  final now = DateTime.utc(2026, 10, 29);
  DocumentPackage package(String revision, {String title = 'Book'}) {
    final manifest = 'books/book/$revision/manifest.json';
    final snapshot = 'web/book/$revision/snapshot.html';
    return DocumentPackage(
      document: Document(
        id: 'book',
        title: title,
        fileName: manifest,
        pageCount: 0,
        importedAt: now,
        format: DocumentFormat.web,
        layout: DocumentLayout.reflow,
        revision: revision,
        contentManifest: manifest,
        sourceFileName: 'documents/original.md',
        origin: DocumentOrigin(url: 'https://example.com', capturedAt: now, snapshotFile: snapshot),
      ),
      files: {
        'documents/original.md': utf8.encode('# Hello'),
        manifest: utf8.encode('{"version":1}'),
        'books/book/$revision/chapters/chapter.json': utf8.encode('{"text":"Hello"}'),
        'books/book/$revision/resources/image.png': [137, 80, 78, 71],
        snapshot: utf8.encode('<p>Hello</p>'),
      },
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mm_doc_package');
    store = FileLibraryStore(root);
    setId = (await store.create(const NewStudySet(title: 'Set', colorIndex: 0))).id;
  });
  tearDown(() async {
    await store.dispose();
    await root.delete(recursive: true);
  });

  test('reconciliation is atomic, uses latest content and guards the source version', () async {
    await store.importDocumentPackage(setId, package('v1'));
    final version = package('v2');
    final update = DocumentPackage(
      document: version.document,
      files: version.files,
      expectedRevision: 'v1',
      reconcile: (content) => content.copyWith(documents: [content.documents.single.copyWith(title: 'Reconciled')]),
    );
    expect((await store.importDocumentPackage(setId, update)).documents.single.title, 'Reconciled');
    await expectLater(store.importDocumentPackage(setId, update), throwsStateError);
    final failed = package('v3');
    await expectLater(
      store.importDocumentPackage(
        setId,
        DocumentPackage(
          document: failed.document,
          files: failed.files,
          expectedRevision: 'v2',
          reconcile: (_) => throw StateError('alignment failed'),
        ),
      ),
      throwsStateError,
    );
    expect((await store.load(setId)).documents.single.revision, 'v2');
    expect(await File(store.resolveFile(setId, failed.document.fileName)).exists(), isFalse);
  });
  test('unchanged content still rejects a stale capture snapshot', () async {
    final first = package('same');
    await store.importDocumentPackage(setId, first);
    const snapshot = 'web/book/capture-2/snapshot.html';
    final updated = DocumentPackage(
      document: first.document.copyWith(
        origin: DocumentOrigin(
          url: 'https://example.com',
          capturedAt: now.add(const Duration(seconds: 1)),
          snapshotFile: snapshot,
        ),
      ),
      files: {...first.files, snapshot: utf8.encode('<p>capture 2</p>')},
      expectedRevision: 'same',
      expectedSnapshotFile: first.document.origin!.snapshotFile,
    );
    await store.importDocumentPackage(setId, updated);
    await expectLater(store.importDocumentPackage(setId, updated), throwsStateError);
    expect((await store.load(setId)).documents.single.origin!.snapshotFile, snapshot);
  });

  test('immutable versions, original, resources and snapshot survive reopen', () async {
    final first = package('v1');
    await store.importDocumentPackage(setId, first);
    for (final entry in first.files.entries) {
      expect(await store.readDocumentFile(setId, entry.key), entry.value);
    }
    await store.importDocumentPackage(setId, package('v2', title: 'Updated'));
    final reopened = FileLibraryStore(root);
    addTearDown(reopened.dispose);
    final doc = (await reopened.load(setId)).documents.single;
    expect(doc.revision, 'v2');
    expect(doc.origin!.snapshotFile, 'web/book/v2/snapshot.html');
    expect(await reopened.readDocumentFile(setId, first.document.fileName), first.files[first.document.fileName]);
    expect((await reopened.load(setId)).documents.single.title, 'Updated');
    await reopened.update(
      setId,
      (c) => c.copyWith(
        documents: [
          c.documents.single.copyWith(
            readingPosition: TextReadingPosition(revision: 'v2', chapterId: 'main', offset: 8),
          ),
        ],
      ),
    );
    final summary = (await reopened.watchAll().first).single;
    expect(summary.readPages, 0);
    expect(summary.lastPosition!.position, isA<TextReadingPosition>());
    expect(() => summary.lastPosition!.page, throwsStateError);
  });

  test('cancel and immutable collision leave published content and files intact', () async {
    final first = package('v1');
    await store.importDocumentPackage(setId, first);
    var checks = 0;
    await expectLater(
      store.importDocumentPackage(setId, package('v2'), cancelled: () => ++checks > 2),
      throwsStateError,
    );
    expect((await store.load(setId)).documents.single.revision, 'v1');
    expect(File(store.resolveFile(setId, 'books/book/v2/manifest.json')).existsSync(), isFalse);
    final bad = DocumentPackage(
      document: first.document,
      files: {
        ...first.files,
        first.document.fileName: [9],
      },
    );
    await expectLater(store.importDocumentPackage(setId, bad), throwsStateError);
    expect(await store.readDocumentFile(setId, first.document.fileName), first.files[first.document.fileName]);
    await store.importDocumentPackage(setId, package('v2'));
    expect((await store.load(setId)).documents.single.revision, 'v2');
    await expectLater(store.readDocumentFile(setId, 'documents/../studyset.json'), throwsArgumentError);
  });

  test('metadata changed while importing survives commit and durable reopen', () async {
    Future<void>? rename;
    await store.importDocumentPackage(
      setId,
      package('v1'),
      cancelled: () {
        rename ??= store.rename(setId, 'Renamed during import');
        return false;
      },
    );
    await rename;
    expect((await store.watchAll().first).single.title, 'Renamed during import');
    final reopened = FileLibraryStore(root);
    addTearDown(reopened.dispose);
    expect((await reopened.watchAll().first).single.title, 'Renamed during import');
    expect((await reopened.load(setId)).documents.single.revision, 'v1');
  });

  test('failed metadata replacement rolls back new files and preserves old revision, then retries', () async {
    await store.importDocumentPackage(setId, package('v1'));
    final target = File('${root.path}/sets/$setId.mmset/studyset.json');
    final before = await target.readAsString();
    final obstruction = await Directory('${target.path}.tmp').create();
    await expectLater(store.importDocumentPackage(setId, package('v2')), throwsA(isA<FileSystemException>()));
    expect(await target.readAsString(), before);
    expect(File(store.resolveFile(setId, 'books/book/v2/manifest.json')).existsSync(), isFalse);
    expect(await store.readDocumentFile(setId, 'documents/original.md'), utf8.encode('# Hello'));
    await obstruction.delete();
    await store.importDocumentPackage(setId, package('v2'));
    expect((await store.load(setId)).documents.single.revision, 'v2');
  });

  test('format 10 backup is exact, defaults are PDF and unknown target leaves source untouched', () async {
    final path = '${root.path}/sets/$setId.mmset/studyset.json';
    final file = File(path);
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    json['format'] = 10;
    json['content']['documents'] = [
      {
        'id': 'pdf',
        'title': 'Old',
        'fileName': 'documents/old.pdf',
        'pageCount': 9,
        'lastPage': 7,
        'importedAt': now.toIso8601String(),
      },
    ];
    final original = jsonEncode(json);
    await file.writeAsString(original);
    final reopened = FileLibraryStore(root);
    addTearDown(reopened.dispose);
    final doc = (await reopened.load(setId)).documents.single;
    expect(doc.lastPage, 7);
    expect(doc.format, DocumentFormat.pdf);
    expect(doc.layout, DocumentLayout.fixed);
    expect(await File('$path.format-10.bak').readAsString(), original);
    final saved = await file.readAsString();
    expect(jsonDecode(saved)['format'], 11);
    final again = FileLibraryStore(root);
    addTearDown(again.dispose);
    await again.load(setId);
    expect(await file.readAsString(), saved);
    final invalid = jsonDecode(saved);
    invalid['content']['documents'][0]['readingPosition'] = {'type': 'future'};
    await file.writeAsString(jsonEncode(invalid));
    final rejected = FileLibraryStore(root);
    addTearDown(rejected.dispose);
    expect(await rejected.watchAll().first, isEmpty);
    expect(rejected.packageLoadErrors, isNotEmpty);
    expect(jsonDecode(await file.readAsString())['content']['documents'][0]['readingPosition']['type'], 'future');
  });
}
