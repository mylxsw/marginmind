import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/format_migration.dart';
import 'package:test/test.dart';

void main() {
  test('v7 migration preserves all old fields and v8 is idempotent', () {
    final old = <String, Object?>{
      'format': 7,
      'unknown': 42,
      'content': {
        'documents': [
          {'id': 'a', 'lastPage': 3},
        ],
        'annotations': [
          {
            'rects': [1, 2, 3, 4],
          },
        ],
        'extra': 'keep',
        'marginNotes': [
          {'future': true},
        ],
      },
    };
    final before = jsonEncode(old);
    final migrated = migrateStudySet(old);
    expect(migrated['format'], currentStudySetFormat);
    expect(migrated['unknown'], 42);
    final content = migrated['content'] as Map;
    for (final e in (old['content'] as Map).entries) {
      expect(content[e.key], e.value);
    }
    expect(content['comparePairs'], isEmpty);
    expect(content['translationCaches'], isEmpty);
    expect(jsonEncode(old), before);
    expect(migrateStudySet(migrated), same(migrated));
    expect(() => migrateStudySet({'format': currentStudySetFormat + 1}), throwsFormatException);
    expect((migrateStudySet({'format': 7})['content'] as Map)['marginNotes'], isEmpty);
  });
  test('reading CRUD and concurrent translations survive durable reopen', () async {
    final root = await Directory.systemTemp.createTemp('reading8_');
    addTearDown(() => root.delete(recursive: true));
    var store = FileLibraryStore(root);
    final set = await store.create(const NewStudySet(title: 'Reading', colorIndex: 0));
    final date = DateTime.utc(2026);
    await store.update(
      set.id,
      (c) => c.copyWith(
        documents: [
          for (final id in ['a', 'b'])
            Document(
              id: id,
              title: id,
              fileName: '$id.pdf',
              pageCount: 2,
              importedAt: date,
              cropSuggestionDismissed: id == 'a',
            ),
        ],
      ),
    );
    await store.setDocumentCrop(set.id, 'a', DocumentCrop(all: CropInsets(left: 10)));
    await store.upsertMarginNote(
      set.id,
      MarginNote(
        id: 'n',
        documentId: 'a',
        page: 1,
        lineY: 50,
        text: 'Note',
        colorIndex: 0,
        createdAt: date,
        updatedAt: date,
      ),
    );
    await store.upsertComparePair(set.id, ComparePair(id: 'pair', leftDocumentId: 'a', right: PdfCompareTarget('b')));
    await Future.wait([
      for (final fp in ['a', 'b'])
        store.mergeTranslationParagraphs(
          set.id,
          TranslationCache(
            documentId: 'a',
            targetLang: 'zh',
            paragraphs: {fp: 'translated $fp'},
            model: 'm',
            createdAt: date,
          ),
        ),
    ]);
    final saved = await store.load(set.id);
    expect(saved.translationCaches.single.paragraphs.length, 2);
    expect(saved.document('a')!.cropSuggestionDismissed, true);
    expect(saved.document('b')!.cropSuggestionDismissed, false);
    await store.dispose();
    store = FileLibraryStore(root);
    expect((await store.load(set.id)).toJson(), saved.toJson());
    await store.removeMarginNote(set.id, 'n');
    await store.removeComparePair(set.id, 'pair');
    await store.removeTranslationCache(set.id, 'a', 'zh');
    await store.setDocumentCrop(set.id, 'a', null);
    await store.dispose();
    store = FileLibraryStore(root);
    final empty = await store.load(set.id);
    expect(empty.document('a')!.crop, isNull);
    expect(empty.marginNotes, isEmpty);
    expect(empty.comparePairs, isEmpty);
    expect(empty.translationCaches, isEmpty);
    await store.dispose();
  });
}
