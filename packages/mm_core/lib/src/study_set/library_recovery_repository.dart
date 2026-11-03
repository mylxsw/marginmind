/// A historical content snapshot offered as a new, independent study set.
/// Selecting it does not resolve or resurrect the original deleted identity.
class LibraryRecoveryEntry {
  LibraryRecoveryEntry({
    required this.studySetId,
    required this.version,
    required this.observedRevision,
    required this.title,
    required this.deleted,
    required Iterable<String> documents,
    required this.cards,
    required this.hasUnresolvedChoices,
    this.copyId,
    Iterable<String> preview = const [],
  }) : documents = List.unmodifiable(documents),
       preview = List.unmodifiable(preview);
  final String studySetId, version, observedRevision, title;
  final bool deleted, hasUnresolvedChoices;
  final List<String> documents, preview;
  final int cards;
  final String? copyId;
}

class LibraryRecovery {
  LibraryRecovery({this.enabled = false, Iterable<LibraryRecoveryEntry> entries = const []})
    : entries = List.unmodifiable(entries);
  final bool enabled;
  final List<LibraryRecoveryEntry> entries;
}

abstract interface class LibraryRecoveryRepository {
  /// Cheap capability check; opening navigation must not replay all history.
  Future<bool> get libraryRecoveryEnabled;
  Stream<LibraryRecovery> watchLibraryRecovery();
  Future<LibraryRecovery> libraryRecovery();

  /// Durable and idempotent for the selected version on this device. The new
  /// set, empty review baseline and local receipt share one atomic commit.
  Future<String> recoverLibraryCopy(LibraryRecoveryEntry selection, {required String title});
}
