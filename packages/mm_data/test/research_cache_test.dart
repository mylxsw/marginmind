import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  test('cache clearing preserves package snapshots and handles repeated writes', () async {
    final root = await Directory.systemTemp.createTemp('research_cache_');
    addTearDown(() => root.delete(recursive: true));
    final store = FileLibraryStore(Directory('${root.path}/Library'));
    final set = await store.create(const NewStudySet(title: 'test', colorIndex: 0));
    final snapshot = await store.writeResearchSnapshot(set.id, 'retained evidence');
    final cache = ResearchWebCache(root);
    final url = Uri.parse('https://example.com/../../research/snapshots');
    expect(await cache.read(url), isNull);
    await cache.write(url, 'first');
    await cache.write(url, 'second');
    expect(await cache.read(url), 'second');
    await cache.clear();
    await cache.clear();
    expect(await cache.read(url), isNull);
    expect(await store.readResearchSnapshot(set.id, snapshot), 'retained evidence');
    await expectLater(cache.write(url, 'x' * 2097153), throwsArgumentError);
    await cache.write(url, 'after rejected write');
    expect(await cache.read(url), 'after rejected write');
  });
}
