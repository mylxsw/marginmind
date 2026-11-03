import 'dart:typed_data';

import 'library_browser_io.dart';

// IndexedDB has no symbolic links. The caller enforces package-relative paths.
Future<void> checkResourceLocation(String root, String path) async {}
Stream<List<int>> readResource(String path) async* {
  yield await File(path).readAsBytes();
}

Future<int> resourceLength(String path) async => (await File(path).readAsBytes()).length;
Future<void> writeResourceStream(String path, Stream<List<int>> bytes) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in bytes) {
    builder.add(chunk);
  }
  await File(path).writeAsBytes(builder.takeBytes(), flush: true);
}
