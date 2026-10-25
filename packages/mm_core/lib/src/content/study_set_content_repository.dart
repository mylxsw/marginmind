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

  /// Absolute path of a stored document file.
  String resolveFile(String studySetId, String fileName);
}
