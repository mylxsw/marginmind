import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> temporaryDocument(Uint8List bytes) async {
  final file = File(p.join((await getTemporaryDirectory()).path, 'marginmind-sample.pdf'));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

void releaseTemporaryDocument(String path) {}
