import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';

final mapDigestCacheProvider = Provider.family<MapDigestCache, String>((ref, studySetId) {
  final repository = ref.watch(contentRepositoryProvider);
  final directory = repository.resolveFile(studySetId, '');
  return MapDigestCache(
    kIsWeb || !p.isAbsolute(directory) ? null : Directory(directory),
    sourcesExist: (documents, annotations) async {
      final content = await repository.load(studySetId);
      return documents.every((id) => content.document(id) != null) &&
          annotations.every((id) => content.annotation(id) != null);
    },
  );
});

/// Study-set-local success cache. One serial queue and epoch cover reads,
/// replacement and clearing; writes queued before clear cannot resurrect data.
class MapDigestCache {
  MapDigestCache(Directory? package, {this.sourcesExist})
    : directory = package == null ? null : Directory(p.join(package.path, 'ai-cache', 'map-digests', 'v1'));
  final Directory? directory;
  final Future<bool> Function(Iterable<String> documents, Iterable<String> annotations)? sourcesExist;
  final _memory = <String, String>{};
  Future<void> _tail = Future.value();
  int _epoch = 0;

  Future<T> _queue<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _checkKey(String key) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) throw ArgumentError('Invalid digest cache key');
  }

  /// Pass the new call's context to remap stored source IDs to its fresh aliases.
  /// Without it, aliases remain as written; IDs/draft refs are never cached.
  Future<List<String>?> read(String key, {MapLineContext? context}) {
    _checkKey(key);
    return _queue(() async {
      try {
        String? text;
        if (directory case final dir?) {
          final file = File(p.join(dir.path, '$key.json'));
          if (!await file.exists()) return null;
          text = await file.readAsString();
        } else {
          text = _memory[key];
        }
        if (text == null) return null;
        final data = jsonDecode(text) as Map;
        if (data['schema'] != 1 || data['key'] != key) return null;
        final documents = (data['documentAlias'] as Map).cast<String, String>();
        final annotations = (data['annotationAliases'] as Map).cast<String, String>();
        if (sourcesExist != null && !await sourcesExist!(documents.values, annotations.values)) return null;
        var lines = (data['lines'] as List).cast<String>();
        // Revalidate even well-formed envelopes: a corrupt cache is a miss.
        _normalize(lines, documents, annotations);
        if (context != null) {
          String remap(String alias, Map<String, String> old, Map<String, String> current) {
            final id = old[alias];
            return current.entries.firstWhere((e) => e.value == id).key;
          }

          lines = [
            for (final line in lines)
              (() {
                final j = jsonDecode(line) as Map<String, dynamic>;
                if (j['doc'] case final String doc) j['doc'] = remap(doc, documents, context.documents);
                if (j['doc'] == null && documents.length == 1) {
                  j['doc'] = remap(documents.keys.single, documents, context.documents);
                }
                if (j['marks'] case final List marks) {
                  j['marks'] = [for (final m in marks) remap(m as String, annotations, context.annotations)];
                }
                return jsonEncode(j);
              })(),
          ];
        }
        return List.unmodifiable(lines);
      } on FileSystemException {
        return null;
      } on FormatException {
        return null;
      } on TypeError {
        return null;
      } on ArgumentError {
        return null;
      } on StateError {
        return null;
      }
    });
  }

  /// Only call after the chapter stream completed successfully. Supplying its
  /// context records local source capabilities, never the input document text.
  Future<void> write(String key, List<String> rawPointLines, {MapLineContext? context}) {
    _checkKey(key);
    final epoch = _epoch;
    final documents = context?.documents ?? const <String, String>{};
    final annotations = context?.annotations ?? const <String, String>{};
    final lines = _normalize(rawPointLines, documents, annotations);
    final text = jsonEncode({
      'schema': 1,
      'key': key,
      'documentAlias': documents,
      'annotationAliases': annotations,
      'lines': lines,
    });
    return _queue(() async {
      if (epoch != _epoch) return;
      if (directory case final dir?) {
        await dir.create(recursive: true);
        final destination = File(p.join(dir.path, '$key.json'));
        final temporary = File('${destination.path}.tmp');
        try {
          await temporary.writeAsString(text, flush: true);
          if (epoch == _epoch) await temporary.rename(destination.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      } else {
        _memory[key] = text;
      }
    });
  }

  List<String> _normalize(List<String> lines, Map<String, String> documents, Map<String, String> annotations) {
    if (lines.isEmpty) throw ArgumentError('Empty chapter');
    final parser = MapLineContext(
      phase: MapLinePhase.chapter,
      mapId: 'cache',
      draftPrefix: 'cache-',
      documents: documents,
      pages: const {},
      annotations: annotations,
    );
    return [
      for (final raw in lines)
        (() {
          if (parseMapLine(raw, parser) == null) throw ArgumentError('Invalid cached point');
          return jsonEncode(jsonDecode(raw));
        })(),
    ];
  }

  Future<int> sizeBytes() => _queue(() async {
    final parent = directory?.parent;
    if (parent == null) return _memory.values.fold<int>(0, (sum, text) => sum + utf8.encode(text).length);
    if (!await parent.exists()) return 0;
    var size = 0;
    await for (final entry in parent.list(recursive: true, followLinks: false)) {
      if (entry is File) size += await entry.length();
    }
    return size;
  });

  Future<void> clear() {
    _epoch++;
    return _queue(() async {
      _memory.clear();
      // Remove only map-digests, including obsolete schema versions.
      final parent = directory?.parent;
      if (parent != null && await parent.exists()) await parent.delete(recursive: true);
    });
  }
}

/// Convert successful parsed chapter results back to portable point NDJSON.
/// References are response-local; real IDs remain only in the envelope tables.
List<String> mapPointCacheLines(List<MapLine> points, MapLineContext context) {
  final refs = <String, String>{};
  String alias(Map<String, String> table, String id) => table.entries.firstWhere((e) => e.value == id).key;
  return [
    for (final (i, point) in points.indexed)
      (() {
        if (point.kind != MapLineKind.point || refs.containsKey('new:${point.id}')) {
          throw ArgumentError('Expected unique chapter points');
        }
        final parent = point.parentId == context.mapId || point.parentId == context.rootParentId
            ? 'ROOT'
            : refs[point.parentId];
        if (parent == null) throw ArgumentError('Missing point parent');
        final ref = 'p${i + 1}';
        refs['new:${point.id}'] = ref;
        return jsonEncode({
          'k': 'point',
          'id': ref,
          'parent': parent,
          'title': point.title,
          if (point.quote != null) 'quote': point.quote,
          if (point.source ?? point.quoteSource case final source?) ...{
            'doc': alias(context.documents, source.documentId),
            'page': source.page,
          },
          'marks': [for (final mark in point.marks) alias(context.annotations, mark)],
        });
      })(),
  ];
}

/// Settings covers every study set, while each cache retains its own queue.
final mapDigestCachesProvider = FutureProvider<List<MapDigestCache>>((ref) async {
  final sets = await ref.watch(studySetsProvider.future);
  return [for (final set in sets) ref.watch(mapDigestCacheProvider(set.id))];
});
final mapDigestCacheSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  final caches = await ref.watch(mapDigestCachesProvider.future);
  final sizes = await Future.wait(caches.map((c) => c.sizeBytes()));
  return sizes.fold<int>(0, (sum, size) => sum + size);
});
