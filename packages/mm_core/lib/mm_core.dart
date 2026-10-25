/// MarginMind domain layer.
///
/// Holds entities, repository ports and pure query logic. Nothing here may
/// import Flutter, a database driver or a PDF engine; those live in outer
/// layers and implement the ports defined here.
library;

export 'src/study_set/folder.dart';
export 'src/study_set/library_query.dart';
export 'src/study_set/study_set.dart';
export 'src/study_set/study_set_repository.dart';
