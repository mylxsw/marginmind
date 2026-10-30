import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

VocabularyEntry entry(String term) => VocabularyEntry(
  id: term,
  term: term,
  language: 'en',
  kind: VocabularyKind.word,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  forms: [term],
);
void main() {
  late Directory dir;
  late FileVocabularyStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vocabulary-test');
    store = FileVocabularyStore(dir);
  });
  tearDown(() async {
    await store.dispose();
    await dir.delete(recursive: true);
  });
  test('atomic durable save, immutable snapshot, watch initial and concurrent ordering', () async {
    final events = <List<VocabularyEntry>>[];
    final sub = store.watch().listen(events.add);
    await store.flush();
    await Future.wait([
      store.save([entry('cat')]),
      store.save([entry('dog')]),
    ]);
    await store.flush();
    await Future<void>.delayed(Duration.zero);
    expect(events.map((e) => e.map((v) => v.term).join()), ['', 'cat', 'dog']);
    expect((await store.load()).single.term, 'dog');
    final fresh = FileVocabularyStore(dir);
    expect((await fresh.load()).single.term, 'dog');
    await fresh.dispose();
    expect(await File('${dir.path}/vocabulary.json.tmp').exists(), isFalse);
    expect((jsonDecode(await File('${dir.path}/vocabulary.json').readAsString()) as Map)['format'], 1);
    await sub.cancel();
  });
  for (final source in [
    'broken',
    '{"format":2,"entries":[]}',
    '{"format":1,"entries":[{}]}',
    '{"format":1,"entries":null}',
    '{"format":1,"entries":[{"id":"x"}]}',
  ]) {
    test('refuses load and first save without overwriting $source', () async {
      final file = File('${dir.path}/vocabulary.json');
      await file.writeAsString(source);
      await expectLater(store.load(), throwsFormatException);
      await expectLater(store.save([]), throwsFormatException);
      expect(await file.readAsString(), source);
      await file.delete();
      await store.save([entry('recovered')]);
      expect((await store.load()).single.term, 'recovered');
    });
  }
  test('external corruption is protected even after loading', () async {
    await store.save([entry('cat')]);
    await File('${dir.path}/vocabulary.json').writeAsString('corrupt');
    await expectLater(store.save([]), throwsFormatException);
    expect((await store.load()).single.term, 'cat');
  });
  test('failed rename does not publish and later writes recover', () async {
    await store.save([entry('cat')]);
    final blocking = Directory('${dir.path}/vocabulary.json.tmp');
    await blocking.create();
    await expectLater(store.save([entry('dog')]), throwsA(isA<FileSystemException>()));
    expect((await store.load()).single.term, 'cat');
    expect((jsonDecode(await File('${dir.path}/vocabulary.json').readAsString()) as Map)['entries'][0]['term'], 'cat');
    await blocking.delete();
    await store.save([entry('dog')]);
    expect((await store.load()).single.term, 'dog');
  });
  test('duplicate IDs and keys are rejected; invalid enum does not overwrite', () async {
    await expectLater(store.save([entry('cat'), entry('cat')]), throwsFormatException);
    final j = entry('cat').toJson()..['status'] = 'future';
    final file = File('${dir.path}/vocabulary.json');
    await file.writeAsString(
      jsonEncode({
        'format': 1,
        'entries': [j],
      }),
    );
    await expectLater(store.load(), throwsFormatException);
    await expectLater(store.watch().first, throwsFormatException);
  });
}
