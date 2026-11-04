import 'dart:io';
import 'dart:async';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileSyncLedger left;
  late RacingLedger right;
  late FileLibraryStore a, b;
  late String id, card, doc;
  final now = DateTime.utc(2026);
  var serial = 0;
  late StudySetEditor editor;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('receive-sync-');
    left = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'library', deviceId: 'left');
    right = RacingLedger(Directory('${root.path}/b'));
    a = FileLibraryStore(left.root, sync: left, clock: () => now);
    b = FileLibraryStore(right.root, sync: right, clock: () => now);
    editor = StudySetEditor(newId: () => 'entity-${++serial}', now: () => now);
    id = (await a.create(const NewStudySet(title: 'Original', colorIndex: 0))).id;
    await a.update(id, (c) {
      final d = editor.addDocument(c, title: 'Doc', fileName: 'documents/a.pdf', pageCount: 10);
      doc = d.$2.id;
      final n = editor.addNote(d.$1, text: 'Question');
      card = n.$2.id;
      return n.$1;
    });
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await root.delete(recursive: true);
  });
  Future<void> sendA() async => b.receiveSync(await left.pending());
  Future<void> sendB() async => a.receiveSync(await right.pending());

  test(
    'fast-forward updates live state, preserves local reading, survives reopen and does not echo receipts',
    () async {
      await sendA();
      expect((await b.load(id)).card(card)!.title, 'Question');
      expect((await right.pending()).where((c) => c.scope == 'sets/$id'), isEmpty);
      await b.update(id, (c) => editor.setLastPage(c, doc, 7));
      await a.update(id, (c) => editor.rename(c, card, 'Remote title'));
      await sendA();
      expect((await b.load(id)).card(card)!.title, 'Remote title');
      expect((await b.load(id)).document(doc)!.lastPage, 7);
      final before = (await right.history()).length;
      await sendA();
      expect((await right.history()).length, before);
      await b.dispose();
      b = FileLibraryStore(right.root);
      expect((await b.load(id)).card(card)!.title, 'Remote title');
      expect((await b.load(id)).document(doc)!.lastPage, 7);
      expect((await (await b.syncLedger)!.pending()).where((c) => c.scope == 'sets/$id'), isEmpty);
    },
  );

  test('independent offline edits merge, preserve both parents and converge without duplicate merges', () async {
    await sendA();
    await a.rename(id, 'Remote set name');
    await b.update(id, (c) => editor.rename(c, card, 'Local card'));
    final localId = (await right.snapshots())['sets/$id']!.commit.id;
    final remoteId = (await left.snapshots())['sets/$id']!.commit.id;
    await sendA();
    final merged = (await right.snapshots())['sets/$id']!.commit;
    expect(merged.parents.toSet(), {localId, remoteId});
    expect((await b.watchAll().first).single.title, 'Remote set name');
    expect((await b.load(id)).card(card)!.title, 'Local card');
    await sendB();
    await sendA();
    final aHead = (await left.snapshots())['sets/$id']!.commit.id;
    final bHead = (await right.snapshots())['sets/$id']!.commit.id;
    expect(aHead, bHead);
    await sendB();
    await sendA();
    expect((await left.snapshots())['sets/$id']!.commit.id, aHead);
    expect((await right.snapshots())['sets/$id']!.commit.id, bHead);
  });

  test(
    'pending transactions travel, independent later writes apply, and explicit resolution survives restart',
    () async {
      await sendA();
      await a.update(id, (c) => editor.rename(c, card, 'A'));
      await b.update(id, (c) => editor.rename(c, card, 'B'));
      final other = (await a.create(const NewStudySet(title: 'Other', colorIndex: 0))).id;
      await sendA();
      expect((await b.load(id)).card(card)!.title, anyOf('A', 'B'));
      expect(await b.load(other), isA<StudySetContent>());
      var head = (await right.snapshots())['sets/$id']!;
      final pending = head.commit.pending.single;
      expect((await b.syncConflicts(id)).single.transaction, pending);
      final thirdLedger = FileSyncLedger(Directory('${root.path}/third'), libraryId: 'library', deviceId: 'third');
      final third = FileLibraryStore(thirdLedger.root, sync: thirdLedger);
      try {
        final waiting = await third.receiveSync([head.commit]);
        expect(waiting.single.reason, 'missingParents');
        await third.receiveSync((await right.history()).values);
        expect((await third.syncConflicts(id)).single.transaction, pending);
        expect(sharedContent(await third.load(id)), sharedContent(await b.load(id)));
      } finally {
        await third.dispose();
      }

      final restored = (await FileSyncLedger.restore(right.root))!;
      expect((await restored.snapshots())['sets/$id']!.commit.pending, [pending]);
      await sendB();
      expect((await left.snapshots())['sets/$id']!.commit.pending, [pending]);
      await a.rename(id, 'Independent after conflict');
      await sendA();
      expect((await b.watchAll().first).firstWhere((s) => s.id == id).title, 'Independent after conflict');
      expect((await right.snapshots())['sets/$id']!.commit.pending, [pending]);
      await expectLater(
        b.resolveSyncConflict(id, pending, expectedRevision: head.revision, useCandidate: true),
        throwsA(isA<SyncRevisionChanged>()),
      );
      head = (await right.snapshots())['sets/$id']!;
      final candidate = (await right.history())[pending]!;
      final chosenTitle = ((candidate.payload['content'] as Map)['cards'] as Map)[card]['title'];
      await b.resolveSyncConflict(id, pending, expectedRevision: head.revision, useCandidate: true);
      expect((await b.load(id)).card(card)!.title, chosenTitle);
      expect((await b.watchAll().first).firstWhere((s) => s.id == id).title, 'Independent after conflict');
      expect((await right.snapshots())['sets/$id']!.commit.resolves, [pending]);
      await sendB();
      expect((await a.load(id)).card(card)!.title, chosenTitle);
      expect((await left.snapshots())['sets/$id']!.commit.pending, isEmpty);
      final before = (await right.history()).length;
      await sendA();
      await sendB();
      expect((await right.history()).length, before);
      await b.dispose();
      b = FileLibraryStore(right.root);
      expect((await b.load(id)).card(card)!.title, chosenTitle);
      expect(await b.syncConflicts(id), isEmpty);
    },
  );

  test('concurrent human choices preserve alternatives, independent writes and restart convergence', () async {
    await sendA();
    await a.update(id, (c) => editor.rename(c, card, 'A'));
    await b.update(id, (c) => editor.rename(c, card, 'B'));
    await sendA();
    await sendB();
    final initial = (await left.snapshots())['sets/$id']!;
    final pending = initial.commit.pending.single;
    final displayed = (await a.load(id)).card(card)!.title;
    await a.resolveSyncConflict(id, pending, expectedRevision: initial.revision, useCandidate: false);
    final keep = (await left.snapshots())['sets/$id']!.commit;
    await b.resolveSyncConflict(
      id,
      pending,
      expectedRevision: (await right.snapshots())['sets/$id']!.revision,
      useCandidate: true,
    );
    final use = (await right.snapshots())['sets/$id']!.commit;
    await b.rename(id, 'Independent after choices');
    await sendB();
    final status = await a.contentSyncStatus(id);
    expect(status.problems, isEmpty);
    expect(status.conflicts.map((c) => c.id).toSet(), {keep.id, use.id});
    expect(status.conflicts.every((c) => c.concurrentChoices == 2 && c.changes.isNotEmpty), isTrue);
    expect(status.conflicts.firstWhere((c) => c.id == keep.id).changes.any((c) => c.candidate == displayed), isTrue);
    expect((await a.watchAll().first).single.title, 'Independent after choices');
    await sendA();
    final thirdLedger = FileSyncLedger(Directory('${root.path}/third'), libraryId: 'library', deviceId: 'third');
    var third = FileLibraryStore(thirdLedger.root, sync: thirdLedger);
    try {
      final head = (await left.snapshots())['sets/$id']!;
      expect((await third.receiveSync([head.commit])).single.reason, 'missingParents');
      await third.receiveSync((await left.history()).values.toList().reversed);
      expect((await third.contentSyncStatus(id)).conflicts, hasLength(2));
      await third.dispose();
      third = FileLibraryStore(thirdLedger.root);
      final restored = await third.contentSyncStatus(id);
      expect(restored.conflicts, hasLength(2));
      await third.rename(id, 'Third device independent edit');
      await expectLater(
        third.chooseContentSync(id, keep.id, expectedRevision: restored.revision!, useCandidate: true),
        throwsA(isA<ContentSyncActionException>()),
      );
      await third.chooseContentSync(
        id,
        keep.id,
        expectedRevision: (await third.contentSyncStatus(id)).revision!,
        useCandidate: true,
      );
      expect((await third.load(id)).card(card)!.title, displayed);
      final ledger = (await third.syncLedger)!;
      final chosen = (await ledger.snapshots())['sets/$id']!.commit;
      expect(chosen.resolves.toSet(), {keep.id, use.id});
      await a.receiveSync(await ledger.pending());
      await b.receiveSync(await ledger.pending());
      expect((await a.contentSyncStatus(id)).conflicts, isEmpty);
      expect((await b.contentSyncStatus(id)).conflicts, isEmpty);
      expect((await a.watchAll().first).single.title, 'Third device independent edit');
      expect(sharedContent(await a.load(id)), sharedContent(await third.load(id)));
      final count = (await left.history()).length;
      await sendA();
      await sendB();
      expect((await left.history()).length, count);
    } finally {
      await third.dispose();
    }
  });

  test('structural moves are isolated atomically while later metadata continues', () async {
    late String one, two;
    await a.update(id, (c) {
      final first = editor.addTopic(c, title: 'One');
      one = first.$2.id;
      final second = editor.addTopic(first.$1, title: 'Two');
      two = second.$2.id;
      return second.$1;
    });
    await sendA();
    await a.update(id, (c) => editor.rename(editor.move(c, one, two), card, 'A related'));
    await b.update(id, (c) => editor.move(c, two, one));
    await a.rename(id, 'Later metadata');
    await sendA();
    final pending = (await b.syncConflicts(id)).single;
    expect(pending.reason, 'structure');
    expect(contentIntegrityErrors(await b.load(id)), isEmpty);
    expect((await b.watchAll().first).single.title, 'Later metadata');
    final blocked = (await right.history())[pending.transaction]!;
    if (blocked.deviceId == 'left') expect((await b.load(id)).card(card)!.title, 'Question');
    await sendB();
    expect(sharedContent(await a.load(id)), sharedContent(await b.load(id)));
    final head = (await right.snapshots())['sets/$id']!;
    await expectLater(
      b.resolveSyncConflict(id, pending.transaction, expectedRevision: head.revision, useCandidate: true),
      throwsFormatException,
    );
    expect((await right.snapshots())['sets/$id']!.revision, head.revision);
    await b.resolveSyncConflict(id, pending.transaction, expectedRevision: head.revision, useCandidate: false);
    await sendB();
    expect(await a.syncConflicts(id), isEmpty);
  });

  test('resolved or clean integrations still permit causal deletion', () async {
    await sendA();
    await a.rename(id, 'Remote title');
    await b.update(id, (c) => editor.rename(c, card, 'Local card'));
    await sendA();
    await sendB();
    await a.delete(id);
    await sendA();
    expect(await b.watchAll().first, isEmpty);
    expect((await right.snapshots())['sets/$id']!.deleted, isTrue);
  });

  test('same-branch unrelated transaction passes a conflict before any merge is returned', () async {
    await sendA();
    await a.update(id, (c) => editor.rename(c, card, 'A'));
    await b.update(id, (c) => editor.rename(c, card, 'B'));
    await a.rename(id, 'A later independent edit');
    await sendA();
    expect((await b.watchAll().first).single.title, 'A later independent edit');
    final head = (await right.snapshots())['sets/$id']!;
    expect(head.commit.pending, hasLength(1));
    final before = (await b.load(id)).card(card)!.title;
    await b.resolveSyncConflict(id, head.commit.pending.single, expectedRevision: head.revision, useCandidate: false);
    expect((await b.load(id)).card(card)!.title, before);
    await sendB();
    expect((await a.load(id)).card(card)!.title, before);
    expect((await left.snapshots())['sets/$id']!.commit.pending, isEmpty);
  });

  test('editing sessions persist drafts and publish one atomic shared edit after the outer end', () async {
    await sendA();
    final before = (await left.snapshots())['sets/$id']!;
    final count = (await left.history()).values.where((c) => c.scope == 'sets/$id').length;
    await a.beginContentTransaction(id);
    await a.beginContentTransaction(id);
    await a.update(id, (c) => editor.rename(c, card, 'First keystroke'));
    await a.update(id, (c) => editor.rename(c, card, 'Final title'));
    final draft = (await left.snapshots())['sets/$id']!;
    expect(draft.draft, isTrue);
    expect(draft.commit.id, before.commit.id);
    expect((await a.load(id)).card(card)!.title, 'Final title');
    expect((await left.pending()).where((c) => c.scope == 'sets/$id'), isEmpty);
    await a.endContentTransaction(id);
    expect((await left.snapshots())['sets/$id']!.draft, isTrue);
    await a.endContentTransaction(id);
    expect((await left.snapshots())['sets/$id']!.draft, isFalse);
    expect((await left.history()).values.where((c) => c.scope == 'sets/$id'), hasLength(count + 1));
    await sendA();
    expect((await b.load(id)).card(card)!.title, 'Final title');
    await a.endContentTransaction(id); // Idempotent close.
  });

  test('cancelled drafts produce no shared content edit and cannot be deleted mid-session', () async {
    final original = await a.load(id);
    final before = (await left.snapshots())['sets/$id']!.commit.id;
    await a.beginContentTransaction(id);
    await a.update(id, (c) => editor.rename(c, card, 'Temporary'));
    await expectLater(a.delete(id), throwsStateError);
    await a.update(id, (_) => original);
    await a.endContentTransaction(id);
    expect((await left.snapshots())['sets/$id']!.commit.id, before);
    expect((await left.snapshots())['sets/$id']!.draft, isFalse);
  });

  test('a crash keeps the last saved draft and reopening seals it as one recoverable edit', () async {
    final count = (await left.history()).values.where((c) => c.scope == 'sets/$id').length;
    await a.beginContentTransaction(id);
    await a.update(id, (c) => editor.rename(c, card, 'Recovered draft'));
    final restored = (await FileSyncLedger.restore(left.root))!;
    expect((await restored.snapshots())['sets/$id']!.draft, isTrue);
    expect((await restored.pending()).where((c) => c.scope == 'sets/$id'), isEmpty);
    await a.dispose();
    a = FileLibraryStore(left.root, sync: restored);
    expect((await a.load(id)).card(card)!.title, 'Recovered draft');
    expect(a.recoveredEditingDrafts, {id});
    expect((await restored.snapshots())['sets/$id']!.draft, isFalse);
    expect((await restored.history()).values.where((c) => c.scope == 'sets/$id'), hasLength(count + 1));
  });

  test('protected cards defer touching updates, allow unrelated metadata and retry on release', () async {
    await sendA();
    final lease = b.protectContent(id, [
      ['cards', card],
    ]);
    await a.rename(id, 'Unrelated metadata');
    await sendA();
    expect((await b.watchAll().first).single.title, 'Unrelated metadata');
    await a.update(id, (c) => editor.rename(c, card, 'Remote text'));
    await sendA();
    expect((await b.load(id)).card(card)!.title, 'Question');
    expect((await right.issues()).values.any((p) => p['reason'] == 'editing'), isTrue);
    await lease.release();
    expect((await b.load(id)).card(card)!.title, 'Remote text');
    expect(await right.issues(), isEmpty);
    await lease.release();
  });

  test('draft completion merges queued remote work against the final local transaction', () async {
    await sendA();
    await b.beginContentTransaction(id);
    await b.update(id, (c) => editor.rename(c, card, 'Local final'));
    await a.rename(id, 'Remote title');
    await sendA();
    expect((await b.watchAll().first).single.title, 'Original');
    await b.endContentTransaction(id);
    expect((await b.watchAll().first).single.title, 'Remote title');
    expect((await b.load(id)).card(card)!.title, 'Local final');
    await sendB();
    expect(sharedContent(await a.load(id)), sharedContent(await b.load(id)));
  });

  test('a lease acquired after planning is checked again at the ledger commit point', () async {
    await sendA();
    await a.update(id, (c) => editor.rename(c, card, 'Remote'));
    late ContentEditLease lease;
    right.beforeAdvance = () async {
      lease = b.protectContent(id, [
        ['cards', card],
      ]);
    };
    await sendA();
    expect((await b.load(id)).card(card)!.title, 'Question');
    await lease.release();
    expect((await b.load(id)).card(card)!.title, 'Remote');
  });

  test('lease readiness waits for an already running repository writer', () async {
    await sendA();
    await a.update(id, (c) => editor.rename(c, card, 'Remote'));
    final entered = Completer<void>(), finish = Completer<void>();
    right.beforeAdvance = () async {
      entered.complete();
      await finish.future;
    };
    final receive = sendA();
    await entered.future;
    final lease = b.protectContent(id, [
      ['cards', card],
    ]);
    var ready = false;
    final barrier = lease.ready.then((_) {
      ready = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    finish.complete();
    await receive;
    await barrier;
    expect(ready, isTrue);
    expect((await b.load(id)).card(card)!.title, 'Question');
    await lease.release();
    expect((await b.load(id)).card(card)!.title, 'Remote');
  });

  test('release retry failures remain observable and do not lose received input', () async {
    await sendA();
    final lease = b.protectContent(id, [
      ['cards', card],
    ]);
    await lease.ready;
    await a.update(id, (c) => editor.rename(c, card, 'Remote'));
    await sendA();
    right.beforeAdvance = () async {
      throw StateError('temporary I/O failure');
    };
    await lease.release();
    expect(b.editSyncErrors[id], isA<StateError>());
    expect((await b.load(id)).card(card)!.title, 'Question');
    final retry = b.protectContent(id, [
      ['cards', card],
    ]);
    await retry.ready;
    await retry.release();
    expect(b.editSyncErrors, isEmpty);
    expect((await b.load(id)).card(card)!.title, 'Remote');
  });

  test('out-of-order receipt and editing deferral recover without changing live content', () async {
    final commits = (await left.pending()).where((c) => c.scope == 'sets/$id').toList();
    final newest = commits.last;
    final missing = await b.receiveSync([newest]);
    expect(missing.single.reason, 'missingParents');
    expect(await b.watchAll().first, isEmpty);
    await b.receiveSync(commits, canApply: (_) => false);
    expect(await b.watchAll().first, isEmpty);
    expect((await right.issues()).values.every((v) => v['reason'] == 'editing'), isTrue);
    await b.reconcileSync();
    expect((await b.load(id)).card(card)!.title, 'Question');
    expect(await right.issues(), isEmpty);
  });

  test('post-commit projection failure stays committed and deletion retains recoverable history', () async {
    await sendA();
    final blocker = Directory('${right.root.path}/sets/$id.mmset/studyset.json.tmp');
    await blocker.create();
    await a.rename(id, 'Durable remote');
    await sendA();
    expect((await b.watchAll().first).single.title, 'Durable remote');
    expect(b.syncProjectionErrors, isNotEmpty);
    await blocker.delete();
    await a.delete(id);
    await sendA();
    expect(await b.watchAll().first, isEmpty);
    final restored = (await FileSyncLedger.restore(right.root))!;
    expect((await restored.snapshots())['sets/$id']!.deleted, isTrue);
    expect((await restored.history()).values.any((c) => c.scope == 'sets/$id' && !c.deleted), isTrue);
  });

  test('delete against offline edit is a durable conflict, never silent deletion', () async {
    await sendA();
    await a.delete(id);
    await b.rename(id, 'Keep my edit');
    await sendA();
    expect((await b.watchAll().first).single.title, 'Keep my edit');
    final reasons = (await right.issues()).values.map((i) => i['reason']);
    expect(reasons, isNotEmpty);
    expect(reasons, everyElement('deleteEdit'));
  });

  test('changed expected revision recomputes the merge and publishes the durable result to watchers', () async {
    await sendA();
    final notifications = <StudySetContent>[];
    final subscription = b.watch(id).listen(notifications.add);
    await Future<void>.delayed(Duration.zero);
    await a.update(id, (c) => editor.rename(c, card, 'Remote'));
    right.beforeAdvance = () async {
      final head = (await right.snapshots())['sets/$id']!;
      await right.commit([
        SyncMutation(
          'sets/$id',
          local: {...head.value!, 'title': 'Intervening local'},
          shared: {...head.commit.payload, 'title': 'Intervening local'},
        ),
      ]);
    };
    await sendA();
    await Future<void>.delayed(Duration.zero);
    expect((await b.watchAll().first).single.title, 'Intervening local');
    expect((await b.load(id)).card(card)!.title, 'Remote');
    expect(notifications.last.card(card)!.title, 'Remote');
    await subscription.cancel();
  });

  test('new document revision does not inherit an old reading anchor', () async {
    await sendA();
    await b.update(id, (c) => editor.setLastPage(c, doc, 9));
    await a.update(id, (c) => c.copyWith(documents: [c.document(doc)!.copyWith(revision: 'new-revision')]));
    await sendA();
    expect((await b.load(id)).document(doc)!.revision, 'new-revision');
    expect((await b.load(id)).document(doc)!.lastPage, 1);
  });

  test('a received device fork is quarantined without blocking local edits or restart', () async {
    await sendA();
    final accepted = (await right.snapshots())['sets/$id']!.commit;
    final fork = SyncCommit.create(
      libraryId: 'library',
      scope: accepted.scope,
      deviceId: accepted.deviceId,
      sequence: accepted.sequence,
      parents: accepted.parents,
      payload: {...accepted.payload, 'title': 'Fork'},
    );
    await b.receiveSync([fork]);
    expect((await right.issues()).values.any((v) => v['reason'] == 'invalidHistory'), isTrue);
    await b.rename(id, 'Local work continues');
    expect((await b.watchAll().first).single.title, 'Local work continues');
    final restored = (await FileSyncLedger.restore(right.root))!;
    expect((await restored.snapshots())['sets/$id']!.value!['title'], 'Local work continues');
  });

  test('invalid remote identity/content and cloned device identity fail without publishing', () async {
    final base = (await left.snapshots())['sets/$id']!.commit;
    final invalid = SyncCommit.create(
      libraryId: 'library',
      deviceId: 'other',
      scope: 'sets/../escape',
      sequence: 1,
      payload: base.payload,
    );
    await b.receiveSync([invalid]);
    expect((await right.issues()).values.single['reason'], 'invalidIdentity');
    final malformed = SyncCommit.create(
      libraryId: 'library',
      deviceId: 'other',
      scope: 'sets/bad',
      sequence: 1,
      payload: {...base.payload, 'id': 'bad', 'lastOpenedAt': 'private'},
    );
    await b.receiveSync([malformed]);
    expect((await right.issues()).values.any((v) => v['reason'] == 'invalidContent'), isTrue);
    expect(await b.watchAll().first, isEmpty);
    final original = await a.load(id);
    final unsafe = original.copyWith(documents: [original.document(doc)!.copyWith(fileName: '../../outside.pdf')]);
    final traversal = SyncCommit.create(
      libraryId: 'library',
      deviceId: 'untrusted',
      scope: 'sets/$id',
      sequence: 1,
      payload: {...base.payload, 'content': sharedContent(unsafe)},
    );
    await b.receiveSync([traversal]);
    expect((await right.issues())[traversal.id]!['reason'], 'invalidContent');
    expect(await b.watchAll().first, isEmpty);
    for (final path in ['../outside.pdf', '/absolute.pdf', r'C:\outside.pdf', 'documents/../../outside.pdf']) {
      expect(() => b.resolveFile(id, path), throwsArgumentError);
    }
    expect(b.resolveFile(id, ''), endsWith('$id.mmset'));
    final clone = SyncCommit.create(
      libraryId: 'library',
      deviceId: 'right',
      scope: 'sets/clone',
      sequence: 1,
      payload: {},
    );
    await expectLater(right.receive([clone]), throwsFormatException);
    expect((await right.history()).containsKey(clone.id), isFalse);
  });
}

class RacingLedger extends FileSyncLedger {
  RacingLedger(super.root) : super(libraryId: 'library', deviceId: 'right');
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
    if (inputs.any((m) => m.adopt != null || m.mergeParent != null)) {
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
