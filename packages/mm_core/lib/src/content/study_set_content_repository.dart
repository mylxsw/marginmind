import 'study_set_content.dart';

/// Port for one study set's content. Implementations persist every update.
abstract interface class StudySetContentRepository {
  /// Emits the current content immediately and after every update.
  Stream<StudySetContent> watch(String studySetId);

  Future<StudySetContent> load(String studySetId);

  /// Applies [change] atomically and persists the result.
  Future<StudySetContent> update(String studySetId, StudySetContent Function(StudySetContent) change);

  /// Copies a PDF into the study set package and returns the stored file
  /// name (relative to the package).
  Future<String> importFile(String studySetId, String sourcePath);

  /// Imports PNG/JPEG bytes as a content-addressed image in the package.
  Future<String> importImage(String studySetId, String sourcePath);

  /// Imports encoded PNG/JPEG [bytes], such as an area captured from a page.
  Future<String> importImageBytes(String studySetId, List<int> bytes);

  /// Resource location of a stored file: native absolute path or browser blob URL.
  String resolveFile(String studySetId, String fileName);
}

/// Optional local-first editing coordination. Each write remains durable;
/// an outer editing session publishes one shared transaction when it ends.
abstract interface class ContentEditRepository {
  Future<void> beginContentTransaction(String studySetId);
  Future<void> endContentTransaction(String studySetId);

  /// Paths use contentDocument's stable entity identities, not array offsets.
  /// Deleting an ancestor of a protected path is protected as well.
  ContentEditLease protectContent(String studySetId, List<List<String>> paths);
}

abstract interface class ContentEditLease {
  /// Wait for a write that already crossed its commit point before opening
  /// an input from the latest snapshot. Later touching writes are deferred.
  Future<void> get ready;
  Future<void> release();
}
