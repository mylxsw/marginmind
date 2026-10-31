import 'library_browser_io.dart';

/// IndexedDB commits replace the byte value atomically; no native fsync exists.
Future<void> appendTranslationLine(File file, List<int> bytes) async {
  final previous = await file.exists() ? await file.readAsBytes() : <int>[];
  await file.writeAsBytes([...previous.take(previous.lastIndexOf(10) + 1), ...bytes], flush: true);
}
