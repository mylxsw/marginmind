import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';

/// Latest durable vocabulary and a monotonic in-process matcher cache version.
class VocabularyState {
  VocabularyState(List<VocabularyEntry> entries, this.version) : entries = List.unmodifiable(entries);
  final List<VocabularyEntry> entries;
  final int version;
}

/// Before/after values for one committed edit. A stale receipt cannot overwrite
/// later changes to the same entry; unrelated entries may still be edited.
class VocabularyUndo {
  VocabularyUndo._(this.before, this.after, this.versions);
  final Map<String, String> versions;
  final Map<String, VocabularyEntry?> before, after;
  bool _used = false;
}

/// Application-level vocabulary. UI callers await mutations before showing HUDs.
final vocabularyProvider = AsyncNotifierProvider<VocabularyController, VocabularyState>(VocabularyController.new);

/// Owns serialization and lookup-to-domain conversion; mm_core never depends on AI.
class VocabularyController extends AsyncNotifier<VocabularyState> {
  Future<void> _queue = Future.value();
  final _editor = const VocabularyEditor();
  late VocabularyRepository _repository;
  var _version = 0;
  String? _published;

  @override
  Future<VocabularyState> build() async {
    _repository = ref.watch(vocabularyRepositoryProvider);
    final entries = await _repository.load();
    if (!ref.mounted) return VocabularyState(entries, _version);
    _published = _encode(entries);
    final sub = _repository.watch().listen(
      (_) {
        unawaited(
          _serial(() async {
            final latest = await _repository.load();
            if (ref.mounted) _publish(latest);
          }).catchError((Object error, StackTrace stack) {
            if (ref.mounted) state = AsyncError(error, stack);
          }),
        );
      },
      onError: (Object error, StackTrace stack) {
        if (ref.mounted) state = AsyncError(error, stack);
      },
    );
    ref.onDispose(() => unawaited(sub.cancel()));
    return VocabularyState(entries, _version);
  }

  String _encode(List<VocabularyEntry> entries) => jsonEncode(entries.map((e) => e.toJson()).toList());
  String? _entry(VocabularyEntry? entry) => entry == null ? null : jsonEncode(entry.toJson());
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _publish(List<VocabularyEntry> entries) {
    final encoded = _encode(entries);
    if (_published == encoded && state.hasValue) return;
    _published = encoded;
    state = AsyncData(VocabularyState(entries, ++_version));
  }

  /// Apply a neutral pure editor operation against the most recent snapshot.
  /// A failed save leaves displayed data and undo history untouched.
  Future<VocabularyUndo> edit(List<VocabularyEntry> Function(List<VocabularyEntry>) change) async {
    await future;
    return _serial(() async {
      late List<VocabularyEntry> before, after;
      var versions = <String, String>{};
      final repository = _repository;
      if (repository is AtomicVocabularyRepository) {
        final result = await (repository as AtomicVocabularyRepository).updateVocabulary(change);
        before = result.before;
        after = result.after;
        versions = result.versions;
      } else {
        before = await repository.load();
        after = change(before);
        if (_encode(before) != _encode(after)) await repository.save(after);
      }
      final old = {for (final e in before) e.id: e}, next = {for (final e in after) e.id: e};
      final changed = {...old.keys, ...next.keys}.where((id) => _entry(old[id]) != _entry(next[id])).toList();
      if (ref.mounted) _publish(after);
      return VocabularyUndo._(
        Map.unmodifiable({for (final id in changed) id: old[id]}),
        Map.unmodifiable({for (final id in changed) id: next[id]}),
        Map.unmodifiable({
          for (final id in changed)
            if (versions.containsKey(id)) id: versions[id]!,
        }),
      );
    });
  }

  /// Add with or without an AI result. Lookup context translation is copied into
  /// the source snapshot; contextMeaning remains ephemeral card content.
  Future<VocabularyUndo> add({
    required String selected,
    required String language,
    required VocabularyKind kind,
    required VocabularyContext context,
    WordLookupResult? lookup,
  }) {
    final now = ref.read(clockProvider)();
    final term = lookup?.lemma ?? selected.trim();
    final source = lookup == null
        ? context
        : VocabularyContext(
            id: context.id,
            studySetId: context.studySetId,
            documentId: context.documentId,
            studySetTitle: context.studySetTitle,
            documentTitle: context.documentTitle,
            sentence: context.sentence,
            hit: context.hit,
            addedAt: context.addedAt,
            sentenceTranslation: lookup.context.sentenceTranslation,
            textAnchor: context.textAnchor,
            page: context.page,
            rects: context.rects,
          );
    final entry = VocabularyEntry(
      id: newId(),
      term: term,
      language: vocabularyLanguage(language),
      kind: kind,
      createdAt: now,
      updatedAt: now,
      forms: vocabularyForms(
        term: term,
        selected: selected,
        language: vocabularyLanguage(language),
        kind: kind,
        supplied: lookup?.forms ?? [],
      ),
      ukPhonetic: lookup?.ukPhonetic,
      usPhonetic: lookup?.usPhonetic,
      gloss: lookup?.gloss ?? '',
      senses: [
        for (final s in lookup?.senses ?? <WordSense>[]) VocabularySense(partOfSpeech: s.pos, meaning: s.meaning),
      ],
      contexts: [source],
    );
    return edit((entries) => _editor.add(entries, entry));
  }

  /// Restore only affected entries. Reject reused receipts, changed entries and
  /// identity collisions rather than replacing newer user data.
  Future<void> undo(VocabularyUndo receipt) async {
    await future;
    return _serial(() async {
      if (receipt._used) throw StateError('Vocabulary undo already used');
      List<VocabularyEntry> restore(List<VocabularyEntry> current) {
        final byId = {for (final e in current) e.id: e};
        for (final id in receipt.after.keys) {
          if (_entry(byId[id]) != _entry(receipt.after[id])) {
            throw StateError('Vocabulary changed since edit');
          }
        }
        final restored = <VocabularyEntry>[
          for (final e in current)
            if (!receipt.before.containsKey(e.id)) e,
          ...receipt.before.values.whereType<VocabularyEntry>(),
        ];
        final keys = <(String, String)>{};
        if (restored.any((e) => !keys.add((e.language, e.key)))) {
          throw StateError('Vocabulary identity conflict');
        }
        return restored;
      }

      final repository = _repository;
      late List<VocabularyEntry> restored;
      if (repository is AtomicVocabularyRepository) {
        restored = (await (repository as AtomicVocabularyRepository).updateVocabulary(
          restore,
          expected: receipt.versions,
        )).after;
      } else {
        restored = restore(await repository.load());
        if (receipt.before.isNotEmpty) await repository.save(restored);
      }
      receipt._used = true;
      if (ref.mounted) _publish(restored);
    });
  }
}
