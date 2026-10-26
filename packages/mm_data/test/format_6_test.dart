import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File file;
  late List<int> source;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mm_format6_');
    file = File('${root.path}/sets/legacy.mmset/studyset.json');
    await file.parent.create(recursive: true);
    source = await File('test/fixtures/format-5.json').readAsBytes();
    await file.writeAsBytes(source);
  });
  tearDown(() => root.delete(recursive: true));

  test('fixed format 5 preserves all data and due counts, migrates only once', () async {
    final original = jsonDecode(utf8.decode(source)) as Map;
    final before = StudySetContent.fromJson((original['content'] as Map).cast());
    final store = FileLibraryStore(root);
    final c = await store.load('legacy');
    final migrated = jsonDecode(await file.readAsString()) as Map;
    expect(migrated['format'], 6);
    for (final key in original.keys.where((k) => k != 'format' && k != 'content')) {
      expect(migrated[key], original[key]);
    }
    for (final key in (original['content'] as Map).keys) {
      expect(migrated['content'][key], original['content'][key], reason: '$key must survive');
    }
    expect(c.reviewLogs, isEmpty);
    expect(c.memoryStates.length, c.reviews.length);
    expect(c.reviews.map((r) => r.toJson()), before.reviews.map((r) => r.toJson()));
    expect(c.cards.every((card) => !card.suspended), isTrue);
    for (var day = 0; day < 30; day++) {
      final time = DateTime.utc(2026, 10, 20 + day);
      expect(c.reviewQueue(time).map((c) => c.id), before.reviewQueue(time).map((c) => c.id));
    }
    final backup = File('${file.path}.format-5.bak');
    expect(await backup.readAsBytes(), source);
    final bytes = await file.readAsBytes();
    final modified = (await file.stat()).modified;
    final backupModified = (await backup.stat()).modified;
    await store.dispose();
    for (var i = 0; i < 2; i++) {
      final reopened = FileLibraryStore(root);
      expect((await reopened.load('legacy')).toJson(), c.toJson());
      expect(await file.readAsBytes(), bytes);
      expect((await file.stat()).modified, modified);
      expect(await backup.readAsBytes(), source);
      expect((await backup.stat()).modified, backupModified);
      expect(await File('${file.path}.format-6.bak').exists(), isFalse);
      await reopened.dispose();
    }
  });

  test('format 5 interrupted replacement and conflicting backup never destroy source', () async {
    final obstruction = Directory('${file.path}.tmp');
    await obstruction.create();
    var store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(store.packageLoadErrors, isNotEmpty);
    expect(await file.readAsBytes(), source);
    final backup = File('${file.path}.format-5.bak');
    expect(await backup.readAsBytes(), source);
    await store.dispose();
    await obstruction.delete();
    await backup.writeAsString('conflict');
    store = FileLibraryStore(root);
    expect(await store.watchAll().first, isEmpty);
    expect(await file.readAsBytes(), source);
    expect(await backup.readAsString(), 'conflict');
    await store.dispose();
    await backup.writeAsBytes(source);
    store = FileLibraryStore(root);
    expect((await store.load('legacy')).cards.length, 3);
    expect(jsonDecode(await file.readAsString())['format'], 6);
    await store.dispose();
  });

  test('format 6 edits persist logs, memory and suspension across reopen', () async {
    final store = FileLibraryStore(root);
    var id = 0;
    final editor = StudySetEditor(newId: () => 'log-${id++}', now: () => DateTime.utc(2026, 10, 26));
    final first = await store.update('legacy', (c) => editor.rate(c, 'excerpt', Rating.good));
    await store.update('legacy', (c) => editor.rate(c, 'excerpt', Rating.again));
    await store.update(
      'legacy',
      (c) => editor.setMemoryState(
        c,
        const MemoryState(cardId: 'excerpt', stability: 3.5, difficulty: 4.5, phase: MemoryPhase.review),
      ),
    );
    final result = await store.update('legacy', (c) => editor.setSuspended(c, 'excerpt', suspended: true));
    await store.dispose();
    final reopened = FileLibraryStore(root);
    final c = await reopened.load('legacy');
    expect(c.toJson(), result.toJson());
    expect(c.reviewLogs.map((r) => r.intervalBefore), [3.0, first.reviewOf('excerpt')!.intervalDays]);
    expect(c.reviewLogs.map((r) => r.intervalAfter), [first.reviewOf('excerpt')!.intervalDays, 0]);
    expect(c.card('excerpt')!.suspended, isTrue);
    expect(c.memoryOf('excerpt')!.stability, 3.5);
    expect(await File('${file.path}.format-5.bak').readAsBytes(), source);
    await reopened.dispose();
  });
}
