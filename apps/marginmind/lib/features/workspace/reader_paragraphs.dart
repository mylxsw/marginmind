import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';

import 'reflow_document.dart';

/// Source paragraph identities never contain layout geometry or a screen page.
List<TranslationParagraph> reflowParagraphs(ReflowDocument book) {
  final result = <TranslationParagraph>[];
  for (final chapter in book.chapters) {
    for (final block in chapter.blocks) {
      if (block.kind == BlockKind.image || block.kind == BlockKind.rule || block.text.trim().isEmpty) continue;
      result.add(
        TranslationParagraph(
          documentId: book.document.id,
          textAnchor: chapter.anchor(block.start, block.end, revision: book.revision),
          index: result.length,
          text: block.text,
          heading: block.kind == BlockKind.heading,
          fingerprint: sha256
              .convert(
                utf8.encode(
                  jsonEncode([1, book.document.id, book.revision, chapter.id, block.start, block.end, block.text]),
                ),
              )
              .toString(),
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

int translationGroup(TranslationParagraph p) => p.unit;

ReadingPosition paragraphPosition(TranslationParagraph p) => switch (p.textAnchor) {
  final a? => TextReadingPosition(revision: a.revision, chapterId: a.chapterId, offset: a.start),
  null => PdfPosition(p.page, y: p.bounds.top),
};

/// Returns no match for a different revision/chapter. A missing paragraph must
/// never be replaced by an unrelated whole-document progress ratio.
TranslationParagraph? paragraphAt(List<TranslationParagraph> paragraphs, ReadingPosition position) {
  final candidates = paragraphs
      .where(
        (p) => switch (position) {
          TextReadingPosition(:final chapterId, :final revision) =>
            p.textAnchor?.chapterId == chapterId && p.textAnchor?.revision == revision,
          PdfPosition(:final page) => p.textAnchor == null && p.page == page,
        },
      )
      .toList();
  if (candidates.isEmpty) return null;
  return candidates.lastWhere(
    (p) => switch (position) {
      TextReadingPosition(:final offset) => p.textAnchor!.start <= offset,
      PdfPosition(:final y) => y == null || p.bounds.top >= y,
    },
    orElse: () => candidates.first,
  );
}

bool sameSourcePosition(ReadingPosition a, ReadingPosition b) => switch ((a, b)) {
  (TextReadingPosition x, TextReadingPosition y) =>
    x.revision == y.revision && x.chapterId == y.chapterId && x.offset == y.offset,
  (PdfPosition x, PdfPosition y) => x.page == y.page && x.y == y.y,
  _ => false,
};

List<SourceAlignPoint> insertParagraphAlignment(
  List<SourceAlignPoint> points,
  SourceAlignPoint point,
  List<TranslationParagraph> left,
  List<TranslationParagraph> right,
) {
  int index(List<TranslationParagraph> paragraphs, ReadingPosition p) =>
      paragraphs.indexWhere((paragraph) => sameSourcePosition(paragraphPosition(paragraph), p));
  final l = index(left, point.left), r = index(right, point.right);
  if (l < 0 || r < 0) throw ArgumentError('Unknown paragraph');
  final result = [
    for (final p in points)
      if (index(left, p.left) case final x when x >= 0 && x != l)
        if (index(right, p.right) case final y when y >= 0 && y != r)
          if ((x < l) == (y < r)) p,
    point,
  ];
  result.sort((a, b) => index(left, a.left).compareTo(index(left, b.left)));
  return result;
}
