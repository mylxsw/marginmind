import 'package:flutter/foundation.dart';
import 'package:mm_core/mm_core.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_engine.dart';
import 'pdf_export_native.dart' if (dart.library.js_interop) 'pdf_export_web.dart' as writer;

/// Resolved 24-bit RGB colors of the marks in a plan.
class MMPdfExportColors {
  const MMPdfExportColors({required this.mark, required this.note, required this.ink});
  final int Function(int colorIndex) mark, note, ink;
}

/// Writes copies of a PDF. The source bytes are never modified.
abstract final class MMPdfExport {
  /// PDFium's annotation API is unavailable to the web build.
  static bool get canWriteMarks => writer.canWriteMarks;

  /// False when the author's permissions forbid adding annotations.
  static Future<bool> allowsMarks(Uint8List source) async {
    if (!canWriteMarks) return false;
    await MMPdfEngine.initialize();
    final document = await PdfDocument.openData(source);
    try {
      return document.permissions?.allowsModifyAnnotations ?? true;
    } finally {
      await document.dispose();
    }
  }

  /// [cancelled] is polled between pages; a cancelled write throws
  /// [MMPdfExportCancelled]. An unchanged copy is returned as [source] itself.
  static Future<Uint8List> write(
    Uint8List source,
    DocumentExportPlan plan,
    MMPdfExportColors colors, {
    void Function(double progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    if (plan.isEmpty && plan.options.pages == null) return source;
    await MMPdfEngine.initialize();
    final document = await PdfDocument.openData(source);
    try {
      // The sheet checks too, but a tap can arrive before its check has finished.
      if (!plan.isEmpty && document.permissions?.allowsModifyAnnotations == false) {
        throw const MMPdfExportNotAllowed();
      }
      await writer.addMarks(document, plan, colors, onProgress: onProgress, cancelled: cancelled);
      return await document.encodePdf();
    } finally {
      await document.dispose();
    }
  }
}

class MMPdfExportCancelled implements Exception {
  const MMPdfExportCancelled();
}

class MMPdfExportNotAllowed implements Exception {
  const MMPdfExportNotAllowed();
}
