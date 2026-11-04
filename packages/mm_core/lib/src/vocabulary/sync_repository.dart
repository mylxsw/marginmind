import '../content/content_sync_repository.dart';
import 'vocabulary.dart';
import '../content/study_set_content_repository.dart';

class VocabularyMutation {
  VocabularyMutation(
    Iterable<VocabularyEntry> before,
    Iterable<VocabularyEntry> after, {
    Map<String, String> versions = const {},
  }) : before = List.unmodifiable(before),
       after = List.unmodifiable(after),
       versions = Map.unmodifiable(versions);
  final Map<String, String> versions;
  final List<VocabularyEntry> before, after;
}

/// Apply the edit against the latest snapshot inside the repository queue.
abstract interface class AtomicVocabularyRepository {
  Future<VocabularyMutation> updateVocabulary(
    List<VocabularyEntry> Function(List<VocabularyEntry>) edit, {
    Map<String, String> expected = const {},
  });
}

/// Resolve old device-local IDs without selecting between ambiguous aliases.
abstract interface class VocabularyIdentityRepository {
  Future<String?> resolveVocabularyEntryId(String id);
}

abstract interface class VocabularyEditRepository {
  ContentEditLease protectVocabulary(String entryId);
}

enum VocabularySyncField { kind, forms, ukPhonetic, usPhonetic, senses, gloss, note, status, alive }

class VocabularySyncChoice {
  const VocabularySyncChoice(this.id, this.text, {this.deleted});
  final String id, text;
  final bool? deleted;
}

class VocabularySyncConflict {
  VocabularySyncConflict({
    required this.entryId,
    required this.term,
    required this.revision,
    required this.field,
    required Iterable<VocabularySyncChoice> choices,
  }) : choices = List.unmodifiable(choices);
  final String entryId, term, revision;
  final VocabularySyncField field;
  final List<VocabularySyncChoice> choices;
}

class VocabularySyncState {
  VocabularySyncState({
    this.enabled = false,
    this.repairNeeded = false,
    this.retryFailed = false,
    Iterable<String> editingEntries = const [],
    Iterable<VocabularySyncConflict> conflicts = const [],
    Iterable<ContentSyncProblem> problems = const [],
  }) : conflicts = List.unmodifiable(conflicts),
       problems = Set.unmodifiable(problems),
       editingEntries = Set.unmodifiable(editingEntries);
  final Set<String> editingEntries;
  final bool retryFailed;
  final bool enabled, repairNeeded;
  final List<VocabularySyncConflict> conflicts;
  final Set<ContentSyncProblem> problems;
}

abstract interface class VocabularySyncRepository {
  Future<VocabularySyncState> vocabularySyncState();
  Stream<VocabularySyncState> watchVocabularySync();
  Future<void> chooseVocabulary(
    String entryId,
    VocabularySyncField field,
    String choice, {
    required String expectedRevision,
  });
  Future<void> retryVocabularySync();
}
