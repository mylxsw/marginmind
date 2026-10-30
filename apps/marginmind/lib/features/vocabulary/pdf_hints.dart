import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'hint_card.dart';
import 'hint_geometry.dart';
import 'vocabulary_controller.dart';
import 'vocabulary_hints.dart';
import 'vocabulary_source_flash.dart';

/// Loads only visible PDF pages and their immediate neighbors. Viewport events
/// are coalesced; stale document/OCR requests cannot publish into a new view.
class PdfVocabularyHints extends ConsumerStatefulWidget {
  const PdfVocabularyHints({
    super.key,
    required this.studySetId,
    required this.documentId,
    required this.pdf,
    required this.builder,
  });
  final String studySetId, documentId;
  final MMPdfViewController pdf;
  final Widget Function(List<MMPdfHighlight>, void Function(String, Rect), VoidCallback) builder;
  @override
  ConsumerState<PdfVocabularyHints> createState() => _PdfVocabularyHintsState();
}

class _PdfVocabularyHintsState extends ConsumerState<PdfVocabularyHints> {
  final _pages = <int, TranslationPage>{};
  final _cache = VocabularyMatchCache();
  final _geometry = <int, (int, bool, List<VocabularyHit>, Map<VocabularyHit, double>)>{};
  List<VocabularyHit> _hits = [];
  bool _queued = false, _loading = false, _dirty = false;
  @override
  void initState() {
    super.initState();
    widget.pdf.addListener(_schedule);
    _schedule();
  }

  @override
  void dispose() {
    widget.pdf.removeListener(_schedule);
    _cache.clear();
    super.dispose();
  }

  void _schedule() {
    _dirty = true;
    if (_queued || !mounted) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      do {
        _dirty = false;
        final prefs = ref.read(vocabularyHintProvider);
        if (prefs.modeFor(widget.documentId) == VocabularyHintMode.off &&
            ref.read(vocabularyAddedFlashProvider) == null) {
          if (_pages.isNotEmpty) {
            setState(() {
              _pages.clear();
              _geometry.clear();
            });
          }
          return;
        }
        final visible = widget.pdf.visiblePages(neighbors: true);
        var changed = false;
        for (final number in visible) {
          if (_pages.containsKey(number)) continue;
          final page = await widget.pdf.translationPage(number);
          if (!mounted) return;
          if (page != null) {
            _pages[number] = page;
            changed = true;
          }
        }
        if (!mounted) return;
        final keep = widget.pdf.visiblePages(neighbors: true).toSet();
        if (_pages.keys.any((key) => !keep.contains(key))) changed = true;
        _pages.removeWhere((key, _) => !keep.contains(key));
        _geometry.removeWhere((key, _) => !keep.contains(key));
        if (changed) setState(() {});
      } while (_dirty && mounted);
    } finally {
      _loading = false;
    }
  }

  void _tap(String id, Rect bounds) {
    if (ref.read(vocabularyHintProvider).modeFor(widget.documentId) == VocabularyHintMode.off) return;
    final index = int.tryParse(id.substring('vocabulary:'.length));
    if (index == null || index < 0 || index >= _hits.length) return;
    final hit = _hits[index];
    widget.pdf.clearSelection();
    showVocabularyHit(
      context,
      studySetId: widget.studySetId,
      anchor: bounds.shift((context.findRenderObject() as RenderBox).localToGlobal(Offset.zero)),
      hit: hit,
      occurrences: (active) async {
        final entry = ref.read(vocabularyProvider).value?.entries.where((e) => e.id == hit.entryId).firstOrNull;
        if (entry == null) return [];
        final matcher = VocabularyMatcher([entry], showKnown: true);
        final result = <VocabularyHit>[];
        // Full text indexing is requested only when navigating this word's hits.
        for (var page = 1; page <= widget.pdf.pageCount; page++) {
          final text = _pages[page] ?? await widget.pdf.translationPage(page);
          if (!mounted || !active()) return [];
          if (text != null) result.addAll(vocabularyPdfHits(text, matcher.match(text.text)));
        }
        return result;
      },
      reveal: (h) async => widget.pdf.reveal(h.page!, h.pdfRects),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(vocabularyHintProvider);
    final vocabulary = ref.watch(vocabularyProvider).value;
    final flash = ref.watch(vocabularyAddedFlashProvider);
    ref.listen(vocabularyHintProvider, (_, _) => _schedule());
    ref.listen(vocabularyAddedFlashProvider, (_, _) => _schedule());
    final flashOnly = prefs.modeFor(widget.documentId) == VocabularyHintMode.off;
    if (vocabulary == null || (flashOnly && flash == null)) {
      return widget.builder([], _tap, _schedule);
    }
    final entries = {for (final e in vocabulary.entries) e.id: e};
    final spaces = <VocabularyHit, double>{};
    _hits = [];
    for (final page in _pages.values) {
      var geometry = _geometry[page.page];
      if (geometry == null || geometry.$1 != vocabulary.version || geometry.$2 != prefs.showKnown) {
        final hits = vocabularyPdfHits(
          page,
          _cache.match(page.text, version: vocabulary.version, entries: vocabulary.entries, showKnown: prefs.showKnown),
        );
        final lines = vocabularyPdfRects(page, 0, page.text.length);
        geometry = (
          vocabulary.version,
          prefs.showKnown,
          hits,
          {
            for (final hit in hits)
              hit: vocabularyGlossSpace(
                hit.rects.first,
                lines,
                ceiling: -(widget.pdf.pageSize(page.page)?.height ?? 0),
              ),
          },
        );
        _geometry[page.page] = geometry;
      }
      _hits.addAll(geometry.$3);
      spaces.addAll(geometry.$4);
    }
    final c = context.mmColors;
    return widget.builder(
      [
        for (var i = 0; i < _hits.length; i++)
          if (entries[_hits[i].entryId] case final entry? when !flashOnly || entry.id == flash)
            MMPdfHighlight(
              id: 'vocabulary:$i',
              temporary: true,
              page: _hits[i].page!,
              rects: _hits[i].pdfRects,
              color: flash == entry.id ? c.vocabularyTint : Colors.transparent,
              underline: flashOnly ? null : (entry.status == VocabularyStatus.known ? c.secondaryLabel : c.vocabulary),
              lineStyle: AnnotationLineStyle.dotted,
              gloss: prefs.mode == VocabularyHintMode.gloss ? String.fromCharCodes(entry.gloss.runes.take(8)) : null,
              glossStyle: context.mmText.footnote.copyWith(
                fontSize: MMSizes.vocabularyGlossSize,
                color: entry.status == VocabularyStatus.known ? c.secondaryLabel : c.vocabulary,
              ),
              glossSpace: spaces[_hits[i]] ?? 0,
            ),
      ],
      _tap,
      _schedule,
    );
  }
}
