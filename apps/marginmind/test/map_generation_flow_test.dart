import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/map_generation_cache.dart';
import 'package:marginmind/features/assistant/map_generation_context.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'map_generation_context_test.dart' show DigestReader, pdf, outline, annotation, digest;

void main() {
  test('two chapters to map, cache replay and only changed chapter reread before diff', () async {
    final builder = DocumentDigestBuilder(DigestReader({1: 'one', 2: 'two', 3: 'three', 4: 'four'}));
    final cache = MapDigestCache(null);
    final engine = FakeMapGenerator(
      chapters: {
        'private-doc:c1:0': ['{"k":"point","id":"p1","title":"One","page":1}'],
        'private-doc:c2:0': ['{"k":"point","id":"p1","title":"Two","page":3,"marks":["A1"]}'],
      },
      generation: ['{"ref":"a","parent":"ROOT","title":"Map branch","page":1}'],
      diff: ['{"op":"add","ref":"b","parent":"ROOT","title":"New material","page":4}'],
    );
    final snapshot = StudySetContent(
      documents: [pdf(lastPage: 2)],
      documentOutlines: [outline],
      annotations: [annotation('mark', 3)],
    );
    Future<List<MapLine>> read(DocumentDigest plan, String prefix) async {
      final points = <MapLine>[];
      for (final chapter in plan.chapters) {
        final input = chapter.input;
        final key = mapDigestCacheKey(
          source: plan.source,
          chapterId: input.chapterId,
          chapterFingerprint: chapter.fingerprint,
          model: 'service:model:v1',
          organization: input.organization,
        );
        final raw = await cache.read(key, context: input.context);
        if (raw != null) {
          points.addAll(raw.map((line) => parseMapLine(line, input.context)!));
        } else {
          final read = await engine.readChapter(input, CancellationToken()).toList();
          await cache.write(key, mapPointCacheLines(read, input.context), context: input.context);
          points.addAll(read);
        }
      }
      return points;
    }

    MapBuildInput build(DocumentDigest plan, List<MapLine> points, MapLinePhase phase) => MapBuildInput(
      title: 'Map',
      generation: MapGeneration(
        sources: [plan.source],
        organization: MapOrganization.chapter,
        depth: 2,
        generatedAt: DateTime.utc(2026),
      ),
      points: points,
      context: MapLineContext(
        phase: phase,
        mapId: 'map',
        draftPrefix: 'build-',
        documents: {'D1': 'private-doc'},
        pages: {
          'D1': {1, 2, 3, 4},
        },
        annotations: {'A1': 'mark'},
      ),
    );
    final first = await digest(builder, snapshot);
    final points = await read(first, 'first');
    expect(points.map((p) => p.title), ['One', 'Two']);
    expect(
      await engine.generate(build(first, points, MapLinePhase.generation), CancellationToken()).toList(),
      hasLength(1),
    );
    final next = await digest(builder, snapshot.copyWith(annotations: [annotation('mark', 3), annotation('new', 4)]));
    final updated = await read(next, 'next');
    expect(updated, hasLength(2));
    expect(engine.calls.where((c) => c.startsWith('chapter:')), [
      'chapter:private-doc:c1:0',
      'chapter:private-doc:c2:0',
      'chapter:private-doc:c2:0',
    ]);
    final diff = await engine.update(build(next, updated, MapLinePhase.diff), CancellationToken()).toList();
    expect(diff.single.title, 'New material');
    expect(mapSourcesChanged(build(first, points, MapLinePhase.generation).generation, [next.source]), isTrue);
    await engine.close();
  });
}
