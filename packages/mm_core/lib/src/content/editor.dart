import 'dart:convert';

import 'models.dart';
import 'research.dart';
import 'map_clipboard.dart';
import 'review.dart';
import 'study_set_content.dart';

/// Every change to a study set's content, as pure functions. The UI calls
/// these through the repository; tests call them directly.
class StudySetEditor {
  StudySetEditor({required this.newId, required this.now, this.mapId = MindMap.defaultId, this.fsrsParameters});

  final FsrsParameters? fsrsParameters;

  final String mapId;

  final String Function() newId;
  final DateTime Function() now;

  /// Save the note and its attachments as one undoable value. Evidence is
  /// immutable: an existing id must retain its original captured bytes.
  StudySetContent saveResearchNote(
    StudySetContent c,
    ResearchNote note, {
    List<NoteTarget> targets = const [],
    List<Evidence> evidence = const [],
    List<ResearchSource> sources = const [],
    bool createCard = false,
    String? parentId,
  }) {
    if (createCard && (c.map(mapId) == null || (parentId != null && c.node(parentId, mapId: mapId) == null))) {
      throw ArgumentError('Invalid research card destination');
    }
    final byEvidence = {for (final e in c.evidence) e.id: e};
    for (final e in evidence) {
      if (byEvidence[e.id] case final existing?) {
        if (jsonEncode(existing.toJson()) != jsonEncode(e.toJson())) throw ArgumentError('Evidence is immutable');
      }
      byEvidence[e.id] = e;
    }
    final bySource = {for (final s in c.researchSources) s.id: s};
    for (final source in sources) {
      final versions = {for (final v in bySource[source.id]?.versions ?? <SourceVersion>[]) v.version: v};
      for (final version in source.versions) {
        final previous = versions[version.version];
        if (previous != null && (previous.hash != version.hash || previous.snapshotFile != version.snapshotFile)) {
          throw ArgumentError('Source versions are immutable');
        }
        versions[version.version] = version;
      }
      bySource[source.id] = ResearchSource.fromJson({
        ...source.toJson(),
        'versions': [for (final v in versions.values) v.toJson()],
      });
    }
    for (final e in byEvidence.values) {
      final source = bySource[e.sourceId];
      if (source == null || !source.versions.any((v) => v.version == e.sourceVersion)) {
        throw ArgumentError('Unresolved evidence source');
      }
    }
    if (note.citations.any((ref) => !byEvidence.containsKey(ref.evidenceId))) {
      throw ArgumentError('Unresolved evidence reference');
    }
    var next = c.copyWith(
      researchNotes: [
        for (final n in c.researchNotes)
          if (n.id != note.id) n,
        note,
      ],
      evidence: byEvidence.values.toList(),
      researchSources: bySource.values.toList(),
    );
    for (final target in targets) {
      next = attachNote(next, note.id, target);
    }
    if (createCard) {
      final card = Card(id: newId(), kind: CardKind.research, researchNoteId: note.id, createdAt: now());
      next = _place(next, card, parentId);
      next = attachNote(next, note.id, CardTarget(cardId: card.id));
    }
    return next;
  }

  StudySetContent attachNote(StudySetContent c, String noteId, NoteTarget target) {
    if (c.researchNote(noteId) == null) throw ArgumentError('Unknown research note');
    switch (target) {
      case PdfTarget(:final documentId, :final pages):
        final doc = c.document(documentId);
        if (doc == null || pages.isEmpty || pages.any((p) => p.page < 1 || p.page > doc.pageCount)) {
          throw ArgumentError('Invalid PDF attachment');
        }
      case CardTarget(:final cardId):
        if (c.card(cardId) == null) throw ArgumentError('Unknown attachment card');
    }
    if (c.noteAttachments.any(
      (a) => a.noteId == noteId && jsonEncode(a.target.toJson()) == jsonEncode(target.toJson()),
    )) {
      return c;
    }
    return c.copyWith(
      noteAttachments: [
        ...c.noteAttachments,
        NoteAttachment(id: newId(), noteId: noteId, target: target),
      ],
    );
  }

  StudySetContent detachNote(StudySetContent c, String attachmentId) => c.copyWith(
    noteAttachments: [
      for (final a in c.noteAttachments)
        if (a.id != attachmentId) a,
    ],
  );

  /// Remove research cards in every map, lifting their unrelated children.
  /// Evidence and snapshots remain available to undo and to other notes.
  StudySetContent deleteNote(StudySetContent c, String noteId) {
    if (c.researchNote(noteId) == null) return c;
    final kill = {
      for (final card in c.cards)
        if (card.researchNoteId == noteId) card.id,
    };
    final nodes = <MapNode>[];
    final orders = <(String, String?), double>{};
    void walk(String mapId, String? parentId, String? destination, Set<String> seen) {
      for (final node in c.childrenOf(parentId, mapId: mapId)) {
        if (!seen.add(node.cardId)) continue;
        if (kill.contains(node.cardId)) {
          walk(mapId, node.cardId, destination, seen);
        } else {
          final key = (mapId, destination);
          final order = orders[key] = (orders[key] ?? 0) + 1;
          nodes.add(node.copyWith(parentId: destination, toRoot: destination == null, order: order));
          walk(mapId, node.cardId, node.cardId, seen);
        }
      }
    }

    for (final map in c.maps) {
      walk(map.id, null, null, <String>{});
    }

    return c.copyWith(
      researchNotes: [
        for (final n in c.researchNotes)
          if (n.id != noteId) n,
      ],
      noteAttachments: [
        for (final a in c.noteAttachments)
          if (a.noteId != noteId && !(a.target is CardTarget && kill.contains((a.target as CardTarget).cardId))) a,
      ],
      cards: [
        for (final card in c.cards)
          if (!kill.contains(card.id)) card,
      ],
      nodes: nodes,
      relations: [
        for (final r in c.relations)
          if (!kill.contains(r.fromId) && !kill.contains(r.toId)) r,
      ],
      summaries: [
        for (final r in c.summaries)
          if (!kill.contains(r.parentId) && !kill.contains(r.fromId) && !kill.contains(r.toId)) r,
      ],
    );
  }

  StudySetContent setNoteFormat(StudySetContent c, String noteId, TextFormat format) => c.copyWith(
    researchNotes: [
      for (final n in c.researchNotes) n.id == noteId ? n.copyWith(textFormat: format, updatedAt: now()) : n,
    ],
  );

  StudySetContent setCardTextFormat(StudySetContent c, String cardId, TextFormat format) =>
      c.copyWith(cards: [for (final card in c.cards) card.id == cardId ? card.copyWith(textFormat: format) : card]);

  StudySetContent setCardWidth(StudySetContent c, String cardId, double? width) {
    if (width != null && (!width.isFinite || width <= 0)) throw ArgumentError.value(width, 'width');
    return c.copyWith(
      nodes: [
        for (final n in c.nodes)
          n.mapId == mapId && n.cardId == cardId ? n.copyWith(width: width, resetWidth: width == null) : n,
      ],
    );
  }

  StudySetContent setMapDensity(StudySetContent c, MapDensity density) =>
      c.copyWith(maps: [for (final m in c.maps) m.id == mapId ? m.copyWith(density: density) : m]);

  StudySetContent addInkStroke(StudySetContent c, InkStroke stroke) {
    final doc = c.document(stroke.documentId);
    final ellipse = stroke.ellipse;
    final invalidEllipse =
        ellipse != null &&
        (![ellipse.left, ellipse.top, ellipse.right, ellipse.bottom].every((v) => v.isFinite) ||
            ellipse.left >= ellipse.right ||
            ellipse.bottom >= ellipse.top);
    if (invalidEllipse ||
        doc == null ||
        stroke.page < 1 ||
        stroke.page > doc.pageCount ||
        !stroke.width.isFinite ||
        stroke.width <= 0 ||
        stroke.colorIndex < 0 ||
        stroke.points.length > InkStroke.maxPoints ||
        stroke.points.any((p) => !p.x.isFinite || !p.y.isFinite) ||
        (stroke.tool == InkTool.ellipse
            ? stroke.ellipse == null || stroke.points.isNotEmpty
            : stroke.points.isEmpty || stroke.ellipse != null)) {
      throw ArgumentError('Invalid ink stroke');
    }
    if (c.inkStrokes.any((s) => s.id == stroke.id)) return c;
    return c.copyWith(inkStrokes: [...c.inkStrokes, stroke]);
  }

  StudySetContent removeInkStroke(StudySetContent c, String strokeId) => c.copyWith(
    inkStrokes: [
      for (final s in c.inkStrokes)
        if (s.id != strokeId) s,
    ],
  );

  /// Tags belong to shared card content, independently of map placements.
  StudySetContent setTags(StudySetContent c, String cardId, Iterable<String> tags) {
    final card = c.card(cardId);
    if (card == null) return c;
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in tags) {
      final tag = value.trim();
      if (tag.isNotEmpty && seen.add(tag.toLowerCase())) normalized.add(tag);
    }
    if (normalized.length == card.tags.length &&
        Iterable.generate(normalized.length).every((i) => normalized[i] == card.tags[i])) {
      return c;
    }
    return c.copyWith(
      cards: [for (final value in c.cards) value.id == cardId ? value.copyWith(tags: normalized) : value],
    );
  }

  (StudySetContent, MindMap) addMap(StudySetContent c, {required String title}) {
    final map = MindMap(id: newId(), title: title.trim());
    return (c.copyWith(maps: [...c.maps, map]), map);
  }

  StudySetContent renameMap(StudySetContent c, String id, String title) =>
      c.copyWith(maps: [for (final m in c.maps) m.id == id ? m.copyWith(title: title.trim()) : m]);

  /// Keep at least one map; shared cards and schedules survive map deletion.
  StudySetContent removeMap(StudySetContent c, String id) {
    if (c.maps.length <= 1 || c.map(id) == null) return c;
    final detached = {
      for (final n in c.nodes)
        if (n.mapId == id && !c.nodes.any((other) => other.mapId != id && other.cardId == n.cardId)) n.cardId,
    };
    return c.copyWith(
      noteAttachments: [
        for (final a in c.noteAttachments)
          if (!(a.target is CardTarget && detached.contains((a.target as CardTarget).cardId))) a,
      ],
      maps: [
        for (final m in c.maps)
          if (m.id != id) m,
      ],
      nodes: [
        for (final n in c.nodes)
          if (n.mapId != id) n,
      ],
      relations: [
        for (final r in c.relations)
          if (r.mapId != id) r,
      ],
      summaries: [
        for (final s in c.summaries)
          if (s.mapId != id) s,
      ],
    );
  }

  /// A line from [fromId] to [toId], both placed in this map. A card cannot
  /// relate to itself, and the same direction is drawn only once.
  (StudySetContent, MapRelation?) addRelation(StudySetContent c, String fromId, String toId, {String label = ''}) {
    if (fromId == toId || c.node(fromId, mapId: mapId) == null || c.node(toId, mapId: mapId) == null) return (c, null);
    if (c.relations.any((r) => r.mapId == mapId && r.fromId == fromId && r.toId == toId)) return (c, null);
    final relation = MapRelation(id: newId(), mapId: mapId, fromId: fromId, toId: toId, label: label.trim());
    return (c.copyWith(relations: [...c.relations, relation]), relation);
  }

  StudySetContent relabelRelation(StudySetContent c, String id, String label) =>
      c.copyWith(relations: [for (final r in c.relations) r.id == id ? r.copyWith(label: label.trim()) : r]);

  StudySetContent removeRelation(StudySetContent c, String id) => c.copyWith(
    relations: [
      for (final r in c.relations)
        if (r.id != id) r,
    ],
  );

  /// Sums up the range of siblings spanned by [cardIds] (first to last in
  /// display order). All of them must share one parent in this map; an
  /// identical range is not summed up twice.
  (StudySetContent, MapSummary?) addSummary(StudySetContent c, Iterable<String> cardIds, {String label = ''}) {
    final ids = cardIds.toSet();
    final placed = [for (final id in ids) c.node(id, mapId: mapId)];
    if (placed.isEmpty || placed.any((n) => n == null)) return (c, null);
    final parentId = placed.first!.parentId;
    if (placed.any((n) => n!.parentId != parentId)) return (c, null);
    final covered = [
      for (final n in c.childrenOf(parentId, mapId: mapId))
        if (ids.contains(n.cardId)) n.cardId,
    ];
    final summary = MapSummary(
      id: newId(),
      mapId: mapId,
      parentId: parentId,
      fromId: covered.first,
      toId: covered.last,
      label: label.trim(),
    );
    final same = c
        .summariesOf(mapId)
        .any((e) => e.$1.parentId == parentId && e.$2.first == covered.first && e.$2.last == covered.last);
    if (same) return (c, null);
    return (c.copyWith(summaries: [...c.summaries, summary]), summary);
  }

  StudySetContent relabelSummary(StudySetContent c, String id, String label) =>
      c.copyWith(summaries: [for (final s in c.summaries) s.id == id ? s.copyWith(label: label.trim()) : s]);

  StudySetContent removeSummary(StudySetContent c, String id) => c.copyWith(
    summaries: [
      for (final s in c.summaries)
        if (s.id != id) s,
    ],
  );

  /// After a structural edit, a summary whose end left its parent shrinks
  /// to the covered siblings that stayed; with none left it goes away.
  StudySetContent _keepSummaries(StudySetContent before, StudySetContent after) {
    if (!after.summaries.any((s) => s.mapId == mapId)) return after;
    var changed = false;
    final summaries = <MapSummary>[];
    for (final s in after.summaries) {
      final old = s.mapId == mapId ? before.summaryRange(s) : null;
      if (old == null || after.summaryRange(s) != null) {
        summaries.add(s);
        continue;
      }
      changed = true;
      final kept = {...old};
      final stayed = [
        for (final n in after.childrenOf(s.parentId, mapId: mapId))
          if (kept.contains(n.cardId)) n.cardId,
      ];
      if (stayed.isNotEmpty) summaries.add(s.copyWith(fromId: stayed.first, toId: stayed.last));
    }
    return changed ? after.copyWith(summaries: summaries) : after;
  }

  /// Places shared content once per map; parent ids are local to that map.
  StudySetContent placeCard(StudySetContent c, String cardId, {String? parentId}) {
    if (c.map(mapId) == null || c.card(cardId) == null || c.node(cardId, mapId: mapId) != null) return c;
    if (parentId != null && c.node(parentId, mapId: mapId) == null) return c;
    return c.copyWith(
      nodes: [
        for (final n in c.nodes) n.mapId == mapId && n.cardId == parentId ? n.copyWith(collapsed: false) : n,
        MapNode(mapId: mapId, cardId: cardId, parentId: parentId, order: _nextOrder(c, parentId)),
      ],
    );
  }

  /// Image bytes are imported through the repository before this pure edit.
  (StudySetContent, Card) createImage(
    StudySetContent c, {
    required String imageFileName,
    required String annotationId,
    String title = '',
    String? parentId,
  }) {
    final card = Card(
      id: newId(),
      kind: CardKind.image,
      title: title.trim(),
      annotationId: annotationId,
      imageFileName: imageFileName,
      createdAt: now(),
    );
    return (_place(c, card, parentId), card);
  }

  /// An area of one page as a framed annotation plus its image card, in one
  /// step. The captured image is imported through the repository first.
  (StudySetContent, Card) createAreaExcerpt(
    StudySetContent c, {
    required String documentId,
    required int page,
    required PageRect rect,
    required String imageFileName,
    required int colorIndex,
    String? parentId,
  }) {
    final (withArea, a) = highlight(
      c,
      documentId: documentId,
      page: page,
      rects: [rect],
      quote: '',
      colorIndex: colorIndex,
    );
    return createImage(withArea, imageFileName: imageFileName, annotationId: a.id, parentId: parentId);
  }

  /// Inserts a portable forest in one immutable edit. Missing source documents
  /// become notes containing the quote instead of dangling excerpt references.
  /// [images] maps clipboard image names to files already imported into this
  /// package; such images stay images even without their source document.
  (StudySetContent, List<String>) paste(
    StudySetContent c,
    List<OutlineEntry> entries, {
    String? parentId,
    Map<String, String> images = const {},
    Map<String, String> snapshots = const {},
  }) {
    if (parentId != null && c.node(parentId, mapId: mapId) == null) return (c, const []);
    var research = c;
    final copiedNotes = <String, String>{};
    final copiedSources = <String, String>{};
    final copiedEvidence = <String, String>{};
    final cards = [...c.cards];
    final nodes = [...c.nodes];
    final annotations = [...c.annotations];
    final parents = <String>[];
    final roots = <String>[];
    var order = _nextOrder(c, parentId);
    for (final entry in entries) {
      if (entry.depth < 0 || entry.depth > parents.length) throw const FormatException('Invalid outline depth');
      parents.length = entry.depth;
      final id = newId();
      final source = entry.annotation;
      String? annotationId;
      var kind = entry.kind;
      var title = entry.title;
      String? imageFileName;
      for (final original in entry.researchNotes) {
        var noteId = copiedNotes[original.id];
        if (noteId == null) {
          final sourceIds = {
            for (final ref in original.citations)
              for (final e in entry.evidence)
                if (e.id == ref.evidenceId) e.sourceId,
          };
          final sources = <ResearchSource>[];
          for (final source in entry.sources.where((s) => sourceIds.contains(s.id))) {
            if (copiedSources.containsKey(source.id)) continue;
            final versions = [
              for (final v in source.versions)
                if (snapshots[v.snapshotFile] case final imported?)
                  SourceVersion(
                    version: v.version,
                    snapshotFile: imported,
                    hash: imported.split('/').last.split('.').first,
                  ),
            ];
            if (versions.length != source.versions.length) {
              throw const FormatException('Research snapshots must be imported before paste');
            }
            for (var i = 0; i < versions.length; i++) {
              if (versions[i].snapshotFile != 'research/snapshots/${source.versions[i].hash}.md') {
                throw const FormatException('Clipboard snapshot hash mismatch');
              }
            }
            final sourceId = copiedSources[source.id] = newId();
            sources.add(
              ResearchSource.fromJson({
                ...source.toJson(),
                'id': sourceId,
                'versions': [for (final v in versions) v.toJson()],
              }),
            );
          }
          final evidence = <Evidence>[];
          for (final ref in original.citations) {
            if (copiedEvidence.containsKey(ref.evidenceId)) continue;
            final source = entry.evidence.where((e) => e.id == ref.evidenceId).firstOrNull;
            if (source == null || !copiedSources.containsKey(source.sourceId)) {
              throw const FormatException('Missing research evidence');
            }
            final evidenceId = copiedEvidence[source.id] = newId();
            evidence.add(
              Evidence.fromJson({...source.toJson(), 'id': evidenceId, 'sourceId': copiedSources[source.sourceId]}),
            );
          }
          noteId = copiedNotes[original.id] = newId();
          final pdf = entry.pdfAttachments
              .where((a) => a.noteId == original.id)
              .map((a) => a.target)
              .whereType<PdfTarget>()
              .toList();
          final missing = pdf.any((p) => c.document(p.documentId) == null);
          final noteJson = {
            ...original.toJson(),
            'id': noteId,
            'citations': [for (final ref in original.citations) EvidenceRef(copiedEvidence[ref.evidenceId]!).toJson()],
            'sourceLocationMissing': original.sourceLocationMissing || missing,
          };
          noteJson.remove('sessionId'); // Session histories are deliberately not copied.
          research = saveResearchNote(
            research,
            ResearchNote.fromJson(noteJson),
            evidence: evidence,
            sources: sources,
            targets: [
              for (final p in pdf)
                if (c.document(p.documentId) != null) p,
            ],
          );
        }
        research = research.copyWith(
          noteAttachments: [
            ...research.noteAttachments,
            NoteAttachment(
              id: newId(),
              noteId: noteId,
              target: CardTarget(cardId: id),
            ),
          ],
        );
      }
      final researchNoteId = copiedNotes[entry.researchNoteId];
      if (kind == CardKind.research && researchNoteId == null) throw const FormatException('Missing research note');
      if (kind == CardKind.image) {
        // Document ids are unique per package: a present source document
        // means the image file (never collected) is in this package too.
        final samePackage = source != null && c.document(source.documentId) != null;
        final name = entry.imageFileName;
        if (name != null && (samePackage || c.cards.any((c) => c.imageFileName == name))) {
          imageFileName = name;
        } else if (images[name] case final imported?) {
          imageFileName = imported;
        } else {
          kind = CardKind.note;
        }
      }
      if (kind == CardKind.excerpt || kind == CardKind.image) {
        final existing = source == null ? null : c.annotation(source.id);
        // Cutting leaves the source highlight in place. Reattach it once;
        // an already attached highlight is copied independently instead.
        if (existing != null &&
            c.document(existing.documentId) != null &&
            !cards.any((card) => card.annotationId == existing.id)) {
          annotationId = existing.id;
        } else if (source != null && c.document(source.documentId) != null) {
          annotationId = newId();
          annotations.add(
            Annotation(
              id: annotationId,
              documentId: source.documentId,
              pages: source.pages,
              quote: source.quote,
              colorIndex: source.colorIndex,
              createdAt: now(),
            ),
          );
        } else if (kind == CardKind.excerpt) {
          kind = CardKind.note;
          title = [if (title.isNotEmpty) title, if (source != null) source.quote].join('\n');
        }
      }
      cards.add(
        Card(
          id: id,
          kind: kind,
          title: title,
          researchNoteId: researchNoteId,
          textFormat: entry.textFormat,
          imageOrigin: entry.imageOrigin,
          annotationId: annotationId,
          imageFileName: imageFileName,
          tags: List.unmodifiable(entry.tags),
          createdAt: now(),
        ),
      );
      nodes.add(
        MapNode(
          mapId: mapId,
          cardId: id,
          parentId: parents.lastOrNull ?? parentId,
          order: entry.depth == 0 ? order++ : nodes.length.toDouble(),
          collapsed: entry.collapsed,
          width: entry.width,
        ),
      );
      if (entry.depth == 0) roots.add(id);
      parents.add(id);
    }
    if (entries.isEmpty) return (c, roots);
    // Pasted children must be visible, even if their target was folded.
    return (
      research.copyWith(
        cards: cards,
        annotations: annotations,
        nodes: [
          for (final node in nodes)
            node.mapId == mapId && node.cardId == parentId ? node.copyWith(collapsed: false) : node,
        ],
      ),
      roots,
    );
  }

  /// Where a new excerpt goes when [selectedCardId] is selected: under a
  /// selected topic, next to a selected excerpt/note (its parent), else the
  /// root. Returns a card id or null for the root.
  static String? excerptTarget(StudySetContent c, String? selectedCardId, {String mapId = MindMap.defaultId}) {
    if (selectedCardId == null) return null;
    final card = c.card(selectedCardId);
    final node = c.node(selectedCardId, mapId: mapId);
    if (card == null || node == null) return null;
    return card.kind == CardKind.topic ? card.id : node.parentId;
  }

  double _nextOrder(StudySetContent c, String? parentId) {
    final siblings = c.childrenOf(parentId, mapId: mapId);
    return siblings.isEmpty ? 1 : siblings.last.order + 1;
  }

  /// Adds a document that has already been copied into the package.
  (StudySetContent, Document) addDocument(
    StudySetContent c, {
    required String title,
    required String fileName,
    required int pageCount,
  }) {
    final doc = Document(id: newId(), title: title, fileName: fileName, pageCount: pageCount, importedAt: now());
    return (c.copyWith(documents: [...c.documents, doc]), doc);
  }

  StudySetContent setLastPage(StudySetContent c, String documentId, int page) => c.copyWith(
    documents: [for (final d in c.documents) d.id == documentId ? d.copyWith(lastPage: page, lastReadAt: now()) : d],
  );

  /// Highlight only (no card).
  (StudySetContent, Annotation) highlight(
    StudySetContent c, {
    required String documentId,
    int? page,
    List<PageRect>? rects,
    List<AnnotationPage>? pages,
    required String quote,
    required int colorIndex,
  }) {
    final a = Annotation(
      id: newId(),
      documentId: documentId,
      page: page,
      rects: rects,
      pages: pages,
      quote: quote.trim(),
      colorIndex: colorIndex,
      createdAt: now(),
    );
    return (c.copyWith(annotations: [...c.annotations, a]), a);
  }

  /// Highlight + excerpt card + map node, in one step.
  (StudySetContent, Card) createExcerpt(
    StudySetContent c, {
    required String documentId,
    int? page,
    List<PageRect>? rects,
    List<AnnotationPage>? pages,
    required String quote,
    required int colorIndex,
    String? parentId,
  }) {
    final (withHighlight, a) = highlight(
      c,
      documentId: documentId,
      page: page,
      rects: rects,
      pages: pages,
      quote: quote,
      colorIndex: colorIndex,
    );
    return attachCard(withHighlight, a.id, parentId: parentId);
  }

  /// Turns an existing highlight into an excerpt card on the map.
  (StudySetContent, Card) attachCard(StudySetContent c, String annotationId, {String? parentId}) {
    final existing = c.cardForAnnotation(annotationId);
    if (existing != null) return (placeCard(c, existing.id, parentId: parentId), existing);
    final card = Card(id: newId(), kind: CardKind.excerpt, annotationId: annotationId, createdAt: now());
    return (_place(c, card, parentId), card);
  }

  (StudySetContent, Card) addTopic(StudySetContent c, {required String title, String? parentId}) =>
      _addCard(c, CardKind.topic, title, parentId);

  /// Adds a sibling before/after a node. The virtual root has no siblings;
  /// null adds a child of the root instead. Missing nodes are a no-op.
  (StudySetContent, Card?) insertSibling(
    StudySetContent c,
    String? cardId, {
    required String title,
    bool before = false,
  }) {
    if (cardId == null) return addTopic(c, title: title);
    final node = c.node(cardId, mapId: mapId);
    if (node == null) return (c, null);
    final siblings = c.childrenOf(node.parentId, mapId: mapId);
    final index = siblings.indexWhere((n) => n.cardId == cardId) + (before ? 0 : 1);
    final (next, card) = addTopic(c, title: title, parentId: node.parentId);
    return (move(next, card.id, node.parentId, index: index), card);
  }

  /// Lifts a node after its parent, keeping its subtree intact.
  /// Root children and the virtual root cannot be lifted further.
  StudySetContent promote(StudySetContent c, String? cardId) {
    final node = cardId == null ? null : c.node(cardId, mapId: mapId);
    final parent = node?.parentId == null ? null : c.node(node!.parentId!, mapId: mapId);
    if (parent == null) return c;
    final index = c.childrenOf(parent.parentId, mapId: mapId).indexWhere((n) => n.cardId == parent.cardId) + 1;
    return move(c, cardId!, parent.parentId, index: index);
  }

  /// Wraps a node in a new topic at its existing sibling position.
  /// The virtual root and missing nodes cannot acquire a parent.
  (StudySetContent, Card?) insertParent(StudySetContent c, String? cardId, {required String title}) {
    final node = cardId == null ? null : c.node(cardId, mapId: mapId);
    if (node == null) return (c, null);
    final (next, parent) = addTopic(c, title: title, parentId: node.parentId);
    return (
      next.copyWith(
        nodes: [
          for (final n in next.nodes)
            if (n.mapId == mapId && n.cardId == parent.id)
              n.copyWith(order: node.order)
            else if (n.mapId == mapId && n.cardId == cardId)
              n.copyWith(parentId: parent.id, order: 1)
            else
              n,
        ],
        summaries: [
          for (final s in next.summaries)
            if (s.mapId == mapId && s.parentId == node.parentId)
              s.copyWith(fromId: s.fromId == cardId ? parent.id : null, toId: s.toId == cardId ? parent.id : null)
            else
              s,
        ],
      ),
      parent,
    );
  }

  /// Removes selected subtrees once; highlights and review history survive.
  StudySetContent removeMany(StudySetContent c, Iterable<String> cardIds) {
    final kill = <String>{};
    for (final id in cardIds.toSet()) {
      if (c.node(id, mapId: mapId) != null) kill.addAll(_subtree(c, id));
    }
    if (kill.isEmpty) return c;
    return _removeNodes(c, kill);
  }

  /// Moves selection roots as one block, in map preorder (independent of
  /// click order). Selected descendants travel with their selected ancestor.
  /// Index refers to destination siblings after removing the selection.
  /// Invalid destinations reject the entire operation, never a partial move.
  StudySetContent moveMany(StudySetContent c, Iterable<String> cardIds, String? parentId, {int? index}) {
    if (parentId != null && c.node(parentId, mapId: mapId) == null) return c;
    final selected = cardIds.toSet();
    final roots = <MapNode>[];
    void walk(String? parent) {
      for (final node in c.childrenOf(parent, mapId: mapId)) {
        if (selected.contains(node.cardId)) {
          roots.add(node);
        } else {
          walk(node.cardId);
        }
      }
    }

    walk(null);
    if (roots.isEmpty) return c;
    if (parentId != null && roots.any((n) => _subtree(c, n.cardId).contains(parentId))) return c;
    final ids = roots.map((n) => n.cardId).toSet();
    final siblings = c.childrenOf(parentId, mapId: mapId).where((n) => !ids.contains(n.cardId)).toList();
    siblings.insertAll((index ?? siblings.length).clamp(0, siblings.length), roots);
    // Renumber the destination together to avoid equal fractional orders.
    final orders = {for (var i = 0; i < siblings.length; i++) siblings[i].cardId: (i + 1).toDouble()};
    return _keepSummaries(
      c,
      c.copyWith(
        nodes: [
          for (final n in c.nodes)
            if (n.mapId == mapId && orders.containsKey(n.cardId))
              n.copyWith(parentId: parentId, toRoot: parentId == null, order: orders[n.cardId])
            else if (n.mapId == mapId && n.cardId == parentId && n.collapsed)
              n.copyWith(collapsed: false)
            else
              n,
        ],
      ),
    );
  }

  /// Colors selected excerpt highlights. Topics/notes have no stored color
  /// in format 1 and are ignored; descendants are not implicitly selected.
  StudySetContent recolorMany(StudySetContent c, Iterable<String> cardIds, int colorIndex) {
    final selected = cardIds.toSet();
    final annotations = {
      for (final card in c.cards)
        if (selected.contains(card.id) && c.node(card.id, mapId: mapId) != null && card.annotationId != null)
          card.annotationId!,
    };
    if (!c.annotations.any((a) => annotations.contains(a.id) && a.colorIndex != colorIndex)) return c;
    return c.copyWith(
      annotations: [for (final a in c.annotations) annotations.contains(a.id) ? a.copyWith(colorIndex: colorIndex) : a],
    );
  }

  (StudySetContent, Card) addNote(StudySetContent c, {required String text, String? parentId}) =>
      _addCard(c, CardKind.note, text, parentId);

  (StudySetContent, Card) _addCard(StudySetContent c, CardKind kind, String title, String? parentId) {
    final card = Card(id: newId(), kind: kind, title: title.trim(), createdAt: now());
    return (_place(c, card, parentId), card);
  }

  /// Adds [card] as the last child of [parentId], expanding the parent so
  /// the new card is visible.
  StudySetContent _place(StudySetContent c, Card card, String? parentId) {
    final node = MapNode(mapId: mapId, cardId: card.id, parentId: parentId, order: _nextOrder(c, parentId));
    return c.copyWith(
      cards: [...c.cards, card],
      nodes: [
        for (final n in c.nodes)
          n.mapId == mapId && n.cardId == parentId && n.collapsed ? n.copyWith(collapsed: false) : n,
        node,
      ],
    );
  }

  StudySetContent rename(StudySetContent c, String cardId, String title) =>
      c.copyWith(cards: [for (final card in c.cards) card.id == cardId ? card.copyWith(title: title.trim()) : card]);

  StudySetContent recolor(StudySetContent c, String annotationId, int colorIndex) => c.copyWith(
    annotations: [for (final a in c.annotations) a.id == annotationId ? a.copyWith(colorIndex: colorIndex) : a],
  );

  /// Moves [cardId] under [newParentId] (null = root), at [index] among
  /// the new siblings (end when null). Refuses to move a node under itself
  /// or its own descendants.
  StudySetContent move(StudySetContent c, String cardId, String? newParentId, {int? index}) {
    if (c.node(cardId, mapId: mapId) == null) return c;
    if (newParentId != null && c.node(newParentId, mapId: mapId) == null) return c;
    if (newParentId != null && _subtree(c, cardId).contains(newParentId)) return c;
    final siblings = [
      for (final n in c.childrenOf(newParentId, mapId: mapId))
        if (n.cardId != cardId) n,
    ];
    final i = (index ?? siblings.length).clamp(0, siblings.length);
    final double order;
    if (siblings.isEmpty) {
      order = 1;
    } else if (i == 0) {
      order = siblings.first.order - 1;
    } else if (i == siblings.length) {
      order = siblings.last.order + 1;
    } else {
      order = (siblings[i - 1].order + siblings[i].order) / 2;
    }
    return _keepSummaries(
      c,
      c.copyWith(
        nodes: [
          for (final n in c.nodes)
            n.mapId == mapId && n.cardId == cardId
                ? n.copyWith(parentId: newParentId, toRoot: newParentId == null, order: order)
                : n,
        ],
      ),
    );
  }

  /// Moves a node one place up (-1) or down (+1) among its siblings.
  StudySetContent shift(StudySetContent c, String cardId, int delta) {
    final node = c.node(cardId, mapId: mapId);
    if (node == null) return c;
    final siblings = c.childrenOf(node.parentId, mapId: mapId);
    final i = siblings.indexWhere((n) => n.cardId == cardId);
    final target = i + delta;
    if (target < 0 || target >= siblings.length) return c;
    return move(c, cardId, node.parentId, index: target);
  }

  StudySetContent setCollapsed(StudySetContent c, String cardId, {required bool collapsed}) => c.copyWith(
    nodes: [for (final n in c.nodes) n.mapId == mapId && n.cardId == cardId ? n.copyWith(collapsed: collapsed) : n],
  );

  /// Stores memory parameters without changing the legacy schedule.
  StudySetContent setMemoryState(StudySetContent c, MemoryState state) {
    if (c.card(state.cardId) == null) return c;
    return c.copyWith(
      memoryStates: [
        for (final existing in c.memoryStates)
          if (existing.cardId != state.cardId) existing,
        state,
      ],
    );
  }

  StudySetContent setSuspended(StudySetContent c, String cardId, {required bool suspended}) {
    final card = c.card(cardId);
    if (card == null || card.suspended == suspended) return c;
    return c.copyWith(
      cards: [for (final value in c.cards) value.id == cardId ? value.copyWith(suspended: suspended) : value],
    );
  }

  /// Fill missing legacy memory states without moving any existing due date.
  /// Existing FSRS states and logs are preserved; repeated calls are no-ops.
  static StudySetContent initializeMemory(StudySetContent c) {
    final known = c.memoryStates.map((m) => m.cardId).toSet();
    final missing = [
      for (final r in c.reviews)
        if (known.add(r.cardId)) ReviewScheduler.fromLegacy(r),
    ];
    return missing.isEmpty ? c : c.copyWith(memoryStates: [...c.memoryStates, ...missing]);
  }

  /// Records a review of [cardId] rated [rating].
  StudySetContent rate(StudySetContent c, String cardId, Rating rating) {
    if (c.card(cardId) == null) return c;
    final reviewedAt = now();
    final previous = c.reviewOf(cardId);
    final result = ReviewScheduler.schedule(
      cardId,
      previous,
      rating,
      reviewedAt,
      memory: c.memoryOf(cardId),
      parameters: fsrsParameters,
    );
    final next = result.review;
    return c.copyWith(
      memoryStates: [
        for (final state in c.memoryStates)
          if (state.cardId != cardId) state,
        result.memory,
      ],
      reviewLogs: [
        ...c.reviewLogs,
        ReviewLog(
          id: newId(),
          cardId: cardId,
          reviewedAt: reviewedAt,
          rating: rating,
          intervalBefore: previous?.intervalDays ?? 0,
          intervalAfter: next.intervalDays,
        ),
      ],
      reviews: [
        for (final r in c.reviews)
          if (r.cardId != cardId) r,
        next,
      ],
    );
  }

  StudySetContent renameDocument(StudySetContent c, String documentId, String title) =>
      c.copyWith(documents: [for (final d in c.documents) d.id == documentId ? d.copyWith(title: title.trim()) : d]);

  /// Removes a document with its highlights and their excerpt cards
  /// (children of those cards go with them).
  StudySetContent removeDocument(StudySetContent c, String documentId) {
    var next = c;
    for (final a in c.annotationsOn(documentId)) {
      next = deleteAnnotation(next, a.id);
    }
    return next.copyWith(
      documents: [
        for (final d in next.documents)
          if (d.id != documentId) d,
      ],
      noteAttachments: [
        for (final a in next.noteAttachments)
          if (!(a.target is PdfTarget && (a.target as PdfTarget).documentId == documentId)) a,
      ],
      inkStrokes: [
        for (final s in next.inkStrokes)
          if (s.documentId != documentId) s,
      ],
      bookmarks: [
        for (final b in next.bookmarks)
          if (b.documentId != documentId) b,
      ],
    );
  }

  /// Adds a bookmark on [page] of [documentId], or removes the one that is
  /// already there. Pages outside the document are ignored.
  StudySetContent toggleBookmark(StudySetContent c, String documentId, int page) {
    final doc = c.document(documentId);
    if (doc == null || page < 1 || page > doc.pageCount) return c;
    final existing = c.bookmarkAt(documentId, page);
    if (existing != null) return removeBookmark(c, existing.id);
    final bookmark = Bookmark(id: newId(), documentId: documentId, page: page, createdAt: now());
    return c.copyWith(bookmarks: [...c.bookmarks, bookmark]);
  }

  /// An empty [title] goes back to the unnamed bookmark.
  StudySetContent renameBookmark(StudySetContent c, String bookmarkId, String title) =>
      c.copyWith(bookmarks: [for (final b in c.bookmarks) b.id == bookmarkId ? b.copyWith(title: title.trim()) : b]);

  StudySetContent removeBookmark(StudySetContent c, String bookmarkId) => c.copyWith(
    bookmarks: [
      for (final b in c.bookmarks)
        if (b.id != bookmarkId) b,
    ],
  );

  /// [snapshot] (an earlier state, for undo/redo) with the parts that are
  /// not undoable taken from [current]: review history and reading position.
  static StudySetContent restore(StudySetContent snapshot, StudySetContent current) => snapshot.copyWith(
    reviews: current.reviews,
    reviewLogs: current.reviewLogs,
    memoryStates: current.memoryStates,
    documents: [
      for (final d in snapshot.documents)
        if (current.document(d.id) case final now?)
          d.copyWith(lastPage: now.lastPage, lastReadAt: now.lastReadAt)
        else
          d,
    ],
  );

  /// Removes the card and its descendants from the map. Excerpt cards are
  /// deleted but their highlights stay in the source (as plain highlights).
  StudySetContent removeFromMap(StudySetContent c, String cardId) => _removeNodes(c, _subtree(c, cardId));

  /// Removes [kill] from this map. Cards placed in other maps survive. An
  /// image card's area only frames that image, so it goes with the card.
  StudySetContent _removeNodes(StudySetContent c, Set<String> kill) {
    final removed = {
      for (final card in c.cards)
        if (kill.contains(card.id) && !c.nodes.any((n) => n.mapId != mapId && n.cardId == card.id)) card.id: card,
    };
    final areas = {
      for (final card in removed.values)
        if (card.kind == CardKind.image && card.annotationId != null) card.annotationId!,
    };
    return _keepSummaries(
      c,
      c.copyWith(
        relations: [
          for (final r in c.relations)
            if (r.mapId != mapId || !(kill.contains(r.fromId) || kill.contains(r.toId))) r,
        ],
        noteAttachments: [
          for (final a in c.noteAttachments)
            if (!(a.target is CardTarget && removed.containsKey((a.target as CardTarget).cardId))) a,
        ],
        cards: [
          for (final card in c.cards)
            if (!removed.containsKey(card.id)) card,
        ],
        nodes: [
          for (final n in c.nodes)
            if (n.mapId != mapId || !kill.contains(n.cardId)) n,
        ],
        annotations: areas.isEmpty
            ? null
            : [
                for (final a in c.annotations)
                  if (!areas.contains(a.id)) a,
              ],
      ),
    );
  }

  /// Deletes a highlight and, if it has one, its card subtree.
  StudySetContent deleteAnnotation(StudySetContent c, String annotationId) {
    final cards = c.cards.where((card) => card.annotationId == annotationId);
    var without = c;
    for (final card in cards) {
      for (final map in c.maps) {
        without = StudySetEditor(newId: newId, now: now, mapId: map.id).removeFromMap(without, card.id);
      }
    }
    return without.copyWith(
      annotations: [
        for (final a in without.annotations)
          if (a.id != annotationId) a,
      ],
    );
  }

  Set<String> _subtree(StudySetContent c, String cardId) {
    final result = {cardId};
    var frontier = [cardId];
    while (frontier.isNotEmpty) {
      final next = <String>[];
      for (final id in frontier) {
        for (final child in c.childrenOf(id, mapId: mapId)) {
          if (result.add(child.cardId)) next.add(child.cardId);
        }
      }
      frontier = next;
    }
    return result;
  }
}
