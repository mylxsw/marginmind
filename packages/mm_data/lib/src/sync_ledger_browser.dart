import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'library_browser_io.dart';

/// The head guard and the record share one IndexedDB transaction. Comparing
/// the guard with this tab's hydrated value prevents two tabs from committing
/// different immutable records on top of the same local revision.
Future<void> writeSyncLedgerRecord(String path, List<int> bytes) => BrowserFiles.commit({
  path: Uint8List.fromList(bytes),
  p.join(p.dirname(path), '.head'): Uint8List.fromList(utf8.encode(p.basename(path))),
}, []);
