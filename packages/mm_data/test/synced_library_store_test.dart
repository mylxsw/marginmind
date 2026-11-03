import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026);
  late Directory root;
  late FileSyncLedger ledger;
  late FileLibraryStore store;
  late StudySetEditor editor;
  var serial = 0;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('synced-library-');
    ledger = FileSyncLedger(root, libraryId: 'library', deviceId: 'device');
    store = FileLibraryStore(root, sync: ledger, clock: () => now);
    editor = StudySetEditor(newId: () => 'entity-${++serial}', now: () => now);
  });
  tearDown(() async {
    await store.dispose();
    await root.delete(recursive: true);
  });
  Future<String> create() async => (await store.create(const NewStudySet(title: 'Set', colorIndex: 0))).id;
  TranslationSegment segment(String key) => TranslationSegment(
    key: key,
    fingerprint: 'fp',
    page: 1,
    index: 0,
    text: '译文',
    model: 'm',
    profile: '',
    origin: TranslationOrigin.edited,
    at: now,
  );
  VocabularyEntry word() => VocabularyEntry(
    id: 'word',
    term: 'hello',
    language: 'en',
    forms: ['hello'],
    kind: VocabularyKind.word,
    createdAt: now,
    updatedAt: now,
  );

  test('real repository separates content, reading and review commits and serializes metadata with content', () async {
    final id = await create();
    late String docId, cardId;
    await store.update(id, (c) {
      final document = editor.addDocument(c, title: 'Doc', fileName: 'documents/a.pdf', pageCount: 9);
      docId = document.$2.id;
      final card = editor.addNote(document.$1, text: 'Question');
      cardId = card.$2.id;
      return card.$1;
    });
    final initial = (await ledger.snapshots())['sets/$id']!;
    await store.update(id, (c) => editor.rate(editor.setLastPage(c, docId, 5), cardId, Rating.good));
    final changed = (await ledger.snapshots())['sets/$id']!;
    expect(changed.commit.id, initial.commit.id);
    expect(changed.revision, isNot(initial.revision));
    final shared = changed.commit.payload['content'] as Map;
    expect(shared.containsKey('reviewLogs'), isFalse);
    expect((shared['documents'] as Map)[docId].containsKey('lastPage'), isFalse);
    await Future.wait([
      store.rename(id, 'Renamed'),
      store.setStarred(id, starred: true),
      store.update(id, (c) => editor.rename(c, cardId, 'Updated')),
    ]);
    final reopened = FileLibraryStore(root);
    final summary = (await reopened.watchAll().first).single;
    expect(summary.title, 'Renamed');
    expect(summary.starred, isTrue);
    final content = await reopened.load(id);
    expect(content.card(cardId)!.title, 'Updated');
    expect(content.document(docId)!.lastPage, 5);
    expect(content.reviewLogs, hasLength(1));
    await reopened.dispose();
  });

  test('failed projection is committed once and recovered without stale JSON or repeat operation', () async {
    final id = await create();
    final blocker = Directory('${root.path}/sets/$id.mmset/studyset.json.tmp');
    await blocker.create();
    await store.rename(id, 'Durably renamed');
    final content = await store.update(id, (c) => editor.addTopic(c, title: 'Once').$1);
    expect(content.cards, hasLength(1));
    expect(store.syncProjectionErrors, isNotEmpty);
    final before = (await ledger.pending()).length;
    final reopened = FileLibraryStore(root);
    expect((await reopened.load(id)).cards.single.title, 'Once');
    expect((await reopened.watchAll().first).single.title, 'Durably renamed');
    expect((await (await reopened.syncLedger)!.pending()).length, before);
    await reopened.dispose();
    await blocker.delete();
    final recovered = FileLibraryStore(root);
    expect((await recovered.load(id)).cards, hasLength(1));
    expect(recovered.syncProjectionErrors, isEmpty);
    expect(
      jsonDecode(await File('${root.path}/sets/$id.mmset/studyset.json').readAsString())['title'],
      'Durably renamed',
    );
    await recovered.dispose();
  });

  test('delete commits dependent tombstones, retains assets, and refuses late translation writes', () async {
    final id = await create();
    await store.update(id, (c) => editor.addDocument(c, title: 'Doc', fileName: 'documents/a.pdf', pageCount: 2).$1);
    final doc = (await store.load(id)).documents.single.id;
    final translation = await store.translationStore(id);
    await translation.append(doc, 'zh', segment('key'));
    final image = await store.importImageBytes(id, [137, 80, 78, 71, 13, 10, 26, 10]);
    await store.delete(id);
    final snapshots = await ledger.snapshots();
    expect(snapshots['sets/$id']!.deleted, isTrue);
    expect(snapshots['translations/$id/$doc/zh']!.deleted, isTrue);
    expect(snapshots['translations/$id/$doc/zh']!.revision, snapshots['sets/$id']!.revision);
    expect(await File(store.resolveFile(id, image)).exists(), isTrue);
    await expectLater(translation.append(doc, 'zh', segment('late')), throwsStateError);
    final reopened = FileLibraryStore(root);
    expect(await reopened.watchAll().first, isEmpty);
    await reopened.dispose();
  });

  test('document package assets survive projection failure after the commit point', () async {
    final id = await create();
    final blocker = Directory('${root.path}/sets/$id.mmset/studyset.json.tmp');
    await blocker.create();
    final package = DocumentPackage(
      document: Document(id: 'doc', title: 'Doc', fileName: 'documents/source.pdf', pageCount: 2, importedAt: now),
      files: {
        'documents/source.pdf': [1, 2, 3],
      },
    );
    await store.importDocumentPackage(id, package);
    expect(await store.readDocumentFile(id, 'documents/source.pdf'), [1, 2, 3]);
    final reopened = FileLibraryStore(root);
    expect((await reopened.load(id)).documents.single.id, 'doc');
    expect(await reopened.readDocumentFile(id, 'documents/source.pdf'), [1, 2, 3]);
    await reopened.dispose();
  });

  test('vocabulary and translated segments recover from failed projections; task state stays local', () async {
    final id = await create();
    await store.update(id, (c) => editor.addDocument(c, title: 'Doc', fileName: 'documents/a.pdf', pageCount: 2).$1);
    final doc = (await store.load(id)).documents.single.id;
    final vocabulary = FileVocabularyStore(root, sync: ledger);
    await Directory('${root.path}/vocabulary.json.tmp').create();
    await vocabulary.save([word()]);
    final translation = await store.translationStore(id);
    await Directory('${root.path}/sets/$id.mmset/translations/$doc/zh/segments.jsonl.tmp').create(recursive: true);
    await translation.append(doc, 'zh', segment('key'));
    expect(ledger.projectionErrors, hasLength(2));
    final fresh = (await FileSyncLedger.restore(root))!;
    final vocab = FileVocabularyStore(root, sync: fresh);
    expect((await vocab.load()).single.term, 'hello');
    final texts = FileTranslationStore(Directory('${root.path}/sets/$id.mmset'), sync: fresh, studySetId: id);
    expect((await texts.load(doc, 'zh')).segments['key']!.origin, TranslationOrigin.edited);
    expect((await fresh.pending()).where((c) => c.scope.startsWith('translations/')).single.payload.keys, ['segments']);
    await texts.remove(doc, 'zh');
    expect((await texts.load(doc, 'zh')).segments, isEmpty);
    await texts.compact(doc, 'zh');
    await texts.append(doc, 'zh', segment('retry'));
    await texts.compact(doc, 'zh');
    expect((await texts.load(doc, 'zh')).segments.keys, ['retry']);
    await vocabulary.dispose();
    await vocab.dispose();
  });

  test('enabling journals preexisting sets and translations without changing local-only mode by default', () async {
    await store.dispose();
    store = FileLibraryStore(root);
    final id = await create();
    await store.update(id, (c) => editor.addDocument(c, title: 'Doc', fileName: 'documents/a.pdf', pageCount: 2).$1);
    final doc = (await store.load(id)).documents.single.id;
    await (await store.translationStore(id)).append(doc, 'zh', segment('existing'));
    expect(await FileSyncLedger.restore(root), isNull);
    await store.dispose();
    store = FileLibraryStore(root, sync: ledger);
    expect((await store.load(id)).documents.single.id, doc);
    expect((await ledger.snapshots())['translations/$id/$doc/zh']!.value!['segments'], contains('existing'));
    await store.update(id, (c) => editor.removeDocument(c, doc));
    expect((await ledger.snapshots())['translations/$id/$doc/zh']!.deleted, isTrue);
  });

  test('local-only failed metadata writes do not publish changes', () async {
    await store.dispose();
    store = FileLibraryStore(root);
    final id = await create();
    await Directory('${root.path}/sets/$id.mmset/studyset.json.tmp').create();
    await expectLater(store.rename(id, 'Not committed'), throwsA(isA<FileSystemException>()));
    expect((await store.watchAll().first).single.title, 'Set');
  });
}
