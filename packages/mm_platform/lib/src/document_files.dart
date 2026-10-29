import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:mm_core/mm_core.dart';

import 'document_files_native.dart' if (dart.library.js_interop) 'document_files_web.dart' as resources;

typedef MMDocumentFile = ({String path, String name});

abstract final class MMDocumentFiles {
  static Future<List<MMDocumentFile>> pick(String label) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: label,
          extensions: DocumentFormat.extensions,
          uniformTypeIdentifiers: const ['com.adobe.pdf', 'org.idpf.epub-container', 'public.text', 'public.data'],
        ),
      ],
    );
    return [for (final file in files) (path: file.path, name: file.name)];
  }

  static Future<Uint8List> read(String path, {int maxBytes = 256 * 1024 * 1024}) async {
    final file = XFile(path);
    if (await file.length() > maxBytes) throw const FormatException('Document exceeds import limit');
    return file.readAsBytes();
  }

  static Future<Uint8List?> readRelativeResource(String source, String path) =>
      resources.readRelativeResource(source, path);
}
