import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import 'reader_translation.dart';

String selectionTerm(String text) =>
    text.trim().replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');

/// Preserve the selected source anchor: examples return to the exact occurrence.
Future<TranslationParagraph> selectionSentence(WidgetRef ref, String setId, TranslationParagraph selection) async {
  final provider = translationParagraphsProvider((setId, selection.documentId));
  final subscription = ref.listenManual(provider, (_, _) {});
  try {
    final paragraphs = await ref.read(provider.future);
    return resolveSelectionSentence(paragraphs, selection);
  } catch (_) {
    // An unavailable text layer still allows adding the selected term offline.
    return selection;
  } finally {
    subscription.close();
  }
}

TranslationParagraph resolveSelectionSentence(List<TranslationParagraph> paragraphs, TranslationParagraph selection) {
  final anchor = selection.textAnchor;
  final candidates = paragraphs
      .where(
        (p) =>
            p.documentId == selection.documentId &&
            (anchor != null
                ? p.textAnchor?.chapterId == anchor.chapterId &&
                      p.textAnchor?.revision == anchor.revision &&
                      p.textAnchor!.start <= anchor.start &&
                      p.textAnchor!.end >= anchor.end
                : p.textAnchor == null && p.page == selection.page && p.text.contains(selection.text)),
      )
      .toList();
  bool intersects(PageRect a, PageRect b) =>
      a.left < b.right && a.right > b.left && a.top > b.bottom && a.bottom < b.top;
  final p =
      candidates.where((p) => p.rects.any((r) => selection.rects.any((s) => intersects(r, s)))).firstOrNull ??
      candidates.firstOrNull;
  if (p == null) return selection;
  final offset = anchor == null ? p.text.indexOf(selection.text) : anchor.start - p.textAnchor!.start;
  if (offset < 0 ||
      offset + selection.text.length > p.text.length ||
      p.text.substring(offset, offset + selection.text.length) != selection.text) {
    return selection;
  }
  final before = p.text.substring(0, offset), after = p.text.substring(offset + selection.text.length);
  final start = RegExp(r'[.!?]\s+|[。！？]\s*').allMatches(before).lastOrNull?.end ?? 0;
  final end = RegExp(r'[.!?](?:\s|$)|[。！？]').firstMatch(after)?.start;
  final text = p.text.substring(start, end == null ? p.text.length : offset + selection.text.length + end + 1).trim();
  return TranslationParagraph(
    documentId: selection.documentId,
    page: anchor == null ? selection.page : null,
    textAnchor: anchor,
    index: selection.index,
    text: text,
    fingerprint: '',
    rects: selection.rects,
  );
}
