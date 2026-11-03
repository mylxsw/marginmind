import 'dart:io';

import 'package:path/path.dart' as p;

/// Repository roots are trusted; resource references cannot traverse a link
/// inside them, even when that link points back into the same package.
Future<void> checkResourceLocation(String root, String path) async {
  final relative = p.relative(path, from: root);
  if (p.isAbsolute(relative) || relative == '..' || relative.startsWith('../')) {
    throw const FormatException('Resource outside repository');
  }
  var current = root;
  for (final part in ['', ...p.split(relative)]) {
    current = p.join(current, part);
    if (await FileSystemEntity.type(current, followLinks: false) == FileSystemEntityType.link) {
      throw const FormatException('Resource symlink');
    }
  }
}

Stream<List<int>> readResource(String path) => File(path).openRead();
Future<int> resourceLength(String path) => File(path).length();

Future<void> writeResourceStream(String path, Stream<List<int>> bytes) async {
  final sink = File(path).openWrite();
  try {
    await sink.addStream(bytes);
    await sink.flush();
  } finally {
    await sink.close();
  }
}
