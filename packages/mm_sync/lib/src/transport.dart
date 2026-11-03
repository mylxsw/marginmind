import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'commit.dart';

/// Identity contains no password/token. A target is immutable for a run.
class SyncTarget {
  SyncTarget({required this.service, required this.account, required this.location, required this.libraryId}) {
    if (![service, account, location, libraryId].every((v) => v.isNotEmpty && v.length <= 2048)) {
      throw ArgumentError('Invalid sync target');
    }
  }
  final String service, account, location, libraryId;
  String get key => syncDigest(toJson());
  Map<String, Object?> toJson() => {
    'service': service,
    'account': account,
    'location': location,
    'libraryId': libraryId,
  };
  factory SyncTarget.fromJson(Map<String, Object?> value) => SyncTarget(
    service: value['service'] as String,
    account: value['account'] as String,
    location: value['location'] as String,
    libraryId: value['libraryId'] as String,
  );
}

enum SyncTransportProblem {
  authentication,
  permission,
  quota,
  unavailable,
  throttled,
  invalidResponse,
  collision,
  wrongLibrary,
  accountChanged,
  paused,
  legacyProtocol,
  missingHistory,
  tooLarge,
}

class SyncTransportException implements Exception {
  const SyncTransportException(this.problem);
  final SyncTransportProblem problem;
  @override
  String toString() => 'Sync transport: ${problem.name}';
}

enum SyncDelivery { staged, confirmed }

/// Only protocol objects, never private journal files or arbitrary disk paths.
/// Implementations must create immutably and verify an existing object's value.
abstract interface class SyncObjectTransport {
  SyncTarget get target;
  Future<void> prepare();
  Future<List<String>> listCommits();
  Future<List<int>?> read(String key);
  Future<SyncDelivery> create(String key, List<int> value);
}

const syncObjectLimit = 16 * 1024 * 1024;
void checkSyncObjectKey(String key) {
  if (key != 'library.json' && !RegExp(r'^(commits/[a-f0-9]{64}\.json|blobs/[a-f0-9]{64}\.bin)$').hasMatch(key)) {
    throw const SyncTransportException(SyncTransportProblem.invalidResponse);
  }
}

void checkSyncObjectSize(List<int> bytes) {
  if (bytes.length > syncObjectLimit) throw const SyncTransportException(SyncTransportProblem.tooLarge);
}

/// Equivalent portable JSON can have different VM/JS number spellings.
bool sameSyncObject(List<int> a, List<int> b) {
  try {
    return syncDigest(jsonDecode(utf8.decode(a))) == syncDigest(jsonDecode(utf8.decode(b)));
  } catch (_) {
    throw const SyncTransportException(SyncTransportProblem.invalidResponse);
  }
}

List<int> syncLibraryManifest(String id) =>
    utf8.encode(jsonEncode({'kind': 'foliarc-library', 'version': 1, 'commitProtocol': 2, 'libraryId': id}));
void validateSyncLibrary(List<int> bytes, String id) {
  if (!sameSyncObject(bytes, syncLibraryManifest(id))) {
    throw const SyncTransportException(SyncTransportProblem.wrongLibrary);
  }
}

/// Legacy aggregate scopes remain local migration inputs. Do not export them.
bool isSyncWireScope(String scope) =>
    {'sets', 'reviews', 'folders', 'reading', 'devices', 'words', 'translated'}.contains(scope.split('/').first);

void checkSyncObjectData(String key, List<int> bytes) {
  checkSyncObjectKey(key);
  checkSyncObjectSize(bytes);
  if (key.startsWith('blobs/') && sha256.convert(bytes).toString() != key.substring(6, 70)) {
    throw const SyncTransportException(SyncTransportProblem.invalidResponse);
  }
}

bool sameSyncStoredObject(String key, List<int> a, List<int> b) {
  checkSyncObjectData(key, a);
  checkSyncObjectData(key, b);
  return key.startsWith('blobs/') ? a.length == b.length : sameSyncObject(a, b);
}
