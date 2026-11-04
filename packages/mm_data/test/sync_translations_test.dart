import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

TranslationSegment segment(String value, {String key = 'key', TranslationOrigin origin = TranslationOrigin.edited}) =>
    TranslationSegment(
      key: key,
      fingerprint: 'fp',
      page: 1,
      index: 0,
      text: value,
      model: 'm',
      profile: 'p',
      origin: origin,
      at: DateTime.utc(2026),
    );
void main() {
  late Directory root;
  late FileSyncLedger left, right;
  late FileLibraryStore a, b;
  late String id;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-translations-');
    left = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    right = TranslationRacingLedger(Directory('${root.path}/b'));
    a = FileLibraryStore(left.root, sync: left);
    b = FileLibraryStore(right.root, sync: right);
    id = (await a.create(const NewStudySet(title: 'Study', colorIndex: 0))).id;
    await a.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(
          id: 'doc',
          title: 'Book',
          fileName: 'documents/book.pdf',
          pageCount: 3,
          importedAt: DateTime.utc(2026),
        ),
        files: {
          'documents/book.pdf': [1, 2, 3],
        },
      ),
    );
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await root.delete(recursive: true);
  });
  Future<void> sendA() async => b.receiveSync(await left.pending());
  Future<void> sendB() async => a.receiveSync(await right.pending());
  test('two devices merge paragraphs, protect human text, retain choices through restart and third device', () async {
    await sendA();
    final x = await a.translationStore(id), y = await b.translationStore(id);
    await x.append('doc', 'zh', segment('human'));
    await y.append('doc', 'zh', segment('auto', origin: TranslationOrigin.ai));
    await y.append('doc', 'zh', segment('other', key: 'other'));
    final events = <TranslationSnapshot>[];
    final sub = y.watchTranslations('doc', 'zh').listen(events.add);
    await sendA();
    await sendB();
    await sendA();
    expect((await y.load('doc', 'zh')).segments['key']!.text, 'human');
    expect((await x.load('doc', 'zh')).segments['other']!.text, 'other');
    final beforeX = await x.load('doc', 'zh'), beforeY = await y.load('doc', 'zh');
    await x.appendGuarded('doc', 'zh', segment('left'), expectedToken: beforeX.tokenFor('key'));
    await y.appendGuarded('doc', 'zh', segment('right'), expectedToken: beforeY.tokenFor('key'));
    await sendA();
    await sendB();
    await sendA();
    expect((await x.load('doc', 'zh')).conflicts['key'], hasLength(2));
    expect((await a.contentSyncStatus(id)).translationConflicts, 1);
    expect((await a.contentSyncStatus(id)).needsAttention, isTrue);
    await b.dispose();
    b = FileLibraryStore(right.root);
    final reopened = await b.translationStore(id);
    final state = await reopened.load('doc', 'zh');
    expect(state.conflicts['key'], hasLength(2));
    await reopened.chooseTranslation(
      'doc',
      'zh',
      'key',
      state.conflicts['key']!.singleWhere((c) => c.segment!.text == 'right').id,
      expectedToken: state.tokenFor('key')!,
    );
    final restored = (await FileSyncLedger.restore(right.root))!;
    await a.receiveSync(await restored.pending());
    expect((await x.load('doc', 'zh')).segments['key']!.text, 'right');
    expect((await a.contentSyncStatus(id)).translationConflicts, 0);
    final thirdLedger = FileSyncLedger(Directory('${root.path}/c'), libraryId: 'lib', deviceId: 'c');
    final third = FileLibraryStore(thirdLedger.root, sync: thirdLedger);
    await third.receiveSync([...await left.history().then((v) => v.values), ...await restored.pending()]);
    final z = await third.translationStore(id);
    expect((await z.load('doc', 'zh')).segments['key']!.text, 'right');
    expect((await z.load('doc', 'zh')).conflicts, isEmpty);
    expect((await thirdLedger.pending()).where((c) => c.scope.startsWith('translated/')), isEmpty);
    await third.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(events, isNotEmpty);
    await sub.cancel();
  });
  test('missing content and ancestors wait; stale edit cannot overwrite a received contribution', () async {
    final x = await a.translationStore(id);
    await x.append('doc', 'zh', segment('first'));
    await x.appendGuarded('doc', 'zh', segment('second'), expectedToken: (await x.load('doc', 'zh')).tokenFor('key'));
    final translated = (await left.pending()).where((c) => c.scope.startsWith('translated/')).toList();
    await b.receiveSync([translated.last]);
    expect((await b.contentSyncStatus(id)).problems, isNotEmpty);
    await sendA();
    final y = await b.translationStore(id);
    final old = await y.load('doc', 'zh');
    await x.appendGuarded('doc', 'zh', segment('third'), expectedToken: (await x.load('doc', 'zh')).tokenFor('key'));
    await sendA();
    await expectLater(
      y.appendGuarded('doc', 'zh', segment('stale'), expectedToken: old.tokenFor('key')),
      throwsA(isA<ContentSyncActionException>()),
    );
    expect((await y.load('doc', 'zh')).segments['key']!.text, 'third');
  });
  test(
    'drafts reject publication, cancel permits retry, replacement isolates cached text and deletion never resurrects',
    () async {
      await sendA();
      final x = await a.translationStore(id);
      await x.append('doc', 'zh', segment('old'));
      await a.beginContentTransaction(id);
      await expectLater(x.append('doc', 'zh', segment('during')), throwsA(isA<ContentSyncActionException>()));
      expect((await left.pending()).where((c) => c.scope.startsWith('translated/')), isEmpty);
      await a.endContentTransaction(id);
      expect((await x.load('doc', 'zh')).segments['key']!.text, 'old');
      await a.update(
        id,
        (c) => c.copyWith(
          documents: [
            Document(
              id: 'doc',
              title: 'new',
              fileName: 'documents/new.pdf',
              pageCount: 3,
              importedAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      expect((await x.load('doc', 'zh')).segments, isEmpty);
      await x.append('doc', 'zh', segment('new'));
      await sendA();
      expect((await (await b.translationStore(id)).load('doc', 'zh')).segments['key']!.text, 'new');
      await b.delete(id);
      await b.receiveSync(await left.pending());
      expect(await b.watchAll().first, isEmpty);
    },
  );
  test('cancelled document deletion preserves translations; a committed draft deletion tombstones them', () async {
    final x = await a.translationStore(id);
    await x.append('doc', 'zh', segment('saved'));
    final scope = 'translated/$id/doc/zh', before = (await left.snapshots())['translated/$id/doc/zh']!.revision;
    final content = await a.load(id);
    await a.beginContentTransaction(id);
    await a.update(id, (c) => c.copyWith(documents: []));
    expect((await left.snapshots())[scope]!.revision, before);
    expect(await Directory('${left.root.path}/sets/$id.mmset/translations/doc').exists(), isTrue);
    await a.update(id, (_) => content);
    await a.endContentTransaction(id);
    expect((await left.snapshots())[scope]!.revision, before);
    expect((await x.load('doc', 'zh')).segments['key']!.text, 'saved');
    await sendA();
    expect((await (await b.translationStore(id)).load('doc', 'zh')).segments['key']!.text, 'saved');
    await a.beginContentTransaction(id);
    await a.update(id, (c) => c.copyWith(documents: []));
    await a.endContentTransaction(id);
    expect((await left.snapshots())[scope]!.deleted, isTrue);
    expect(await Directory('${left.root.path}/sets/$id.mmset/translations/doc').exists(), isFalse);
    await sendA();
    expect((await (await b.translationStore(id)).load('doc', 'zh')).segments, isEmpty);
  });
  test('an old aggregate removal blocks reimport without hiding later paragraph edits', () async {
    final scope = 'translations/$id/doc/zh';
    await left.commit([SyncMutation(scope, local: null, shared: null)]);
    final x = await a.translationStore(id);
    await x.append('doc', 'zh', segment('new human'));
    final state = await x.importLegacy('doc', 'zh', paragraphs: [], caches: []);
    expect(state.segments['key']!.text, 'new human');
    expect(state.documentVersion, isNotNull);
  });
  test('legacy migration is atomic and retries after a failed initial publication', () async {
    await sendA();
    final ledger = right as TranslationRacingLedger;
    final package = Directory('${right.root.path}/sets/$id.mmset');
    final legacy = FileTranslationStore(package);
    await legacy.append('doc', 'zh', segment('legacy human'));
    final x = await b.translationStore(id);
    ledger.beforeWrite = () async => throw const FileSystemException('disk full');
    await expectLater(x.load('doc', 'zh'), throwsA(isA<FileSystemException>()));
    expect((await right.snapshots())['translated/$id/doc/zh'], isNull);
    expect((await legacy.load('doc', 'zh')).segments['key']!.text, 'legacy human');
    expect((await x.load('doc', 'zh')).segments['key']!.text, 'legacy human');
    await b.dispose();
    b = FileLibraryStore(right.root);
    expect((await (await b.translationStore(id)).load('doc', 'zh')).segments['key']!.text, 'legacy human');
  });
  test('failed adoption stays received and a changed revision is recomputed without losing local text', () async {
    await sendA();
    final x = await a.translationStore(id), y = await b.translationStore(id);
    await y.load('doc', 'zh');
    await x.append('doc', 'zh', segment('remote'));
    final ledger = right as TranslationRacingLedger;
    ledger.beforeWrite = () async => throw const FileSystemException('disk full');
    await expectLater(sendA(), throwsA(isA<FileSystemException>()));
    expect((await y.load('doc', 'zh')).segments, isEmpty);
    ledger.beforeWrite = () => y.append('doc', 'zh', segment('independent', key: 'another'));
    await b.reconcileSync();
    final state = await y.load('doc', 'zh');
    expect(state.segments['key']!.text, 'remote');
    expect(state.segments['another']!.text, 'independent');
    expect((await b.contentSyncStatus(id)).problems, isEmpty);
  });
  test('queued choice rejects a newer contribution and draft input waits until cancellation finishes', () async {
    await sendA();
    final x = await a.translationStore(id), y = await b.translationStore(id);
    await x.append('doc', 'zh', segment('left'));
    await y.append('doc', 'zh', segment('right'));
    await sendA();
    final before = await y.load('doc', 'zh');
    final ledger = right as TranslationRacingLedger;
    ledger.beforeWrite = () async {
      final head = (await right.snapshots())['translated/$id/doc/zh']!;
      final value = TranslationRegister.fromJson(head.value!)
          .append(before.documentVersion!, segment('third'), 'b', 'racing');
      await ledger.commit([
        SyncMutation(head.commit.scope, local: value.toJson(), shared: value.toJson(), requireScopes: ['sets/$id']),
      ]);
    };
    await expectLater(
      y.chooseTranslation(
        'doc',
        'zh',
        'key',
        before.conflicts['key']!.first.id,
        expectedToken: before.tokenFor('key')!,
      ),
      throwsA(isA<ContentSyncActionException>()),
    );
    expect((await y.load('doc', 'zh')).conflicts['key'], hasLength(3));
    await b.beginContentTransaction(id);
    await x.append('doc', 'zh', segment('later', key: 'another'));
    await sendA();
    expect((await y.load('doc', 'zh')).segments.containsKey('another'), isFalse);
    expect((await b.contentSyncStatus(id)).problems, contains(ContentSyncProblem.editing));
    await b.endContentTransaction(id);
    expect((await y.load('doc', 'zh')).segments['another']!.text, 'later');
  });
  test('clear versus edit remains explicit and background work cannot undo a user removal', () async {
    await sendA();
    final x = await a.translationStore(id), y = await b.translationStore(id);
    await x.append('doc', 'zh', segment('original'));
    await sendA();
    final observed = await y.load('doc', 'zh');
    await x.remove('doc', 'zh');
    await y.appendGuarded('doc', 'zh', segment('edited'), expectedToken: observed.tokenFor('key'));
    await sendA();
    await sendB();
    final s = await x.load('doc', 'zh');
    expect(s.conflicts['key'], hasLength(2));
    await x.chooseTranslation(
      'doc',
      'zh',
      'key',
      s.conflicts['key']!.singleWhere((c) => c.segment == null).id,
      expectedToken: s.tokenFor('key')!,
    );
    await x.append('doc', 'zh', segment('late', origin: TranslationOrigin.ai));
    expect((await x.load('doc', 'zh')).segments, isEmpty);
  });
}

class TranslationRacingLedger extends FileSyncLedger {
  TranslationRacingLedger(super.root) : super(libraryId: 'lib', deviceId: 'b');
  Future<void> Function()? beforeWrite;
  @override
  Future<Map<String, LocalSyncSnapshot>> commit(
    Iterable<SyncMutation> mutations, {
    Map<String, String?> expected = const {},
    void Function(Map<String, LocalSyncSnapshot>)? validate,
    bool Function(String scope)? tombstoneWhere,
    Iterable<String> resolved = const [],
    Map<String, String> recovered = const {},
  }) async {
    final inputs = mutations.toList();
    if (inputs.any((m) => m.scope.startsWith('translated/'))) {
      final action = beforeWrite;
      beforeWrite = null;
      await action?.call();
    }
    return super.commit(
      inputs,
      expected: expected,
      validate: validate,
      tombstoneWhere: tombstoneWhere,
      resolved: resolved,
      recovered: recovered,
    );
  }
}
