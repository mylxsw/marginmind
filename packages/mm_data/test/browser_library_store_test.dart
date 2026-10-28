@TestOn('browser')
library;

import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/library_browser_io.dart';
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
}
