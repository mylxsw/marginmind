import 'dart:io';

/// Discard an uncommitted tail, then append and fsync before acknowledging.
Future<void> appendTranslationLine(File file, List<int> bytes) async {
  final handle = await file.open(mode: FileMode.append);
  try {
    var end = await handle.length();
    var committed = 0;
    while (end > 0) {
      final start = end > 4096 ? end - 4096 : 0;
      await handle.setPosition(start);
      final chunk = await handle.read(end - start);
      final newline = chunk.lastIndexOf(10);
      if (newline >= 0) {
        committed = start + newline + 1;
        break;
      }
      end = start;
    }
    await handle.truncate(committed);
    await handle.setPosition(committed);
    await handle.writeFrom(bytes);
    await handle.flush();
  } finally {
    await handle.close();
  }
}
