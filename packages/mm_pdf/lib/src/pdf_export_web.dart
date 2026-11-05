import 'package:mm_core/mm_core.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_export.dart';

const canWriteMarks = false;

Future<void> addMarks(
  PdfDocument document,
  DocumentExportPlan plan,
  MMPdfExportColors colors, {
  void Function(double progress)? onProgress,
  bool Function()? cancelled,
}) async {
  throw UnsupportedError('The web build cannot edit PDF files');
}
