import 'models.dart';
import 'reading.dart';

/// A paragraph is one contiguous block on one page. Wider gaps, blank lines,
/// or multiple pages fall back to the first line, in original PDF coordinates.
({AnnotationAnchor? anchor, double? lineY}) marginAnchor(List<AnnotationPage> pages, String quote) {
  if (pages.isEmpty || pages.first.rects.isEmpty) throw ArgumentError('Empty selection');
  var contiguous = pages.length == 1 && !RegExp(r'\n\s*\n').hasMatch(quote);
  final rects = pages.first.rects;
  for (var i = 1; i < rects.length; i++) {
    final before = rects[i - 1], after = rects[i];
    if (before.bottom - after.top > (before.top - before.bottom) * .9) contiguous = false;
  }
  return contiguous
      ? (anchor: AnnotationAnchor(pages: pages, quote: quote), lineY: null)
      : (anchor: null, lineY: rects.first.top);
}
