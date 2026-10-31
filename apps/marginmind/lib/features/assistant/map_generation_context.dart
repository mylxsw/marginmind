import 'dart:convert';
import 'dart:math' as math;

import 'package:mm_core/mm_core.dart';
import 'package:mm_assistant/mm_assistant.dart' show mapChapterPayload, mapChapterSystemPrompt;

import '../workspace/reflow_document.dart';

/// A complete, frozen read plan. Chapter fingerprints drive incremental cache reuse.
class DocumentDigest {
  DocumentDigest({required this.source, required List<MapDigestChapter> chapters})
    : chapters = List.unmodifiable(chapters);
  final MapSource source;
  final List<MapDigestChapter> chapters;
}

class MapDigestChapter {
  const MapDigestChapter({required this.input, required this.fingerprint});
  final MapChapterInput input;
  final String fingerprint;
}

/// Explicit result for image-only PDFs; callers can offer the existing OCR flow.
class MapDigestNeedsText implements Exception {
  const MapDigestNeedsText(this.documentId);
  final String documentId;
  String get message => '需要识别文字';
}

/// PDF text comes from the workspace reader (including existing OCR). Reflow
/// formats share canonical Book IR, avoiding PDF-only page accessors.
class DocumentDigestBuilder {
  const DocumentDigestBuilder(this.reader, {this.repository, this.loadOutline});
  final StudySetReader reader;
  final DocumentRepository? repository;
  final Future<DocumentOutline?> Function(Document, CancellationToken)? loadOutline;

  Future<DocumentDigest> build(
    StudySetContent snapshot, {
    required String studySetId,
    required String documentId,
    required String mapId,
    required String draftPrefix,
    String documentAlias = 'D1',
    List<String> chapters = const [],
    bool includeAnnotations = true,
    MapOrganization organization = MapOrganization.chapter,
    String? instructions,
    int inputCharacters = 24000,
    CancellationToken? cancellation,
  }) async {
    final cancel = cancellation ?? CancellationToken();
    cancel.check();
    final document = snapshot.document(documentId);
    if (document == null || inputCharacters < 1024) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    final units = <_DigestUnit>[];
    final reflow = document.contentManifest != null;
    DocumentOutline? outline = snapshot.outlineOn(documentId);
    if (reflow) {
      final repo = repository;
      if (repo == null) throw const ResearchFailure(ResearchFailureKind.unavailable, 'documentRepositoryRequired');
      final book = await cancel.bind(ReflowDocument.load(repo, studySetId, document));
      for (final (i, chapter) in book.chapters.indexed) {
        units.add(_DigestUnit(i + 1, chapter.id, chapter.canonicalText));
      }
      outline ??= DocumentOutline(
        documentId: documentId,
        items: [for (final entry in book.toc) _bookOutline(book, entry.id)],
      );
    } else {
      final scope = ReadScope(studySetId: studySetId, documents: {documentId});
      for (var p = 1; p <= document.pageCount; p++) {
        cancel.check();
        final result = await cancel.bind(reader.readPages(documentId, p, p, scope, cancel));
        units.add(
          _DigestUnit(
            p,
            'page-$p',
            result.where((r) => r.documentId == documentId && r.page == p).map((r) => r.text).join('\n'),
          ),
        );
      }
      outline ??= await cancel.bind(loadOutline?.call(document, cancel) ?? Future.value(null));
    }
    cancel.check();
    if (units.every((u) => u.text.trim().isEmpty)) {
      if (document.format == DocumentFormat.pdf) throw MapDigestNeedsText(documentId);
      throw const ResearchFailure(ResearchFailureKind.protocol, 'noDocumentText');
    }
    var length = 0;
    for (final unit in units) {
      unit.start = length;
      length += unit.text.length;
    }
    int? offset(PdfOutlineEntry e) {
      if (e.position case TextReadingPosition(:final chapterId, :final offset)) {
        final unit = units.where((u) => u.chapter == chapterId).firstOrNull;
        return unit == null ? null : unit.start + offset.clamp(0, unit.text.length);
      }
      return units.where((u) => u.page == e.page).firstOrNull?.start;
    }

    final entries = OutlineTree.flatten(outline?.items ?? []).where((e) => offset(e) != null).toList()
      ..sort((a, b) => offset(a)!.compareTo(offset(b)!));
    if (chapters.any((id) => !entries.any((e) => e.id == id))) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest, 'unknownChapter');
    }
    final selected = <String>{};
    for (final e in entries.where((e) => chapters.contains(e.id))) {
      selected.addAll(OutlineTree.flatten([e]).map((e) => e.id));
    }
    final ranges = <({String id, int start, int end})>[];
    if (entries.isEmpty) {
      for (final u in units) {
        ranges.add((id: u.chapter, start: u.start, end: u.start + u.text.length));
      }
    } else {
      if (chapters.isEmpty && offset(entries.first)! > 0) {
        ranges.add((id: 'preface', start: 0, end: offset(entries.first)!));
      }
      for (var i = 0; i < entries.length; i++) {
        if (chapters.isNotEmpty && !selected.contains(entries[i].id)) continue;
        final start = offset(entries[i])!, end = i + 1 < entries.length ? offset(entries[i + 1])! : length;
        if (end > start) ranges.add((id: entries[i].id, start: start, end: end));
      }
    }
    final annotations = snapshot.annotations.where((a) => a.documentId == documentId).toList();
    final notes = <String, Object?>{};
    final comments = <_DigestComment>[];
    for (final n in snapshot.marginNotes.where((n) => n.documentId == documentId)) {
      comments.add(
        _DigestComment(
          n.text,
          n.anchor?.textAnchors.map((a) => a.chapterId).toSet() ?? {},
          n.anchor?.textAnchors.isNotEmpty == true ? {} : {n.page},
        ),
      );
      notes[n.id] = {
        'text': n.text,
        'anchor': n.anchor?.toJson(),
        if (n.anchor?.textAnchors.isNotEmpty != true) 'page': n.page,
        'lineY': n.lineY,
      };
    }
    for (final a in snapshot.noteAttachments) {
      final target = a.target;
      final matches = switch (target) {
        PdfTarget(:final documentId) || TextTarget(:final documentId) => documentId == document.id,
        CardTarget(:final cardId) =>
          snapshot.card(cardId) != null &&
              snapshot.segmentsOf(snapshot.card(cardId)!).any((s) => annotations.any((a) => a.id == s.annotationId)),
      };
      if (matches) {
        final text = snapshot.researchNote(a.noteId)?.body ?? '';
        notes[a.id] = {'text': text, 'target': target.toJson()};
        switch (target) {
          case PdfTarget(:final pages):
            comments.add(_DigestComment(text, {}, pages.map((p) => p.page).toSet()));
          case TextTarget(:final textAnchors):
            comments.add(_DigestComment(text, textAnchors.map((a) => a.chapterId).toSet(), {}));
          case CardTarget(:final cardId):
            final card = snapshot.card(cardId)!;
            for (final mark in annotations.where((a) => snapshot.segmentsOf(card).any((s) => s.annotationId == a.id))) {
              comments.add(
                _DigestComment(
                  text,
                  mark.textAnchors.map((a) => a.chapterId).toSet(),
                  mark.isText ? {} : mark.pages.map((p) => p.page).toSet(),
                ),
              );
            }
        }
      }
    }
    final annotationData = {
      for (final a in annotations)
        a.id: {
          'quote': a.quote,
          'kind': a.kind.name,
          if (a.isText)
            'textAnchors': a.textAnchors.map((a) => a.toJson()).toList()
          else
            'pages': a.pages.map((p) => p.toJson()).toList(),
        },
    };
    var readThrough = document.lastPage.clamp(1, math.max(1, units.length));
    if (document.readingPosition case TextReadingPosition(:final chapterId)) {
      readThrough = units.where((u) => u.chapter == chapterId).firstOrNull?.page ?? 1;
    }
    final source = MapSource(
      documentId: documentId,
      chapters: chapters,
      fingerprint: mapSourceFingerprint(
        pageCount: units.length,
        textHash: mapContentHash([
          for (final u in units) [u.page, u.text],
        ]),
        annotations: annotationData,
        notes: notes,
      ),
      readThrough: readThrough.toInt(),
    );
    final result = <MapDigestChapter>[];
    for (final range in ranges) {
      // Count encoded characters rather than assuming a multiplier for CJK.
      final bodyLimit = inputCharacters ~/ 2, annotationLimit = inputCharacters ~/ 5;
      var part = 0;
      for (var start = range.start; start < range.end;) {
        final slice = _slicePages(units, start, range.end, bodyLimit);
        final end = slice.end, pages = slice.pages, unitIds = slice.unitIds;
        final aliases = <String, String>{}, texts = <String, String>{};
        bool addText(String alias, String text) {
          final available =
              annotationLimit - jsonEncode(texts).length - (texts.isEmpty ? 0 : 1) - jsonEncode(alias).length - 1 - 2;
          if (available <= 0) return false;
          final end = _encodedEnd(text, 0, text.length, available);
          if (end == 0) return false;
          texts[alias] = text.substring(0, end);
          return true;
        }

        if (includeAnnotations) {
          for (final a in annotations) {
            final matches = a.isText
                ? a.textAnchors.any((t) => unitIds.contains(t.chapterId))
                : a.pages.any((p) => pages.containsKey(p.page));
            if (!matches) continue;
            final text = jsonEncode({
              'quote': a.quote,
              'kind': a.kind.name,
              if (!a.isText) 'pages': a.pages.map((p) => p.page).toList(),
            });
            final alias = 'A${aliases.length + 1}';
            if (!addText(alias, text)) break;
            aliases[alias] = a.id;
          }
          // Independent document notes also belong to the reading context, but
          // never receive annotation aliases (they cannot be attached as excerpts).
          for (final (index, note)
              in comments.where((n) => n.pages.any(pages.containsKey) || n.chapters.any(unitIds.contains)).indexed) {
            if (!addText('comment${index + 1}', note.text)) break;
          }
        }
        final chapterId = '$documentId:${range.id}:${part++}';
        final ctx = MapLineContext(
          phase: MapLinePhase.chapter,
          mapId: mapId,
          draftPrefix: '$draftPrefix${result.length}-',
          documents: {documentAlias: documentId},
          // Reflow units are canonical spine sections, not physical pages.
          pages: {documentAlias: reflow ? <int>{} : pages.keys.toSet()},
          annotations: aliases,
        );
        final input = MapChapterInput(
          chapterId: chapterId,
          documentAlias: documentAlias,
          context: ctx,
          textByPage: pages,
          annotations: texts,
          organization: organization,
          instructions: instructions,
        );
        if (mapChapterSystemPrompt.length + jsonEncode(mapChapterPayload(input)).length > inputCharacters) {
          throw const ResearchFailure(ResearchFailureKind.budget, 'chapterMetadataExceedsBudget');
        }
        result.add(
          MapDigestChapter(
            input: input,
            fingerprint: mapContentHash({
              'pages': {for (final e in pages.entries) '${e.key}': e.value},
              'annotations': texts,
              'anchors': {for (final id in aliases.values) id: annotationData[id]},
              'aliases': aliases,
              'progress': [
                for (final p in pages.keys)
                  if (p <= readThrough) p,
              ],
              'textProgress': switch (document.readingPosition) {
                TextReadingPosition(:final chapterId, :final offset) when unitIds.contains(chapterId) => offset,
                _ => null,
              },
            }),
          ),
        );
        start = end;
      }
    }
    cancel.check();
    return DocumentDigest(source: source, chapters: result);
  }
}

// Largest rune-aligned prefix whose JSON string contents fit the allowance.
// JSON encodes CJK verbatim; only controls, quotes and backslashes expand.
int _encodedEnd(String text, int start, int end, int allowance) {
  var i = start, used = 0;
  while (i < end) {
    final c = text.codeUnitAt(i);
    final width =
        c >= 0xd800 &&
            c <= 0xdbff &&
            i + 1 < end &&
            text.codeUnitAt(i + 1) >= 0xdc00 &&
            text.codeUnitAt(i + 1) <= 0xdfff
        ? 2
        : 1;
    final cost = switch (c) {
      34 || 92 || 8 || 9 || 10 || 12 || 13 => 2,
      < 32 => 6,
      >= 0xd800 && <= 0xdfff when width == 1 => 6,
      _ => width,
    };
    if (used + cost > allowance) break;
    used += cost;
    i += width;
  }
  return i;
}

({int end, Map<int, String> pages, Set<String> unitIds}) _slicePages(
  List<_DigestUnit> units,
  int start,
  int end,
  int allowance,
) {
  final pages = <int, String>{}, unitIds = <String>{};
  var used = 2, through = start; // JSON object braces.
  for (final u in units) {
    final a = math.max(start, u.start), b = math.min(end, u.start + u.text.length);
    if (b <= a) continue;
    final overhead = jsonEncode('${u.page}').length + 1 + 2 + (pages.isEmpty ? 0 : 1);
    final stop = _encodedEnd(u.text, a - u.start, b - u.start, allowance - used - overhead);
    if (stop == a - u.start) break;
    final text = u.text.substring(a - u.start, stop);
    pages[u.page] = text;
    unitIds.add(u.chapter);
    used += overhead + jsonEncode(text).length - 2;
    through = u.start + stop;
    if (through < b) break;
  }
  if (through == start) throw const ResearchFailure(ResearchFailureKind.budget, 'chapterTextExceedsBudget');
  return (end: through, pages: pages, unitIds: unitIds);
}

PdfOutlineEntry _bookOutline(ReflowDocument book, String id) {
  final e = book.outline.firstWhere((e) => e.id == id);
  return PdfOutlineEntry(
    id: e.id,
    title: e.title,
    position: book.position(e.chapterId, e.offset),
    children: [for (final child in e.children) _bookOutline(book, child.id)],
  );
}

class _DigestUnit {
  _DigestUnit(this.page, this.chapter, this.text);
  final int page;
  final String chapter, text;
  int start = 0;
}

class _DigestComment {
  const _DigestComment(this.text, this.chapters, this.pages);
  final String text;
  final Set<String> chapters;
  final Set<int> pages;
}
