import 'package:mm_platform/mm_platform.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_drop.dart';

/// Asks for supported documents with the system open panel; [typeLabel] names the file type
/// in the panel. Returns nothing when cancelled.
typedef PdfPicker = Future<List<DroppedFile>> Function(String typeLabel);

/// Widget tests have no open panel; they override this.
final pdfPickerProvider = Provider<PdfPicker>((ref) => MMDocumentFiles.pick);
