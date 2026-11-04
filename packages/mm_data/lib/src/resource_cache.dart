// Required by the browser IO branch; dart:io also re-exports it on native.
// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:path/path.dart' as p;

import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';
import 'resource_io.dart' if (dart.library.js_interop) 'resource_browser_io.dart' as io;
import 'sync_cache_usage.dart';

/// Only explicit content references enter this cache. Chunks are immutable and
/// durable before the ledger can publish a manifest referring to them.
class ResourceCache {
  ResourceCache(this.root);
  final Directory root;

  /// Called with the owning ledger queue held and new manifest staging excluded.
  /// Only fixed chunk names are considered; no package/private tree traversal.
  Future<SyncCacheUsage> usage(
    Set<String> retained, {
    bool reclaim = false,
    bool staging = false,
    bool incompleteHistory = false,
  }) async {
    if (reclaim && (!io.supportsCacheReclamation || staging || incompleteHistory)) {
      throw StateError('Cache reclamation is unavailable while resources are staged');
    }
    final directory = Directory(p.join(root.path, '.foliarc-sync', 'blobs'));
    await io.checkResourceLocation(root.path, directory.path);
    if (await File(directory.path).exists()) throw const FormatException('Invalid resource cache directory');
    var bytes = 0, chunks = 0, unusedBytes = 0, unusedChunks = 0, reclaimed = 0;
    if (await directory.exists()) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !RegExp(r'^[a-f0-9]{64}$').hasMatch(p.basename(entity.path))) continue;
        await io.checkResourceLocation(root.path, entity.path);
        final length = await io.resourceLength(entity.path);
        if (!retained.contains(p.basename(entity.path))) {
          if (reclaim) {
            await io.checkResourceLocation(root.path, entity.path);
            await entity.delete();
            reclaimed += length;
            continue;
          }
          unusedBytes += length;
          unusedChunks++;
        }
        bytes += length;
        chunks++;
      }
    }
    return SyncCacheUsage(
      bytes: bytes,
      chunks: chunks,
      reclaimableBytes: staging || incompleteHistory ? 0 : unusedBytes,
      reclaimableChunks: staging || incompleteHistory ? 0 : unusedChunks,
      canReclaim: io.supportsCacheReclamation && !staging && !incompleteHistory,
      staging: staging,
      incompleteHistory: incompleteHistory,
      reclaimedBytes: reclaimed,
    );
  }

  String _chunk(String hash) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) throw const FormatException('Invalid chunk');
    return p.join(root.path, '.foliarc-sync', 'blobs', hash);
  }

  Future<List<int>?> readChunk(String hash) async {
    final path = _chunk(hash);
    await io.checkResourceLocation(root.path, path);
    final file = File(path);
    if (!await file.exists()) return null;
    if (await io.resourceLength(path) > syncResourceChunkSize) return null;
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != hash) return null;
    return bytes;
  }

  Future<void> storeChunk(String hash, List<int> bytes) async {
    if (bytes.length > syncResourceChunkSize || sha256.convert(bytes).toString() != hash) {
      throw const FormatException('Corrupt resource download');
    }
    final path = _chunk(hash);
    await io.checkResourceLocation(root.path, path);
    if (await readChunk(hash) != null) return;
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('$path.tmp');
    await io.checkResourceLocation(root.path, temporary.path);
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
  }

  Future<SyncResourceFile?> inspect(String path, {bool cache = false}) async {
    await io.checkResourceLocation(root.path, path);
    if (!await File(path).exists()) return null;
    final length = await io.resourceLength(path);
    if (length > syncResourceFileLimit) throw const FormatException('Resource too large');
    final result = _DigestSink();
    final digest = sha256.startChunkedConversion(result);
    var total = 0;
    final chunks = <String>[];
    var buffer = BytesBuilder(copy: false);
    Future<void> flush() async {
      final bytes = buffer.takeBytes();
      final hash = sha256.convert(bytes).toString();
      if (cache) await storeChunk(hash, bytes);
      chunks.add(hash);
    }

    await for (final bytes in io.readResource(path)) {
      total += bytes.length;
      if (total > syncResourceFileLimit) throw const FormatException('Resource too large');
      digest.add(bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final end = (offset + syncResourceChunkSize - buffer.length).clamp(0, bytes.length);
        buffer.add(bytes.sublist(offset, end));
        offset = end;
        if (buffer.length == syncResourceChunkSize) await flush();
      }
    }
    if (buffer.isNotEmpty) await flush();
    digest.close();
    await io.checkResourceLocation(root.path, path);
    if (length != total || await io.resourceLength(path) != total) throw const FormatException('Resource changed');
    return SyncResourceFile(hash: result.value!.toString(), length: total, chunks: chunks);
  }

  Future<void> materialize(String path, SyncResourceFile descriptor, Future<void> Function() check) async {
    await check();
    await io.checkResourceLocation(root.path, path);
    final existing = await inspect(path);
    if (existing != null) {
      if (existing.hash != descriptor.hash || existing.length != descriptor.length) {
        throw const FormatException('Local resource changed');
      }
      return;
    }
    final file = File(path), temporary = File('$path.sync-tmp');
    await file.parent.create(recursive: true);
    await io.checkResourceLocation(root.path, temporary.path);
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < descriptor.chunks.length; i++) {
        await check();
        final bytes = await readChunk(descriptor.chunks[i]);
        if (bytes == null || bytes.length != descriptor.chunkLength(i)) throw const FormatException('Missing chunk');
        yield bytes;
      }
    }

    await io.writeResourceStream(temporary.path, chunks());
    final verified = await inspect(temporary.path);
    if (verified?.hash != descriptor.hash || verified?.length != descriptor.length) {
      throw const FormatException('Corrupt assembled resource');
    }
    await check();
    await io.checkResourceLocation(root.path, path);
    if (await file.exists()) throw const FormatException('Resource appeared during download');
    await temporary.rename(path);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
