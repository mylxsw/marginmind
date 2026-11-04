import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import 'file_sync_ledger.dart';
import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';

/// Private activation intent. Writing it does not change a running repository.
/// The next process creates/restores ONE ledger before constructing any stores.
class SyncSetup {
  SyncSetup({required this.libraryId, required this.deviceId, required this.deviceName, required this.joining}) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(libraryId) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(deviceId) ||
        deviceName.trim().isEmpty ||
        deviceName.length > 100) {
      throw const FormatException('Invalid sync setup');
    }
  }
  final String libraryId, deviceId, deviceName;
  final bool joining;
  Map<String, Object?> toJson() => {
    'version': 1,
    'libraryId': libraryId,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'joining': joining,
  };
  factory SyncSetup.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) throw const FormatException('Unsupported sync setup');
    return SyncSetup(
      libraryId: json['libraryId'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      joining: json['joining'] as bool,
    );
  }
}

class FileSyncSetup {
  FileSyncSetup(this.root);
  final Directory root;
  File get _file => File(p.join(root.path, '.foliarc-sync', 'setup.json'));
  Future<SyncSetup?> read() async => await _file.exists()
      ? SyncSetup.fromJson((jsonDecode(await _file.readAsString()) as Map).cast<String, Object?>())
      : null;

  /// Native single-owner startup only; never called while live repositories exist.
  Future<FileSyncLedger?> openLedger() async {
    final current = await FileSyncLedger.restore(root), setup = await read();
    if (current != null) {
      if (setup != null && (current.libraryId != setup.libraryId || current.deviceId != setup.deviceId)) {
        throw const FormatException('Activation identity differs from existing library');
      }
      return current;
    }
    if (setup == null) return null;
    final ledger = FileSyncLedger(root, libraryId: setup.libraryId, deviceId: setup.deviceId);
    await ledger.snapshots(); // Persist identity before repositories seed existing files.
    return ledger;
  }

  /// Does not seed, replace files, change an existing identity, or access a service.
  Future<SyncSetup> request({String? libraryId, required String deviceName}) async {
    if (await FileSyncLedger.restore(root) != null || await read() != null) {
      throw StateError('Sync identity is already selected');
    }
    final setup = SyncSetup(
      libraryId: libraryId ?? newId(),
      deviceId: newId(),
      deviceName: deviceName.trim(),
      joining: libraryId != null,
    );
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsBytes(utf8.encode(jsonEncode(setup.toJson())), flush: true);
    await temporary.rename(_file.path);
    return setup;
  }

  Future<void> cancel() async {
    if (await FileSyncLedger.restore(root) != null) throw StateError('Library is already initialized');
    if (await _file.exists()) await _file.delete();
  }
}
