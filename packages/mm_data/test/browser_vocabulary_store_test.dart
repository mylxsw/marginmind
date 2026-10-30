@TestOn('browser')
library;

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/library_browser_io.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('vocabulary survives IndexedDB reopen outside study set packages', () async {
    final database = 'mm-vocabulary-${newId()}';
    await BrowserFiles.open(name: database);
    var store = FileVocabularyStore.browser();
    final now = DateTime.utc(2026);
    await store.save([
      VocabularyEntry(
        id: 'cat',
        term: 'cat',
        language: 'en',
        kind: VocabularyKind.word,
        createdAt: now,
        updatedAt: now,
        forms: ['cat'],
      ),
    ]);
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileVocabularyStore.browser();
    try {
      expect((await store.load()).single.term, 'cat');
      await store.save([]);
      expect(await store.load(), isEmpty);
    } finally {
      await store.dispose();
      BrowserFiles.close();
      web.window.indexedDB.deleteDatabase(database);
    }
  });
}
