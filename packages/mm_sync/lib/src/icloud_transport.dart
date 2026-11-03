import 'commit.dart';
import 'transport.dart';

/// Optional invalidation signal. It carries no account token or personal data.
abstract interface class ICloudAccountEvents {
  Stream<void> get accountChanges;
}

/// Native bridge contract: coordinate ubiquitous files, atomically create only
/// if absent, and validate expectedAccount INSIDE each coordinated operation.
/// A downloaded local file is not proof that its latest bytes were uploaded.
abstract interface class ICloudDrivePort {
  String get containerIdentifier;
  Future<String?> accountIdentity();
  Future<void> prepare(String directory, String expectedAccount);
  Future<List<String>> list(String directory, String expectedAccount);
  Future<List<int>?> read(String path, String expectedAccount);
  Future<void> create(String path, List<int> bytes, String expectedAccount);

  /// True only for this exact current file, with no unresolved file versions or
  /// uploading error, and ubiquitousItemIsUploaded == true. Compare expectedBytes
  /// inside the same coordinated read; a newer file cannot acknowledge old bytes.
  Future<bool> uploaded(String path, List<int> expectedBytes, String expectedAccount);
}

/// Testable Drive adapter; the signed Apple native port is supplied separately.
class ICloudSyncTransport implements SyncObjectTransport {
  ICloudSyncTransport({
    required this.port,
    required String account,
    required String container,
    required String libraryId,
  }) : target = SyncTarget(service: 'icloud', account: account, location: container, libraryId: libraryId) {
    if (port.containerIdentifier != container) throw ArgumentError('Wrong iCloud container port');
  }
  final ICloudDrivePort port;
  @override
  final SyncTarget target;
  String get _root => 'foliarc-v2/${syncDigest(target.libraryId)}';
  Future<void> _check() async {
    if (await port.accountIdentity() != target.account) {
      throw const SyncTransportException(SyncTransportProblem.accountChanged);
    }
  }

  @override
  Future<void> prepare() async {
    await _check();
    await port.prepare('$_root/commits', target.account);
    await _check();
    await port.prepare('$_root/blobs', target.account);
    await _check();
  }

  @override
  Future<List<int>?> read(String key) async {
    checkSyncObjectKey(key);
    await _check();
    final bytes = await port.read('$_root/$key', target.account);
    await _check();
    if (bytes != null) checkSyncObjectData(key, bytes);
    return bytes;
  }

  @override
  Future<List<String>> listCommits() async {
    await _check();
    final names = await port.list('$_root/commits', target.account);
    await _check();
    if (names.length > 100000) throw const SyncTransportException(SyncTransportProblem.tooLarge);
    return names
        .where((n) => RegExp(r'^[a-f0-9]{64}\.json$').hasMatch(n))
        .map((n) => n.substring(0, 64))
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<SyncDelivery> create(String key, List<int> value) async {
    checkSyncObjectKey(key);
    checkSyncObjectData(key, value);
    await _check();
    final bytes = List<int>.unmodifiable(value), path = '$_root/$key';
    await port.create(path, bytes, target.account);
    await _check();
    final stored = await read(key);
    if (stored == null || !sameSyncStoredObject(key, stored, bytes)) {
      throw const SyncTransportException(SyncTransportProblem.collision);
    }
    final uploaded = await port.uploaded(path, stored, target.account);
    await _check();
    return uploaded ? SyncDelivery.confirmed : SyncDelivery.staged;
  }
}
