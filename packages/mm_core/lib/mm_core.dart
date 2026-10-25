/// MarginMind domain layer.
///
/// Holds entities, repository ports and pure query logic. Nothing here may
/// import Flutter, a database driver or a PDF engine; those live in outer
/// layers and implement the ports defined here.
library;

export 'src/content/editor.dart';
export 'src/content/models.dart';
export 'src/content/study_set_content.dart';
export 'src/content/study_set_content_repository.dart';
export 'src/ids.dart';
export 'src/study_set/folder.dart';
export 'src/study_set/library_query.dart';
export 'src/study_set/study_set.dart';
export 'src/study_set/study_set_repository.dart';
