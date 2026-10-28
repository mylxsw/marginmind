import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:file_selector/file_selector.dart';

Future<String> temporaryDocument(Uint8List bytes) async => XFile.fromData(bytes, mimeType: 'application/pdf').path;
void releaseTemporaryDocument(String path) => web.URL.revokeObjectURL(path);
