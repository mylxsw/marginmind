import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'library_browser_io.dart';

import 'package:mm_sync/mm_sync.dart';

// A tab cannot prove that another tab has no uncommitted editing/resource
// staging. Keep explicit whole-history forwarding native-only for now.
const supportsHistoryCopy = false;

/// The head guard and the record share one IndexedDB transaction. Comparing
/// the guard with this tab's hydrated value prevents two tabs from committing
/// different immutable records on top of the same local revision.
Future<void> writeSyncLedgerRecord(String path, List<int> bytes) => BrowserFiles.commit({
  path: Uint8List.fromList(bytes),
  p.join(p.dirname(path), '.head'): Uint8List.fromList(utf8.encode(p.basename(path))),
}, []);

Future<List<int>?> readSyncConnection(String path) => BrowserFiles.readCurrent(path);

/// Revoking an observed target cannot disconnect a newer tab's connection.
Future<void> replaceSyncConnection(String path, List<int> bytes, String expectedRevision) async {
  final current = await BrowserFiles.readCurrent(path);
  if (current == null || (jsonDecode(utf8.decode(current)) as Map)['revision'] != expectedRevision) {
    throw const SyncTransportException(SyncTransportProblem.accountChanged);
  }
  await BrowserFiles.commit({path: Uint8List.fromList(bytes)}, [], guards: {path: current});
}

/// Confirmation and the connection guard share the very same IDB transaction.
Future<void> writeSyncDelivery(String path, List<int> bytes, {String? connectionPath, String? expectedRevision}) async {
  final guards = <String, Uint8List?>{};
  if (connectionPath != null) {
    final current = await BrowserFiles.readCurrent(connectionPath);
    final value = current == null ? null : jsonDecode(utf8.decode(current)) as Map;
    if (value == null || value['paused'] != false || value['revision'] != expectedRevision) {
      throw const SyncTransportException(SyncTransportProblem.paused);
    }
    guards[connectionPath] = current;
  }
  await BrowserFiles.commit({path: Uint8List.fromList(bytes)}, [], guards: guards);
}
