import 'document_outline.dart';
import 'models.dart';
import 'note_format.dart';
import 'research.dart';
import 'reading.dart';
import 'study_note.dart';
import 'study_set_content.dart';
import 'text_anchor.dart';

/// Text already extracted by the reader, OCR or book parser. No I/O in core.
class NoteTextSource {
  const NoteTextSource({this.chapters = const {}, this.pages = const {}});

  /// Document ID -> chapter ID -> canonical text (UTF-16 anchor offsets).
  final Map<String, Map<String, String>> chapters;

  /// Document ID -> one-based PDF page -> extracted text.
  final Map<String, Map<int, String>> pages;
}

/// Context is separate from the immutable, verbatim quote.
class NoteContext {
  const NoteContext({
    this.before = '',
    this.after = '',
    this.fragment = false,
    this.noText = false,
    this.unresolved = false,
  });
  final String before, after;
  final bool fragment, noText;

  /// Text exists but the anchor could not be located unambiguously.
  final bool unresolved;
  Map<String, Object?> toJson() => {
    'before': before,
    'after': after,
    'fragment': fragment,
    'noText': noText,
    'unresolved': unresolved,
  };
}

/// A short ID is scoped to this collection; it must survive outline/write/place.
class NoteMaterial {
  const NoteMaterial({
    required this.ref,
    required this.sourceId,
    required this.text,
    required this.groupKey,
    required this.groupTitle,
    required this.createdAt,
    this.documentId,
    this.annotationId,
    this.source,
    this.origin = NoteOrigin.user,
    this.context = const NoteContext(),
    this.branchKey,
    this.branchTitle,
    this.mapOrder = 0,
  });
  final String ref, sourceId, text, groupKey, groupTitle;
  final String? documentId, annotationId, branchKey, branchTitle;

  /// Null means a highlight; otherwise identifies the live source of an OwnBlock.
  final OwnSource? source;
  final NoteOrigin origin;
  final NoteContext context;
  final DateTime createdAt;
  final int mapOrder;
  bool get isHighlight => source == null;
  Map<String, Object?> toJson() => {
    'id': ref,
    'source': source?.name ?? 'highlight',
    'text': text,
    'group': groupKey,
    'title': groupTitle,
    'context': context.toJson(),
    'origin': origin.name,
  };
}

/// An immutable ID dictionary, including the collection's cutoff time.
class NoteMaterials {
  NoteMaterials(List<NoteMaterial> items, {required this.collectedAt, List<NoteMaterial>? catalog})
    : items = List.unmodifiable(items),
      catalog = List.unmodifiable(catalog ?? items) {
    if (items.map((m) => m.ref).toSet().length != items.length) throw ArgumentError('Duplicate material ID');
  }
  final List<NoteMaterial> items;

  /// Full collection retained for deterministic placement relative to existing quotes.
  final List<NoteMaterial> catalog;
  final DateTime collectedAt;
  NoteMaterial? operator [](String ref) => items.where((m) => m.ref == ref).firstOrNull;
  List<NoteMaterial> get highlights => items.where((m) => m.isHighlight).toList();

  /// Strictly newer than the completed organization; preserves short IDs.
  NoteMaterials since(DateTime cutoff) => NoteMaterials(
    items.where((m) => m.createdAt.isAfter(cutoff)).toList(),
    collectedAt: collectedAt,
    catalog: catalog,
  );
}

/// Collects scoped highlights and optional notes in deterministic reading order.
class NoteMaterialCollector {
  const NoteMaterialCollector();

  /// Uses an injected clock and text snapshot for reproducible previews and exports.
  NoteMaterials collect(
    StudySetContent content,
    NoteScope scope,
    NoteSettings settings, {
    required DateTime now,
    NoteTextSource text = const NoteTextSource(),
  }) {
    final branch = scope is BranchScope ? content.branch(scope.nodeId, mapId: scope.mapId) : null;
    final mapId = scope is BranchScope ? scope.mapId : settings.mapId;
    final order = <String, int>{}, branches = <String, String>{};
    final visited = <String>{};
    void walk(String? parent, String? root) {
      for (final node in content.childrenOf(parent, mapId: mapId)) {
        if (!visited.add(node.cardId)) continue;
        order[node.cardId] = order.length;
        final group = content.card(node.cardId)?.kind == CardKind.topic ? node.cardId : root ?? node.cardId;
        branches[node.cardId] = group;
        walk(node.cardId, group);
      }
    }

    walk(null, null);
    List<String> cardsFor(Annotation a) => content.segmentsForAnnotation(a.id).map((m) => m.card.id).toList();
    bool include(Annotation a) => switch (scope) {
      SelectedAnnotations(:final ids) => ids.contains(a.id),
      WholeSet() => true,
      DocumentScope(:final id) => a.documentId == id,
      BranchScope() => cardsFor(a).any(branch!.contains),
      SinceScope(:final date) => !a.createdAt.isBefore(date),
    };
    final annotations = content.annotations.where((a) => a.quote.trim().isNotEmpty && include(a)).toList();
    final docOrder = {for (final (i, d) in content.documents.indexed) d.id: i};
    annotations.sort((a, b) {
      final byDoc = (docOrder[a.documentId] ?? -1).compareTo(docOrder[b.documentId] ?? -1);
      if (byDoc != 0) return byDoc;
      int pos;
      if (a.isText && b.isText) {
        final chapters = text.chapters[a.documentId]?.keys.toList() ?? const <String>[];
        final aa = a.textAnchors.first, bb = b.textAnchors.first;
        pos = aa.chapterId == bb.chapterId
            ? aa.start.compareTo(bb.start)
            : chapters.indexOf(aa.chapterId).compareTo(chapters.indexOf(bb.chapterId));
      } else if (!a.isText && !b.isText) {
        pos = a.page.compareTo(b.page);
        if (pos == 0 && a.rects.isNotEmpty && b.rects.isNotEmpty) pos = b.rects.first.top.compareTo(a.rects.first.top);
      } else {
        pos = a.isText ? 1 : -1;
      }
      if (pos != 0) return pos;
      pos = a.createdAt.compareTo(b.createdAt);
      return pos != 0 ? pos : a.id.compareTo(b.id);
    });
    final items = <NoteMaterial>[];
    for (final a in annotations) {
      final section = _section(content, a);
      final card = cardsFor(a)
          .where((id) => order.containsKey(id) && (branch == null || branch.contains(id)))
          .firstOrNull;
      final root = branches[card];
      items.add(
        NoteMaterial(
          ref: 'h${items.length + 1}',
          sourceId: a.id,
          annotationId: a.id,
          text: a.quote,
          documentId: a.documentId,
          origin: NoteOrigin.excerpt,
          createdAt: a.createdAt,
          groupKey: '${a.documentId}:${section?.id ?? (a.isText ? a.textAnchors.first.chapterId : '')}',
          groupTitle: section?.title ?? content.document(a.documentId)?.title ?? a.documentId,
          branchKey: root,
          branchTitle: content.card(root ?? '')?.title,
          mapOrder: order[card] ?? 0x7fffffff,
          context: contextFor(content, a, settings.contextSentences, text: text),
        ),
      );
    }
    final selectedIds = annotations.map((a) => a.id).toSet();
    NoteMaterial? related(String? documentId, String? quote, String? cardId, AnnotationAnchor? anchor) {
      final ancestors = <String>{};
      var cursor = cardId;
      while (cursor != null && ancestors.add(cursor)) {
        cursor = content.node(cursor, mapId: mapId)?.parentId;
      }
      final matches = items.where((m) {
        if (!m.isHighlight) return false;
        if (ancestors.isNotEmpty &&
            content.segmentsForAnnotation(m.sourceId).any((v) => ancestors.contains(v.card.id))) {
          return true;
        }
        if (quote == null || m.documentId != documentId || m.text != quote) return false;
        final a = content.annotation(m.sourceId)!;
        if (anchor == null) return false;
        if (a.isText) {
          return anchor.textAnchors.any(
            (n) => a.textAnchors.any((h) => n.chapterId == h.chapterId && n.start < h.end && n.end > h.start),
          );
        }
        return anchor.pages.any(
          (n) => a.pages.any(
            (h) =>
                n.page == h.page &&
                n.rects.any(
                  (nr) => h.rects.any(
                    (hr) => nr.left < hr.right && nr.right > hr.left && nr.bottom < hr.top && nr.top > hr.bottom,
                  ),
                ),
          ),
        );
      }).toList();
      return matches.length == 1 ? matches.single : null;
    }

    bool ownInScope(DateTime created, String? doc, String? cardId, NoteMaterial? near) => switch (scope) {
      WholeSet() => true,
      DocumentScope(:final id) => doc == id || near?.documentId == id,
      SinceScope(:final date) => !created.isBefore(date),
      SelectedAnnotations() => near != null && selectedIds.contains(near.sourceId),
      BranchScope() => (cardId != null && branch!.contains(cardId)) || near != null,
    };
    var ownIndex = 0;
    void addOwn(
      String id,
      String body,
      OwnSource source,
      DateTime created, {
      String? documentId,
      String? cardId,
      String? quote,
      AnnotationAnchor? anchor,
      int? page,
      NoteOrigin origin = NoteOrigin.user,
    }) {
      final near = related(documentId, quote, cardId, anchor);
      final position = documentId == null
          ? null
          : Annotation(
              id: id,
              documentId: documentId,
              textAnchors: anchor?.textAnchors ?? const [],
              page: anchor?.textAnchors.isNotEmpty == true ? null : page ?? 1,
              rects: anchor?.textAnchors.isNotEmpty == true ? null : const [],
              quote: quote ?? '',
              colorIndex: 0,
              createdAt: created,
            );
      final chapter = position == null ? null : _section(content, position);
      if (!ownInScope(created, documentId, cardId, near)) return;
      final root = branches[cardId];
      items.add(
        NoteMaterial(
          ref: 'n${++ownIndex}',
          sourceId: id,
          source: source,
          text: body,
          annotationId: near?.annotationId,
          documentId: documentId ?? near?.documentId,
          createdAt: created,
          origin: origin,
          groupKey: near?.groupKey ?? '${documentId ?? 'notes'}:${chapter?.id ?? ''}',
          groupTitle: near?.groupTitle ?? chapter?.title ?? content.document(documentId ?? '')?.title ?? '笔记',
          branchKey: root ?? near?.branchKey,
          branchTitle: content.card(root ?? '')?.title ?? near?.branchTitle,
          mapOrder: order[cardId] ?? near?.mapOrder ?? 0x7fffffff,
        ),
      );
    }

    if (settings.marginNotes) {
      for (final n in content.marginNotes) {
        addOwn(
          n.id,
          n.text,
          OwnSource.marginNote,
          n.createdAt,
          documentId: n.documentId,
          cardId: n.nodeId,
          quote: n.anchor?.quote,
          anchor: n.anchor,
          page: n.anchor?.textAnchors.isNotEmpty == true ? null : n.page,
        );
      }
    }
    for (final c in content.cards) {
      if (!order.containsKey(c.id)) continue;
      final a = content.annotation(c.annotationId ?? '');
      if (settings.mapNotes && c.kind == CardKind.note) {
        addOwn(
          c.id,
          [
            notePlainText(c.title, c.textFormat),
            notePlainText(c.body, c.textFormat),
          ].where((s) => s.isNotEmpty).join('\n'),
          OwnSource.card,
          c.createdAt,
          cardId: c.id,
          documentId: a?.documentId,
        );
      }
      if (settings.images && c.kind == CardKind.image) {
        addOwn(c.id, c.imageFileName ?? '', OwnSource.image, c.createdAt, cardId: c.id, documentId: a?.documentId);
      }
      if (settings.researchNotes && c.researchNoteId != null) {
        final n = content.researchNote(c.researchNoteId!);
        if (n != null && !items.any((m) => m.source == OwnSource.researchNote && m.sourceId == n.id)) {
          addOwn(n.id, n.body, OwnSource.researchNote, n.createdAt, cardId: c.id, origin: n.origin);
        }
      }
    }
    if (settings.researchNotes) {
      for (final attachment in content.noteAttachments) {
        final n = content.researchNote(attachment.noteId);
        if (n == null || items.any((m) => m.source == OwnSource.researchNote && m.sourceId == n.id)) continue;
        switch (attachment.target) {
          case PdfTarget(:final documentId, :final pages, :final quote):
            AnnotationAnchor? anchor;
            try {
              anchor = AnnotationAnchor(pages: pages, quote: quote);
            } on ArgumentError {
              /* Legacy unlocatable target. */
            }
            addOwn(
              n.id,
              n.body,
              OwnSource.researchNote,
              n.createdAt,
              documentId: documentId,
              page: pages.firstOrNull?.page,
              quote: quote,
              anchor: anchor,
              origin: n.origin,
            );
          case TextTarget(:final documentId, :final textAnchors):
            final quote = textAnchors.map((a) => a.quote).join();
            addOwn(
              n.id,
              n.body,
              OwnSource.researchNote,
              n.createdAt,
              documentId: documentId,
              quote: quote,
              anchor: AnnotationAnchor(textAnchors: textAnchors, quote: quote),
              origin: n.origin,
            );
          case CardTarget(:final cardId):
            if (order.containsKey(cardId)) {
              addOwn(n.id, n.body, OwnSource.researchNote, n.createdAt, cardId: cardId, origin: n.origin);
            }
        }
      }
    }
    if (settings.researchNotes && (scope is WholeSet || scope is SinceScope)) {
      for (final n in content.researchNotes) {
        if (!items.any((m) => m.source == OwnSource.researchNote && m.sourceId == n.id)) {
          addOwn(n.id, n.body, OwnSource.researchNote, n.createdAt, origin: n.origin);
        }
      }
    }
    return NoteMaterials(items, collectedAt: now);
  }

  /// Local heuristic only; it never rewrites a quote.
  static bool isFragment(String quote) {
    final s = quote.trim();
    return s.runes.length < 12 || RegExp(r'^(这|那|它|其|此|该|上述|以上|但是|因此|所以|然而|不过|而且)').hasMatch(s);
  }

  /// A human-readable source location; storage chapter IDs are never display labels.
  String? sectionTitle(StudySetContent content, Annotation annotation) => _section(content, annotation)?.title;

  PdfOutlineEntry? _section(StudySetContent c, Annotation a) {
    PdfOutlineEntry? result;
    for (final e in OutlineTree.flatten(c.outlineOn(a.documentId)?.items ?? const [])) {
      if (a.isText) {
        final p = e.position, anchor = a.textAnchors.first;
        if (p is TextReadingPosition &&
            p.chapterId == anchor.chapterId &&
            p.offset <= anchor.start &&
            (result == null || (result.position as TextReadingPosition).offset <= p.offset)) {
          result = e;
        }
      } else if (e.position is! TextReadingPosition &&
          e.page > 0 &&
          e.page <= a.page &&
          (result == null || result.page <= e.page)) {
        result = e;
      }
    }
    return result;
  }

  /// Takes complete surrounding sentences, clipped to the current chapter.
  /// Ambiguous PDF matches and stale text anchors never produce guessed context.
  NoteContext contextFor(
    StudySetContent c,
    Annotation a,
    int sentences, {
    NoteTextSource text = const NoteTextSource(),
  }) {
    if (sentences < 0 || sentences > 3) throw ArgumentError.value(sentences);
    final fragment = isFragment(a.quote);
    String? body;
    int start = -1, end = -1;
    if (a.isText) {
      final first = a.textAnchors.first, last = a.textAnchors.last;
      body = text.chapters[a.documentId]?[first.chapterId];
      if (body != null &&
          first.chapterId == last.chapterId &&
          first.start <= last.start &&
          a.textAnchors.every(
            (anchor) =>
                anchor.chapterId == first.chapterId &&
                anchor.end <= body!.length &&
                body.substring(anchor.start, anchor.end) == anchor.quote,
          )) {
        start = first.start;
        end = last.end;
        var lo = 0, hi = body.length;
        for (final e in OutlineTree.flatten(c.outlineOn(a.documentId)?.items ?? const [])) {
          final p = e.position;
          if (p is! TextReadingPosition || p.chapterId != first.chapterId) continue;
          if (p.offset <= start && p.offset > lo) lo = p.offset;
          if (p.offset > start && p.offset < hi) hi = p.offset;
        }
        if (end > hi) return NoteContext(fragment: fragment, unresolved: true);
        body = body.substring(lo, hi);
        start -= lo;
        end -= lo;
      }
    } else {
      final pages = text.pages[a.documentId];
      final section = _section(c, a);
      var lo = section?.page ?? 1;
      var hi = c.document(a.documentId)?.pageCount ?? a.pages.last.page;
      for (final e in OutlineTree.flatten(c.outlineOn(a.documentId)?.items ?? const [])) {
        if (e.position is! TextReadingPosition && e.page > a.page && e.page <= hi) hi = e.page - 1;
      }
      // A page-level destination has no character offset. On a boundary page,
      // restrict to the quote rather than borrowing text from another chapter.
      final starts = OutlineTree.flatten(c.outlineOn(a.documentId)?.items ?? const [])
          .where((e) => e.position is! TextReadingPosition && e.page == a.page)
          .toList();
      final ambiguous =
          starts.length > 1 ||
          starts.any((e) => e.page > 1 || (e.position is PdfPosition && ((e.position as PdfPosition).y ?? 0) > 0));
      // A previous boundary page can contain the tail of the preceding chapter.
      if (lo > 1 && lo < a.page) lo++;
      if (pages != null && pages[a.page]?.trim().isNotEmpty == true) {
        final selectedPages = [for (var page = a.page; page <= a.pages.last.page; page++) pages[page]];
        final pageText = selectedPages.whereType<String>().join('\n');
        body = pageText;
        final at = a.quote.isEmpty ? -1 : pageText.indexOf(a.quote);
        final complete = selectedPages.every((value) => value != null) && a.pages.last.page <= hi;
        if (complete && at >= 0 && at < pages[a.page]!.length && pageText.indexOf(a.quote, at + 1) < 0 && !ambiguous) {
          var before = '', after = '';
          for (var page = a.page - 1; page >= lo; page--) {
            final value = pages[page];
            if (value == null) break;
            before = '$value\n$before';
            if (RegExp(r'[。！？.!?]').allMatches(before).length >= sentences + 1) break;
          }
          for (var page = a.pages.last.page + 1; page <= hi; page++) {
            final value = pages[page];
            if (value == null) break;
            after += '\n$value';
            if (RegExp(r'[。！？.!?]').allMatches(after).length >= sentences + 1) break;
          }
          body = '$before$pageText$after';
          start = before.length + at;
          end = start + a.quote.length;
        }
      }
    }
    if (body == null || body.trim().isEmpty) return NoteContext(fragment: fragment, noText: true);
    if (start < 0) return NoteContext(fragment: fragment, unresolved: true);
    if (sentences == 0) return NoteContext(fragment: fragment);
    final spans = RegExp(r'[^。！？.!?]+[。！？.!?]*|[。！？.!?]+').allMatches(body).toList();
    final first = spans.indexWhere((s) => s.end > start);
    final last = spans.lastIndexWhere((s) => s.start < end);
    if (first < 0 || last < 0) return NoteContext(fragment: fragment, unresolved: true);
    final from = spans[(first - sentences).clamp(0, spans.length - 1)].start;
    final to = spans[(last + sentences).clamp(0, spans.length - 1)].end;
    return NoteContext(
      before: body.substring(from, start).trim(),
      after: body.substring(end, to).trim(),
      fragment: fragment,
    );
  }
}
