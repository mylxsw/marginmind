import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/map_generation_cache.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

MapLineContext ctx({String doc = 'D1', String mark = 'A1'}) => MapLineContext(
  phase: MapLinePhase.chapter,
  mapId: 'map',
  draftPrefix: 'fresh-',
  documents: {doc: 'doc'},
  annotations: {mark: 'mark'},
  pages: {
    doc: {1},
  },
);
const point = '{"k":"point","id":"p1","title":"Point","doc":"D1","page":1,"marks":["A1"]}';
void main() {
  test('disk roundtrip, alias remap, corrupt misses, deletion and isolated clear', () async {
    final dir = await Directory.systemTemp.createTemp('map-cache-test-');
    addTearDown(() => dir.delete(recursive: true));
    final key = 'a' * 64;
    final cache = MapDigestCache(
      dir,
      sourcesExist: (docs, marks) async => docs.single == 'doc' && marks.single == 'mark',
    );
    expect(await cache.read(key), isNull);
    await cache.write(key, [point], context: ctx());
    final values = await cache.read(
      key,
      context: ctx(doc: 'D2', mark: 'A2'),
    );
    final parsed = parseMapLine(values!.single, ctx(doc: 'D2', mark: 'A2'))!;
    expect(parsed.source?.documentId, 'doc');
    expect(parsed.marks, ['mark']);
    expect(parsed.id, 'fresh-1');
    final file = File('${cache.directory!.path}/$key.json');
    final envelope = jsonDecode(await file.readAsString()) as Map;
    expect(envelope['documentAlias'], {'D1': 'doc'});
    expect(await File('${file.path}.tmp').exists(), isFalse);
    expect(
      await cache.read(
        key,
        context: MapLineContext(phase: MapLinePhase.chapter, mapId: 'm', draftPrefix: 'x', documents: {}, pages: {}),
      ),
      isNull,
    );
    for (final broken in [
      'invalid',
      jsonEncode({...envelope, 'schema': 2}),
      jsonEncode({
        ...envelope,
        'lines': ['invalid'],
      }),
      jsonEncode({
        ...envelope,
        'lines': [2],
      }),
    ]) {
      await file.writeAsString(broken);
      expect(await cache.read(key), isNull);
    }
    await cache.write(key, [point], context: ctx());
    expect(await MapDigestCache(dir, sourcesExist: (_, _) async => false).read(key), isNull);
    final sibling = File('${dir.path}/ai-cache/other.txt');
    await sibling.writeAsString('keep');
    await cache.clear();
    expect(await cache.read(key), isNull);
    expect(await sibling.readAsString(), 'keep');
  });
  test('clear epoch cancels queued writes, later writes work', () async {
    final dir = await Directory.systemTemp.createTemp('map-cache-epoch-');
    addTearDown(() => dir.delete(recursive: true));
    final cache = MapDigestCache(dir), key = 'b' * 64;
    final old = cache.write(key, [point], context: ctx());
    final clear = cache.clear();
    await Future.wait([old, clear]);
    expect(await cache.read(key), isNull);
    expect(await cache.directory!.exists(), isFalse);
    await cache.write(key, [point], context: ctx());
    expect(await cache.read(key), hasLength(1));
  });
  test('memory cache validates keys, complete point sequences and clearing', () async {
    final cache = MapDigestCache(null), key = 'c' * 64;
    expect(() => cache.read('../escape'), throwsArgumentError);
    expect(() => cache.write(key, []), throwsArgumentError);
    expect(() => cache.write(key, ['invalid']), throwsArgumentError);
    await cache.write(key, ['{"k":"point","id":"p1","title":"Safe"}']);
    expect(await cache.read(key), hasLength(1));
    await cache.clear();
    expect(await cache.read(key), isNull);
    expect(() => cache.write(key, [point]), throwsArgumentError);
    expect(() => cache.write('x', [point]), throwsArgumentError);
  });
  test('provider selects memory and checks current source existence', () async {
    final repo = InMemoryStudySetContentRepository();
    final container = ProviderContainer(overrides: [contentRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final cache = container.read(mapDigestCacheProvider('set')), key = 'd' * 64;
    expect(cache.directory, isNull);
    await cache.write(key, [point], context: ctx());
    expect(await cache.read(key), isNull);
    await repo.update(
      'set',
      (c) => c.copyWith(
        documents: [Document(id: 'doc', title: '', fileName: '', pageCount: 1, importedAt: DateTime.utc(2026))],
        annotations: [
          Annotation(
            id: 'mark',
            documentId: 'doc',
            page: 1,
            rects: [],
            quote: '',
            colorIndex: 0,
            createdAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    expect(await cache.read(key), hasLength(1));
  });
}
