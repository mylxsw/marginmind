import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';

/// Only the container configured in the signed Apple app can be opened.
/// Account IDs are opaque, device-local bindings, never cross-device user IDs.
class MMICloudDrive implements ICloudDrivePort, ICloudAccountEvents, ICloudCancellablePort {
  MMICloudDrive._(this.containerIdentifier, this._channel, this._events);
  static const _defaultChannel = MethodChannel('marginmind/icloud_drive');
  static const _defaultEvents = EventChannel('marginmind/icloud_account');
  final MethodChannel _channel;
  final EventChannel _events;
  final _pending = <String>{};
  final _cancelled = <String>{};

  @override
  Future<void> cancelPending() async {
    // Snapshot before awaiting: a later request must never inherit this cancel.
    final ids = _pending.toList();
    _cancelled.addAll(ids);
    try {
      await Future.wait(ids.map((id) => _channel.invokeMethod<void>('cancel', {'requestId': id})));
    } on PlatformException {
      throw const SyncTransportException(SyncTransportProblem.unavailable);
    } on MissingPluginException {
      throw const SyncTransportException(SyncTransportProblem.unavailable);
    }
  }

  @override
  late final Stream<void> accountChanges = _events.receiveBroadcastStream().map<void>((_) {});
  @override
  final String containerIdentifier;

  static Future<MMICloudDrive?> configured({
    MethodChannel channel = _defaultChannel,
    EventChannel events = _defaultEvents,
    bool? supported,
  }) async {
    if (!(supported ?? (!kIsWeb && {TargetPlatform.iOS, TargetPlatform.macOS}.contains(defaultTargetPlatform)))) {
      return null;
    }
    try {
      final value = await channel.invokeMethod<Object?>('configuration');
      if (value == null) return null;
      if (value is! String || !RegExp(r'^iCloud\.[A-Za-z0-9.-]{1,200}$').hasMatch(value)) {
        throw const SyncTransportException(SyncTransportProblem.invalidResponse);
      }
      return MMICloudDrive._(value, channel, events);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      throw const SyncTransportException(SyncTransportProblem.unavailable);
    }
  }

  Future<Object?> _call(String method, [String? path, String? account, List<int>? bytes]) async {
    if (path != null && !_validPath(path, directory: method == 'prepare' || method == 'list')) {
      throw ArgumentError('Invalid iCloud sync path');
    }
    if (account != null && (account.isEmpty || account.length > 256)) throw ArgumentError('Invalid account');
    if (bytes != null) checkSyncObjectSize(bytes);
    final id = newId();
    _pending.add(id);
    try {
      final value = await _channel.invokeMethod<Object?>(method, {
        'requestId': id,
        'container': containerIdentifier,
        'path': ?path,
        'account': ?account,
        'bytes': bytes == null ? null : Uint8List.fromList(bytes),
      });
      if (_cancelled.contains(id)) throw const SyncTransportException(SyncTransportProblem.paused);
      return value;
    } on PlatformException catch (error) {
      final problem = switch (error.code) {
        'cancelled' => SyncTransportProblem.paused,
        'timedOut' => SyncTransportProblem.timedOut,
        'accountChanged' => SyncTransportProblem.accountChanged,
        'authentication' => SyncTransportProblem.authentication,
        'permission' => SyncTransportProblem.permission,
        'quota' => SyncTransportProblem.quota,
        'tooLarge' => SyncTransportProblem.tooLarge,
        'collision' => SyncTransportProblem.collision,
        'invalidResponse' => SyncTransportProblem.invalidResponse,
        _ => SyncTransportProblem.unavailable,
      };
      // Native descriptions may contain filesystem paths or account details.
      throw SyncTransportException(problem);
    } on MissingPluginException {
      throw const SyncTransportException(SyncTransportProblem.unavailable);
    } finally {
      _pending.remove(id);
      _cancelled.remove(id);
    }
  }

  static bool _validPath(String path, {required bool directory}) => RegExp(
    directory
        ? r'^foliarc-v2/[a-f0-9]{64}/(commits|blobs)$'
        : r'^foliarc-v2/[a-f0-9]{64}/(library\.json|commits/[a-f0-9]{64}\.json|blobs/[a-f0-9]{64}\.bin)$',
  ).hasMatch(path);

  @override
  Future<String?> accountIdentity() async {
    final value = await _call('account');
    if (value == null) return null;
    if (value is! String || value.isEmpty || value.length > 256) {
      throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    }
    return value;
  }

  @override
  Future<void> prepare(String directory, String expectedAccount) async =>
      await _call('prepare', directory, expectedAccount);

  @override
  Future<List<String>> list(String directory, String expectedAccount) async {
    final value = await _call('list', directory, expectedAccount);
    if (value is! List || value.length > 100000 || value.any((v) => v is! String)) {
      throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  @override
  Future<List<int>?> read(String path, String expectedAccount) async {
    final value = await _call('read', path, expectedAccount);
    if (value == null) return null;
    if (value is! Uint8List) throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    checkSyncObjectSize(value);
    return value;
  }

  @override
  Future<void> create(String path, List<int> bytes, String expectedAccount) async =>
      await _call('create', path, expectedAccount, bytes);

  @override
  Future<bool> uploaded(String path, List<int> expectedBytes, String expectedAccount) async {
    final value = await _call('uploaded', path, expectedAccount, expectedBytes);
    if (value is! bool) throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    return value;
  }
}
