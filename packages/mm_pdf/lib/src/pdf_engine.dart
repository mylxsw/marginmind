import 'package:pdfrx/pdfrx.dart';

import 'open_document.dart';

/// Document-level operations that do not need a viewer.
abstract final class MMPdfEngine {
  static bool _initialized = false;

  /// Call once at startup, before any document API is used.
  static Future<void> initialize() async {
    if (_initialized) return;
    await pdfrxFlutterInitialize();
    _initialized = true;
  }

  /// Reads the page count (and title, if the file has one) of [path].
  /// Throws if the file is not a readable PDF.
  static Future<({int pageCount, String? title})> inspect(String path) async {
    final doc = await openDocument(path);
    try {
      return (pageCount: doc.pages.length, title: null);
    } finally {
      await doc.dispose();
    }
  }

  /// The text of 1-based [page] of [path], or null when the file or page
  /// cannot be read.
  static Future<String?> pageText(String path, int page) async => (await pageContent(path, page))?.text;

  /// Like [pageText], with the page height in points.
  static Future<({String text, double height})?> pageContent(String path, int page) async {
    PdfDocument? doc;
    try {
      doc = await openDocument(path);
      if (page < 1 || page > doc.pages.length) return null;
      final pdfPage = doc.pages[page - 1];
      final text = (await pdfPage.loadText())?.fullText;
      return text == null ? null : (text: text, height: pdfPage.height);
    } catch (_) {
      return null;
    } finally {
      await doc?.dispose();
    }
  }
}
