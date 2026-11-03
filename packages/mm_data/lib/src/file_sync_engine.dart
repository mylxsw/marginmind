import 'dart:async';
import 'dart:convert';

import 'package:mm_sync/mm_sync.dart';

import 'file_sync_ledger.dart';
import 'file_sync_receiver.dart';

class SyncRunResult {
  const SyncRunResult({this.received = 0, this.confirmed = 0, this.staged = 0});
  final int received, confirmed, staged;
}

/// Explicit foreground cycle. No credentials or automatic timers are persisted.
/// Bind/resume is separate from constructing an adapter or discovering a library.
class FileSyncEngine {
  FileSyncEngine(this.ledger, this.receiver);
  final FileSyncLedger ledger;
  final FileSyncReceiver receiver;
  SyncObjectTransport? _transport;
  int _generation = 0;
  Future<SyncRunResult>? _running;
  bool get running => _running != null;

  Future<void> bind(SyncObjectTransport transport) async {
    _generation++;
    _transport = null;
    await ledger.bindTransport(transport.target); // Always paused after a binding change.
    _transport = transport;
  }

  Future<void> pause() async {
    _generation++; // Invalidates a pending response before storage IO can block.
    await ledger.pauseTransport();
  }

  Future<void> resume() async {
    final target = _transport?.target;
    if (target == null) throw const SyncTransportException(SyncTransportProblem.paused);
    await ledger.resumeTransport(target.key);
  }

  Future<SyncRunResult> run() {
    if (_running case final existing?) return existing;
    late final Future<SyncRunResult> future;
    future = _run().whenComplete(() {
      if (identical(_running, future)) _running = null;
    });
    _running = future;
    return future;
  }

  Future<SyncRunResult> _run() async {
    final remote = _transport, generation = _generation;
    final connection = await ledger.transportConnection();
    if (remote == null || connection == null || connection.paused || connection.target.key != remote.target.key) {
      throw const SyncTransportException(SyncTransportProblem.paused);
    }
    Future<void> check() async {
      if (generation != _generation) throw const SyncTransportException(SyncTransportProblem.paused);
      final active = await ledger.transportConnection();
      if (active == null ||
          active.paused ||
          active.revision != connection.revision ||
          active.target.key != remote.target.key) {
        throw const SyncTransportException(SyncTransportProblem.paused);
      }
    }

    await receiver.validateLedger(ledger);
    var history = await ledger.history();
    // The unpublished v1 JSON digest cannot be transported safely across VM/JS.
    // No lossy re-ID, history clearing, or network IO before this explicit gate.
    if (history.values.any((c) => c.protocol != syncProtocolVersion)) {
      throw const SyncTransportException(SyncTransportProblem.legacyProtocol);
    }
    await check();
    await remote.prepare();
    await check();
    final manifest = await remote.read('library.json');
    await check();
    if (manifest != null) validateSyncLibrary(manifest, ledger.libraryId);
    final manifestDelivery = await remote.create('library.json', syncLibraryManifest(ledger.libraryId));
    await check();
    final ids = await remote.listCommits();
    await check();
    final incoming = <SyncCommit>[];
    for (final id in ids) {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
        throw const SyncTransportException(SyncTransportProblem.invalidResponse);
      }
      if (history.containsKey(id)) continue;
      await check();
      final bytes = await remote.read('commits/$id.json');
      await check();
      if (bytes == null) throw const SyncTransportException(SyncTransportProblem.unavailable);
      checkSyncObjectSize(bytes);
      SyncCommit c;
      try {
        final json = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
        if (json['protocol'] != syncProtocolVersion) {
          throw const SyncTransportException(SyncTransportProblem.legacyProtocol);
        }
        c = SyncCommit.fromJson(json);
      } on SyncTransportException {
        rethrow;
      } catch (_) {
        throw const SyncTransportException(SyncTransportProblem.invalidResponse);
      }
      if (c.id != id || c.libraryId != ledger.libraryId || !isSyncWireScope(c.scope)) {
        throw const SyncTransportException(SyncTransportProblem.invalidResponse);
      }
      incoming.add(c);
    }
    await check();
    if (incoming.isNotEmpty) await receiver.receive(incoming);
    await check();
    await receiver.retry();
    await check();
    history = await ledger.history();
    if (history.values.any((c) => c.protocol != syncProtocolVersion)) {
      throw const SyncTransportException(SyncTransportProblem.legacyProtocol);
    }
    final outgoing = (await ledger.pending(
      target: connection.target.key,
      includeDelivered: true,
    )).where((c) => isSyncWireScope(c.scope)).toList();
    final candidates = {for (final c in outgoing) c.id: c};
    final available = ids.toSet();
    // A changed target may not have remote-authored ancestors. Never publish a
    // partial graph or upload private recovery files to fill that gap.
    bool reconstructible(String id) {
      final c = history[id];
      if (c == null) return false;
      if (c.deviceId == 'translation-baseline-v1') return c.id == translationBaseline(c.libraryId, c.scope).id;
      if (c.deviceId == 'vocabulary-baseline-v1') {
        final word = VocabularyWord.fromJson(c.payload);
        return c.id == vocabularyBaseline(c.libraryId, word.language, word.key).id;
      }
      return false;
    }

    for (final c in outgoing) {
      for (final ref in [...c.parents, ...c.requires.values]) {
        if (!available.contains(ref) && !candidates.containsKey(ref) && !reconstructible(ref)) {
          throw const SyncTransportException(SyncTransportProblem.missingHistory);
        }
      }
    }
    var confirmed = 0, staged = manifestDelivery == SyncDelivery.staged ? 1 : 0;
    // Topological publication also follows cross-domain requires dependencies.
    final remaining = Map<String, SyncCommit>.of(candidates);
    while (remaining.isNotEmpty) {
      final ready =
          remaining.values
              .where((c) => [...c.parents, ...c.requires.values].every((id) => !remaining.containsKey(id)))
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      if (ready.isEmpty) throw const SyncTransportException(SyncTransportProblem.invalidResponse);
      for (final c in ready) {
        await check();
        final eligible = await ledger.pending(target: connection.target.key, includeDelivered: true);
        if (!eligible.any((v) => v.id == c.id)) {
          // A draft began while this cycle awaited IO. Dependants wait too.
          return SyncRunResult(received: incoming.length, confirmed: confirmed, staged: staged);
        }
        final delivery = await remote.create('commits/${c.id}.json', utf8.encode(jsonEncode(c.toJson())));
        await check();
        if (delivery == SyncDelivery.confirmed && manifestDelivery == SyncDelivery.confirmed) {
          await ledger.acknowledge([c.id], target: connection.target.key, connectionRevision: connection.revision);
          confirmed++;
        } else {
          staged++;
        }
        remaining.remove(c.id);
      }
    }
    return SyncRunResult(received: incoming.length, confirmed: confirmed, staged: staged);
  }
}
