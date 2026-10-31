import 'dart:convert';

import 'document_outline.dart';
import 'note_editor.dart';

import 'models.dart';
import 'document_format.dart';
import 'text_anchor.dart';
import 'reading.dart';
import 'reading_editor.dart';
import 'research.dart';
import 'map_clipboard.dart';
import 'map_notes.dart';
import 'review.dart';
import 'study_set_content.dart';

part 'mindmap_editor.dart';

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
    if (createCard && (c.map(mapId) == null || (parentId != null && !c.isPlaced(parentId, mapId: mapId)))) {
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
      case TextTarget(:final documentId):
        if (c.document(documentId) == null) throw ArgumentError('Unknown attachment document');
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

  /// One note shown in the source and the map: editing it here changes both.
  /// Citations are kept; an unchanged or emptied title is ignored.
  StudySetContent editResearchNote(StudySetContent c, String noteId, {String? title, String? body}) {
    final note = c.researchNote(noteId);
    final nextTitle = title?.trim();
    if (note == null) return c;
    final changesTitle = nextTitle != null && nextTitle.isNotEmpty && nextTitle != note.title;
    final changesBody = body != null && body != note.body;
    if (!changesTitle && !changesBody) return c;
    return c.copyWith(
      researchNotes: [
        for (final n in c.researchNotes)
          n.id == noteId
              ? n.copyWith(title: changesTitle ? nextTitle : null, body: changesBody ? body : null, updatedAt: now())
              : n,
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
        (stroke.textAnchor == null && (stroke.page < 1 || stroke.page > doc.pageCount)) ||
        !stroke.width.isFinite ||
        stroke.width <= 0 ||
        stroke.colorIndex < 0 ||
        stroke.points.length > InkStroke.maxPoints ||
        stroke.points.any((p) => !p.x.isFinite || !p.y.isFinite) ||
        switch (stroke.tool) {
          InkTool.ellipse => stroke.ellipse == null || stroke.points.isNotEmpty,
          InkTool.arrow => stroke.points.length != 2 || stroke.ellipse != null,
          _ => stroke.points.isEmpty || stroke.ellipse != null,
        }) {
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
      marginNotes: [
        for (final note in c.marginNotes)
          (note.mapId ?? MindMap.defaultId) == id ? note.copyWith(nodeId: null, mapId: null) : note,
      ],
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
  /// relate to itself; either direction of an existing pair selects that line.
  (StudySetContent, MapRelation?) addRelation(StudySetContent c, String fromId, String toId, {String label = ''}) {
    if (fromId == toId || !c.isPlaced(fromId, mapId: mapId) || !c.isPlaced(toId, mapId: mapId)) return (c, null);
    final existing = c.relations
        .where(
          (r) => r.mapId == mapId && ((r.fromId == fromId && r.toId == toId) || (r.fromId == toId && r.toId == fromId)),
        )
        .firstOrNull;
    if (existing != null) return (c, existing);
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
  /// overlapping ranges are rejected.
  (StudySetContent, MapSummary?) addSummary(StudySetContent c, Iterable<String> cardIds, {String label = ''}) {
    final result = createSummary(c, cardIds, label: label);
    return (result.content, result.value);
  }

  StudySetContent relabelSummary(StudySetContent c, String id, String label) {
    final summary = c.summaries.where((s) => s.mapId == mapId && s.id == id).firstOrNull;
    if (summary == null) return c;
    return c.copyWith(
      summaries: [for (final s in c.summaries) s.id == id ? s.copyWith(label: label.trim()) : s],
      cards: [for (final card in c.cards) card.id == summary.cardId ? card.copyWith(title: label.trim()) : card],
    );
  }

  StudySetContent removeSummary(StudySetContent c, String id) {
    final summary = c.summaries.where((s) => s.mapId == mapId && s.id == id).firstOrNull;
    if (summary == null) return c;
    final next = c.copyWith(
      summaries: [
        for (final s in c.summaries)
          if (s.id != id) s,
      ],
    );
    return summary.cardId == null ? next : _removeNodes(next, _subtree(c, summary.cardId!));
  }

  /// After a structural edit, a summary whose end left its parent shrinks
  /// to the covered siblings that stayed; with none left it goes away.
  StudySetContent _keepSummaries(StudySetContent before, StudySetContent after) {
    if (!after.summaries.any((s) => s.mapId == mapId)) return after;
    var changed = false;
    final summaries = <MapSummary>[];
    final dropped = <String>[];
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
      if (stayed.isNotEmpty) {
        summaries.add(s.copyWith(fromId: stayed.first, toId: stayed.last));
      } else if (s.cardId != null) {
        dropped.add(s.cardId!);
      }
    }
    var result = changed ? after.copyWith(summaries: summaries) : after;
    for (final id in dropped) {
      result = _removeNodes(result, _subtree(result, id));
    }
    return result;
  }

  /// Places shared content once per map; parent ids are local to that map.
  StudySetContent placeCard(StudySetContent c, String cardId, {String? parentId}) {
    if (c.map(mapId) == null || c.card(cardId) == null || c.isPlaced(cardId, mapId: mapId)) return c;
    if (parentId != null && !c.isPlaced(parentId, mapId: mapId)) return c;
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
    String? annotationId,
    String? imageOrigin,
    String title = '',
    String? parentId,
  }) {
    final card = Card(
      id: newId(),
      kind: CardKind.image,
      title: title.trim(),
      annotationId: annotationId,
      imageFileName: imageFileName,
      imageOrigin: imageOrigin,
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
    if (parentId != null && !c.isPlaced(parentId, mapId: mapId)) return (c, const []);
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
              .where((t) => t is PdfTarget || t is TextTarget)
              .toList();
          final missing = pdf.any(
            (p) =>
                c.document(switch (p) {
                  PdfTarget(:final documentId) || TextTarget(:final documentId) => documentId,
                  _ => '',
                }) ==
                null,
          );
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
                if (c.document(switch (p) {
                      PdfTarget(:final documentId) || TextTarget(:final documentId) => documentId,
                      _ => '',
                    }) !=
                    null)
                  p,
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
              pages: source.isText ? null : source.pages,
              textAnchors: source.textAnchors,
              capture: source.capture,
              quote: source.quote,
              colorIndex: source.colorIndex,
              kind: source.kind,
              lineStyle: source.lineStyle,
              needsReview: source.needsReview,
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
          body: entry.body,
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

  /// New excerpts become children of the selected node, regardless of its
  /// kind. With no valid selection in this map, they go under the root.
  static String? excerptTarget(StudySetContent c, String? selectedCardId, {String mapId = MindMap.defaultId}) {
    if (selectedCardId == null) return null;
    final card = c.card(selectedCardId);
    final node = c.node(selectedCardId, mapId: mapId);
    if (card == null || node == null) return null;
    return card.id;
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
    DocumentFormat format = DocumentFormat.pdf,
    DocumentLayout layout = DocumentLayout.fixed,
    String? sourceFileName,
    String? contentManifest,
    String? revision,
    DocumentOrigin? origin,
  }) {
    final doc = Document(
      id: newId(),
      title: title,
      fileName: fileName,
      pageCount: pageCount,
      importedAt: now(),
      format: format,
      layout: layout,
      sourceFileName: sourceFileName,
      contentManifest: contentManifest,
      revision: revision,
      origin: origin,
    );
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
    List<TextAnchor> textAnchors = const [],
    required String quote,
    required int colorIndex,
  }) {
    final a = Annotation(
      id: newId(),
      documentId: documentId,
      page: page,
      rects: rects,
      pages: pages,
      textAnchors: textAnchors,
      quote: quote.trim(),
      colorIndex: colorIndex,
      createdAt: now(),
    );
    return (c.copyWith(annotations: [...c.annotations, a]), a);
  }

  /// Reapplying to exactly the same text edits the existing underline.
  (StudySetContent, Annotation) underline(
    StudySetContent c, {
    required String documentId,
    List<AnnotationPage>? pages,
    List<TextAnchor> textAnchors = const [],
    required String quote,
    required int colorIndex,
    required AnnotationLineStyle lineStyle,
  }) {
    if (quote.trim().isEmpty ||
        (textAnchors.isEmpty && (pages == null || pages.isEmpty || pages.any((p) => p.rects.isEmpty)))) {
      throw ArgumentError('An underline needs text and a source target');
    }
    if (pages != null && textAnchors.isNotEmpty) throw ArgumentError('Mixed annotation targets');
    for (final anchor in textAnchors) {
      anchor.validate();
    }
    final existing = c.annotations
        .where(
          (a) =>
              a.kind == AnnotationKind.underline &&
              a.documentId == documentId &&
              (textAnchors.isNotEmpty
                  ? a.isText && _sameTextAnchors(a.textAnchors, textAnchors)
                  : !a.isText && _sameAnnotationPages(a.pages, pages!)),
        )
        .firstOrNull;
    if (existing != null) {
      if (existing.colorIndex == colorIndex && existing.lineStyle == lineStyle) return (c, existing);
      final next = restyleAnnotation(c, existing.id, lineStyle: lineStyle, colorIndex: colorIndex);
      return (next, next.annotation(existing.id)!);
    }
    final a = Annotation(
      id: newId(),
      documentId: documentId,
      pages: pages,
      textAnchors: textAnchors,
      quote: quote.trim(),
      colorIndex: colorIndex,
      kind: AnnotationKind.underline,
      lineStyle: lineStyle,
      createdAt: now(),
    );
    return (c.copyWith(annotations: [...c.annotations, a]), a);
  }

  static bool _sameTextAnchors(List<TextAnchor> a, List<TextAnchor> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].chapterId != b[i].chapterId ||
          a[i].revision != b[i].revision ||
          a[i].normalizationVersion != b[i].normalizationVersion ||
          a[i].start != b[i].start ||
          a[i].end != b[i].end ||
          a[i].quote != b[i].quote) {
        return false;
      }
    }
    return true;
  }

  static bool _sameAnnotationPages(List<AnnotationPage> a, List<AnnotationPage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].page != b[i].page || a[i].rects.length != b[i].rects.length) return false;
      for (var j = 0; j < a[i].rects.length; j++) {
        if (a[i].rects[j] != b[i].rects[j]) return false;
      }
    }
    return true;
  }

  StudySetContent restyleAnnotation(
    StudySetContent c,
    String id, {
    required AnnotationLineStyle lineStyle,
    required int colorIndex,
  }) {
    final original = c.annotation(id);
    if (original == null || original.quote.isEmpty) return c;
    final colored = original.colorIndex == colorIndex ? c : recolor(c, id, colorIndex);
    return colored.copyWith(
      annotations: [
        for (final a in colored.annotations)
          a.id == id ? a.copyWith(kind: AnnotationKind.underline, lineStyle: lineStyle) : a,
      ],
    );
  }

  /// Highlight + excerpt card + map node, in one step.
  (StudySetContent, Card) createExcerpt(
    StudySetContent c, {
    required String documentId,
    int? page,
    List<PageRect>? rects,
    List<AnnotationPage>? pages,
    List<TextAnchor> textAnchors = const [],
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
      textAnchors: textAnchors,
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

  /// Removes one attached note. Legacy children become its parent's children,
  /// preserving their reading order rather than deleting visible topics.
  StudySetContent removeAttachedNote(StudySetContent c, String cardId) {
    if (!MapNoteAttachments(c, mapId: mapId).owners.containsKey(cardId)) return c;
    final node = c.node(cardId, mapId: mapId)!;
    final children = c.childrenOf(cardId, mapId: mapId);
    final siblings = [
      for (final sibling in c.childrenOf(node.parentId, mapId: mapId))
        if (sibling.cardId == cardId) ...children else sibling,
    ];
    final orders = {for (final (i, n) in siblings.indexed) n.cardId: i.toDouble()};
    return _removeNodes(
      c.copyWith(
        nodes: [
          for (final n in c.nodes)
            if (n.mapId == mapId && orders.containsKey(n.cardId))
              n.copyWith(parentId: node.parentId, order: orders[n.cardId])
            else
              n,
        ],
      ),
      {cardId},
    );
  }

  /// Removes selected subtrees once; highlights and review history survive.
  StudySetContent removeMany(StudySetContent c, Iterable<String> cardIds) {
    final kill = <String>{};
    for (final id in cardIds.toSet()) {
      if (c.isPlaced(id, mapId: mapId)) kill.addAll(_subtree(c, id));
    }
    if (kill.isEmpty) return c;
    return _removeNodes(c, kill);
  }

  /// Moves selection roots as one block, in map preorder (independent of
  /// click order). Selected descendants travel with their selected ancestor.
  /// Index refers to destination siblings after removing the selection.
  /// Invalid destinations reject the entire operation, never a partial move.
  StudySetContent moveMany(StudySetContent c, Iterable<String> cardIds, String? parentId, {int? index}) {
    if (parentId != null && !c.isPlaced(parentId, mapId: mapId)) return c;
    final selected = cardIds.toSet();
    if (_movesIntoDependentSummary(c, selected, parentId)) return c;
    final roots = <MapNode>[];
    void walk(String? parent) {
      for (final node in c.childrenOf(parent, mapId: mapId)) {
        if (selected.contains(node.cardId)) {
          roots.add(node);
        } else {
          walk(node.cardId);
        }
      }
      for (final summary in c.summaries.where((s) => s.mapId == mapId && s.parentId == parent && s.cardId != null)) {
        walk(summary.cardId);
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
        if (selected.contains(card.id) && c.node(card.id, mapId: mapId) != null)
          for (final segment in c.segmentsOf(card)) ?segment.annotationId,
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

  StudySetContent rename(StudySetContent c, String cardId, String title) {
    final linked = c.marginNotes.where((n) => n.nodeId == cardId).firstOrNull;
    if (linked != null) return upsertMarginNote(c, linked.copyWith(text: title, updatedAt: now()));
    return c.copyWith(
      summaries: [for (final s in c.summaries) s.cardId == cardId ? s.copyWith(label: title.trim()) : s],
      cards: [for (final card in c.cards) card.id == cardId ? card.copyWith(title: title.trim()) : card],
    );
  }

  StudySetContent recolor(StudySetContent c, String annotationId, int colorIndex) {
    final linkedCards = {
      for (final card in c.cards)
        if (card.annotationId == annotationId) card.id,
    };
    final note = c.marginNotes.where((n) => linkedCards.contains(n.nodeId)).firstOrNull;
    if (note != null) return upsertMarginNote(c, note.copyWith(colorIndex: colorIndex, updatedAt: now()));
    return c.copyWith(
      annotations: [for (final a in c.annotations) a.id == annotationId ? a.copyWith(colorIndex: colorIndex) : a],
    );
  }

  /// Moves [cardId] under [newParentId] (null = root), at [index] among
  /// the new siblings (end when null). Refuses to move a node under itself
  /// or its own descendants.
  StudySetContent move(StudySetContent c, String cardId, String? newParentId, {int? index}) {
    if (c.node(cardId, mapId: mapId) == null) return c;
    if (newParentId != null && !c.isPlaced(newParentId, mapId: mapId)) return c;
    if (newParentId != null && _subtree(c, cardId).contains(newParentId)) return c;
    if (_movesIntoDependentSummary(c, [cardId], newParentId)) return c;
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

  /// Opt-in uses existing Card/FSRS fields without changing format 7.
  StudySetContent setResearchReview(StudySetContent c, String noteId, {required bool enabled}) {
    if (c.researchNote(noteId) == null) return c;
    final id = StudySetContent.researchReviewId(noteId);
    if (c.card(id) != null) return setSuspended(c, id, suspended: !enabled);
    if (!enabled) return c;
    return c.copyWith(
      cards: [
        ...c.cards,
        Card(id: id, kind: CardKind.research, researchNoteId: noteId, createdAt: now()),
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
      documentOutlines: [
        for (final o in next.documentOutlines)
          if (o.documentId != documentId) o,
      ],
      marginNotes: [
        for (final n in next.marginNotes)
          if (n.documentId != documentId) n,
      ],
      translationCaches: [
        for (final t in next.translationCaches)
          if (t.documentId != documentId) t,
      ],
      comparePairs: [
        for (final p in next.comparePairs)
          if (p.leftDocumentId != documentId &&
              !(p.right is PdfCompareTarget && (p.right as PdfCompareTarget).documentId == documentId))
            p,
      ],
      documents: [
        for (final d in next.documents)
          if (d.id != documentId) d,
      ],
      noteAttachments: [
        for (final a in next.noteAttachments)
          if (!(switch (a.target) {
            PdfTarget(documentId: final id) || TextTarget(documentId: final id) => id == documentId,
            _ => false,
          }))
            a,
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

  StudySetContent setReadingPosition(StudySetContent c, String documentId, ReadingPosition position) {
    final doc = c.document(documentId);
    if (doc == null ||
        (position is PdfPosition && position.page > doc.pageCount) ||
        (position is TextReadingPosition && doc.contentManifest == null)) {
      throw ArgumentError('Invalid reading position');
    }
    return c.copyWith(
      documents: [
        for (final d in c.documents)
          d.id == documentId
              ? d.copyWith(
                  readingPosition: position,
                  lastPage: position is PdfPosition ? position.page : null,
                  lastReadAt: now(),
                )
              : d,
      ],
    );
  }

  StudySetContent toggleTextBookmark(
    StudySetContent c,
    String documentId,
    TextReadingPosition position, {
    String title = '',
  }) {
    if (c.document(documentId)?.contentManifest == null) throw ArgumentError('Unknown text document');
    final existing = c.bookmarks
        .where(
          (b) =>
              b.documentId == documentId &&
              b.position is TextReadingPosition &&
              jsonEncode(b.position!.toJson()) == jsonEncode(position.toJson()),
        )
        .firstOrNull;
    if (existing != null) return removeBookmark(c, existing.id);
    return c.copyWith(
      bookmarks: [
        ...c.bookmarks,
        Bookmark(id: newId(), documentId: documentId, position: position, title: title, createdAt: now()),
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
    return addBookmark(c, documentId, page);
  }

  StudySetContent addBookmark(StudySetContent c, String documentId, int page, {String title = ''}) {
    final doc = c.document(documentId);
    if (doc == null || page < 1 || page > doc.pageCount || c.bookmarkAt(documentId, page) != null) return c;
    final existing = c.bookmarksOn(documentId);
    final custom = existing.any((b) => b.order != null);
    final bookmark = Bookmark(id: newId(), documentId: documentId, page: page, createdAt: now(), title: title.trim());
    final next = c.copyWith(bookmarks: [...c.bookmarks, bookmark]);
    return custom ? orderBookmarks(next, documentId, [...existing.map((b) => b.id), bookmark.id]) : next;
  }

  StudySetContent editBookmark(StudySetContent c, String id, String title, int page) {
    final bookmark = c.bookmarks.where((b) => b.id == id).firstOrNull;
    if (bookmark == null) return c;
    final doc = c.document(bookmark.documentId);
    final occupied = c.bookmarkAt(bookmark.documentId, page);
    if (doc == null || page < 1 || page > doc.pageCount || (occupied != null && occupied.id != id)) return c;
    return c.copyWith(
      bookmarks: [for (final b in c.bookmarks) b.id == id ? b.copyWith(title: title.trim(), page: page) : b],
    );
  }

  StudySetContent orderBookmarks(StudySetContent c, String documentId, List<String> ids) {
    final existing = c.bookmarksOn(documentId);
    if (ids.length != existing.length ||
        ids.toSet().length != ids.length ||
        !existing.every((b) => ids.contains(b.id))) {
      return c;
    }
    final positions = {for (final (index, id) in ids.indexed) id: index};
    return c.copyWith(
      bookmarks: [for (final b in c.bookmarks) b.documentId == documentId ? b.copyWith(order: positions[b.id]) : b],
    );
  }

  StudySetContent setDocumentOutline(StudySetContent c, String documentId, List<PdfOutlineEntry> items) {
    final doc = c.document(documentId);
    if (doc == null) return c;
    final entries = OutlineTree.flatten(items).toList();
    if (entries.map((e) => e.id).toSet().length != entries.length ||
        entries.any((e) => e.position is! TextReadingPosition && (e.page < 0 || e.page > doc.pageCount))) {
      return c;
    }
    return c.copyWith(
      documentOutlines: [
        for (final o in c.documentOutlines)
          if (o.documentId != documentId) o,
        DocumentOutline(documentId: documentId, items: items),
      ],
    );
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
    assistantReceipts: current.assistantReceipts,
    reviews: current.reviews,
    reviewLogs: current.reviewLogs,
    memoryStates: current.memoryStates,
    documents: [
      for (final d in snapshot.documents)
        if (current.document(d.id) case final now?)
          d.copyWith(
            lastPage: now.lastPage,
            readingPosition: now.readingPosition,
            lastReadAt: now.lastReadAt,
            cropSuggestionDismissed: now.cropSuggestionDismissed,
          )
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
    for (final annotationId in areas) {
      c = archiveNoteSource(c, annotationId);
    }
    return _keepSummaries(
      c,
      c.copyWith(
        summaries: [
          for (final s in c.summaries)
            if (s.mapId != mapId || !kill.contains(s.cardId)) s,
        ],
        marginNotes: [
          for (final note in c.marginNotes)
            (note.mapId ?? MindMap.defaultId) == mapId && kill.contains(note.nodeId)
                ? note.copyWith(nodeId: null, mapId: null)
                : note,
        ],
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
    c = archiveNoteSource(c, annotationId);
    final cards = c.cards.where(
      (card) => card.annotationId == annotationId || card.segments.any((s) => s.annotationId == annotationId),
    );
    var without = c;
    for (final card in cards) {
      if (card.segments.length > 1) {
        // Removing one source must not delete excerpts from other documents.
        // Keep the captured text as own words after its highlight disappears.
        final segments = [
          for (final s in card.segments) s.annotationId == annotationId ? s.copyWith(annotationId: null) : s,
        ];
        final firstSource = segments.where((s) => s.annotationId != null).firstOrNull?.annotationId;
        final changed = card.copyWith(
          segments: segments,
          annotationId: firstSource,
          kind: firstSource == null ? CardKind.topic : card.kind,
          title: firstSource == null ? segments.map((s) => s.text).join('\n') : card.title,
        );
        without = without.copyWith(cards: [for (final old in without.cards) old.id == card.id ? changed : old]);
      } else {
        for (final map in c.maps) {
          without = StudySetEditor(newId: newId, now: now, mapId: map.id).removeFromMap(without, card.id);
        }
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
        for (final s in c.summaries.where((s) => s.mapId == mapId && s.parentId == id && s.cardId != null)) {
          if (result.add(s.cardId!)) next.add(s.cardId!);
        }
      }
      frontier = next;
    }
    return result;
  }
}
