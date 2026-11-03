import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileSyncLedger left, right;
  late FileLibraryStore a, b;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-folders-');
    left = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    right = FolderRacingLedger(Directory('${root.path}/b'));
    a = FileLibraryStore(left.root, sync: left);
    b = FileLibraryStore(right.root, sync: right);
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await root.delete(recursive: true);
  });
  Future<FolderEntry> entry(FileLibraryStore store, String id) async =>
      (await store.watchOrganization().first).entries.singleWhere((e) => e.id == id);
  Future<void> rename(FileLibraryStore store, String id, String name) async =>
      store.renameFolder(id, name, expectedRevision: (await entry(store, id)).revision);
  Future<void> sendA() async => b.receiveSync(await left.pending());
  Future<void> sendB() async => a.receiveSync(await right.pending());

  test('concurrent folder choices remain reviewable and a grouped choice converges', () async {
    final folder = await a.createFolder('Initial');
    await sendA();
    await rename(a, folder.id, 'A');
    await rename(b, folder.id, 'B');
    await sendB();
    await sendA();
    final state = await entry(a, folder.id);
    final pending = state.choices.single.transaction;
    await a.chooseFolderName(folder.id, pending, expectedRevision: state.revision, useCandidate: false);
    final keep = (await left.snapshots())['folders/${folder.id}']!.commit;
    await b.chooseFolderName(
      folder.id,
      pending,
      expectedRevision: (await entry(b, folder.id)).revision,
      useCandidate: true,
    );
    await sendB();
    final combined = await entry(a, folder.id);
    expect(combined.choices, hasLength(2));
    expect(combined.choices.every((c) => c.concurrentChoices == 2), isTrue);
    expect(combined.problems, isEmpty);
    await a.chooseFolderName(folder.id, keep.id, expectedRevision: combined.revision, useCandidate: true);
    await sendA();
    final finalState = await entry(b, folder.id);
    expect(finalState.choices, isEmpty);
    expect(finalState.folder!.name, state.folder!.name);
  });

  test('unfiled display preserves the original membership guard for an explicit move', () async {
    final set = await a.create(const NewStudySet(title: 'Set', colorIndex: 0, folderId: 'not-received'));
    final destination = await a.createFolder('Destination');
    expect((await a.watchAll().first).single.folderId, isNull);
    expect((await a.watchOrganization().first).placements[set.id], 'not-received');
    await expectLater(
      a.moveStudySet(set.id, destination.id, expectedFolderId: null),
      throwsA(isA<ContentSyncActionException>()),
    );
    await a.moveStudySet(set.id, destination.id, expectedFolderId: 'not-received');
    expect((await a.watchAll().first).single.folderId, destination.id);
  });

  test('a local revision change at the commit point recomputes the merge and retains both names', () async {
    final folder = await a.createFolder('Initial');
    await sendA();
    await rename(a, folder.id, 'Remote');
    (right as FolderRacingLedger).beforeAdvance = () async {
      final heads = await right.snapshots();
      final value = sharedFolder(Folder(id: folder.id, name: 'Intervening local'));
      await right.commit([
        SyncMutation('folders/${folder.id}', local: value, shared: value),
        SyncMutation(
          'library',
          local: {
            'folders': [value],
          },
          shared: heads['library']!.commit.payload,
        ),
      ]);
    };
    await sendA();
    final state = await entry(b, folder.id);
    expect({state.folder!.name, state.choices.single.name}, {'Remote', 'Intervening local'});
    await b.dispose();
    b = FileLibraryStore(right.root);
    final restored = await entry(b, folder.id);
    expect(restored.choices.single.name, state.choices.single.name);
    expect(restored.folder!.name, state.folder!.name);
  });

  test('failed durable folder writes leave the index and outgoing history unchanged', () async {
    final folder = await a.createFolder('Original');
    final before = (await left.pending()).map((c) => c.id).toList();
    final records = Directory('${left.root.path}/.foliarc-sync/local');
    final saved = await records.rename('${records.path}.saved');
    final obstruction = File(records.path);
    await obstruction.writeAsString('blocked');
    await expectLater(rename(a, folder.id, 'Failed'), throwsA(isA<FileSystemException>()));
    expect((await entry(a, folder.id)).folder!.name, 'Original');
    expect((await left.pending()).map((c) => c.id), before);
    await obstruction.delete();
    await saved.rename(records.path);
    await rename(a, folder.id, 'Retried');
    expect((await a.watchFolders().first).single.name, 'Retried');
  });

  test('independent empty libraries adopt folders and preserve sets through deletion and restart', () async {
    await b.watchAll().first;
    final folder = await a.createFolder(' Language ');
    final set = await a.create(NewStudySet(title: 'Set', colorIndex: 0, folderId: folder.id));
    await sendA();
    expect((await b.watchFolders().first).single.name, 'Language');
    expect((await b.watchAll().first).single.folderId, folder.id);
    expect(await right.issues(), isEmpty);
    await a.deleteFolder(folder.id, expectedRevision: (await entry(a, folder.id)).revision);
    await sendA();
    expect(await b.watchFolders().first, isEmpty);
    expect((await b.watchAll().first).single.folderId, isNull);
    expect((await right.snapshots())['sets/${set.id}']!.value!['folderId'], folder.id);
    await b.dispose();
    b = FileLibraryStore(right.root);
    expect(await b.watchFolders().first, isEmpty);
    expect((await b.watchAll().first).single.id, set.id);
    expect((await b.watchAll().first).single.folderId, isNull);
  });

  test(
    'concurrent names retain candidates, other folders progress, and an explicit choice converges on three devices',
    () async {
      final folder = await a.createFolder('Initial');
      await sendA();
      await rename(a, folder.id, 'First');
      await rename(b, folder.id, 'Second');
      final other = await b.createFolder('Independent');
      await sendB();
      var state = await entry(a, folder.id);
      expect(state.choices, hasLength(1));
      expect({state.folder!.name, state.choices.single.name}, {'First', 'Second'});
      expect((await a.watchFolders().first).map((f) => f.id), contains(other.id));
      await expectLater(
        a.deleteFolder(folder.id, expectedRevision: state.revision),
        throwsA(isA<ContentSyncActionException>()),
      );
      await rename(a, other.id, 'Still independent');
      final third = FileLibraryStore(
        Directory('${root.path}/c'),
        sync: FileSyncLedger(Directory('${root.path}/c'), libraryId: 'lib', deviceId: 'c'),
      );
      try {
        await third.receiveSync((await left.history()).values);
        expect((await entry(third, folder.id)).choices, hasLength(1));
        final selected = state.choices.single.name;
        await a.chooseFolderName(
          folder.id,
          state.choices.single.transaction,
          expectedRevision: state.revision,
          useCandidate: true,
        );
        await sendA();
        await third.receiveSync(await left.pending());
        for (final store in [a, b, third]) {
          state = await entry(store, folder.id);
          expect(state.folder!.name, selected);
          expect(state.choices, isEmpty);
          expect(state.problems, isEmpty);
        }
      } finally {
        await third.dispose();
      }
    },
  );

  test('stale rename, deletion, move and conflict choice cannot overwrite later work', () async {
    final folder = await a.createFolder('Initial');
    final old = await entry(a, folder.id);
    await sendA();
    await rename(a, folder.id, 'A');
    await rename(b, folder.id, 'B');
    await sendB();
    final conflict = await entry(a, folder.id);
    for (final action in [
      () => a.renameFolder(folder.id, 'Lost', expectedRevision: old.revision),
      () => a.deleteFolder(folder.id, expectedRevision: old.revision),
      () => a.chooseFolderName(
        folder.id,
        conflict.choices.single.transaction,
        expectedRevision: old.revision,
        useCandidate: true,
      ),
    ]) {
      await expectLater(action(), throwsA(isA<ContentSyncActionException>()));
    }
    await a.chooseFolderName(
      folder.id,
      conflict.choices.single.transaction,
      expectedRevision: conflict.revision,
      useCandidate: false,
    );
    expect((await entry(a, folder.id)).folder!.name, conflict.folder!.name);
    final set = await a.create(const NewStudySet(title: 'Set', colorIndex: 0));
    await a.moveStudySet(set.id, folder.id, expectedFolderId: null);
    await expectLater(a.moveStudySet(set.id, null, expectedFolderId: null), throwsA(isA<ContentSyncActionException>()));
    await a.moveStudySet(set.id, null, expectedFolderId: folder.id);
    await expectLater(
      a.moveStudySet(set.id, 'absent', expectedFolderId: null),
      throwsA(isA<ContentSyncActionException>()),
    );
    await sendA();
    expect((await b.watchAll().first).single.folderId, isNull);
  });

  test('delete versus rename stays visible as an unresolved branch', () async {
    final folder = await a.createFolder('Initial');
    await sendA();
    await a.deleteFolder(folder.id, expectedRevision: (await entry(a, folder.id)).revision);
    await rename(b, folder.id, 'Renamed');
    await sendB();
    expect((await entry(a, folder.id)).problems, contains(ContentSyncProblem.deletion));
    expect((await entry(a, folder.id)).folder, isNull);
    await a.retryOrganization();
    expect((await entry(a, folder.id)).problems, contains(ContentSyncProblem.deletion));
  });

  test('out-of-order names wait for ancestors then publish and notify', () async {
    final folder = await a.createFolder('Initial');
    await rename(a, folder.id, 'Next');
    final commits = (await left.pending()).where((c) => c.scope == 'folders/${folder.id}').toList();
    final states = <LibraryOrganization>[];
    final sub = b.watchOrganization().listen(states.add);
    await b.receiveSync([commits.last]);
    expect((await entry(b, folder.id)).problems, contains(ContentSyncProblem.missingHistory));
    expect(await b.watchFolders().first, isEmpty);
    await b.receiveSync([commits.first]);
    expect((await entry(b, folder.id)).folder!.name, 'Next');
    await Future<void>.delayed(Duration.zero);
    expect(states.any((s) => s.entries.any((f) => f.folder?.name == 'Next')), isTrue);
    await sub.cancel();
  });

  test('malformed names and extra fields are retained without publishing', () async {
    for (final payload in [
      <String, Object?>{'id': 'bad', 'name': ''},
      {'id': 'bad', 'name': 'valid', 'private': 'field'},
    ]) {
      final commit = SyncCommit.create(
        libraryId: 'lib',
        scope: 'folders/bad',
        deviceId: 'remote',
        sequence: 1,
        payload: payload,
      );
      await b.receiveSync([commit]);
      expect(await b.watchFolders().first, isEmpty);
      expect((await entry(b, 'bad')).problems, contains(ContentSyncProblem.invalidHistory));
    }
    await expectLater(a.createFolder('   '), throwsFormatException);
  });

  test('local mode supports folders and moves without enabling a sync ledger', () async {
    final local = FileLibraryStore(Directory('${root.path}/local'));
    try {
      final folder = await local.createFolder('Local');
      await rename(local, folder.id, 'Renamed');
      final set = await local.create(const NewStudySet(title: 'Set', colorIndex: 0));
      await local.moveStudySet(set.id, folder.id, expectedFolderId: null);
      expect((await local.watchAll().first).single.folderId, folder.id);
      await local.deleteFolder(folder.id, expectedRevision: (await entry(local, folder.id)).revision);
      expect((await local.watchAll().first).single.folderId, isNull);
      expect((await local.watchOrganization().first).syncEnabled, isFalse);
      expect(await local.syncLedger, isNull);
      await local.retryOrganization();
    } finally {
      await local.dispose();
    }
  });

  test('legacy folder index upgrades without changing study-set files or creating duplicate roots', () async {
    await left.root.create(recursive: true);
    await File('${left.root.path}/library.json').writeAsString(
      jsonEncode({
        'folders': [
          {'id': 'old', 'name': 'Existing'},
        ],
      }),
    );
    expect((await a.watchFolders().first).single.name, 'Existing');
    final initial = (await left.pending()).where((c) => c.scope == 'folders/old').single.id;
    await a.dispose();
    a = FileLibraryStore(left.root);
    expect((await a.watchFolders().first).single.id, 'old');
    expect((await (await a.syncLedger)!.pending()).where((c) => c.scope == 'folders/old').single.id, initial);
  });

  test('projection failure is recoverable and does not fail the committed folder edit', () async {
    final folder = await a.createFolder('Initial');
    final file = File('${left.root.path}/library.json');
    await file.delete();
    final obstruction = Directory(file.path);
    await obstruction.create();
    await rename(a, folder.id, 'Durable');
    expect((await entry(a, folder.id)).folder!.name, 'Durable');
    expect((await a.watchOrganization().first).repairNeeded, isTrue);
    await obstruction.delete();
    await a.retryOrganization();
    expect((await a.watchOrganization().first).repairNeeded, isFalse);
    expect(jsonDecode(await file.readAsString())['folders'][0]['name'], 'Durable');
  });
}

class FolderRacingLedger extends FileSyncLedger {
  FolderRacingLedger(super.root) : super(libraryId: 'lib', deviceId: 'b');
  Future<void> Function()? beforeAdvance;
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
    if (inputs.any((m) => m.scope.startsWith('folders/') && (m.adopt != null || m.mergeParent != null))) {
      final race = beforeAdvance;
      beforeAdvance = null;
      await race?.call();
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
