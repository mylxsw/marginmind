/// MarginMind PDF layer. Wraps pdfrx (PDFium) behind a small API so the
/// rest of the app never imports pdfrx directly.
library;

export 'src/ink.dart' show MMPdfInk, MMPdfInkDraft, MMPdfInkTool;
export 'src/pdf_engine.dart';
export 'src/pdf_view.dart';
export 'src/pdf_navigation.dart';
