import 'vocabulary.dart';

/// Pure immutable edits. The caller supplies time, IDs and neutral domain input.
class VocabularyEditor {
  const VocabularyEditor();

  /// Merge source contexts on a duplicate (language, key), preserving user edits.
  List<VocabularyEntry> add(List<VocabularyEntry> entries, VocabularyEntry input) {
    final old = entries.where((e) => e.language == input.language && e.key == input.key).firstOrNull;
    if (old == null) {
      if (entries.any((e) => e.id == input.id)) {
        throw ArgumentError('Duplicate vocabulary ID');
      }
      return List.unmodifiable([...entries, input]);
    }
    return _replace(
      entries,
      old.id,
      (e) => e.copyWith(contexts: _contexts([...e.contexts, ...input.contexts]), updatedAt: input.updatedAt),
    );
  }

  List<VocabularyContext> _contexts(List<VocabularyContext> items) {
    final sorted = [...items]
      ..sort((a, b) {
        final time = b.addedAt.compareTo(a.addedAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    final seen = <(String, String, String)>{};
    return sorted.where((c) => seen.add(c.identity)).take(20).toList();
  }

  List<VocabularyEntry> _replace(
    List<VocabularyEntry> entries,
    String id,
    VocabularyEntry Function(VocabularyEntry) change,
  ) => List.unmodifiable([
    for (final e in entries)
      if (e.id == id) change(e) else e,
  ]);

  /// Add one source, keeping at most the newest twenty distinct sentences.
  List<VocabularyEntry> addContext(List<VocabularyEntry> entries, String id, VocabularyContext context, DateTime now) =>
      _replace(entries, id, (e) => e.copyWith(contexts: _contexts([...e.contexts, context]), updatedAt: now));

  /// Change learning state without changing dictionary data.
  List<VocabularyEntry> setStatus(List<VocabularyEntry> entries, String id, VocabularyStatus status, DateTime now) =>
      _replace(entries, id, (e) => e.copyWith(status: status, updatedAt: now));

  /// Replace user-managed forms; the canonical term is always retained.
  List<VocabularyEntry> updateForms(List<VocabularyEntry> entries, String id, List<String> forms, DateTime now) =>
      _replace(
        entries,
        id,
        (e) => e.copyWith(
          forms: {e.key, ...forms.map(vocabularyKey).where((f) => f.isNotEmpty)}.take(16).toList(),
          updatedAt: now,
        ),
      );

  /// Replace the inline gloss (at most eight Unicode code points).
  List<VocabularyEntry> updateGloss(List<VocabularyEntry> entries, String id, String gloss, DateTime now) =>
      _replace(entries, id, (e) => e.copyWith(gloss: gloss, updatedAt: now));

  /// Replace the user's note.
  List<VocabularyEntry> updateNote(List<VocabularyEntry> entries, String id, String note, DateTime now) =>
      _replace(entries, id, (e) => e.copyWith(note: note, updatedAt: now));

  /// Replace dictionary senses (at most six).
  List<VocabularyEntry> updateSenses(
    List<VocabularyEntry> entries,
    String id,
    List<VocabularySense> senses,
    DateTime now,
  ) => _replace(entries, id, (e) => e.copyWith(senses: senses, updatedAt: now));

  /// Remove an entry, leaving its sources untouched in the library.
  List<VocabularyEntry> remove(List<VocabularyEntry> entries, String id) =>
      List.unmodifiable(entries.where((e) => e.id != id));

  /// Remove one stored sentence.
  List<VocabularyEntry> removeContext(List<VocabularyEntry> entries, String id, String contextId, DateTime now) =>
      _replace(
        entries,
        id,
        (e) => e.copyWith(contexts: e.contexts.where((c) => c.id != contextId).toList(), updatedAt: now),
      );
}
