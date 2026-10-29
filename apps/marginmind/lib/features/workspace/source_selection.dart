import 'package:flutter/painting.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

/// App boundary shared by the two renderers. Text never invents PDF geometry.
class SourceSelection {
  SourceSelection.pdf(MMPdfSelection selection)
    : pages = selection.pages,
      textAnchors = const [],
      text = selection.text,
      viewportRect = selection.viewportRect;
  SourceSelection.text(List<TextAnchor> anchors, {this.viewportRect})
    : textAnchors = List.unmodifiable(anchors),
      pages = const [],
      text = anchors.map((a) => a.quote).join('\n') {
    if (anchors.isEmpty) throw ArgumentError('Missing text anchors');
    for (final a in anchors) {
      a.validate();
    }
  }
  final List<AnnotationPage> pages;
  final List<TextAnchor> textAnchors;
  final String text;
  final Rect? viewportRect;
}
