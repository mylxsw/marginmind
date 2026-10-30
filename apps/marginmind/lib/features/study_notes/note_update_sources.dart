import 'dart:convert';

import 'package:mm_core/mm_core.dart';

/// Detect source changes while a preview is open, including edits and deletions.
String noteSourceFingerprint(StudySetContent content) => jsonEncode([
  content.documents
      .map(
        (v) => v.toJson()
          ..remove('lastPage')
          ..remove('lastReadAt')
          ..remove('readingPosition')
          ..remove('crop')
          ..remove('cropSuggestionDismissed'),
      )
      .toList(),
  content.annotations.map((v) => v.toJson()).toList(),
  content.marginNotes.map((v) => v.toJson()).toList(),
  content.cards.map((v) => v.toJson()).toList(),
  content.nodes.map((v) => v.toJson()).toList(),
  content.documentOutlines.map((v) => v.toJson()).toList(),
  content.researchNotes.map((v) => v.toJson()).toList(),
  content.noteSourceArchive.map((v) => v.toJson()).toList(),
]);
