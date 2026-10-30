import 'note_editor.dart';
import 'note_material.dart';
import 'note_organizer.dart';
import 'study_note.dart';

/// Immutable preview tied to the exact note the user reviewed.
class NoteUpdatePreview {
  const NoteUpdatePreview({required this.base, required this.materials, required this.placements});
  final StudyNote base;

  /// Only new materials, with IDs from the full collection preserved.
  final NoteMaterials materials;
  final NotePlacements placements;
}

/// Pure merge operations: no existing block is rewritten by an incremental update.
class NoteUpdater {
  const NoteUpdater();
  Future<NoteUpdatePreview> preview(NoteOrganizer organizer, NoteMaterials all, StudyNote note) async {
    final fresh = all.since(note.organizedAt);
    return NoteUpdatePreview(base: note, materials: fresh, placements: await organizer.place(fresh, note));
  }

  /// Rejects stale previews instead of losing edits made during generation.
  StudyNote apply(StudyNote current, NoteUpdatePreview preview, {required String Function() newId}) {
    if (!sameStudyNote(current, preview.base)) throw StateError('Note changed; refresh the preview');
    final sections = current.sections.toList();
    final usedQuotes = {
      for (final s in sections)
        for (final b in s.blocks)
          if (b is QuoteBlock) b.annotationId,
    };
    final usedOwn = {
      for (final s in sections)
        for (final b in s.blocks)
          if (b is OwnBlock) '${b.source}:${b.sourceId}',
    };
    final consumed = <String>{};
    final insertedAfter = <String, String>{};
    final newSections = <String, int>{};
    for (final p in preview.placements.items) {
      final m = preview.materials[p.ref];
      if (m == null || !consumed.add(p.ref)) continue;
      if (m.isHighlight ? !usedQuotes.add(m.sourceId) : !usedOwn.add('${m.source}:${m.sourceId}')) continue;
      var index = sections.indexWhere((s) => s.id == p.sectionId);
      if (p.sectionId != null && index < 0) throw StateError('Missing target section');
      if (index < 0) {
        final key = p.newSectionKey ?? p.title;
        index = newSections[key] ?? -1;
        if (index < 0) {
          sections.add(NoteSection(id: newId(), title: p.title));
          index = sections.length - 1;
          newSections[key] = index;
        }
      }
      final section = sections[index], blocks = sections[index].blocks.toList();
      final after = p.afterBlockId == null ? null : insertedAfter['${section.id}:${p.afterBlockId}'] ?? p.afterBlockId;
      var position = after == null ? blocks.length : blocks.indexWhere((b) => b.id == after) + 1;
      if (p.beforeBlockId != null) {
        if (p.afterBlockId != null) throw ArgumentError('Specify before or after, not both');
        position = blocks.indexWhere((b) => b.id == p.beforeBlockId);
        if (position < 0) throw StateError('Missing target block');
      }
      if (after != null && position == 0) throw StateError('Missing target block');
      if (!m.isHighlight && m.annotationId != null && p.beforeBlockId == null && p.afterBlockId == null) {
        final quoteAt = blocks.indexWhere((b) => b is QuoteBlock && b.annotationId == m.annotationId);
        if (quoteAt >= 0) {
          position = quoteAt + 1;
          while (position < blocks.length && blocks[position] is OwnBlock) {
            position++;
          }
        }
      }
      final block = m.isHighlight
          ? QuoteBlock(id: newId(), annotationId: m.sourceId, contextOpen: m.context.fragment)
          : OwnBlock(id: newId(), sourceId: m.sourceId, source: m.source!, origin: m.origin);
      blocks.insert(position, block);
      insertedAfter['${section.id}:${p.afterBlockId}'] = block.id;
      sections[index] = section.copyWith(blocks: blocks);
    }
    return current.copyWith(
      sections: sections,
      updatedAt: preview.materials.collectedAt,
      organizedAt: preview.materials.collectedAt,
      unusedAnnotationIds: {
        ...current.unusedAnnotationIds.where((id) => !usedQuotes.contains(id)),
        ...preview.materials.highlights.where((m) => !usedQuotes.contains(m.sourceId)).map((m) => m.sourceId),
      }.toList(),
    );
  }

  /// Reorganization preserves locked blocks in their original section. New
  /// references to the same locked source are removed, not duplicated.
  StudyNote reorganize(StudyNote current, NoteAssembly assembly, {required DateTime organizedAt}) {
    final locked = current.sections.expand((s) => s.blocks).where((b) => b.edited).toList();
    String key(StudyNoteBlock b) => switch (b) {
      QuoteBlock() => 'quote:${b.annotationId}',
      OwnBlock() => 'own:${b.source}:${b.sourceId}',
      _ => 'id:${b.id}',
    };
    final keys = locked.map(key).toSet();
    final next = [
      for (final s in assembly.sections) s.copyWith(blocks: s.blocks.where((b) => !keys.contains(key(b))).toList()),
    ];
    for (final old in current.sections) {
      final keep = old.blocks.where((b) => b.edited).toList();
      if (keep.isEmpty) continue;
      final at = next.indexWhere((s) => s.id == old.id);
      if (at >= 0) {
        next[at] = next[at].copyWith(blocks: [...keep, ...next[at].blocks]);
      } else {
        next.add(old.copyWith(blocks: keep));
      }
    }
    final used = {
      for (final s in next)
        for (final b in s.blocks)
          if (b is QuoteBlock) b.annotationId,
    };
    return current.copyWith(
      sections: next.where((s) => s.blocks.isNotEmpty).toList(),
      unusedAnnotationIds: assembly.unusedAnnotationIds.where((id) => !used.contains(id)).toList(),
      updatedAt: organizedAt,
      organizedAt: organizedAt,
    );
  }
}
