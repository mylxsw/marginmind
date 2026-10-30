import 'dart:convert';

import 'editor.dart';
import 'models.dart';
import 'research.dart';
import 'study_note.dart';
import 'study_set_content.dart';

/// Status for a quote's source; controls navigation without losing its text.
enum NoteSourceStatus { available, annotationDeleted, documentRemoved, missing }

/// Live or archived quote resolved for rendering and exporting.
class ResolvedNoteSource {
  const ResolvedNoteSource({required this.status, this.annotation, this.documentTitle});
  final NoteSourceStatus status;
  final Annotation? annotation;
  final String? documentTitle;
}

/// Pure lookup; a live source always wins over any archived source.
ResolvedNoteSource resolveNoteSource(StudySetContent content, String annotationId) {
  final live = content.annotation(annotationId);
  final archived = content.noteSourceArchive.where((s) => s.annotation.id == annotationId).firstOrNull;
  final annotation = live ?? archived?.annotation;
  if (annotation == null) return const ResolvedNoteSource(status: NoteSourceStatus.missing);
  final document = content.document(annotation.documentId);
  return ResolvedNoteSource(
    annotation: annotation,
    documentTitle: document?.title ?? archived?.documentTitle,
    status: document == null
        ? NoteSourceStatus.documentRemoved
        : live == null
        ? NoteSourceStatus.annotationDeleted
        : NoteSourceStatus.available,
  );
}

/// Annotation IDs whose quote text is still needed by at least one note.
Set<String> noteReferencedAnnotations(StudySetContent c) => {
  for (final n in c.studyNotes)
    for (final s in n.sections)
      for (final b in s.blocks)
        if (b is QuoteBlock) b.annotationId,
};

/// Removes archives immediately when their last quote reference is removed.
StudySetContent pruneNoteSourceArchive(StudySetContent c) {
  final referenced = noteReferencedAnnotations(c);
  return c.copyWith(
    noteSourceArchive: [
      for (final a in c.noteSourceArchive)
        if (referenced.contains(a.annotation.id) && c.annotation(a.annotation.id) == null) a,
    ],
  );
}

/// Called inside the same edit as source deletion, before live data is removed.
StudySetContent archiveNoteSource(StudySetContent c, String annotationId) {
  final a = c.annotation(annotationId);
  if (a == null || !noteReferencedAnnotations(c).contains(annotationId)) return c;
  return c.copyWith(
    noteSourceArchive: [
      for (final old in c.noteSourceArchive)
        if (old.annotation.id != annotationId) old,
      NoteSourceArchive(annotation: a, documentTitle: c.document(a.documentId)?.title ?? a.documentId),
    ],
  );
}

/// Written-note edits follow the existing immutable commit/undo model.
extension StudyNoteEditing on StudySetEditor {
  /// Save a complete note atomically. Block and section IDs must be unique.
  StudySetContent saveStudyNote(StudySetContent c, StudyNote note) {
    final sectionIds = <String>{}, blockIds = <String>{};
    for (final s in note.sections) {
      if (!sectionIds.add(s.id)) throw ArgumentError('Duplicate section ID');
      for (final b in s.blocks) {
        if (!blockIds.add(b.id)) throw ArgumentError('Duplicate block ID');
      }
    }
    return pruneNoteSourceArchive(
      c.copyWith(
        studyNotes: [
          for (final n in c.studyNotes)
            if (n.id != note.id) n,
          note,
        ],
      ),
    );
  }

  /// Removing a note also releases source archives no longer referenced.
  StudySetContent deleteStudyNote(StudySetContent c, String id) => pruneNoteSourceArchive(
    c.copyWith(
      studyNotes: [
        for (final n in c.studyNotes)
          if (n.id != id) n,
      ],
    ),
  );

  /// Changes a generated block or its live own-note source in one undo step.
  /// Quotes are immutable. Editing generated content marks it mixed and locked.
  StudySetContent editStudyNoteBlock(
    StudySetContent c,
    String noteId,
    String blockId, {
    String? text,
    List<String>? items,
  }) {
    final note = c.studyNote(noteId);
    if (note == null) throw ArgumentError('Unknown study note');
    final block = note.sections.expand((s) => s.blocks).where((b) => b.id == blockId).firstOrNull;
    if (block == null || block is QuoteBlock) throw ArgumentError('Block cannot be edited');
    final origin = block.origin == NoteOrigin.ai || block.origin == NoteOrigin.mixed
        ? NoteOrigin.mixed
        : NoteOrigin.user;
    var next = c;
    StudyNoteBlock replacement;
    if (block is OwnBlock) {
      if (text == null) throw ArgumentError('Expected text');
      switch (block.source) {
        case OwnSource.marginNote:
          if (!c.marginNotes.any((n) => n.id == block.sourceId)) throw StateError('Missing source');
          next = c.copyWith(
            marginNotes: [
              for (final n in c.marginNotes) n.id == block.sourceId ? n.copyWith(text: text, updatedAt: now()) : n,
            ],
          );
        case OwnSource.card:
          if (c.card(block.sourceId) == null) throw StateError('Missing source');
          next = c.copyWith(
            cards: [
              for (final card in c.cards)
                card.id == block.sourceId ? card.copyWith(title: text, body: '', textFormat: TextFormat.plain) : card,
            ],
          );
        case OwnSource.researchNote:
          final source = c.researchNote(block.sourceId);
          if (source == null) throw StateError('Missing source');
          next = c.copyWith(
            researchNotes: [
              for (final n in c.researchNotes)
                n.id == source.id
                    ? ResearchNote.fromJson({
                        ...n.toJson(),
                        'body': text,
                        'edited': true,
                        'origin': origin.name,
                        'updatedAt': now().toIso8601String(),
                      })
                    : n,
            ],
          );
        case OwnSource.image:
          throw ArgumentError('Image content cannot be edited as text');
      }
      replacement = OwnBlock(
        id: block.id,
        sourceId: block.sourceId,
        source: block.source,
        origin: origin,
        edited: true,
      );
    } else {
      replacement = switch (block) {
        TextBlock() => TextBlock(
          id: block.id,
          text: text ?? block.text,
          kind: block.kind,
          annotationId: block.annotationId,
          origin: origin,
          edited: true,
        ),
        PointsBlock() => PointsBlock(id: block.id, items: items ?? block.items, origin: origin, edited: true),
        XrefBlock() => XrefBlock(
          id: block.id,
          toSectionId: block.toSectionId,
          text: text ?? block.text,
          origin: origin,
          edited: true,
        ),
        _ => throw ArgumentError('Block cannot be edited'),
      };
    }
    return saveStudyNote(
      next,
      note.copyWith(
        updatedAt: now(),
        sections: [
          for (final s in note.sections)
            s.copyWith(blocks: [for (final b in s.blocks) b.id == blockId ? replacement : b]),
        ],
      ),
    );
  }
}

/// Optimistic guard used by preview/apply and UI editors.
bool sameStudyNote(StudyNote a, StudyNote b) => jsonEncode(a.toJson()) == jsonEncode(b.toJson());
