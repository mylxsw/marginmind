import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final now = DateTime.utc(2026, 10, 31);
TranslationSegment segment(String key, {String text = '译文', TranslationOrigin origin = TranslationOrigin.ai}) =>
    TranslationSegment(
      key: key,
      fingerprint: 'fp',
      page: 1,
      index: 0,
      text: text,
      model: 'model',
      profile: '',
      origin: origin,
      at: now,
    );
TranslationJob job({TranslationJobState state = TranslationJobState.running}) => TranslationJob(
  id: 'j',
  documentId: 'doc',
  targetLang: 'zh',
  range: TranslationRange(1, 20),
  mode: TranslationMode.batch,
  batchSize: 10,
  model: 'm',
  state: state,
  batch: TranslationBatch(index: 1, range: TranslationRange(1, 10)),
  estimateTokens: 100,
  createdAt: now,
  updatedAt: now,
);
void main() {
  late Directory root;
  late FileTranslationStore store;
  File journal() => File(p.join(root.path, 'translations/doc/zh/segments.jsonl'));
  File jobFile() => File(p.join(root.path, 'translations/doc/zh/job.json'));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('translation-test-');
    store = FileTranslationStore(root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('empty, append durability, last value wins and immutable snapshots', () async {
    expect((await store.load('doc', 'zh')).segments, isEmpty);
    expect(await store.loadJob('doc', 'zh'), isNull);
    await store.append('doc', 'zh', segment('a'));
    await store.append('doc', 'zh', segment('a', text: '修改', origin: TranslationOrigin.edited));
    final snapshot = await FileTranslationStore(root).load('doc', 'zh');
    expect(snapshot.segments['a']!.text, '修改');
    expect(snapshot.lineCount, 2);
    expect(snapshot.overwrittenLines, 1);
    expect(snapshot.needsCompaction, isTrue);
    expect((await journal().readAsString()).split('\n'), hasLength(3));
    await store.append('doc', 'en', segment('a', text: 'English'));
    expect((await store.load('doc', 'zh')).segments['a']!.text, '修改');
  });
  test('torn UTF8 tail is discarded; next append repairs it without losing earlier values', () async {
    await store.append('doc', 'zh', segment('a'));
    await journal().writeAsBytes([123, 34, 0xe4, 0xbd], mode: FileMode.append, flush: true);
    var snapshot = await store.load('doc', 'zh');
    expect(snapshot.discardedTail, isTrue);
    expect(snapshot.corruptLines, 0);
    await store.append('doc', 'zh', segment('b'));
    snapshot = await store.load('doc', 'zh');
    expect(snapshot.segments.keys, ['a', 'b']);
    expect(snapshot.discardedTail, isFalse);
    expect(snapshot.corruptLines, 0);
    await journal().writeAsString(jsonEncode(segment('c').toJson()), flush: true);
    expect((await store.load('doc', 'zh')).segments, isEmpty);
    await store.append('doc', 'zh', segment('d'));
    expect((await store.load('doc', 'zh')).segments.keys, ['d']);
  });
  test('middle invalid JSON, UTF8 and invalid schema are counted and skipped', () async {
    await store.append('doc', 'zh', segment('a'));
    await journal().writeAsBytes([...utf8.encode('broken\n{}\n{"v":2}\n'), 0xff, 10], mode: FileMode.append);
    await store.append('doc', 'zh', segment('b'));
    final snapshot = await store.load('doc', 'zh');
    expect(snapshot.segments.keys, ['a', 'b']);
    expect(snapshot.corruptLines, 4);
    expect(snapshot.lineCount, 6);
    expect(snapshot.needsCorruptionWarning, isTrue);
  });
  test('concurrent instances serialize append and atomic compaction', () async {
    final other = FileTranslationStore(root);
    await Future.wait([
      for (var i = 0; i < 40; i++) (i.isEven ? store : other).append('doc', 'zh', segment('${i % 10}', text: '$i')),
    ]);
    final before = await journal().readAsString();
    await File('${journal().path}.tmp').writeAsString('interrupted previous compaction');
    expect(await journal().readAsString(), before);
    await Future.wait([store.compact('doc', 'zh'), other.append('doc', 'zh', segment('end'))]);
    final snapshot = await store.load('doc', 'zh');
    expect(snapshot.segments, hasLength(11));
    expect(snapshot.segments['0']!.text, '30');
    expect(snapshot.lineCount, 11);
    expect(snapshot.overwrittenLines, 0);
    expect(await File('${journal().path}.tmp').exists(), isFalse);
    await store.compact('doc', 'zh');
    expect((await store.load('doc', 'zh')).lineCount, 11);
  });
  test('job recovery preserves checkpoint, malformed jobs do not affect translations', () async {
    await store.append('doc', 'zh', segment('a'));
    await store.saveJob(job());
    final recovered = (await store.loadJob('doc', 'zh'))!;
    expect(recovered.state, TranslationJobState.paused);
    expect(recovered.pauseReason, TranslationPauseReason.quit);
    await store.saveJob(job(state: TranslationJobState.offline));
    expect((await store.loadJob('doc', 'zh'))!.state, TranslationJobState.paused);
    expect((await store.loadJob('doc', 'zh'))!.pauseReason, TranslationPauseReason.quit);
    await store.saveJob(job(state: TranslationJobState.review));
    expect((await store.loadJob('doc', 'zh'))!.state, TranslationJobState.review);
    for (final malformed in [
      '{',
      '{}',
      '{"v":2}',
      jsonEncode({...job().toJson(), 'state': 'unknown'}),
      jsonEncode({...job().toJson(), 'documentId': 'other'}),
    ]) {
      await jobFile().writeAsString(malformed);
      expect(await store.loadJob('doc', 'zh'), isNull);
      expect((await store.load('doc', 'zh')).segments, hasLength(1));
    }
    expect(await File('${jobFile().path}.tmp').exists(), isFalse);
  });
  test('failed operation does not poison queue and path traversal is rejected', () async {
    await root.create(recursive: true);
    await File(p.join(root.path, 'translations')).writeAsString('obstruction');
    await expectLater(store.append('doc', 'zh', segment('a')), throwsA(isA<FileSystemException>()));
    await File(p.join(root.path, 'translations')).delete();
    await store.append('doc', 'zh', segment('a'));
    for (final id in ['..', '../escape', 'a/b', 'a\\b', '']) {
      expect(() => store.load(id, 'zh'), throwsArgumentError);
    }
    await expectLater(store.load('doc', '../en'), throwsArgumentError);
    expect((await store.load('doc', 'zh')).segments, hasLength(1));
  });
  test('remove pair, document and orphans preserve live documents and languages', () async {
    await store.remove('doc', 'zh');
    await store.removeDocument('doc');
    await store.cleanOrphans({});
    await store.append('doc', 'zh', segment('a'));
    await store.append('doc', 'en', segment('b'));
    await store.append('other', 'zh', segment('c'));
    await store.remove('doc', 'zh');
    expect((await store.load('doc', 'zh')).segments, isEmpty);
    expect((await store.load('doc', 'en')).segments, hasLength(1));
    await store.cleanOrphans({'doc'});
    expect((await store.load('other', 'zh')).segments, isEmpty);
    await store.removeDocument('doc');
    expect(await Directory(p.join(root.path, 'translations/doc')).exists(), isFalse);
  });
  test('legacy fingerprint import is read-only, idempotent, and preserves edits', () async {
    final paras = [
      for (var i = 0; i < 3; i++)
        TranslationParagraph(documentId: 'doc', page: 1, index: i, text: 'text$i', fingerprint: 'fp$i'),
    ];
    final legacy = TranslationCache(
      documentId: 'doc',
      targetLang: 'zh',
      model: 'old',
      createdAt: now,
      paragraphs: {'fp0': '旧译文', 'fp1': '旧修改'},
    );
    final original = jsonEncode(legacy.toJson());
    final key = textKey('text1', 'zh');
    await store.append('doc', 'zh', segment(key, text: '手动修改', origin: TranslationOrigin.edited));
    var snapshot = await store.importLegacy('doc', 'zh', paragraphs: paras, caches: [legacy]);
    expect(snapshot.segments[key]!.text, '手动修改');
    expect(snapshot.segments[textKey('text0', 'zh')]!.origin, TranslationOrigin.legacy);
    expect(snapshot.segments, hasLength(2));
    snapshot = await store.importLegacy('doc', 'zh', paragraphs: paras, caches: [legacy]);
    expect(snapshot.lineCount, 2);
    expect(jsonEncode(legacy.toJson()), original);
    await store.remove('doc', 'zh');
    expect(
      (await FileTranslationStore(root).importLegacy('doc', 'zh', paragraphs: paras, caches: [legacy])).segments,
      isEmpty,
    );

    expect((await store.importLegacy('doc', 'en', paragraphs: paras, caches: [legacy])).segments, isEmpty);
    expect((await store.importLegacy('another', 'zh', paragraphs: paras, caches: [legacy])).segments, isEmpty);
  });
  test('library deletion cleans translations, late writes fail, reopen cleans orphan directories', () async {
    final library = FileLibraryStore(root);
    final set = await library.create(const NewStudySet(title: 'Test', colorIndex: 0));
    final editor = StudySetEditor(newId: () => 'doc', now: () => now);
    await library.update(set.id, (c) => editor.addDocument(c, title: 'PDF', fileName: 'test.pdf', pageCount: 20).$1);
    final translations = await library.translationStore(set.id);
    await translations.append('doc', 'zh', segment('a'));
    final metadata = File(p.join(root.path, 'sets', '${set.id}.mmset', 'studyset.json'));
    final before = await metadata.readAsBytes();
    await translations.saveJob(job());
    await translations.append('doc', 'zh', segment('b'));
    expect(await metadata.readAsBytes(), before, reason: 'translation writes never modify studyset.json');
    await library.update(set.id, (c) => c.copyWith(documents: []));
    expect((await translations.load('doc', 'zh')).segments, isEmpty);
    await expectLater(translations.append('doc', 'zh', segment('late')), throwsStateError);
    await expectLater(translations.saveJob(job()), throwsStateError);
    final raw = FileTranslationStore(Directory(p.dirname(metadata.path)));
    await raw.append('orphan', 'zh', segment('old'));
    await library.dispose();
    final reopened = FileLibraryStore(root);
    expect((await reopened.load(set.id)).documents, isEmpty);
    expect((await raw.load('orphan', 'zh')).segments, isEmpty);
    await reopened.dispose();
  });

  test('failed compaction and job replacement leave the committed files intact', () async {
    await store.append('doc', 'zh', segment('a'));
    await store.append('doc', 'zh', segment('a', text: 'new'));
    final before = await journal().readAsBytes();
    final blocked = Directory('${journal().path}.tmp');
    await blocked.create();
    await expectLater(store.compact('doc', 'zh'), throwsA(isA<FileSystemException>()));
    expect(await journal().readAsBytes(), before);
    await blocked.delete();
    await store.compact('doc', 'zh');
    expect((await store.load('doc', 'zh')).lineCount, 1);
    await store.saveJob(job(state: TranslationJobState.review));
    final beforeJob = await jobFile().readAsBytes();
    final blockedJob = Directory('${jobFile().path}.tmp');
    await blockedJob.create();
    await expectLater(store.saveJob(job()), throwsA(isA<FileSystemException>()));
    expect(await jobFile().readAsBytes(), beforeJob);
  });
  test('malformed final committed line is tail loss rather than middle corruption', () async {
    await store.append('doc', 'zh', segment('a'));
    await journal().writeAsString('broken\n', mode: FileMode.append);
    final snapshot = await store.load('doc', 'zh');
    expect(snapshot.discardedTail, isTrue);
    expect(snapshot.corruptLines, 0);
    expect(snapshot.segments.keys, ['a']);
  });
}
