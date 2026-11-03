/// Optional product-facing sync port. It exposes decisions and recovery state,
/// never the private journal or a transport's credentials.
abstract interface class ContentSyncRepository {
  Stream<ContentSyncStatus> watchContentSync(String studySetId);
  Future<ContentSyncStatus> contentSyncStatus(String studySetId);
  Future<void> chooseContentSync(
    String studySetId,
    String conflictId, {
    required String expectedRevision,
    required bool useCandidate,
  });
  Future<void> acknowledgeContentRecovery(String studySetId, String recoveryId);
  Future<void> retryContentSync(String studySetId);
}

enum ContentSyncProblem {
  editing,
  missingHistory,
  unrelatedHistory,
  ambiguousHistory,
  concurrentChoices,
  invalidHistory,
  deletion,
  unsupported,
}

enum ContentSyncEntity {
  studySet,
  card,
  document,
  studyNote,
  researchNote,
  annotation,
  marginNote,
  map,
  relation,
  summary,
  bookmark,
  other,
}

enum ContentSyncField { title, text, tags, order, structure, source, appearance, collectionBaseline, other }

class ContentSyncDifference {
  const ContentSyncDifference({
    required this.entity,
    required this.title,
    required this.field,
    required this.current,
    required this.candidate,
  });
  final ContentSyncEntity entity;
  final ContentSyncField field;

  /// Human-authored entity name or excerpt, not its internal ID.
  final String title;

  /// Plain text for review; null means the value is absent. Structure changes
  /// use referenced entity names instead of raw IDs or serialized objects.
  final String? current, candidate;
}

class ContentSyncConflict {
  ContentSyncConflict({
    required this.id,
    required Iterable<ContentSyncDifference> changes,
    required this.canUseCandidate,
    this.concurrentChoices = 0,
  }) : changes = List.unmodifiable(changes);
  final String id;
  final List<ContentSyncDifference> changes;
  final bool canUseCandidate;

  /// Number of observed human choices reviewed together by this action.
  final int concurrentChoices;
}

class ContentSyncStatus {
  ContentSyncStatus({
    this.enabled = false,
    this.revision,
    this.recoveryId,
    this.queued = 0,
    this.translationConflicts = 0,
    this.editing = false,
    this.repairNeeded = false,
    this.retryFailed = false,
    Iterable<ContentSyncConflict> conflicts = const [],
    Iterable<ContentSyncProblem> problems = const [],
  }) : conflicts = List.unmodifiable(conflicts),
       problems = List.unmodifiable(problems);
  final bool enabled, editing, repairNeeded, retryFailed;
  final String? revision, recoveryId;

  /// Local versions waiting for a transport; does not imply a configured account
  /// or confirmation that any data has reached a cloud service.
  final int queued;

  /// Paragraph choices are reviewed beside their source in the translation reader.
  final int translationConflicts;
  final List<ContentSyncConflict> conflicts;
  final List<ContentSyncProblem> problems;
  bool get needsAttention =>
      recoveryId != null ||
      repairNeeded ||
      retryFailed ||
      conflicts.isNotEmpty ||
      translationConflicts > 0 ||
      problems.isNotEmpty;
}

enum ContentSyncActionFailure { stale, editing, invalidCandidate }

class ContentSyncActionException implements Exception {
  const ContentSyncActionException(this.reason);
  final ContentSyncActionFailure reason;
}
