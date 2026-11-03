import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_sync/mm_sync.dart';

final syncSettingsControllerProvider = Provider<SyncSettingsController?>((ref) => null);

enum SyncSettingsFailure {
  storage,
  invalidInput,
  incompleteLibrary,
  missingLibrary,
  unsupported,
  authentication,
  accountChanged,
  legacyProtocol,
  missingHistory,
  paused,
  service,
}

/// App composition service; widgets never read ledger JSON or handle credentials
/// outside their explicit form. No automatic networking, including on startup.
class SyncSettingsController extends ChangeNotifier {
  SyncSettingsController(
    this.library,
    this.vocabulary, {
    required this.secrets,
    required this.canActivate,
    required this.canStoreSecrets,
    Future<ICloudDrivePort?> Function()? cloud,
    SyncObjectTransport Function(SyncTarget, String?)? transport,
  }) : _cloud = cloud ?? MMICloudDrive.configured,
       _transportFactory = transport;

  final FileLibraryStore library;
  final FileVocabularyStore vocabulary;
  final SecretStore secrets;
  final bool canActivate, canStoreSecrets;
  final Future<ICloudDrivePort?> Function() _cloud;
  final SyncObjectTransport Function(SyncTarget, String?)? _transportFactory;
  FileSyncLedger? _ledger;
  FileSyncEngine? _engine;
  http.Client? _client;
  StreamSubscription<void>? _changes;
  SyncSetup? setup;
  SyncTarget? target;
  String? libraryId;
  bool initialized = false, busy = false, restartRequired = false, paused = true;
  int pending = 0, _generation = 0;
  bool _disposed = false;
  SyncSettingsFailure? failure;
  SyncRunResult? result;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) throw const SyncTransportException(SyncTransportProblem.paused);
  }

  Future<void> _action(Future<void> Function(int) body) async {
    if (busy || _disposed) return;
    busy = true;
    failure = null;
    result = null;
    final generation = _generation;
    _notify();
    try {
      await body(generation);
    } on SyncTransportException catch (error) {
      failure = switch (error.problem) {
        SyncTransportProblem.authentication || SyncTransportProblem.permission => SyncSettingsFailure.authentication,
        SyncTransportProblem.accountChanged => SyncSettingsFailure.accountChanged,
        SyncTransportProblem.legacyProtocol => SyncSettingsFailure.legacyProtocol,
        SyncTransportProblem.missingHistory => SyncSettingsFailure.missingHistory,
        SyncTransportProblem.paused => SyncSettingsFailure.paused,
        _ => SyncSettingsFailure.service,
      };
    } on FormatException {
      failure = SyncSettingsFailure.invalidInput;
    } on ArgumentError {
      failure = SyncSettingsFailure.invalidInput;
    } catch (_) {
      failure ??= SyncSettingsFailure.storage;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> initialize() => _action((generation) async {
    await _changes?.cancel();
    setup = await FileSyncSetup(library.root).read();
    _ledger = await library.syncLedger;
    libraryId = _ledger?.libraryId ?? setup?.libraryId;
    restartRequired = _ledger == null && setup != null;
    if (_ledger case final ledger?) {
      final receiver = FileSyncReceiver(library, vocabulary);
      await receiver.validateLedger(ledger);
      _engine = FileSyncEngine(ledger, receiver);
      // A restarted process never resumes a previous process's consent to run.
      await _engine!.pause();
      target = (await ledger.transportConnection())?.target;
      await _refresh();
    }
    _check(generation);
    initialized = true;
    _changes = _ledger?.changes.listen((_) async {
      try {
        await _refresh();
      } catch (_) {
        failure = SyncSettingsFailure.storage;
      }
      _notify();
    });
  });

  Future<void> activate({String? existingLibraryId, required String deviceName}) => _action((generation) async {
    if (!canActivate || !initialized || _ledger != null) {
      failure = SyncSettingsFailure.unsupported;
      return;
    }
    setup = await FileSyncSetup(library.root).request(libraryId: existingLibraryId, deviceName: deviceName);
    libraryId = setup!.libraryId;
    restartRequired = true;
  });

  Future<void> _ready() async {
    if (_ledger == null || _engine == null) throw StateError('Library is not initialized');
    if (library.packageLoadErrors.isNotEmpty || _ledger!.projectionErrors.isNotEmpty) {
      failure = SyncSettingsFailure.incompleteLibrary;
      throw StateError('Repair local library before transfer');
    }
    if ((await _ledger!.history()).values.any((c) => c.protocol != syncProtocolVersion)) {
      throw const SyncTransportException(SyncTransportProblem.legacyProtocol);
    }
  }

  Future<void> cancelActivation() => _action((generation) async {
    if (_ledger != null || !canActivate) throw StateError('Library is already initialized');
    await FileSyncSetup(library.root).cancel();
    setup = null;
    libraryId = null;
    restartRequired = false;
  });

  Future<void> connectWebDav({required String directory, required String username, required String password}) =>
      _action((generation) async {
        await _ready();
        await _engine!.pause();
        paused = true;
        if (!canStoreSecrets) {
          failure = SyncSettingsFailure.unsupported;
          return;
        }
        if (username.trim().isEmpty || username.contains(':') || username.contains(RegExp(r'[\r\n]'))) {
          throw const FormatException('Invalid account');
        }
        final uri = Uri.parse(directory.trim());
        // Constructor performs the same URL validation as the production adapter.
        final validationClient = http.Client();
        late SyncTarget selected;
        try {
          selected = WebDavSyncTransport(
            client: validationClient,
            directory: uri,
            account: username.trim(),
            libraryId: _ledger!.libraryId,
            authorization: '',
          ).target;
        } finally {
          validationClient.close();
        }
        final key = 'sync-${selected.key}';
        final authorization = password.isEmpty
            ? await secrets.read(key)
            : 'Basic ${base64Encode(utf8.encode('${selected.account}:$password'))}';
        if (authorization == null || authorization.isEmpty) {
          throw const SyncTransportException(SyncTransportProblem.authentication);
        }
        _check(generation);
        final adapter = await _adapter(selected, authorization);
        await _probe(adapter, generation);
        if (password.isNotEmpty) await secrets.writeVerified(key, authorization);
        _check(generation);
        await _engine!.bind(adapter);
        target = selected;
        await _refresh();
      });

  Future<void> connectICloud() => _action((generation) async {
    await _ready();
    await _engine!.pause();
    paused = true;
    final port = await _cloud();
    final account = await port?.accountIdentity();
    if (port == null || account == null) {
      failure = SyncSettingsFailure.unsupported;
      return;
    }
    _check(generation);
    final adapter = ICloudSyncTransport(
      port: port,
      account: account,
      container: port.containerIdentifier,
      libraryId: _ledger!.libraryId,
    );
    await _probe(adapter, generation);
    await _engine!.bind(adapter);
    target = adapter.target;
    await _refresh();
  });

  Future<void> _probe(SyncObjectTransport adapter, int generation) async {
    // Read only: connecting does not create a cloud library or upload content.
    final manifest = await adapter.read('library.json');
    _check(generation);
    if (manifest == null && setup?.joining == true) {
      failure = SyncSettingsFailure.missingLibrary;
      throw StateError('Joining requires an existing manifest');
    }
    if (manifest != null) validateSyncLibrary(manifest, _ledger!.libraryId);
  }

  Future<SyncObjectTransport> _adapter(SyncTarget selected, String? authorization) async {
    if (_transportFactory != null) return _transportFactory(selected, authorization);
    if (selected.service == 'webdav') {
      if (!canStoreSecrets || authorization == null) {
        throw const SyncTransportException(SyncTransportProblem.authentication);
      }
      _client?.close();
      _client = http.Client();
      return WebDavSyncTransport(
        client: _client!,
        directory: Uri.parse(selected.location),
        account: selected.account,
        libraryId: selected.libraryId,
        authorization: authorization,
      );
    }
    final port = await _cloud();
    if (selected.service != 'icloud' ||
        port == null ||
        port.containerIdentifier != selected.location ||
        await port.accountIdentity() != selected.account) {
      throw const SyncTransportException(SyncTransportProblem.accountChanged);
    }
    return ICloudSyncTransport(
      port: port,
      account: selected.account,
      container: selected.location,
      libraryId: selected.libraryId,
    );
  }

  Future<void> syncOnce() => _action((generation) async {
    await _ready();
    final selected = target;
    if (selected == null) throw const SyncTransportException(SyncTransportProblem.paused);
    try {
      final secret = selected.service == 'webdav' ? await secrets.read('sync-${selected.key}') : null;
      final adapter = await _adapter(selected, secret);
      _check(generation);
      await _probe(adapter, generation);
      await _engine!.bind(adapter);
      _check(generation);
      await _engine!.resume();
      paused = false;
      _notify();
      final completed = await _engine!.run();
      _check(generation);
      result = completed;
    } finally {
      await _engine!.pause();
      paused = true;
      await _refresh();
    }
  });

  Future<void> pause() async {
    _generation++;
    try {
      await _engine?.pause();
    } catch (_) {
      failure = SyncSettingsFailure.storage;
    }
    paused = true;
    _notify();
  }

  Future<void> _refresh() async {
    pending = (await _ledger!.pending(target: target?.key)).where((c) => isSyncWireScope(c.scope)).length;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_changes?.cancel());
    _client?.close();
    super.dispose();
  }
}
