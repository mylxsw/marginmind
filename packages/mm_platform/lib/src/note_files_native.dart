import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

Future<void> write(String directory, String relative, Uint8List bytes) async {
  final root = await Directory(directory).resolveSymbolicLinks();
  final file = File(p.join(root, relative));
  await file.parent.create(recursive: true);
  final parent = await file.parent.resolveSymbolicLinks();
  if (!p.isWithin(root, parent) || await FileSystemEntity.isLink(file.path)) {
    throw const FileSystemException('Attachment points outside export directory');
  }
  await file.writeAsBytes(bytes, flush: true);
}
