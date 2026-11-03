import 'package:mm_core/mm_core.dart';
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
  final empty = VocabularyWord.empty(' EN_us ', ' WORD ');
  test('canonical language and spelling identity retains all source snapshots and round trips', () {
    expect(vocabularyIdentity(' EN_us ', ' WORD '), vocabularyIdentity('en-US', 'word'));
    final word = empty.edit(
      null,
      entry(language: 'en-US', contexts: List.generate(30, (i) => source('$i'))),
      deviceId: 'a',
      operation: 'create',
    );
    expect(word.aliases, {'old-Word'});
    expect(word.entry!.contexts, hasLength(30));
    expect(word.entry!.language, 'en-us');
    expect(word.entry!.id, 'word-${empty.identity}');
    expect(VocabularyWord.fromJson(word.toJson()).toJson(), word.toJson());
  });
  test('independent adds join without losing sources and concurrent notes stay explicit', () {
    final left = empty.edit(
      null,
      entry(language: 'en-us', note: 'Left', contexts: [source('a')]),
      deviceId: 'a',
      operation: 'a',
    );
    final right = empty.edit(
      null,
      entry(term: 'word', language: 'EN-US', note: 'Right', contexts: [source('b')]),
      deviceId: 'b',
      operation: 'b',
    );
    final merged = left.join(right);
    expect(merged.toJson(), right.join(left).toJson());
    expect(merged.join(merged).toJson(), merged.toJson());
    expect(merged.aliases, {'old-Word', 'old-word'});
    expect(merged.conflicts, {'note'});
    expect(merged.entry!.contexts, hasLength(2));
    final typed = merged.edit(
      merged.entry,
      merged.entry!.copyWith(note: 'Typed'),
      deviceId: 'a',
      operation: 'typed',
    );
    expect(typed.conflicts, {'note'});
    expect(typed.alternatives('note').values, contains('Typed'));
    expect(typed.alternatives('note'), hasLength(2));

    expect(merged.alternatives('note').values, containsAll(['Left', 'Right']));
    final choice = merged.choose(
      'note',
      merged.alternatives('note').entries.singleWhere((e) => e.value == 'Right').key,
      deviceId: 'a',
      operation: 'choose',
    );
    expect(choice.entry!.note, 'Right');
    expect(choice.conflicts, isEmpty);
    expect(choice.join(left).toJson(), choice.toJson());
    final other = merged.choose(
      'note',
      merged.alternatives('note').entries.singleWhere((e) => e.value == 'Left').key,
      deviceId: 'b',
      operation: 'choose',
    );
    expect(choice.join(other).conflicts, {'note'});
  });
  test('delete against edit retains life choice; later independent sources and fields still merge', () {
    final initial = empty.edit(
      null,
      entry(language: 'en-us'),
      deviceId: 'a',
      operation: 'a',
    );
    final deleted = initial.edit(initial.entry, null, deviceId: 'a', operation: 'delete');
    final edited = initial.edit(
      initial.entry,
      initial.entry!.copyWith(note: 'New', contexts: [source('b')]),
      deviceId: 'b',
      operation: 'edit',
    );
    final merged = deleted.join(edited);
    expect(merged.conflicts, {'alive'});
    expect(merged.entry!.note, 'New');
    expect(merged.entry!.contexts, hasLength(1));
    final picked = merged.choose(
      'alive',
      merged.alternatives('alive').entries.singleWhere((e) => e.value == false).key,
      deviceId: 'a',
      operation: 'choose',
    );
    expect(picked.entry, isNull);
    expect(picked.conflicts, isEmpty);
    final restored = picked.edit(
      null,
      entry(language: 'en-us'),
      deviceId: 'a',
      operation: 'restore',
    );
    expect(restored.entry, isNotNull);
  });
  test('observed source removal does not remove concurrent additions and explicit re-add survives', () {
    final original = empty.edit(
      null,
      entry(language: 'en-us', contexts: [source('a')]),
      deviceId: 'a',
      operation: 'a',
    );
    final remove = original.edit(
      original.entry,
      original.entry!.copyWith(contexts: []),
      deviceId: 'a',
      operation: 'remove',
    );
    final add = original.edit(
      original.entry,
      original.entry!.copyWith(contexts: [...original.entry!.contexts, source('b')]),
      deviceId: 'b',
      operation: 'add',
    );
    final merged = remove.join(add);
    expect(merged.entry!.contexts.single.documentId, 'doc-b');
    final restored = merged.edit(
      merged.entry,
      merged.entry!.copyWith(contexts: [...merged.entry!.contexts, source('a')]),
      deviceId: 'a',
      operation: 'restore',
    );
    expect(restored.entry!.contexts, hasLength(2));
    merged.validateSuccessor(restored, 'a');
  });
  test('unknown schema, value mutation, unobserved removals and forged author fail closed', () {
    final original = empty.edit(
      null,
      entry(language: 'en-us'),
      deviceId: 'a',
      operation: 'a',
    );
    final next = original.edit(
      original.entry,
      original.entry!.copyWith(note: 'changed'),
      deviceId: 'b',
      operation: 'b',
    );
    expect(() => original.validateSuccessor(next, 'a'), throwsFormatException);
    expect(() => next.validateSuccessor(original, 'a'), throwsFormatException);
    expect(() => VocabularyWord.fromJson({...original.toJson(), 'version': 2}), throwsFormatException);
    final lostAlias = VocabularyWord.fromJson(original.toJson());
    lostAlias.removed['aliases']!.add(lostAlias.writes['aliases']!.keys.single);
    expect(() => VocabularyWord.fromJson(lostAlias.toJson()), throwsFormatException);
    final broken = VocabularyWord.fromJson(original.toJson());
    broken.writes['note']![broken.writes['note']!.keys.first] = 'tampered';
    expect(() => original.join(broken), throwsFormatException);
    final unseen = VocabularyWord.fromJson(original.toJson());
    unseen.writes['note']!['a:${syncDigest('unknown')}'] = 'new';
    unseen.removed['note']!.add('a:${syncDigest('unknown')}');
    expect(() => original.validateSuccessor(unseen, 'a'), throwsFormatException);
    expect(() => original.choose('note', 'missing', deviceId: 'a', operation: 'choose'), throwsFormatException);
  });
  test('deterministic empty baseline and validated integrations preserve causal histories', () {
    final root = vocabularyBaseline('lib', 'en-us', 'word');
    final base = VocabularyWord.fromJson(root.payload);
    final a = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'a',
      sequence: 1,
      parents: [root.id],
      payload: base
          .edit(
            null,
            entry(language: 'en-us', note: 'a'),
            deviceId: 'a',
            operation: 'a',
          )
          .toJson(),
    );
    final b = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'b',
      sequence: 1,
      parents: [root.id],
      payload: base
          .edit(
            null,
            entry(language: 'en-us', note: 'b'),
            deviceId: 'b',
            operation: 'b',
          )
          .toJson(),
    );
    final graph = {root.id: root, a.id: a, b.id: b};
    expect(planVocabularyWord(graph, remote: a.id).adopt, isTrue);
    final plan = planVocabularyWord(graph, remote: b.id, local: a.id);
    expect(plan.state, SyncMergeState.ready);
    expect(plan.adopt, isFalse);
    expect(VocabularyWord.fromJson(plan.payload!).conflicts, {'note'});
    final merge = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'a',
      sequence: 2,
      parents: [a.id, b.id],
      payload: plan.payload!,
    );
    graph[merge.id] = merge;
    expect(planVocabularyWord(graph, remote: merge.id, local: b.id).adopt, isTrue);
    expect(planVocabularyWord(graph, remote: a.id, local: merge.id).state, SyncMergeState.unchanged);
    final forged = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'a',
      sequence: 3,
      parents: [a.id, b.id],
      payload: a.payload,
    );
    expect(planVocabularyWord({...graph, forged.id: forged}, remote: forged.id).state, SyncMergeState.conflict);
    expect(planVocabularyWord({a.id: a}, remote: a.id).state, SyncMergeState.waiting);
    final unknown = SyncCommit.create(
      libraryId: 'lib',
      scope: root.scope,
      deviceId: 'x',
      sequence: 1,
      payload: root.payload,
    );
    expect(planVocabularyWord({unknown.id: unknown}, remote: unknown.id).reason, 'noBase');
  });
}
