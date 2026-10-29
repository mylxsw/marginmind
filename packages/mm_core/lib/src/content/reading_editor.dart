import 'editor.dart';
import 'models.dart';
import 'reading.dart';
import 'study_set_content.dart';

/// Pure reading edits, used inside the repository's serialized update callback.
extension ReadingEditor on StudySetEditor {
  StudySetContent setDocumentCrop(StudySetContent c, String documentId, DocumentCrop? crop) {
    final doc = _document(c, documentId);
    if (crop != null && crop.pages.keys.any((p) => p > doc.pageCount)) throw ArgumentError('Invalid crop page');
    return c.copyWith(documents: [for (final d in c.documents) d.id == documentId ? d.copyWith(crop: crop) : d]);
  }

  StudySetContent upsertMarginNote(StudySetContent c, MarginNote note) {
    final doc = _document(c, note.documentId);
    if ((note.anchor?.textAnchors.isEmpty ?? true) &&
        (note.page > doc.pageCount || (note.anchor?.pages.any((p) => p.page > doc.pageCount) ?? false))) {
      throw ArgumentError('Invalid anchor page');
    }
    final previous = c.marginNotes.where((n) => n.id == note.id).firstOrNull;
    if (previous != null && previous.documentId != note.documentId) {
      throw ArgumentError('Cannot move a note between documents');
    }
    if (note.text.trim().isEmpty) return removeMarginNote(c, note.id);
    if (note.nodeId != null) {
      final card = c.card(note.nodeId!);
      if (card == null ||
          c.node(note.nodeId!, mapId: note.mapId ?? MindMap.defaultId) == null ||
          c.marginNotes.any((n) => n.id != note.id && n.nodeId == note.nodeId)) {
        throw ArgumentError('Invalid or already linked card');
      }
    }
    final saved = note.copyWith(text: note.text.trim());
    final linkedAnnotationId = note.nodeId == null ? null : c.card(note.nodeId!)?.annotationId;
    return c.copyWith(
      marginNotes: [
        for (final n in c.marginNotes)
          if (n.id != note.id) n,
        saved,
      ],
      cards: [for (final card in c.cards) card.id == note.nodeId ? card.copyWith(title: saved.text) : card],
      annotations: [
        for (final annotation in c.annotations)
          linkedAnnotationId != null && annotation.id == linkedAnnotationId
              ? annotation.copyWith(colorIndex: saved.colorIndex)
              : annotation,
      ],
    );
  }

  /// Keep the linked card and captured source as a standalone snapshot.
  StudySetContent removeMarginNote(StudySetContent c, String id) => c.copyWith(
    marginNotes: [
      for (final n in c.marginNotes)
        if (n.id != id) n,
    ],
  );

  StudySetContent attachMarginNote(StudySetContent c, String id, {String? parentId}) {
    final note = c.marginNotes.where((n) => n.id == id).firstOrNull;
    if (note == null) throw ArgumentError('Unknown margin note');
    if (note.nodeId != null) return c;
    if (c.map(mapId) == null || (parentId != null && c.node(parentId, mapId: mapId) == null)) {
      throw ArgumentError('Unknown map or parent');
    }
    final anchor = note.anchor;
    final cardId = newId();
    final annotationId = anchor == null ? null : newId();
    final card = Card(
      id: cardId,
      kind: anchor == null ? CardKind.note : CardKind.excerpt,
      title: note.text,
      body: anchor?.quote ?? '',
      annotationId: annotationId,
      createdAt: now(),
    );
    final next = c.copyWith(
      annotations: [
        ...c.annotations,
        if (anchor != null)
          Annotation(
            id: annotationId!,
            documentId: note.documentId,
            pages: anchor.textAnchors.isEmpty ? anchor.pages : null,
            textAnchors: anchor.textAnchors,
            quote: anchor.quote,
            colorIndex: note.colorIndex,
            createdAt: now(),
          ),
      ],
      cards: [...c.cards, card],
      nodes: [
        ...c.nodes,
        MapNode(
          cardId: cardId,
          mapId: mapId,
          parentId: parentId,
          order: (c.childrenOf(parentId, mapId: mapId).lastOrNull?.order ?? 0) + 1,
        ),
      ],
    );
    return upsertMarginNote(next, note.copyWith(nodeId: cardId, mapId: mapId, updatedAt: now()));
  }

  StudySetContent upsertComparePair(StudySetContent c, ComparePair pair) {
    final left = _document(c, pair.leftDocumentId);
    if (pair.right case PdfCompareTarget(:final documentId)) {
      final right = _document(c, documentId);
      AlignPoint? previous;
      for (final point in pair.alignPoints) {
        if (point.left.page > left.pageCount ||
            point.right.page > right.pageCount ||
            (previous != null && (!_before(previous.left, point.left) || !_before(previous.right, point.right)))) {
          throw ArgumentError('Alignment must be strictly increasing on both documents');
        }
        previous = point;
      }
    }
    return c.copyWith(
      comparePairs: [
        for (final p in c.comparePairs)
          if (p.id != pair.id) p,
        pair,
      ],
    );
  }

  StudySetContent removeComparePair(StudySetContent c, String id) => c.copyWith(
    comparePairs: [
      for (final p in c.comparePairs)
        if (p.id != id) p,
    ],
  );

  StudySetContent mergeTranslationParagraphs(StudySetContent c, TranslationCache cache) {
    _document(c, cache.documentId);
    final old = c.translationCaches
        .where((t) => t.documentId == cache.documentId && t.targetLang == cache.targetLang)
        .firstOrNull;
    // A cache records one model provenance. Do not relabel old paragraphs as
    // produced by a different model; explicit removal starts a new cache.
    if (old != null && old.model != cache.model) throw ArgumentError('Remove the old cache before changing its model');
    final merged = old == null ? cache : old.copyWith(paragraphs: {...old.paragraphs, ...cache.paragraphs});
    return c.copyWith(
      translationCaches: [
        for (final t in c.translationCaches)
          if (t.documentId != cache.documentId || t.targetLang != cache.targetLang) t,
        merged,
      ],
    );
  }

  StudySetContent removeTranslationCache(StudySetContent c, String documentId, String targetLang) => c.copyWith(
    translationCaches: [
      for (final t in c.translationCaches)
        if (t.documentId != documentId || t.targetLang != targetLang) t,
    ],
  );
}

Document _document(StudySetContent c, String id) => c.document(id) ?? (throw ArgumentError('Unknown document: $id'));
bool _before(PdfReadingPosition a, PdfReadingPosition b) => a.page < b.page || (a.page == b.page && a.y > b.y);
