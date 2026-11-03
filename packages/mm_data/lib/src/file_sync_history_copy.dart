part of 'file_sync_engine.dart';

/// An in-memory, target-bound preview. Restart/pause/rebinding needs a fresh
/// preview; immutable remote objects make an interrupted copy retryable.
class SyncHistoryCopyPlan {
  SyncHistoryCopyPlan._(
    this._source,
    this.target,
    this._connectionRevision,
    this._generation,
    this._order,
    this._chunks,
    this.unverifiedVersions,
  );
  final SyncHistoryCopySource _source;
  final SyncTarget target;
  final String _connectionRevision;
  final int _generation;
  final int unverifiedVersions;
  final List<SyncCommit> _order;
  final Set<String> _chunks;
  int get commits => _order.length;
  int get otherDeviceCommits => _order
      .where(
        (c) =>
            !_source.ownIds.contains(c.id) &&
            !{'vocabulary-baseline-v1', 'translation-baseline-v1'}.contains(c.deviceId),
      )
      .length;
  int get chunks => _chunks.length;
  int get excluded => _source.excluded;
}

extension SyncHistoryCopy on FileSyncEngine {
  /// Read-only network inspection: does not create a target or transfer data.
  Future<SyncHistoryCopyPlan> previewHistoryCopy() async {
    if (running) throw const SyncTransportException(SyncTransportProblem.unavailable);
    _previewing = true;
    try {
      return await _previewHistoryCopy();
    } finally {
      _previewing = false;
    }
  }

  Future<SyncHistoryCopyPlan> _previewHistoryCopy() async {
    _copyPlan = null;
    final remote = _transport, generation = _generation;
    if (remote == null) throw const SyncTransportException(SyncTransportProblem.paused);
    final observedConnection = await ledger.transportConnection();
    if (observedConnection == null) throw const SyncTransportException(SyncTransportProblem.paused);
    await receiver.validateLedger(ledger);
    final source = await ledger.historyCopySource();
    final history = source.commits;
    validatePortableSyncHistory(history);
    try {
      SyncGraph(history.values);
    } on FormatException {
      throw const SyncTransportException(SyncTransportProblem.missingHistory);
    }
    // Topological order includes dependencies even for modern-only histories.
    final remaining = Map<String, SyncCommit>.of(history), ordered = <SyncCommit>[];
    for (final c in history.values) {
      if (c.libraryId != ledger.libraryId ||
          c.requires.entries.any((e) => history[e.value]?.scope != e.key) ||
          [...c.parents, ...c.requires.values].any((id) => !history.containsKey(id))) {
        throw const SyncTransportException(SyncTransportProblem.missingHistory);
      }
      checkSyncObjectSize(utf8.encode(jsonEncode(c.toJson())));
    }
    while (remaining.isNotEmpty) {
      final ready =
          remaining.values
              .where((c) => [...c.parents, ...c.requires.values].every((id) => !remaining.containsKey(id)))
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      if (ready.isEmpty) throw const SyncTransportException(SyncTransportProblem.missingHistory);
      ordered.addAll(ready);
      for (final c in ready) {
        remaining.remove(c.id);
      }
    }
    Future<void> check() async {
      if (generation != _generation || !identical(remote, _transport)) {
        throw const SyncTransportException(SyncTransportProblem.paused);
      }
      final connection = await ledger.transportConnection();
      if (connection?.target.key != remote.target.key || connection?.revision != observedConnection.revision) {
        throw const SyncTransportException(SyncTransportProblem.paused);
      }
      await ledger.checkHistoryCopy(source.revision);
    }

    await check();
    final manifest = await remote.read('library.json');
    await check();
    if (manifest != null) validateSyncLibrary(manifest, ledger.libraryId);
    final cache = ResourceCache(receiver.library.root), chunks = <String>{};
    Future<List<int>> read(String hash) async {
      await check();
      final bytes = await cache.readChunk(hash) ?? await remote.read('blobs/$hash.bin');
      await check();
      if (bytes == null) throw const SyncTransportException(SyncTransportProblem.unavailable);
      checkSyncObjectData('blobs/$hash.bin', bytes);
      return bytes;
    }

    final verifiedFiles = <String>{};
    var unverified = 0;
    for (final c in ordered) {
      if (!c.scope.startsWith('sets/') || c.deleted) continue;
      final currentContent = contentFromDocument((c.payload['content'] as Map).cast<String, Object?>());
      final groups = syncResourceGroups(currentContent);
      if (c.payload['resources'] == null) {
        if (groups.isNotEmpty) unverified++;
        continue;
      }
      final resources = SyncResources.fromJson((c.payload['resources'] as Map).cast<String, Object?>());
      final content = contentFromDocument((c.payload['content'] as Map).cast<String, Object?>());
      resources.validate(content);
      if (groups.any((g) => !resources.groups.containsKey(g.key))) unverified++;
      final capabilities = {for (final g in syncResourceGroups(content)) g.key: g};
      for (final group in resources.groups.entries) {
        final capability = capabilities[group.key]!, files = group.value;
        final allowed = Set<String>.of(capability.roots);
        for (final path in [
          if (capability.bookBase != null) '${capability.bookBase}/manifest.json',
          if (capability.webBase != null) '${capability.webBase}/resources.json',
        ]) {
          final descriptor = files[path];
          if (descriptor == null || descriptor.length > syncObjectLimit) {
            throw const FormatException('Missing package manifest');
          }
          final bytes = <int>[];
          for (final hash in descriptor.chunks) {
            bytes.addAll(await read(hash));
          }
          if (bytes.length != descriptor.length || sha256.convert(bytes).toString() != descriptor.hash) {
            throw const FormatException('Corrupt package manifest');
          }
          final dependencies = syncResourceDependencies(
            capability,
            path,
            (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(),
          );
          allowed.addAll(dependencies.keys);
          if (dependencies.entries.any((e) => files[e.key]?.hash != e.value)) {
            throw const FormatException('Incomplete package references');
          }
        }
        if (files.keys.any((p) => !allowed.contains(p))) throw const FormatException('Unexpected package file');
        for (final file in files.values) {
          chunks.addAll(file.chunks);
          if (!verifiedFiles.add(syncDigest(file.toJson()))) continue;
          Stream<List<int>> bytes() async* {
            for (var i = 0; i < file.chunks.length; i++) {
              final value = await read(file.chunks[i]);
              if (value.length != file.chunkLength(i)) throw const FormatException('Wrong resource length');
              yield value;
            }
          }

          if ((await sha256.bind(bytes()).first).toString() != file.hash) {
            throw const FormatException('Corrupt historical resource');
          }
        }
      }
    }
    await check();
    return _copyPlan = SyncHistoryCopyPlan._(
      source,
      remote.target,
      observedConnection.revision,
      generation,
      ordered,
      chunks,
      unverified,
    );
  }

  Future<SyncRunResult> copyHistory(SyncHistoryCopyPlan plan) {
    if (running) return Future.error(const SyncTransportException(SyncTransportProblem.unavailable));
    late final Future<SyncRunResult> work;
    work = _copyHistory(plan).whenComplete(() {
      if (identical(_running, work)) _running = null;
      _copyPlan = null;
    });
    _running = work;
    return work;
  }

  Future<SyncRunResult> _copyHistory(SyncHistoryCopyPlan plan) async {
    final remote = _transport;
    if (!identical(_copyPlan, plan) || remote == null || plan._generation != _generation) {
      throw const SyncTransportException(SyncTransportProblem.paused);
    }
    final revision = await ledger.resumeHistoryCopy(plan.target.key, plan._connectionRevision, plan._source.revision);
    Future<void> check() async {
      final active = await ledger.transportConnection();
      if (plan._generation != _generation ||
          active == null ||
          active.paused ||
          active.revision != revision ||
          active.target.key != plan.target.key ||
          remote.target.key != plan.target.key) {
        throw const SyncTransportException(SyncTransportProblem.paused);
      }
      await ledger.checkHistoryCopy(plan._source.revision);
    }

    await check();
    final manifest = await remote.read('library.json');
    await check();
    if (manifest != null) validateSyncLibrary(manifest, ledger.libraryId);
    await remote.prepare();
    await check();
    var resourcesConfirmed =
        await remote.create('library.json', syncLibraryManifest(ledger.libraryId)) == SyncDelivery.confirmed;
    await check();
    final cache = ResourceCache(receiver.library.root);
    for (final hash in plan._chunks) {
      await check();
      final key = 'blobs/$hash.bin';
      final bytes = await cache.readChunk(hash) ?? await remote.read(key);
      await check();
      if (bytes == null) throw const SyncTransportException(SyncTransportProblem.unavailable);
      checkSyncObjectData(key, bytes);
      final delivery = await remote.create(key, bytes);
      await check();
      resourcesConfirmed = resourcesConfirmed && delivery == SyncDelivery.confirmed;
    }
    var confirmed = 0;
    for (final c in plan._order) {
      await check();
      final delivery = await remote.create('commits/${c.id}.json', utf8.encode(jsonEncode(c.toJson())));
      await check();
      if (resourcesConfirmed && delivery == SyncDelivery.confirmed) confirmed++;
    }
    if (confirmed == plan.commits) {
      await check();
      // Received authors remain received; ordinary pending never starts echoing
      // them. Only this device's existing outbox can be acknowledged.
      await ledger.acknowledge(plan._source.ownIds, target: plan.target.key, connectionRevision: revision);
    }
    return SyncRunResult(confirmed: confirmed, staged: plan.commits - confirmed);
  }
}
