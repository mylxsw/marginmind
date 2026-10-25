import 'folder.dart';
import 'study_set.dart';

/// Port for reading and changing the library. Implemented by mm_data
/// (SQLite) and by [InMemoryStudySetRepository] for tests and previews.
abstract interface class StudySetRepository {
  /// Emits the full list immediately and again after every change.
  Stream<List<StudySet>> watchAll();

  Stream<List<Folder>> watchFolders();

  Future<StudySet> create(NewStudySet input);

  Future<void> setStarred(String id, {required bool starred});

  /// Records that the study set was just opened (drives "Recent").
  Future<void> markOpened(String id);
}
