part of 'file_library_store.dart';

enum SyncResourceAvailability { available, missing, unverified, changed }

class SyncResourceStatus {
  const SyncResourceStatus(this.studySetId, this.group, this.title, this.revision, this.availability, this.bytes);
  final String studySetId, group, title, revision;
  final SyncResourceAvailability availability;
  final int bytes;
}

extension FileLibraryResources on FileLibraryStore {
  String _referencedResourceToken(String id, String path) => syncDigest({
    'references': [
      for (final group in _sets[id] == null ? <SyncResourceGroup>[] : syncResourceGroups(_sets[id]!.content))
        if ((group.key.startsWith('image/') || group.key.startsWith('research/')) && group.roots.contains(path))
          {'group': group.key, 'file': _sets[id]?.resources?.groups[group.key]?[path]?.toJson()},
    ],
    'epoch': _resourceVersions[id] ?? 0,
  });

  Stream<ReferencedResource> _watchReferencedResource(String id, String path) =>
      _watch(
        _contentChanges.stream.where((changed) => changed == id),
        () => _referencedResourceToken(id, path),
      ).distinct().asyncMap((token) async {
        final record = _sets[id];
        final references = record == null
            ? <SyncResourceGroup>[]
            : syncResourceGroups(record.content)
                  .where((g) => (g.key.startsWith('image/') || g.key.startsWith('research/')) && g.roots.contains(path))
                  .toList();
        if (references.isEmpty || !validSyncResourcePath(path)) {
          return ReferencedResource(DocumentResourceAvailability.missing);
        }
        try {
          final location = _resolvePath(id, path);
          // Inspect rejects symlinks into private storage as well as invalid
          // sizes. Verify the returned bytes again, not just the path.
          final actual = await ResourceCache(root).inspect(location);
          if (actual == null) return ReferencedResource(DocumentResourceAvailability.missing);
          for (final reference in references) {
            final expected = record!.resources?.groups[reference.key]?[path];
            if (expected != null && !contentValueEquals(expected.toJson(), actual.toJson())) {
              return ReferencedResource(DocumentResourceAvailability.changed);
            }
          }
          final bytes = await File(location).readAsBytes();
          final hash = sha256.convert(bytes).toString();
          final namedHash = RegExp(r'/([a-f0-9]{64})\.[a-z0-9]+$').firstMatch(path)?.group(1);
          if (bytes.length != actual.length ||
              hash != actual.hash ||
              (namedHash != null && namedHash != hash) ||
              token != _referencedResourceToken(id, path)) {
            return ReferencedResource(DocumentResourceAvailability.changed);
          }
          return ReferencedResource(DocumentResourceAvailability.ready, bytes);
        } catch (_) {
          return ReferencedResource(DocumentResourceAvailability.changed);
        }
      });

  Stream<DocumentResourceAvailability> _watchDocumentResources(String id, String documentId) =>
      _watch(_contentChanges.stream.where((changed) => changed == id), () {
        final record = _sets[id], doc = _sets[id]?.content.document(documentId);
        final group = doc == null ? null : 'document/${doc.id}/${readingDocumentVersion(doc)}';
        final files = record?.resources?.groups[group];
        return syncDigest({
          'group': group,
          'files': files == null ? null : {for (final f in files.entries) f.key: f.value.toJson()},
          'epoch': _resourceVersions[id] ?? 0,
        });
      }).distinct().asyncMap((_) async {
        if (_sync == null) return DocumentResourceAvailability.ready;
        final record = _sets[id], doc = _sets[id]?.content.document(documentId);
        if (doc == null) return DocumentResourceAvailability.missing;
        final files = record?.resources?.groups['document/${doc.id}/${readingDocumentVersion(doc)}'];
        if (files == null) {
          return await File(_resolvePath(id, doc.contentManifest ?? doc.fileName)).exists()
              ? DocumentResourceAvailability.ready
              : DocumentResourceAvailability.missing;
        }
        var missing = false;
        for (final file in files.entries) {
          try {
            final actual = await ResourceCache(root).inspect(_resolvePath(id, file.key));
            if (actual == null) {
              missing = true;
            } else if (!contentValueEquals(actual.toJson(), file.value.toJson())) {
              return DocumentResourceAvailability.changed;
            }
          } catch (_) {
            return DocumentResourceAvailability.changed;
          }
        }
        return missing ? DocumentResourceAvailability.missing : DocumentResourceAvailability.ready;
      });

  /// Build manifests from explicit content references, never directory scans.
  /// Missing files on a newly joined device do not prevent metadata exchange.
  Future<void> prepareSyncResources() async {
    await _ensureLoaded();
    if (_sync == null) return;
    await _sync!.stageResources(() async {
      final cache = ResourceCache(root);
      for (final id in _sets.keys.toList()) {
        await _queueWrite(id, () async {
          if (!_sets.containsKey(id) || _contentTransactions.containsKey(id)) return;
          final record = _require(id);
          final groups = <String, Map<String, SyncResourceFile>>{...?record.resources?.retain(record.content).groups};
          for (final capability in syncResourceGroups(record.content)) {
            final existing = groups[capability.key];
            final paths = Set<String>.of(capability.roots);
            final files = <String, SyncResourceFile>{};
            final expected = <String, String>{};
            var missing = false;
            // The package's two manifests describe the dependency closure. They
            // cannot grant access outside the content-derived package capability.
            for (final manifest in [
              if (capability.bookBase != null) '${capability.bookBase}/manifest.json',
              if (capability.webBase != null) '${capability.webBase}/resources.json',
            ]) {
              if (!capability.permits(manifest)) throw const FormatException('Invalid resource manifest path');
              final descriptor = await cache.inspect(_resolvePath(id, manifest), cache: true);
              if (descriptor == null) {
                missing = true;
                break;
              }
              if (descriptor.length > syncObjectLimit) throw const FormatException('Resource manifest too large');
              if (existing != null && !contentValueEquals(existing[manifest]?.toJson(), descriptor.toJson())) {
                throw const FormatException('Local resource manifest changed');
              }
              final bytes = await File(_resolvePath(id, manifest)).readAsBytes();
              if (sha256.convert(bytes).toString() != descriptor.hash) {
                throw const FormatException('Resource manifest changed');
              }
              final data = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
              final dependencies = syncResourceDependencies(capability, manifest, data);
              paths.addAll(dependencies.keys);
              expected.addAll(dependencies);
              // Preserve the very bytes whose references were followed below.
              files[manifest] = descriptor;
            }
            if (missing) continue;
            for (final path in paths) {
              if (!capability.permits(path)) throw const FormatException('Resource outside referenced package');
              final descriptor = await cache.inspect(_resolvePath(id, path), cache: true);
              if (descriptor == null) {
                missing = true;
                break;
              }
              if (existing != null && !contentValueEquals(existing[path]?.toJson(), descriptor.toJson())) {
                throw const FormatException('Local resource changed');
              }
              if (files[path] != null && !contentValueEquals(files[path]!.toJson(), descriptor.toJson())) {
                throw const FormatException('Resource manifest changed');
              }
              files[path] = descriptor;
            }
            if (!missing) {
              if (expected.entries.any((e) => files[e.key]?.hash != e.value)) {
                throw const FormatException('Resource dependency changed');
              }
              if (existing != null &&
                  (existing.length != files.length || !existing.keys.toSet().containsAll(files.keys))) {
                throw const FormatException('Resource list exceeds package references');
              }
              groups[capability.key] = files;
            }
          }
          final resources = SyncResources(groups)..validate(record.content);
          if (groups.isEmpty && record.resources == null ||
              contentValueEquals(resources.toJson(), record.resources?.toJson())) {
            return;
          }
          final next = record.copyWith(resources: resources);
          await _saveRecord(next);
          _sets[id] = next;
          _contentChanges.add(id);
        });
      }
    });
  }

  Future<List<SyncResourceStatus>> syncResources() async {
    await _ensureLoaded();
    final result = <SyncResourceStatus>[], cache = ResourceCache(root);
    for (final record in _sets.values.toList()) {
      for (final capability in syncResourceGroups(record.content)) {
        final files = record.resources?.groups[capability.key];
        var state = files == null ? SyncResourceAvailability.unverified : SyncResourceAvailability.available;
        for (final file in files?.entries ?? <MapEntry<String, SyncResourceFile>>[]) {
          try {
            final actual = await cache.inspect(_resolvePath(record.id, file.key));
            if (actual == null) {
              if (state != SyncResourceAvailability.changed) state = SyncResourceAvailability.missing;
            } else if (!contentValueEquals(actual.toJson(), file.value.toJson())) {
              state = SyncResourceAvailability.changed;
            }
          } catch (_) {
            state = SyncResourceAvailability.changed;
          }
        }
        final docId = capability.key.startsWith('document/') ? capability.key.split('/')[1] : null;
        final docs = record.content.documents.where((d) => d.id == docId);
        final entity = capability.key.split('/')[1];
        final label =
            docs.firstOrNull?.title ??
            (capability.key.startsWith('image/')
                ? record.content.cards.where((c) => c.id == entity).firstOrNull?.title
                : record.content.researchSources.where((s) => s.id == entity).firstOrNull?.title);

        result.add(
          SyncResourceStatus(
            record.id,
            capability.key,
            label == null || label.isEmpty ? record.title : '${record.title} · $label',
            syncDigest(
              files == null ? {'group': capability.key} : {for (final f in files.entries) f.key: f.value.toJson()},
            ),
            state,
            files?.values.fold<int>(0, (n, f) => n + f.length) ?? 0,
          ),
        );
      }
    }
    return result;
  }

  /// Download immutable chunks outside the write queue; publication rechecks
  /// the selected content manifest inside the queue, so a late download cannot
  /// restore a deleted/replaced document or overwrite a local file.
  Future<void> downloadSyncResource(
    SyncResourceStatus selected,
    SyncObjectTransport remote,
    Future<void> Function() check,
  ) async {
    await _ensureLoaded();
    final id = selected.studySetId;
    Map<String, SyncResourceFile> selection() {
      final record = _require(id), files = _require(id).resources?.groups[selected.group];
      if (files == null ||
          !syncResourceGroups(record.content).any((g) => g.key == selected.group) ||
          syncDigest({for (final f in files.entries) f.key: f.value.toJson()}) != selected.revision) {
        throw StateError('Resource selection changed');
      }
      return files;
    }

    final files = selection(), cache = ResourceCache(root);
    for (final descriptor in files.values) {
      for (var i = 0; i < descriptor.chunks.length; i++) {
        await check();
        selection();
        final hash = descriptor.chunks[i];
        var bytes = await cache.readChunk(hash);
        bytes ??= await remote.read('blobs/$hash.bin');
        await check();
        if (bytes == null) throw const SyncTransportException(SyncTransportProblem.unavailable);
        if (bytes.length != descriptor.chunkLength(i)) throw const FormatException('Invalid resource length');
        await cache.storeChunk(hash, bytes);
      }
    }
    final capability = syncResourceGroups(_require(id).content).firstWhere((g) => g.key == selected.group);
    final allowedPaths = Set<String>.of(capability.roots);
    for (final path in [
      if (capability.bookBase != null) '${capability.bookBase}/manifest.json',
      if (capability.webBase != null) '${capability.webBase}/resources.json',
    ]) {
      final descriptor = files[path];
      if (descriptor == null || descriptor.length > syncObjectLimit) {
        throw const FormatException('Missing resource manifest');
      }
      final bytes = <int>[];
      for (final hash in descriptor.chunks) {
        bytes.addAll((await cache.readChunk(hash))!);
      }
      if (sha256.convert(bytes).toString() != descriptor.hash) throw const FormatException('Corrupt resource manifest');
      final references = syncResourceDependencies(
        capability,
        path,
        (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(),
      );
      allowedPaths.addAll(references.keys);
      if (references.entries.any((e) => files[e.key]?.hash != e.value)) {
        throw const FormatException('Incomplete resource manifest');
      }
    }
    if (files.keys.any((path) => !allowedPaths.contains(path))) {
      throw const FormatException('Resource list exceeds package references');
    }
    await _queueWrite(id, () async {
      await check();
      selection();
      if (_contentTransactions.containsKey(id) || _editLeases.any((l) => l.id == id)) {
        throw StateError('Finish editing before downloading');
      }
      for (final file in files.entries) {
        await cache.materialize(_resolvePath(id, file.key), file.value, check);
      }
      _resourceVersions[id] = (_resourceVersions[id] ?? 0) + 1;
      _contentChanges.add(id);
      _syncStatusChanges.add(null);
    });
  }
}
