/// MarginMind domain layer.
///
/// Holds entities, repository ports and pure query logic. Nothing here may
/// import Flutter, a database driver or a PDF engine; those live in outer
/// layers and implement the ports defined here.
library;

export 'src/content/editor.dart';
export 'src/content/excerpt_lines.dart';
export 'src/content/map_export.dart';
export 'src/content/map_clipboard.dart';
export 'src/content/models.dart';
export 'src/content/note_format.dart';
export 'src/content/review.dart';
export 'src/content/review_face.dart';
export 'src/content/review_stats.dart';
export 'src/content/study_set_content.dart';
export 'src/content/study_set_content_repository.dart';
export 'src/ids.dart';
export 'src/study_set/folder.dart';
export 'src/study_set/library_query.dart';
export 'src/study_set/study_set.dart';
export 'src/study_set/study_set_repository.dart';

export 'src/content/research.dart';
export 'src/content/research_repository.dart';
export 'src/research/ports.dart';

export 'src/assistant/ports.dart';
export 'src/assistant/proposals.dart';

export 'src/assistant/writes.dart';

export 'src/content/reading.dart';
export 'src/content/reading_repository.dart';
export 'src/content/reading_editor.dart';

export 'src/content/margin_anchor.dart';

export 'src/content/translation.dart';

export 'src/content/document_outline.dart';

export 'src/content/document_format.dart';
export 'src/content/text_anchor.dart';
export 'src/content/document_repository.dart';

export 'src/vocabulary/vocabulary.dart';

export 'src/vocabulary/editor.dart';

export 'src/vocabulary/words.dart';

export 'src/vocabulary/matcher.dart';

export 'src/content/study_note.dart';
export 'src/content/note_material.dart';
export 'src/content/note_organizer.dart';
export 'src/content/note_editor.dart';
export 'src/content/note_update.dart';
export 'src/content/note_export.dart';

export 'src/assistant/expansion.dart';
export 'src/content/note_rich_export.dart';
