import '../content/content_sync_repository.dart';
import 'folder.dart';

class FolderChoice {
  const FolderChoice({required this.transaction, required this.name});
  final String transaction, name;
}

class FolderEntry {
  FolderEntry({
    required this.id,
    required this.revision,
    this.folder,
    Iterable<FolderChoice> choices = const [],
    Iterable<ContentSyncProblem> problems = const [],
  }) : choices = List.unmodifiable(choices),
       problems = Set.unmodifiable(problems);
  final String id, revision;
  final Folder? folder;
  final List<FolderChoice> choices;
  final Set<ContentSyncProblem> problems;
}

class LibraryOrganization {
  LibraryOrganization({
    Iterable<FolderEntry> entries = const [],
    this.syncEnabled = false,
    this.queued = 0,
    this.repairNeeded = false,
    Map<String, String?> placements = const {},
  }) : entries = List.unmodifiable(entries),
       placements = Map.unmodifiable(placements);
  final List<FolderEntry> entries;

  /// Original membership, including a folder not received yet or deleted.
  /// Retain it while a move dialog is open; displaying Unfiled must not weaken
  /// the write guard when the original destination has not arrived yet.
  final Map<String, String?> placements;
  final bool syncEnabled, repairNeeded;
  final int queued;
}

/// Optional library organization port. Folder deletion never deletes study
/// sets; their original association remains recoverable in the content history.
abstract interface class LibraryOrganizationRepository {
  Stream<LibraryOrganization> watchOrganization();
  Future<Folder> createFolder(String name);
  Future<void> renameFolder(String id, String name, {required String expectedRevision});
  Future<void> deleteFolder(String id, {required String expectedRevision});
  Future<void> moveStudySet(String id, String? folderId, {required String? expectedFolderId});
  Future<void> chooseFolderName(
    String id,
    String transaction, {
    required String expectedRevision,
    required bool useCandidate,
  });
  Future<void> retryOrganization();
}
