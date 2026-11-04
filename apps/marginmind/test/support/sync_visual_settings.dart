import 'package:mm_core/mm_core.dart';

import 'dart:async';
import 'dart:io';

import 'package:marginmind/settings/sync_settings_controller.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String account) async => null;
  @override
  Future<void> write(String account, String value) async {}
  @override
  Future<void> delete(String account) async {}
}

class _CopyPlan implements SyncHistoryCopyPlan {
  _CopyPlan(this.target);
  @override
  final SyncTarget target;
  @override
  int get commits => 12;
  @override
  int get otherDeviceCommits => 7;
  @override
  int get chunks => 3;
  @override
  int get excluded => 2;
  @override
  int get unverifiedVersions => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuditSettings extends SyncSettingsController {
  AuditSettings({bool available = true})
    : super(
        FileLibraryStore(Directory('unused')),
        FileVocabularyStore(Directory('unused')),
        secrets: _Secrets(),
        canActivate: available,
        canStoreSecrets: available,
      ) {
    initialized = true;
  }
  final actions = <Object>[];
  SyncSettingsFailure? nextFailure;
  bool usedCopyDestination = false;
  Completer<void>? gate;
  Future<void> action(Object value) async {
    actions.add(value);
    busy = true;
    notifyListeners();
    if (gate != null) await gate!.future;
    busy = false;
    failure = nextFailure;
    notifyListeners();
  }

  @override
  Future<void> activate({String? existingLibraryId, required String deviceName}) async {
    await action((existingLibraryId, deviceName));
    if (failure == null) {
      restartRequired = true;
      libraryId = existingLibraryId ?? 'new-library';
      notifyListeners();
    }
  }

  @override
  Future<void> cancelActivation() async {
    restartRequired = false;
    libraryId = null;
    notifyListeners();
  }

  @override
  Future<void> connectWebDav({
    required String directory,
    required String username,
    required String password,
    bool copyDestination = false,
  }) {
    usedCopyDestination = copyDestination;
    return action((directory, username, password));
  }

  @override
  Future<void> renameDevice(String name, {required String? expectedRevision}) => action((name, expectedRevision));
  @override
  Future<void> disconnect() => action('disconnect');
  @override
  Future<void> connectICloud({bool copyDestination = false}) {
    usedCopyDestination = copyDestination;
    return action('icloud');
  }

  @override
  Future<void> syncOnce() => action('sync');
  @override
  Future<void> previewHistoryCopy() async {
    await action('copy-preview');
    if (failure == null) historyCopy = _CopyPlan(target!);
    notifyListeners();
  }

  @override
  Future<void> copyHistory(SyncHistoryCopyPlan plan) async {
    await action(plan);
    historyCopy = null;
    notifyListeners();
  }

  @override
  Future<void> downloadResource(SyncResourceStatus resource) => action(resource);
  @override
  Future<void> refreshResources() => action('resources');
  @override
  Future<void> inspectCache() => action('cache-inspect');
  @override
  Future<void> reclaimCache() => action('cache-reclaim');
  @override
  Future<void> pause() async {
    historyCopy = null;
    await action('pause');
  }

  @override
  Future<void> initialize() => action('initialize');
  void publish() => notifyListeners();
}
