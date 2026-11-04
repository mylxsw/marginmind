@TestOn('browser')
library;

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:mm_data/src/library_browser_io.dart' show BrowserFiles;
import 'package:mm_data/src/library_io.dart' if (dart.library.js_interop) 'package:mm_data/src/library_browser_io.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('remote human choices and document dependencies survive IndexedDB reopen', () async {
    final database = 'mm-translated-sync-${newId()}';
    await BrowserFiles.open(name: database);
    final root = Directory('/Library');
    final ledger = FileSyncLedger(root, libraryId: 'lib', deviceId: 'web');
    var library = FileLibraryStore(root, sync: ledger);
    try {
      final id = (await library.create(const NewStudySet(title: 'Study', colorIndex: 0))).id;
      final doc = Document(
        id: 'doc',
        title: 'Book',
        fileName: 'documents/book.pdf',
        pageCount: 1,
        importedAt: DateTime.utc(2026),
      );
      await library.importDocumentPackage(
        id,
        DocumentPackage(
          document: doc,
          files: {
            'documents/book.pdf': [1, 2, 3],
          },
        ),
      );
      var store = await library.translationStore(id);
      TranslationSegment segment(String text) => TranslationSegment(
        key: 'key',
        fingerprint: 'fp',
        page: 1,
        index: 0,
        text: text,
        model: 'm',
        profile: 'p',
        origin: TranslationOrigin.edited,
        at: DateTime.utc(2026),
      );
      await store.append('doc', 'zh', segment('local'));
      final baseline = translationBaseline('lib', 'translated/$id/doc/zh');
      final content = (await ledger.snapshots())['sets/$id']!.commit;
      final remote = SyncCommit.create(
        libraryId: 'lib',
        scope: baseline.scope,
        deviceId: 'remote',
        sequence: 1,
        parents: [baseline.id],
        requires: {'sets/$id': content.id},
        payload: TranslationRegister.empty()
            .append(readingDocumentVersion(doc), segment('remote'), 'remote', 'remote')
            .toJson(),
      );
      await library.receiveSync([remote]);
      expect((await store.load('doc', 'zh')).conflicts['key'], hasLength(2));
      await library.dispose();
      BrowserFiles.close();
      await BrowserFiles.open(name: database);
      library = FileLibraryStore(root);
      store = await library.translationStore(id);
      final s = await store.load('doc', 'zh');
      await store.chooseTranslation(
        'doc',
        'zh',
        'key',
        s.conflicts['key']!.singleWhere((c) => c.segment!.text == 'remote').id,
        expectedToken: s.tokenFor('key')!,
      );
      expect((await store.load('doc', 'zh')).segments['key']!.text, 'remote');
      expect((await store.load('doc', 'zh')).conflicts, isEmpty);
    } finally {
      await library.dispose();
      BrowserFiles.close();
      web.window.indexedDB.deleteDatabase(database);
    }
  });
  test('translation journal survives IndexedDB reopen, compact and removal', () async {
    final database = 'mm-translations-${newId()}';
    await BrowserFiles.open(name: database);
    final root = Directory('/Library/test.mmset');
    var store = FileTranslationStore(root);
    final now = DateTime.utc(2026);
    TranslationSegment segment(String text) => TranslationSegment(
      key: textKey('source', 'zh'),
      fingerprint: 'fp',
      page: 1,
      index: 0,
      text: text,
      model: 'm',
      profile: '',
      origin: TranslationOrigin.ai,
      at: now,
    );
    try {
      await store.append('doc', 'zh', segment('旧译文'));
      await store.append('doc', 'zh', segment('新译文'));
      await store.compact('doc', 'zh');
      BrowserFiles.close();
      await BrowserFiles.open(name: database);
      store = FileTranslationStore(root);
      final snapshot = await store.load('doc', 'zh');
      expect(snapshot.lineCount, 1);
      expect(snapshot.segments.values.single.text, '新译文');
      await store.remove('doc', 'zh');
      expect((await store.load('doc', 'zh')).segments, isEmpty);
      await store.removeDocument('doc');
      expect(await Directory('${root.path}/translations/doc').exists(), isFalse);
    } finally {
      BrowserFiles.close();
      web.window.indexedDB.deleteDatabase(database);
    }
  });
}
