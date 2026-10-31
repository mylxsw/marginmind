import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../workspace/reflow_document.dart';

/// Geometry must come from the same text layer as the verified quotation.
/// Ambiguous repeated text uses its first occurrence on the cited page.
Annotation? mapQuoteAnnotation(TranslationPage page, MapLine point, String id, DateTime now) {
  final quote = point.quote, source = point.source;
  if (quote == null || quote.trim().isEmpty || source == null || page.page != source.page) return null;
  final start = page.text.indexOf(quote);
  if (start < 0 || page.boxes.length != page.text.length) return null;
  final rects = excerptLineRects(page.boxes.sublist(start, start + quote.length));
  if (rects.isEmpty) return null;
  return Annotation(
    id: id,
    documentId: source.documentId,
    page: source.page,
    rects: rects,
    quote: quote,
    colorIndex: 0,
    createdAt: now,
    kind: AnnotationKind.underline,
    lineStyle: AnnotationLineStyle.dashed,
  );
}

Annotation? mapTextQuoteAnnotation(ReflowDocument book, MapLine point, String id, DateTime now) {
  final quote = point.quote, source = point.quoteSource;
  if (quote == null || source == null || source.page > book.chapters.length) return null;
  final chapter = book.chapters[source.page - 1];
  final start = chapter.canonicalText.indexOf(quote);
  if (start < 0) return null;
  final anchor = chapter.anchor(start, start + quote.length, revision: book.revision);
  if (anchor.quote != quote) return null;
  return Annotation(
    id: id,
    documentId: source.documentId,
    textAnchors: [anchor],
    quote: quote,
    colorIndex: 0,
    createdAt: now,
    kind: AnnotationKind.underline,
    lineStyle: AnnotationLineStyle.dashed,
  );
}
