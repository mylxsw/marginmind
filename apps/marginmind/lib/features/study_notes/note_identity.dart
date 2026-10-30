import 'package:mm_core/mm_core.dart';

/// Reorganization keeps the supplied outline. Reuse its identities so locks
/// replace corresponding generated blocks and edited links keep their targets.
NoteAssembly reuseNoteIdentity(StudyNote previous, NoteAssembly assembly) {
  final available = previous.sections.toList();
  final matched = <String, NoteSection>{};
  for (final section in assembly.sections) {
    final index = available.indexWhere((s) => s.title == section.title);
    if (index >= 0) matched[section.id] = available.removeAt(index);
  }
  final sectionIds = {for (final entry in matched.entries) entry.key: entry.value.id};
  String blockKey(StudyNoteBlock block, {bool generated = false}) => switch (block) {
    QuoteBlock() => 'quote:${block.annotationId}',
    OwnBlock() => 'own:${block.source}:${block.sourceId}',
    TextBlock() => 'text:${block.kind}',
    PointsBlock() => 'points',
    XrefBlock() => 'xref:${generated ? sectionIds[block.toSectionId] ?? block.toSectionId : block.toSectionId}',
  };
  return NoteAssembly(
    sections: [
      for (final section in assembly.sections)
        (() {
          final candidates = <String, List<StudyNoteBlock>>{};
          for (final block in matched[section.id]?.blocks ?? <StudyNoteBlock>[]) {
            candidates.putIfAbsent(blockKey(block), () => []).add(block);
          }
          return NoteSection(
            id: sectionIds[section.id] ?? section.id,
            title: section.title,
            why: section.why,
            question: section.question,
            questionOrigin: section.questionOrigin,
            blocks: [
              for (final block in section.blocks)
                (() {
                  final queue = candidates[blockKey(block, generated: true)];
                  return StudyNoteBlock.fromJson({
                    ...block.toJson(),
                    if (queue != null && queue.isNotEmpty) 'id': queue.removeAt(0).id,
                    if (block is XrefBlock) 'toSectionId': sectionIds[block.toSectionId] ?? block.toSectionId,
                  });
                })(),
            ],
          );
        })(),
    ],
    unusedAnnotationIds: assembly.unusedAnnotationIds,
    rejectedRefs: assembly.rejectedRefs,
    usedHighlights: assembly.usedHighlights,
  );
}
