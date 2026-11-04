import 'dart:io';
import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

VocabularyContext source(String id) => VocabularyContext(
  id: id,
  studySetId: 'set',
  documentId: 'doc-$id',
  studySetTitle: 'Study',
  documentTitle: 'Book',
  sentence: 'The word in $id',
  hit: 'Word',
  addedAt: DateTime.utc(2026),
  page: 1,
);
VocabularyEntry entry({
  String term = 'Word',
  String language = 'en',
  String note = '',
  List<VocabularyContext> contexts = const [],
}) => VocabularyEntry(
  id: 'old-$term',
  term: term,
  language: language,
  kind: VocabularyKind.word,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  forms: [vocabularyKey(term)],
  note: note,
  contexts: contexts,
);
void main() {
  late Directory root;
  late FileSyncLedger left, right;
  late FileVocabularyStore a, b;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('word-sync-');
    left = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    right = VocabularyRacingLedger(Directory('${root.path}/b'));
    a = FileVocabularyStore(left.root, sync: left);
    b = FileVocabularyStore(right.root, sync: right);
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await root.delete(recursive: true);
  });
  Future<void> sendA() async => b.receiveSync(await left.pending());
  Future<void> sendB() async => a.receiveSync(await right.pending());
  test('independent normalized identities converge with every source and persist unresolved fields', () async {
    await a.save([entry(note: 'left', contexts: List.generate(25, (i) => source('a$i')))]);
    await b.save([
      entry(term: 'word', language: ' EN ', note: 'right', contexts: [source('b')]),
    ]);
    final events = <List<VocabularyEntry>>[];
    final sub = b.watch().listen(events.add);
    await sendA();
    await sendB();
    await sendA();
    expect((await a.load()).single.id, (await b.load()).single.id);
    expect(await b.resolveVocabularyEntryId('old-Word'), (await b.load()).single.id);
    expect(await b.resolveVocabularyEntryId('old-word'), (await b.load()).single.id);
    expect((await b.load()).single.contexts, hasLength(26));
    expect((await a.vocabularySyncState()).conflicts.single.field, VocabularySyncField.note);
    await Future<void>.delayed(Duration.zero);
    expect(events.last.single.contexts, hasLength(26));
    await sub.cancel();
    final pending = (await right.pending()).map((c) => c.id).toList();
    await b.dispose();
    b = FileVocabularyStore(right.root);
    expect((await b.load()).single.contexts, hasLength(26));
    final conflict = (await b.vocabularySyncState()).conflicts.single;
    await b.chooseVocabulary(
      conflict.entryId,
      conflict.field,
      conflict.choices.singleWhere((c) => c.text == 'right').id,
      expectedRevision: conflict.revision,
    );
    await a.receiveSync(await (await FileSyncLedger.restore(right.root))!.pending());
    expect((await a.load()).single.note, 'right');
    expect((await a.vocabularySyncState()).conflicts, isEmpty);
    expect((await right.pending()).map((c) => c.id), pending); // stale instance does not manufacture uploads
  });
  test('missing histories wait, unrelated roots and malformed word data stay diagnostic', () async {
    await a.save([entry()]);
    await a.updateVocabulary((e) => [e.single.copyWith(note: 'later')]);
    final commits = (await left.pending()).where((c) => c.scope.startsWith('words/')).toList();
    await b.receiveSync([commits.last]);
    expect(await b.load(), isEmpty);
    expect((await b.vocabularySyncState()).problems, contains(ContentSyncProblem.missingHistory));
    await b.receiveSync(commits);
    expect((await b.load()).single.note, 'later');
    final bad = SyncCommit.create(
      libraryId: 'lib',
      scope: commits.last.scope,
      deviceId: 'other',
      sequence: 1,
      payload: commits.last.payload,
    );
    await b.receiveSync([bad]);
    expect((await b.vocabularySyncState()).problems, isNotEmpty);
    expect((await b.load()).single.note, 'later');
  });
  test('delete against edit remains a choice, independent words and third devices continue', () async {
    await a.save([entry()]);
    await sendA();
    await a.updateVocabulary((_) => []);
    await b.updateVocabulary((e) => [e.single.copyWith(note: 'Keep me'), entry(term: 'Other')]);
    await sendA();
    await sendB();
    expect(await a.load(), hasLength(2));
    final conflict = (await a.vocabularySyncState()).conflicts.single;
    expect(conflict.field, VocabularySyncField.alive);
    final thirdLedger = FileSyncLedger(Directory('${root.path}/third'), libraryId: 'lib', deviceId: 'third');
    final third = FileVocabularyStore(thirdLedger.root, sync: thirdLedger);
    try {
      await third.receiveSync([...await left.pending(), ...await right.pending()]);
      expect((await third.vocabularySyncState()).conflicts.single.field, VocabularySyncField.alive);
      expect(await third.load(), hasLength(2));
      await third.chooseVocabulary(
        conflict.entryId,
        conflict.field,
        conflict.choices.singleWhere((c) => c.deleted == false).id,
        expectedRevision: (await third.vocabularySyncState()).conflicts.single.revision,
      );
      await a.receiveSync(await thirdLedger.pending());
      expect((await a.vocabularySyncState()).conflicts, isEmpty);
      expect((await a.load()).singleWhere((e) => e.key == 'word').note, 'Keep me');
    } finally {
      await third.dispose();
    }
  });
  test('stale choices and stale complete saves cannot overwrite a newer publication', () async {
    await a.save([entry(note: 'a')]);
    await b.save([entry(note: 'b')]);
    await sendA();
    final c = (await b.vocabularySyncState()).conflicts.single;
    final observed = await b.load();
    await b.updateVocabulary((e) => [e.single.copyWith(gloss: 'new')]);
    await expectLater(
      b.chooseVocabulary(c.entryId, c.field, c.choices.first.id, expectedRevision: c.revision),
      throwsA(isA<ContentSyncActionException>()),
    );
    // Callers using the atomic port edit only their intended fields, even when
    // another device has added a source since the UI originally loaded.
    await a.updateVocabulary(
      (e) => [
        e.single.copyWith(contexts: [source('new')]),
      ],
    );
    await sendA();
    final changed = await b.updateVocabulary((e) => [e.single.copyWith(gloss: 'next')]);
    expect(changed.after.single.contexts, hasLength(1));
    expect(observed.single.contexts, isEmpty);
    await expectLater(b.save(observed), throwsStateError);
    expect((await b.load()).single.contexts, hasLength(1));
  });
  test('legacy normalized duplicates migrate together and projection errors retry without losing sources', () async {
    await left.root.create(recursive: true);
    await File('${left.root.path}/vocabulary.json').writeAsString(
      jsonEncode({
        'format': 1,
        'entries': [
          entry(note: 'a', contexts: [source('a')]).toJson(),
          {
            ...entry(term: 'word', note: 'b', contexts: [source('b')]).toJson(),
            'language': ' EN ',
          },
        ],
      }),
    );
    expect((await a.load()).single.contexts, hasLength(2));
    expect((await a.vocabularySyncState()).conflicts.single.field, VocabularySyncField.note);
    final blocker = Directory('${left.root.path}/vocabulary.json.tmp');
    await blocker.create();
    await a.updateVocabulary((e) => [e.single.copyWith(gloss: 'x')]);
    expect((await a.vocabularySyncState()).repairNeeded, isTrue);
    await blocker.delete();
    await a.retryVocabularySync();
    expect((await a.vocabularySyncState()).repairNeeded, isFalse);
    expect((await a.load()).single.gloss, 'x');
    await a.dispose();
    a = FileVocabularyStore(left.root);
    expect((await a.load()).single.contexts, hasLength(2));
  });
  test('old aliases survive restart and ambiguous aliases never select another word', () async {
    await a.save([entry()]);
    final id = (await a.load()).single.id;
    expect(await a.resolveVocabularyEntryId(id), id);
    expect(await a.resolveVocabularyEntryId('unknown'), isNull);
    await b.save([
      VocabularyEntry.fromJson({...entry(term: 'other').toJson(), 'id': 'old-Word'}),
    ]);
    await sendB();
    expect(await a.resolveVocabularyEntryId('old-Word'), isNull);
    await a.updateVocabulary((e) => e.where((v) => v.key == 'word').toList());
    await a.dispose();
    a = FileVocabularyStore(left.root);
    expect(await a.resolveVocabularyEntryId('old-Word'), id);
    await a.updateVocabulary((e) => []);
    expect(await a.resolveVocabularyEntryId('old-Word'), isNull);
  });
  test('active vocabulary input defers only its word and release merges against saved text', () async {
    await a.save([entry()]);
    await sendA();
    final local = (await b.load()).single;
    final lease = b.protectVocabulary(local.id);
    await lease.ready;
    await a.updateVocabulary((e) => [e.single.copyWith(note: 'remote'), entry(term: 'other')]);
    await sendA();
    expect((await b.load()).singleWhere((e) => e.key == 'word').note, '');
    expect((await b.load()).any((e) => e.key == 'other'), isTrue);
    expect((await b.vocabularySyncState()).problems, contains(ContentSyncProblem.editing));
    await b.updateVocabulary(
      (e) => [
        for (final v in e)
          if (v.id == local.id) v.copyWith(note: 'typed') else v,
      ],
    );
    await lease.release();
    final conflict = (await b.vocabularySyncState()).conflicts.single;
    expect(conflict.choices.map((c) => c.text), containsAll(['typed', 'remote']));
    final again = b.protectVocabulary(local.id);
    await again.ready;
    await expectLater(
      b.chooseVocabulary(
        conflict.entryId,
        conflict.field,
        conflict.choices.first.id,
        expectedRevision: conflict.revision,
      ),
      throwsA(isA<ContentSyncActionException>().having((e) => e.reason, 'reason', ContentSyncActionFailure.editing)),
    );
    await again.release();
  });
  test('journal failure leaves committed vocabulary and pending versions unchanged', () async {
    await a.save([entry()]);
    final before = (await left.pending()).map((c) => c.id).toList();
    final logs = Directory('${left.root.path}/.foliarc-sync/local');
    final saved = await logs.rename('${logs.path}.saved');
    final obstruction = File(logs.path);
    await obstruction.writeAsString('block');
    await expectLater(
      a.updateVocabulary((e) => [e.single.copyWith(note: 'not saved')]),
      throwsA(isA<FileSystemException>()),
    );
    expect((await a.load()).single.note, '');
    expect((await left.pending()).map((c) => c.id), before);
    await obstruction.delete();
    await saved.rename(logs.path);
    await a.updateVocabulary((e) => [e.single.copyWith(note: 'saved')]);
    expect((await a.load()).single.note, 'saved');
  });
  test('shared receiver dispatches content and words through their live repositories', () async {
    final libraryA = FileLibraryStore(left.root, sync: left), libraryB = FileLibraryStore(right.root, sync: right);
    try {
      final id = (await libraryA.create(const NewStudySet(title: 'Study', colorIndex: 0))).id;
      await a.updateVocabulary(
        (_) => [
          entry(contexts: [source('linked')]),
        ],
      );
      final receiver = FileSyncReceiver(libraryB, b);
      await receiver.receive(await left.pending());
      expect((await libraryB.watchAll().first).single.id, id);
      expect((await b.load()).single.contexts, hasLength(1));
      await receiver.retry();
      expect(await b.load(), hasLength(1));
      await expectLater(FileSyncReceiver(libraryA, b).retry(), throwsStateError);
    } finally {
      await libraryA.dispose();
      await libraryB.dispose();
    }
  });
  test('adoption recomputes after another repository advances the shared index', () async {
    await a.save([entry()]);
    await b.load();
    final other = FileVocabularyStore(right.root, sync: right);
    try {
      (right as VocabularyRacingLedger).beforeAdvance = () async {
        await other.updateVocabulary((e) => [...e, entry(term: 'Other')]);
      };
      await sendA();
      expect((await b.load()).map((e) => e.key).toSet(), {'word', 'other'});
    } finally {
      await other.dispose();
    }
  });
  test('input acquired after planning still blocks publication at the commit boundary', () async {
    await a.save([entry()]);
    await sendA();
    final id = (await b.load()).single.id;
    await a.updateVocabulary((e) => [e.single.copyWith(note: 'remote')]);
    ContentEditLease? lease;
    (right as VocabularyRacingLedger).beforeAdvance = () async {
      lease = b.protectVocabulary(id);
    };
    await sendA();
    await lease!.ready;
    expect((await b.load()).single.note, '');
    expect((await b.vocabularySyncState()).problems, contains(ContentSyncProblem.editing));
    await lease!.release();
    expect((await b.load()).single.note, 'remote');
  });
}

class VocabularyRacingLedger extends FileSyncLedger {
  VocabularyRacingLedger(super.root) : super(libraryId: 'lib', deviceId: 'b');
  Future<void> Function()? beforeAdvance;
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
    if (inputs.any((m) => m.scope.startsWith('words/') && (m.adopt != null || m.mergeParent != null))) {
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
