import 'dart:convert';
import 'dart:io';

import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileSyncJournal journal;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('foliarc-sync-');
    journal = FileSyncJournal(root, libraryId: 'library', scope: 'set');
  });
  tearDown(() async => root.delete(recursive: true));
  SyncCommit commit({int seq = 1, List<String> parents = const [], String scope = 'set', bool deleted = false}) =>
      SyncCommit.create(
        libraryId: 'library',
        scope: scope,
        deviceId: 'device',
        sequence: seq,
        parents: parents,
        payload: deleted ? {} : {'name': 'value-$seq'},
        deleted: deleted,
      );

  test('durable append recovers after reopen, retries idempotently, retains acknowledged history', () async {
    expect(await journal.load(), isEmpty);
    final c = commit();
    await Future.wait([journal.append(c), journal.append(c)]);
    final reopened = FileSyncJournal(root, libraryId: 'library', scope: 'set');
    expect((await reopened.pending()).map((c) => c.id), [c.id]);
    await reopened.acknowledge([c.id]);
    expect(await journal.pending(), isEmpty);
    expect(await journal.load(), hasLength(1));
    final deleted = commit(seq: 2, parents: [c.id], deleted: true);
    await journal.append(deleted);
    expect((await journal.pending()).single.deleted, isTrue);
    expect(await journal.load(), hasLength(2));
  });

  test('wrong identity, missing parents and device forks do not write or poison queue', () async {
    await expectLater(journal.append(commit(scope: 'other')), throwsFormatException);
    await expectLater(journal.acknowledge(['unknown']), throwsFormatException);
    final first = commit();
    await journal.append(first);
    await expectLater(journal.append(commit(seq: 2)), throwsFormatException);
    await expectLater(
      journal.append(
        SyncCommit.create(
          libraryId: 'library',
          scope: 'set',
          deviceId: 'device',
          sequence: 1,
          payload: {'different': true},
        ),
      ),
      throwsFormatException,
    );
    await journal.append(commit(seq: 2, parents: [first.id]));
    expect(await journal.load(), hasLength(2));
  });

  test('failed atomic write remains pending only after successful retry; incomplete temp is ignored', () async {
    final c = commit();
    final dir = Directory('${root.path}/.foliarc-sync/${legacySyncDigest(['library', 'set'])}');
    await dir.create(recursive: true);
    final obstruction = Directory('${dir.path}/${c.id}.json.tmp');
    await obstruction.create();
    await expectLater(journal.append(c), throwsA(isA<FileSystemException>()));
    expect(await journal.load(), isEmpty);
    await obstruction.delete();
    await File('${dir.path}/${c.id}.json.tmp').writeAsString('{');
    expect(await journal.load(), isEmpty);
    await journal.append(c);
    expect(await journal.pending(), hasLength(1));
  });

  test('corrupt history fails closed without overwriting bytes; acknowledgements validate version', () async {
    final c = commit();
    await journal.append(c);
    final dir = Directory('${root.path}/.foliarc-sync/${legacySyncDigest(['library', 'set'])}');
    final file = File('${dir.path}/${c.id}.json');
    await file.writeAsString(jsonEncode({...c.toJson(), 'protocol': 99}));
    await expectLater(journal.load(), throwsFormatException);
    await expectLater(journal.append(commit(seq: 2, parents: [c.id])), throwsFormatException);
    expect(jsonDecode(await file.readAsString())['protocol'], 99);
    await file.writeAsString(jsonEncode(c.toJson()));
    await File('${dir.path}/delivered.json').writeAsString('{"version":99,"ids":[]}');
    await expectLater(journal.pending(), throwsFormatException);
  });
}
