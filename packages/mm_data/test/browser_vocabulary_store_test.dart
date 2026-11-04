@TestOn('browser')
library;

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:mm_data/src/library_browser_io.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('word registers and conflict choices survive IndexedDB reopen', () async {
    final database = 'mm-word-sync-${newId()}';
    await BrowserFiles.open(name: database);
    final ledger = FileSyncLedger.browser(libraryId: 'lib', deviceId: 'browser');
    var store = FileVocabularyStore.browser(sync: ledger);
    final now = DateTime.utc(2026);
    final entry = VocabularyEntry(
      id: 'old',
      term: 'Word',
      language: 'en',
      kind: VocabularyKind.word,
      createdAt: now,
      updatedAt: now,
      forms: ['word'],
      note: 'local',
    );
    await store.updateVocabulary((_) => [entry]);
    final root = vocabularyBaseline('lib', 'en', 'word');
    final remote = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'remote',
      sequence: 1,
      parents: [root.id],
      payload: VocabularyWord.fromJson(root.payload)
          .edit(
            null,
            entry.copyWith(note: 'remote'),
            deviceId: 'remote',
            operation: 'remote',
          )
          .toJson(),
    );
    await store.receiveSync([remote]);
    expect(
      (await store.vocabularySyncState()).conflicts.single.choices.map((c) => c.text),
      containsAll(['local', 'remote']),
    );
    await store.dispose();
    BrowserFiles.close();
    await BrowserFiles.open(name: database);
    store = FileVocabularyStore.browser();
    try {
      final c = (await store.vocabularySyncState()).conflicts.single;
      await store.chooseVocabulary(
        c.entryId,
        c.field,
        c.choices.singleWhere((c) => c.text == 'remote').id,
        expectedRevision: c.revision,
      );
      expect((await store.load()).single.note, 'remote');
      expect((await store.vocabularySyncState()).conflicts, isEmpty);
    } finally {
      await store.dispose();
      BrowserFiles.close();
      web.window.indexedDB.deleteDatabase(database);
    }
  });
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
