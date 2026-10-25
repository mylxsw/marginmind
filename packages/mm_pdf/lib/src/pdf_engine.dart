import 'package:pdfrx/pdfrx.dart';

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
    final doc = await PdfDocument.openFile(path);
    try {
      return (pageCount: doc.pages.length, title: null);
    } finally {
      await doc.dispose();
    }
  }
}
