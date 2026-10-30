import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026);
VocabularyContext context(String id, {String document = 'd', String? sentence, int day = 1}) => VocabularyContext(
  id: id,
  studySetId: 's',
  documentId: document,
  studySetTitle: 'Set',
  documentTitle: 'Book',
  sentence: sentence ?? 'The cat sat.',
  hit: 'cat',
  addedAt: DateTime.utc(2026, 1, day),
  sentenceTranslation: '猫坐着。',
  page: 1,
  rects: [const PageRect(0, 10, 10, 0)],
);
VocabularyEntry entry(
  String term, {
  String? id,
  String language = 'en',
  List<String>? forms,
  VocabularyStatus status = VocabularyStatus.learning,
  List<VocabularyContext> contexts = const [],
}) => VocabularyEntry(
  id: id ?? term,
  term: term,
  language: language,
  kind: term.contains(' ') ? VocabularyKind.phrase : VocabularyKind.word,
  createdAt: now,
  updatedAt: now,
  forms: forms ?? [vocabularyKey(term)],
  status: status,
  contexts: contexts,
);

void main() {
  const editor = VocabularyEditor();
  test('JSON preserves all fields, anchors and ignores future fields', () {
    final source = VocabularyContext(
      id: 'c',
      studySetId: 's',
      documentId: 'd',
      studySetTitle: 'set',
      documentTitle: 'doc',
      sentence: 'cat',
      hit: 'cat',
      addedAt: now,
      textAnchor: const TextAnchor('ch', 0, 3, 'cat', revision: 'r'),
    );
    final original = VocabularyEntry(
      id: 'v',
      term: ' Cat ',
      language: 'en',
      kind: VocabularyKind.word,
      createdAt: now,
      updatedAt: now,
      forms: ['cat', 'cats'],
      senses: [const VocabularySense(partOfSpeech: 'n', meaning: '猫')],
      ukPhonetic: 'kæt',
      usPhonetic: 'kæt',
      gloss: '猫',
      note: 'note',
      contexts: [source, context('pdf')],
    );
    final json = (jsonDecode(jsonEncode(original.toJson())) as Map).cast<String, Object?>()..['future'] = true;
    expect(VocabularyEntry.fromJson(json).toJson(), original.toJson());
    expect(() => VocabularyEntry.fromJson({...json, 'key': 'wrong'}), throwsFormatException);
    expect(() => VocabularyEntry.fromJson({...json, 'status': 'future'}), throwsArgumentError);
    expect(() => original.forms.add('x'), throwsUnsupportedError);
    expect(() => original.contexts.clear(), throwsUnsupportedError);
    expect(() => original.contexts.first.rects.clear(), throwsUnsupportedError);
    expect(() => original.copyWith(gloss: '123456789'), throwsArgumentError);
    expect(() => context('', sentence: ''), throwsArgumentError);
  });
  test('edits deduplicate language/key, keep user edits, cap distinct source sentences', () {
    var entries = editor.add([], entry('cat', contexts: [context('a')]));
    entries = editor.updateNote(entries, 'cat', 'mine', now);
    entries = editor.setStatus(entries, 'cat', VocabularyStatus.known, now);
    entries = editor.add(
      entries,
      entry(
        'CAT',
        id: 'other',
        contexts: [context('b', document: 'other')],
      ),
    );
    expect(entries, hasLength(1));
    expect(entries.single.contexts, hasLength(2));
    expect(entries.single.note, 'mine');
    expect(entries.single.status, VocabularyStatus.known);
    entries = editor.add(entries, entry('cat', id: 'fr', language: 'fr'));
    expect(entries, hasLength(2));
    expect(() => editor.add(entries, entry('dog', id: 'cat')), throwsArgumentError);
    for (var i = 1; i <= 25; i++) {
      entries = editor.addContext(entries, 'cat', context('c$i', sentence: 'cat $i', day: i), now);
    }
    expect(entries.first.contexts, hasLength(20));
    expect(entries.first.contexts.first.id, 'c25');
    entries = editor.addContext(entries, 'cat', context('duplicate', sentence: ' cat   25 ', day: 26), now);
    expect(entries.first.contexts, hasLength(20));
    expect(entries.first.contexts.first.id, 'duplicate');
    entries = editor.updateForms(entries, 'cat', [
      ' CAT ',
      'cats',
      'cats',
      '',
      ...List.generate(20, (i) => 'cat$i'),
    ], now);
    expect(entries.first.forms, hasLength(16));
    expect(entries.first.forms.take(2), ['cat', 'cats']);
    entries = editor.updateGloss(entries, 'cat', '猫', now);
    entries = editor.updateSenses(entries, 'cat', [const VocabularySense(partOfSpeech: 'n', meaning: '猫')], now);
    expect(entries.first.gloss, '猫');
    expect(entries.first.senses.single.meaning, '猫');
    entries = editor.removeContext(entries, 'cat', 'duplicate', now);
    expect(entries.first.contexts, hasLength(19));
    expect(editor.remove(entries, 'cat').single.id, 'fr');
    expect(() => entries.clear(), throwsUnsupportedError);
  });
  test('selection limits and punctuation', () {
    for (final s in ['cat', '“Cat”', "don't", 'l’été']) {
      expect(classifyVocabularySelection(s), VocabularySelectionKind.word, reason: s);
    }
    for (final s in ['a b c d e f g h', '机器学习', 'a  b', 'a b.', 'take for granted.', '“feedback loop,”']) {
      expect(classifyVocabularySelection(s), VocabularySelectionKind.phrase, reason: s);
    }
    for (final s in [
      '',
      '...',
      'a b c d e f g h i',
      'a. b',
      'deliberate. Practice',
      'a! b',
      'a? b',
      'a; b',
      'a: b',
      'a—b',
      'a。b',
      '${'a ' * 32}b',
    ]) {
      expect(classifyVocabularySelection(s), VocabularySelectionKind.sentence, reason: s);
    }
  });
  test('English fallback preserves selected spelling without guessing comparatives', () {
    List<String> forms(String s) => vocabularyForms(term: s, selected: s, language: 'en', kind: VocabularyKind.word);
    expect(forms('try'), containsAll(['tries', 'tried', 'trying']));
    expect(forms('watch'), containsAll(['watches', 'watched', 'watching']));
    expect(forms('love'), containsAll(['loved', 'loving']));
    expect(forms('run'), containsAll(['running']));
    expect(forms('plan'), isNot(contains('planner')));
    expect(forms('big'), isNot(contains('bigger')));
    expect(forms('big'), isNot(contains('biggest')));
    expect(forms('happy'), containsAll(['happily']));
    expect(forms('tie'), contains('tying'));
    expect(forms('see'), contains('seeing'));
    expect(
      vocabularyForms(
        term: 'be',
        selected: 'WAS',
        supplied: List.generate(20, (i) => 'form$i'),
        language: 'en',
        kind: VocabularyKind.word,
      ),
      hasLength(16),
    );
    expect(vocabularyForms(term: 'be', selected: 'WAS', language: 'en', kind: VocabularyKind.word), contains('was'));
    expect(vocabularyForms(term: 'take off', selected: 'take off', language: 'en', kind: VocabularyKind.phrase), [
      'take off',
    ]);
    expect(vocabularyForms(term: '猫', selected: '猫', language: 'zh', kind: VocabularyKind.word), ['猫']);
  });
  test('supplied forms suppress local guesses while retaining lemma and selected spelling', () {
    for (final (term, selected, supplied) in [
      ('rule', 'RULES', ['rule', 'rules']),
      ('plan', 'PLANNED', ['plan', 'planned']),
      ('ring', 'RANG', ['ring', 'rang']),
      ('big', 'BIGGEST', ['big', 'bigger', 'biggest']),
    ]) {
      expect(
        vocabularyForms(term: term, selected: selected, language: 'en', kind: VocabularyKind.word, supplied: supplied),
        unorderedEquals({term, selected.toLowerCase(), ...supplied}),
        reason: term,
      );
    }
    expect(vocabularyForms(term: 'be', selected: 'WAS', language: 'en', kind: VocabularyKind.word, supplied: ['is']), [
      'be',
      'was',
      'is',
    ]);
  });
  test('matching boundaries, longest phrases, stable collisions and original UTF16 offsets', () {
    final matcher = VocabularyMatcher([
      entry('cat'),
      entry('cat sat'),
      entry('cat sat down'),
      entry('cats', status: VocabularyStatus.known),
      entry('CAT', id: 'z'),
      entry('机器'),
      entry('机器学习'),
      entry('ai学习'),
      entry("don't"),
      entry('i'),
    ]);
    final text = "😀 CAT\tSAT down, cat.sat; cats scatter. 机器学习机器 don't İ AI学习";
    final hits = matcher.match(text);
    expect(hits.map((m) => text.substring(m.start, m.end)), [
      'CAT\tSAT down',
      'cat',
      '机器学习',
      '机器',
      "don't",
      'İ',
      'AI学习',
    ]);
    expect(hits.first.start, 3);
    expect(hits[1].entryId, 'cat');
    expect(VocabularyMatcher([entry('cat sat')]).match('cat-sat cat.sat cat!sat cat;sat cat:sat cat—sat'), isEmpty);
    expect(VocabularyMatcher([entry('cat sat')]).match('cat\nsat'), hasLength(1));
    expect(
      VocabularyMatcher([entry('cats', status: VocabularyStatus.known)], showKnown: true).match('CATS'),
      hasLength(1),
    );
    expect(VocabularyMatcher([entry('cat sat')]).match('cat'), isEmpty);
    expect(VocabularyMatcher([entry('cat-sat')]).match('cat-sat'), isEmpty);
  });
  test('bounded cache isolates versions, visibility and collision-free text', () {
    final cache = VocabularyMatchCache(capacity: 1);
    final entries = [entry('cat')];
    final first = cache.match('cat', version: 1, entries: entries);
    expect(identical(cache.match('cat', version: 1, entries: entries), first), isTrue);
    expect(cache.match('dog', version: 1, entries: entries), isEmpty);
    expect(identical(cache.match('cat', version: 1, entries: entries), first), isFalse);
    expect(cache.match('cat', version: 2, entries: []), isEmpty);
    expect(cache.match('cat', version: 2, entries: entries, showKnown: true), hasLength(1));
    cache.clear();
    expect(() => VocabularyMatchCache(capacity: 0), throwsArgumentError);
  });
  test('memory repository watch emits initial state and committed immutable snapshots', () async {
    final repo = InMemoryVocabularyRepository();
    final events = <List<VocabularyEntry>>[];
    final sub = repo.watch().listen(events.add);
    await Future<void>.delayed(Duration.zero);
    await repo.save([entry('cat')]);
    await Future<void>.delayed(Duration.zero);
    expect(events.map((e) => e.length), [0, 1]);
    expect((await repo.load()).single.term, 'cat');
    await sub.cancel();
    await repo.dispose();
  });
}
