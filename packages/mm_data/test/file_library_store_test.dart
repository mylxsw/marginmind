import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  final editor = StudySetEditor(newId: newId, now: () => DateTime(2026, 10, 25));

  setUp(() async => dir = await Directory.systemTemp.createTemp('mm_data_test'));
  tearDown(() async => dir.delete(recursive: true));

  test('creates, edits and reloads a study set from disk', () async {
    final store = FileLibraryStore(dir, clock: () => DateTime(2026, 10, 25, 9));
    final set = await store.create(const NewStudySet(title: '认知心理学', colorIndex: 2));

    final pdf = File(p.join(dir.path, 'source.pdf'))..writeAsBytesSync(List.filled(64, 7));
    final fileName = await store.importFile(set.id, pdf.path);
    expect(File(store.resolveFile(set.id, fileName)).existsSync(), isTrue);
    expect(await store.importFile(set.id, pdf.path), fileName, reason: 'same bytes dedupe');

    await store.update(set.id, (c) {
      final (c1, doc) = editor.addDocument(c, title: '记忆', fileName: fileName, pageCount: 120);
      final (c2, _) = editor.createExcerpt(
        c1,
        documentId: doc.id,
        page: 5,
        rects: const [PageRect(1, 2, 3, 1)],
        quote: '遗忘曲线',
        colorIndex: 0,
      );
      return editor.setLastPage(c2, doc.id, 12);
    });
    await store.setStarred(set.id, starred: true);
    await store.dispose();

    final reopened = FileLibraryStore(dir);
    final sets = await reopened.watchAll().first;
    expect(sets.single.title, '认知心理学');
    expect(sets.single.starred, isTrue);
    expect(sets.single.documentCount, 1);
    expect(sets.single.cardCount, 1);
    expect(sets.single.lastPosition!.page, 12);
    final content = await reopened.load(set.id);
    expect(content.annotations.single.quote, '遗忘曲线');
    await reopened.dispose();
  });

  test('content watchers see updates; damaged packages are skipped', () async {
    final store = FileLibraryStore(dir);
    final set = await store.create(const NewStudySet(title: 'A', colorIndex: 0));
    final counts = <int>[];
    final sub = store.watch(set.id).listen((c) => counts.add(c.cards.length));
    await Future<void>.delayed(Duration.zero);
    await store.update(set.id, (c) => editor.addTopic(c, title: 'T').$1);
    await Future<void>.delayed(Duration.zero);
    expect(counts, [0, 1]);
    await sub.cancel();
    await store.dispose();

    final broken = Directory(p.join(dir.path, 'sets', 'broken.mmset'))..createSync(recursive: true);
    File(p.join(broken.path, 'studyset.json')).writeAsStringSync('{not json');
    final reopened = FileLibraryStore(dir);
    expect((await reopened.watchAll().first).map((s) => s.title), ['A']);
    await reopened.dispose();
  });

  test('unknown ids throw', () async {
    final store = FileLibraryStore(dir);
    expect(() => store.load('nope'), throwsStateError);
    await store.dispose();
  });
}
