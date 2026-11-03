import 'dart:io';

/// The immutable record is the native commit point. Single process ownership
/// is required; .mmset projections are repaired separately from this record.
Future<void> writeSyncLedgerRecord(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final temp = File('$path.tmp');
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
  } catch (_) {
    try {
      if (await temp.exists()) await temp.delete();
    } catch (_) {
      /* Original error wins. */
    }
    rethrow;
  }
}
