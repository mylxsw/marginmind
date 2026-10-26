import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_drop.dart';

/// Asks for PDFs with the system open panel; [typeLabel] names the file type
/// in the panel. Returns nothing when cancelled.
typedef PdfPicker = Future<List<DroppedFile>> Function(String typeLabel);

/// Widget tests have no open panel; they override this.
final pdfPickerProvider = Provider<PdfPicker>(
  (ref) => (typeLabel) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: typeLabel, extensions: const ['pdf'], uniformTypeIdentifiers: const ['com.adobe.pdf']),
      ],
    );
    return [for (final f in files) (path: f.path, name: f.name)];
  },
);
