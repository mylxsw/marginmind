import 'dart:convert';
import 'dart:io';

import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileSyncLedger ledger;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-ledger-');
    ledger = FileSyncLedger(root, libraryId: 'library', deviceId: 'device');
  });
  tearDown(() => root.delete(recursive: true));
  SyncMutation value(String scope, int n, {int? local}) =>
      SyncMutation(scope, local: {'n': n, 'private': local ?? n}, shared: {'n': n});

  test('recovery acknowledgement is atomic, private and cannot dismiss a newer notice', () async {
    await ledger.commit([value('set', 1)], recovered: {'set': 'draft-one'});
    await expectLater(ledger.commit([], recovered: {'unknown': 'draft'}), throwsFormatException);
    await expectLater(ledger.commit([], recovered: {'set': ''}), throwsFormatException);
    final directory = Directory('${root.path}/.foliarc-sync/local');
    final saved = await directory.rename('${directory.path}.saved');
    final obstruction = File(directory.path);
    await obstruction.writeAsString('blocked');
    await expectLater(ledger.acknowledgeRecovery('set', 'draft-one'), throwsA(isA<FileSystemException>()));
    expect(await ledger.recoveries(), {'set': 'draft-one'});
    await obstruction.delete();
    await saved.rename(directory.path);
    await ledger.commit([value('set', 2)], recovered: {'set': 'draft-two'});
    await expectLater(ledger.acknowledgeRecovery('set', 'draft-one'), throwsA(isA<SyncRevisionChanged>()));
    final head = (await ledger.snapshots())['set']!.revision;
    await ledger.acknowledgeRecovery('set', 'draft-two');
    expect((await ledger.snapshots())['set']!.revision, head);
    expect(await (await FileSyncLedger.restore(root))!.recoveries(), isEmpty);
    expect((await ledger.pending()).map((c) => c.payload), [
      {'n': 1},
      {'n': 2},
    ]);
  });

  test('version two records migrate without recovery notices', () async {
    await ledger.commit([value('set', 1)]);
    final file = await Directory('${root.path}/.foliarc-sync/local').list().cast<File>().single;
    final body = jsonDecode(await file.readAsString()) as Map<String, dynamic>
      ..remove('id')
      ..remove('recoveries');
    body['version'] = 2;
    final id = syncDigest(body);
    await file.delete();
    await File('${file.parent.path}/$id.json').writeAsString(jsonEncode({'id': id, ...body}));
    final restored = (await FileSyncLedger.restore(root))!;
    expect(await restored.recoveries(), isEmpty);
    await restored.commit([value('set', 2)], recovered: {'set': 'draft'});
    expect(await (await FileSyncLedger.restore(root))!.recoveries(), {'set': 'draft'});
  });

  test('adoption requires a known compatible descendant and never queues the received version', () async {
    final first = (await ledger.commit([value('set', 1)]))['set']!;
    final remote = SyncCommit.create(
      libraryId: 'library',
      scope: 'set',
      deviceId: 'other',
      sequence: 1,
      parents: [first.commit.id],
      payload: {'n': 2},
    );
    await expectLater(
      ledger.commit([
        SyncMutation('set', local: {'n': 2}, shared: {'n': 2}, adopt: remote.id),
      ]),
      throwsFormatException,
    );
    await ledger.receive([remote, remote]);
    await expectLater(ledger.acknowledge([remote.id]), throwsFormatException);
    await expectLater(
      ledger.commit([
        SyncMutation('set', local: {'n': 3}, shared: {'n': 3}, adopt: remote.id),
      ]),
      throwsFormatException,
    );
    await expectLater(
      ledger.commit([
        SyncMutation('set', local: {'n': 2}, shared: {'n': 2}, adopt: remote.id, mergeParent: remote.id),
      ]),
      throwsFormatException,
    );
    await ledger.commit([
      SyncMutation('set', local: {'n': 2}, shared: {'n': 2}, adopt: remote.id),
    ]);
    expect((await ledger.pending()).map((c) => c.id), [first.commit.id]);
    await expectLater(
      ledger.commit([SyncMutation('set', local: first.value, shared: first.commit.payload, adopt: first.commit.id)]),
      throwsFormatException,
    );
    await ledger.commit([value('set', 3)]);
    expect((await ledger.snapshots())['set']!.commit.sequence, 2); // this device's sequence
    final reopened = (await FileSyncLedger.restore(root))!;
    expect((await reopened.snapshots())['set']!.value!['n'], 3);
    expect((await reopened.pending()).every((c) => c.deviceId == 'device'), isTrue);
    final otherLibrary = SyncCommit.create(
      libraryId: 'other-library',
      scope: 'set',
      deviceId: 'other',
      sequence: 1,
      payload: {},
    );
    await expectLater(ledger.receive([otherLibrary]), throwsFormatException);
  });

  test('version one records remain readable and can advance into the current version', () async {
    await ledger.commit([value('set', 1)]);
    final file = await Directory('${root.path}/.foliarc-sync/local').list().cast<File>().single;
    final body = jsonDecode(await file.readAsString()) as Map<String, dynamic>
      ..remove('id')
      ..remove('received')
      ..remove('issues')
      ..remove('recoveries');
    body['version'] = 1;
    final id = syncDigest(body);
    await file.delete();
    await File('${file.parent.path}/$id.json').writeAsString(jsonEncode({'id': id, ...body}));
    final reopened = (await FileSyncLedger.restore(root))!;
    expect((await reopened.snapshots())['set']!.value!['n'], 1);
    await reopened.commit([value('set', 2)]);
    expect((await (await FileSyncLedger.restore(root))!.snapshots())['set']!.value!['n'], 2);
  });

  test('one record recovers local state and outbox; local-only changes do not create cloud versions', () async {
    expect(await FileSyncLedger.restore(root), isNull);
    final first = await ledger.commit([value('set', 1)]);
    final id = first['set']!.commit.id;
    final second = await ledger.commit([value('set', 1, local: 99)]);
    expect(second['set']!.revision, isNot(first['set']!.revision));
    expect(second['set']!.commit.id, id);
    expect((await ledger.pending()).single.payload, {'n': 1});
    final retry = await ledger.commit([value('set', 1, local: 99)]);
    expect(retry['set']!.revision, second['set']!.revision);
    final reopened = (await FileSyncLedger.restore(root))!;
    expect((await reopened.snapshots())['set']!.value, {'n': 1, 'private': 99});
    expect((await reopened.pending()).single.id, id);
    await reopened.acknowledge([id]);
    expect(await reopened.pending(), isEmpty);
    expect((await reopened.snapshots())['set']!.commit.id, id);
    await expectLater(reopened.acknowledge(['unknown']), throwsFormatException);
  });

  test('drafts require an existing live head and cannot be bypassed by ordinary publication', () async {
    await expectLater(
      ledger.commit([
        SyncMutation('sets/a', local: {'n': 1}, shared: {'n': 1}, deferShared: true),
      ]),
      throwsFormatException,
    );
    await ledger.commit([value('sets/a', 1)]);
    final before = (await ledger.snapshots())['sets/a']!.commit.id;
    final draft = await ledger.commit([
      SyncMutation('sets/a', local: {'n': 2}, shared: {'n': 2}, deferShared: true),
    ]);
    expect(draft['sets/a']!.commit.id, before);
    expect(draft['sets/a']!.value!['n'], 2);
    expect(await ledger.pending(), isEmpty);
    await expectLater(ledger.commit([value('sets/a', 3)]), throwsStateError);
    await expectLater(
      ledger.commit([
        SyncMutation('sets/a', local: {'n': 2}, shared: {'n': 2}, deferShared: true, finishDraft: true),
      ]),
      throwsFormatException,
    );
    await ledger.commit([
      SyncMutation('sets/a', local: {'n': 2}, shared: {'n': 2}, finishDraft: true),
    ]);
    expect((await ledger.snapshots())['sets/a']!.draft, isFalse);
    expect((await ledger.pending()).last.payload['n'], 2);
  });

  test('batch is atomic, rejects stale revisions and freezes inputs before asynchronous work', () async {
    final first = await ledger.commit([value('a', 1), value('b', 1)]);
    expect(first['a']!.revision, first['b']!.revision);
    await ledger.commit([value('a', 2)], expected: {'a': first['a']!.revision});
    await expectLater(
      ledger.commit([value('a', 3), value('b', 3)], expected: {'a': first['a']!.revision}),
      throwsA(isA<SyncRevisionChanged>()),
    );
    expect((await ledger.snapshots())['b']!.value!['n'], 1);
    await expectLater(ledger.commit([value('a', 4)], validate: (_) => throw StateError('invalid')), throwsStateError);
    final source = <String, Object?>{
      'nested': [1],
    };
    final writing = ledger.commit([SyncMutation('c', local: source, shared: source)]);
    (source['nested'] as List).add(2);
    final snapshot = (await writing)['c']!;
    expect(snapshot.value!['nested'], [1]);
    expect(() => (snapshot.value!['nested'] as List).clear(), throwsUnsupportedError);
    // The returned future reports duplicate mutations; it must not poison later writes.
    await expectLater(ledger.commit([value('d', 1), value('d', 2)]), throwsFormatException);
    await ledger.commit([value('d', 1)]);
  });

  test('cascade discovers children inside the transaction after earlier queued writes', () async {
    await ledger.commit([value('parent', 1), value('unrelated', 1)]);
    final childWrite = ledger.commit([value('children/late', 1)]);
    final deletion = ledger.commit([
      SyncMutation('parent', local: null, shared: null),
    ], tombstoneWhere: (scope) => scope.startsWith('children/'));
    await childWrite;
    final heads = await deletion;
    expect(heads['children/late']!.deleted, isTrue);
    expect(heads['children/late']!.revision, heads['parent']!.revision);
    expect(heads['unrelated']!.deleted, isFalse);
    final recovered = await (await FileSyncLedger.restore(root))!.snapshots();
    expect(recovered['children/late']!.deleted, isTrue);
    expect(recovered['children/late']!.revision, recovered['parent']!.revision);
  });

  test('failure before atomic commit publishes neither snapshot nor pending version', () async {
    await ledger.commit([value('a', 1)]);
    final directory = Directory('${root.path}/.foliarc-sync/local');
    final saved = await directory.rename('${directory.path}.saved');
    final obstruction = File(directory.path);
    await obstruction.writeAsString('blocked');
    await expectLater(ledger.commit([value('a', 2)]), throwsA(isA<FileSystemException>()));
    expect((await ledger.snapshots())['a']!.value!['n'], 1);
    expect(await ledger.pending(), hasLength(1));
    await obstruction.delete();
    await saved.rename(directory.path);
    await ledger.commit([value('a', 2)]);
    expect((await (await FileSyncLedger.restore(root))!.snapshots())['a']!.value!['n'], 2);
  });

  test('tombstones survive restart and identity or history corruption fails closed', () async {
    await ledger.commit([value('a', 1)]);
    await ledger.commit([SyncMutation('a', local: null, shared: null)]);
    final reopened = (await FileSyncLedger.restore(root))!;
    expect((await reopened.snapshots())['a']!.deleted, isTrue);
    expect((await reopened.pending()).last.deleted, isTrue);
    await expectLater(FileSyncLedger(root, libraryId: 'other', deviceId: 'device').snapshots(), throwsFormatException);
    final files = await Directory('${root.path}/.foliarc-sync/local')
        .list()
        .where((f) => f is File)
        .cast<File>()
        .toList();
    final file = files.first;
    final original = await file.readAsString();
    final data = jsonDecode(original) as Map<String, dynamic>;
    data['sequence'] = 500;
    await file.writeAsString(jsonEncode(data));
    final corrupt = (await FileSyncLedger.restore(root))!;
    await expectLater(corrupt.snapshots(), throwsFormatException);
    await expectLater(corrupt.commit([value('a', 3)]), throwsFormatException);
    expect(jsonDecode(await file.readAsString())['sequence'], 500);
    await file.writeAsString(original);
    await File('${root.path}/.foliarc-sync/local/unfinished.tmp').writeAsString('{');
    expect((await corrupt.snapshots())['a']!.deleted, isTrue);
    await File('${root.path}/.foliarc-sync/delivered.json').writeAsString('{"version":99,"ids":[]}');
    await expectLater(corrupt.pending(), throwsFormatException);
  });

  test('even correctly hashed records reject unsupported versions, broken ancestry and invalid mutations', () async {
    final variants = <void Function(Map<String, dynamic>)>[
      (j) => j['version'] = 99,
      (j) => j['sequence'] = 2,
      (j) => j['previous'] = 'missing',
      (j) => j['extra'] = true,
      (j) => j['changes'] = [],
      (j) => (j['changes'] as List).add((j['changes'] as List).first),
      (j) => j['changes'][0]['local'] = null,
      (j) => j['changes'][0]['local'] = [],
      (j) => j['changes'][0]['commit'] = null,
      (j) => j['changes'][0]['scope'] = 'different',
      (j) => j['changes'][0]['extra'] = true,
      (j) => j['changes'][0]['commit'] = SyncCommit.create(
        libraryId: 'library',
        deviceId: 'device',
        scope: 'a',
        sequence: 2,
        payload: {'n': 1},
      ).toJson(),
    ];
    for (var i = 0; i < variants.length; i++) {
      final directory = Directory('${root.path}/case-$i');
      final initial = FileSyncLedger(directory, libraryId: 'library', deviceId: 'device');
      await initial.commit([value('a', 1)]);
      final file = await Directory('${directory.path}/.foliarc-sync/local').list().cast<File>().single;
      final body = jsonDecode(await file.readAsString()) as Map<String, dynamic>..remove('id');
      variants[i](body);
      final id = syncDigest(body);
      await file.delete();
      await File('${file.parent.path}/$id.json').writeAsString(jsonEncode({'id': id, ...body}));
      final reopened = (await FileSyncLedger.restore(directory))!;
      await expectLater(reopened.snapshots(), throwsFormatException, reason: 'variant $i');
    }
  });

  test('binding changes stop a live writer, and missing identity never falls back to unsynced mode', () async {
    await ledger.commit([value('a', 1)]);
    final identity = File('${root.path}/.foliarc-sync/identity.json');
    final original = await identity.readAsString();
    await identity.writeAsString('{"version":1,"libraryId":"other","deviceId":"device"}');
    await expectLater(ledger.commit([value('a', 2)]), throwsFormatException);
    await identity.delete();
    await expectLater(FileSyncLedger.restore(root), throwsFormatException);
    await identity.writeAsString('{"version":2}');
    await expectLater(FileSyncLedger.restore(root), throwsFormatException);
    await identity.writeAsString(original);
    await ledger.commit([value('a', 2)]);
    await ledger.project('view', () async => throw StateError('failed'));
    expect(ledger.projectionErrors.keys, ['view']);
    await ledger.project('view', () async {});
    expect(ledger.projectionErrors, isEmpty);
    await expectLater(ledger.commit([SyncMutation('bad', local: {}, shared: null)]), throwsFormatException);
    expect(
      () => ledger.commit([
        SyncMutation('bad', local: {'object': Object()}, shared: {}),
      ]),
      throwsFormatException,
    );
  });
}
