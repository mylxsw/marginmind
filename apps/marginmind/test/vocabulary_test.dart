import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/vocabulary/vocabulary_controller.dart';
import 'package:marginmind/features/vocabulary/vocabulary_hints.dart';

final now = DateTime.utc(2026);
VocabularyContext context(String id) => VocabularyContext(
  id: id,
  studySetId: 's',
  documentId: 'd',
  studySetTitle: 'set',
  documentTitle: 'doc',
  sentence: 'Cats sleep.',
  hit: 'Cats',
  addedAt: now,
  page: 1,
  rects: [const PageRect(0, 10, 10, 0)],
);

class FailingRepository extends InMemoryVocabularyRepository {
  bool fail = false;
  @override
  Future<void> save(List<VocabularyEntry> entries) async {
    if (fail) throw StateError('disk failed');
    await super.save(entries);
  }
}

class UnreadableRepository extends InMemoryVocabularyRepository {
  @override
  Future<List<VocabularyEntry>> load() => Future.error(const FormatException('corrupt file'));
}

// A delegating fake exercises provider failure semantics without a platform plugin.
class PreferenceFailure implements SharedPreferences {
  PreferenceFailure(this.delegate);
  final SharedPreferences delegate;
  String? failKey;
  @override
  Object? get(String key) => delegate.get(key);
  @override
  Future<bool> setString(String key, String value) async {
    await delegate.setString(key, value);
    if (key == failKey) {
      failKey = null;
      return false;
    }
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    await delegate.setBool(key, value);
    if (key == failKey) {
      failKey = null;
      throw StateError('prefs failure');
    }
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    await delegate.setStringList(key, value);
    if (key == failKey) {
      failKey = null;
      return false;
    }
    return true;
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('lookup conversion, neutral fallback, serialized edits and independent undo', () async {
    final repository = InMemoryVocabularyRepository();
    final container = ProviderContainer(
      overrides: [
        vocabularyRepositoryProvider.overrideWithValue(repository),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    expect((await container.read(vocabularyProvider.future)).entries, isEmpty);
    final controller = container.read(vocabularyProvider.notifier);
    final receipt = await controller.add(
      selected: 'Cats',
      language: 'en',
      kind: VocabularyKind.word,
      context: context('c'),
      lookup: WordLookupResult(
        lemma: 'cat',
        ukPhonetic: 'kæt',
        usPhonetic: 'kæt',
        senses: [const WordSense(pos: 'n', meaning: '猫')],
        context: const WordContext(contextMeaning: '猫', sentenceTranslation: '猫在睡觉。'),
        gloss: '猫',
        forms: ['cat', 'cats'],
      ),
    );
    final cat = (await repository.load()).single;
    expect(cat.forms, containsAll(['cat', 'cats']));
    expect(cat.senses.single.meaning, '猫');
    expect(cat.contexts.single.sentenceTranslation, '猫在睡觉。');
    expect(cat.ukPhonetic, 'kæt');
    final second = await controller.add(
      selected: 'dog',
      language: 'en',
      kind: VocabularyKind.word,
      context: context('d'),
    );
    await controller.undo(receipt);
    expect((await repository.load()).single.term, 'dog');
    await expectLater(controller.undo(receipt), throwsStateError);
    await controller.undo(second);
    expect(await repository.load(), isEmpty);
    final results = await Future.wait([
      controller.add(selected: 'a', language: 'en', kind: VocabularyKind.word, context: context('a')),
      controller.add(selected: 'b', language: 'en', kind: VocabularyKind.word, context: context('b')),
    ]);
    expect(await repository.load(), hasLength(2));
    expect(results, hasLength(2));
    final version = container.read(vocabularyProvider).requireValue.version;
    await Future<void>.delayed(Duration.zero);
    expect(container.read(vocabularyProvider).requireValue.version, version);
    expect(version, greaterThan(0));
  });
  test('stale undo rejected, failed save leaves snapshot and permits retry', () async {
    final repository = FailingRepository();
    final container = ProviderContainer(overrides: [vocabularyRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await container.read(vocabularyProvider.future);
    final controller = container.read(vocabularyProvider.notifier);
    final receipt = await controller.add(
      selected: 'cat',
      language: 'en',
      kind: VocabularyKind.word,
      context: context('a'),
    );
    final cat = (await repository.load()).single;
    const editor = VocabularyEditor();
    await controller.edit((e) => editor.updateNote(e, cat.id, 'my note', now));
    await expectLater(controller.undo(receipt), throwsStateError);
    repository.fail = true;
    await expectLater(controller.edit((e) => editor.remove(e, cat.id)), throwsStateError);
    expect(container.read(vocabularyProvider).requireValue.entries.single.note, 'my note');
    repository.fail = false;
    final removed = await controller.edit((e) => editor.remove(e, cat.id));
    await controller.undo(removed);
    expect((await repository.load()).single.note, 'my note');
    final noop = await controller.edit((e) => e);
    await controller.undo(noop);
    expect(await repository.load(), hasLength(1));
  });
  test('undo detects a new entry with the same language and canonical key', () async {
    final repository = InMemoryVocabularyRepository();
    final container = ProviderContainer(overrides: [vocabularyRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await container.read(vocabularyProvider.future);
    final controller = container.read(vocabularyProvider.notifier);
    await controller.add(selected: 'cat', language: 'en', kind: VocabularyKind.word, context: context('a'));
    final removed = await controller.edit((_) => []);
    await controller.add(selected: 'cat', language: 'en', kind: VocabularyKind.word, context: context('b'));
    await expectLater(controller.undo(removed), throwsStateError);
  });
  test('hint defaults, settings API, resume mode and per-document visibility persist', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    expect(container.read(vocabularyHintProvider).showKnown, isFalse);
    final controller = container.read(vocabularyHintProvider.notifier);
    expect(controller.defaultMode, VocabularyHintMode.underline);
    await controller.setDefaultMode(VocabularyHintMode.gloss);
    await controller.toggle();
    expect(container.read(vocabularyHintProvider).mode, VocabularyHintMode.off);
    expect(prefs.getString('vocabulary.lastHintMode'), 'gloss');
    await controller.toggle();
    await Future.wait([
      controller.setShowKnown(true),
      controller.setDocumentHidden('d', true),
      controller.setDocumentHidden('other', true),
    ]);
    expect(container.read(vocabularyHintProvider).modeFor('d'), VocabularyHintMode.off);
    expect(container.read(vocabularyHintProvider).modeFor('visible'), VocabularyHintMode.gloss);
    await controller.setDocumentHidden('d', false);
    final fresh = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(fresh.dispose);
    final restored = fresh.read(vocabularyHintProvider);
    expect(restored.defaultMode, VocabularyHintMode.gloss);
    expect(restored.hiddenDocuments, {'other'});
    expect(restored.showKnown, isTrue);
    expect(() => restored.hiddenDocuments.clear(), throwsUnsupportedError);
  });
  test('unknown preferences fall back to safe defaults', () async {
    SharedPreferences.setMockInitialValues({
      'vocabulary.hintMode': 'future',
      'vocabulary.lastHintMode': 'off',
      'vocabulary.showKnown': 'yes',
      'vocabulary.hiddenDocuments': 42,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final state = container.read(vocabularyHintProvider);
    expect(state.mode, VocabularyHintMode.underline);
    expect(state.lastMode, VocabularyHintMode.underline);
    expect(state.showKnown, isFalse);
    expect(state.hiddenDocuments, isEmpty);
  });
  test('preference failures restore state and cache, then allow retry', () async {
    SharedPreferences.setMockInitialValues({
      'vocabulary.hintMode': 'underline',
      'vocabulary.lastHintMode': 'underline',
      'vocabulary.showKnown': false,
      'vocabulary.hiddenDocuments': <String>[],
    });
    final prefs = PreferenceFailure(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    container.read(vocabularyHintProvider);
    final controller = container.read(vocabularyHintProvider.notifier);
    prefs.failKey = 'vocabulary.hintMode';
    await expectLater(controller.setMode(VocabularyHintMode.gloss), throwsStateError);
    expect(container.read(vocabularyHintProvider).mode, VocabularyHintMode.underline);
    expect(prefs.get('vocabulary.lastHintMode'), 'underline');
    expect(prefs.get('vocabulary.hintMode'), 'underline');
    prefs.failKey = 'vocabulary.showKnown';
    await expectLater(controller.setShowKnown(true), throwsStateError);
    expect(container.read(vocabularyHintProvider).showKnown, false);
    expect(prefs.get('vocabulary.showKnown'), false);
    prefs.failKey = 'vocabulary.hiddenDocuments';
    await expectLater(controller.setDocumentHidden('d', true), throwsStateError);
    expect(prefs.get('vocabulary.hiddenDocuments'), isEmpty);
    await controller.setMode(VocabularyHintMode.gloss);
    expect(controller.defaultMode, VocabularyHintMode.gloss);
  });
  test('load errors are exposed instead of silently creating an empty vocabulary', () async {
    final repository = UnreadableRepository();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [vocabularyRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await expectLater(container.read(vocabularyProvider.future), throwsFormatException);
    expect(container.read(vocabularyProvider).hasError, true);
  });
}
