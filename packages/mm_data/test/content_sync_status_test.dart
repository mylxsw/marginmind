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
  late String id, card;
  var serial = 0;
  final editor = StudySetEditor(newId: () => 'item-${++serial}', now: () => DateTime.utc(2026));
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-status-');
    left = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    right = FileSyncLedger(Directory('${root.path}/b'), libraryId: 'lib', deviceId: 'b');
    a = FileLibraryStore(left.root, sync: left);
    b = FileLibraryStore(right.root, sync: right);
    id = (await a.create(const NewStudySet(title: 'My set', colorIndex: 0))).id;
    await a.update(id, (c) {
      final created = editor.addNote(c, text: 'Original question');
      card = created.$2.id;
      return created.$1;
    });
    await b.receiveSync(await left.pending());
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await root.delete(recursive: true);
  });
  Future<ContentSyncStatus> conflict() async {
    await a.update(id, (c) => editor.rename(c, card, 'Choice A'));
    await b.update(id, (c) => editor.rename(c, card, 'Choice B'));
    await b.receiveSync(await left.pending());
    return b.contentSyncStatus(id);
  }

  Matcher failure(ContentSyncActionFailure reason) =>
      throwsA(isA<ContentSyncActionException>().having((e) => e.reason, 'reason', reason));

  test('local mode stays disabled and status subscriptions close with the repository', () async {
    final local = FileLibraryStore(Directory('${root.path}/local'));
    final states = <ContentSyncStatus>[];
    final done = Completer<void>();
    final first = Completer<void>();
    local.watchContentSync('missing').listen((s) {
      states.add(s);
      if (!first.isCompleted) first.complete();
    }, onDone: done.complete);
    await first.future;
    expect(states.single.enabled, isFalse);
    expect(states.single.needsAttention, isFalse);
    await local.retryContentSync('missing');
    await local.acknowledgeContentRecovery('missing', 'none');
    await local.dispose();
    await done.future;
  });

  test('current-head conflicts and unapplied branches both appear without leaking IDs into preview', () async {
    final status = await conflict();
    expect(await right.issues(), isEmpty);
    expect(status.needsAttention, isTrue);
    expect(status.queued, greaterThan(0));
    final choice = status.conflicts.single;
    final change = choice.changes.single;
    expect(change.entity, ContentSyncEntity.card);
    expect(change.field, ContentSyncField.title);
    expect({change.current, change.candidate}, {'Choice A', 'Choice B'});
    expect(change.title, (await b.load(id)).card(card)!.title);
    expect(choice.canUseCandidate, isTrue);
    final missing = SyncCommit.create(
      libraryId: 'lib',
      scope: 'sets/$id',
      deviceId: 'unavailable',
      sequence: 1,
      parents: ['0' * 64],
      payload: {},
    );
    await b.receiveSync([missing]);
    final combined = await b.contentSyncStatus(id);
    expect(combined.conflicts.single.id, choice.id);
    expect(combined.problems, contains(ContentSyncProblem.missingHistory));
    await b.chooseContentSync(id, choice.id, expectedRevision: combined.revision!, useCandidate: true);
    expect((await b.load(id)).card(card)!.title, change.candidate);
    expect((await b.contentSyncStatus(id)).conflicts, isEmpty);
    expect((await b.contentSyncStatus(id)).problems, contains(ContentSyncProblem.missingHistory));
  });

  test('stale and editing choices are typed; explicit keep preserves subsequent edits', () async {
    final status = await conflict();
    final choice = status.conflicts.single;
    await b.rename(id, 'New unrelated title');
    await expectLater(
      b.chooseContentSync(id, choice.id, expectedRevision: status.revision!, useCandidate: true),
      failure(ContentSyncActionFailure.stale),
    );
    final lease = b.protectContent(id, [
      ['cards', card],
    ]);
    await lease.ready;
    var fresh = await b.contentSyncStatus(id);
    expect(fresh.editing, isTrue);
    await expectLater(
      b.chooseContentSync(id, choice.id, expectedRevision: fresh.revision!, useCandidate: false),
      failure(ContentSyncActionFailure.editing),
    );
    await lease.release();
    fresh = await b.contentSyncStatus(id);
    final title = (await b.load(id)).card(card)!.title;
    await b.chooseContentSync(id, choice.id, expectedRevision: fresh.revision!, useCandidate: false);
    expect((await b.load(id)).card(card)!.title, title);
    expect((await b.watchAll().first).single.title, 'New unrelated title');
    expect((await b.contentSyncStatus(id)).needsAttention, isFalse);
  });

  test('invalid structural candidate is reviewable but cannot be applied', () async {
    late String one, two;
    await a.update(id, (c) {
      final first = editor.addTopic(c, title: 'First topic');
      one = first.$2.id;
      final second = editor.addTopic(first.$1, title: 'Second topic');
      two = second.$2.id;
      return second.$1;
    });
    await b.receiveSync(await left.pending());
    await a.update(id, (c) => editor.move(c, one, two));
    await b.update(id, (c) => editor.move(c, two, one));
    await b.receiveSync(await left.pending());
    final status = await b.contentSyncStatus(id);
    final choice = status.conflicts.single;
    expect(choice.canUseCandidate, isFalse);
    expect(
      choice.changes.where((c) => c.field == ContentSyncField.structure).single.candidate,
      anyOf('First topic', 'Second topic'),
    );
    await expectLater(
      b.chooseContentSync(id, choice.id, expectedRevision: status.revision!, useCandidate: true),
      failure(ContentSyncActionFailure.invalidCandidate),
    );
    expect((await b.contentSyncStatus(id)).revision, status.revision);
  });

  test('recovery notice survives repeated restarts and exact acknowledgement is durable', () async {
    await a.beginContentTransaction(id);
    await a.update(id, (c) => editor.rename(c, card, 'Recovered saved text'));
    final draft = (await left.snapshots())['sets/$id']!.revision;
    await a.dispose();
    a = FileLibraryStore(left.root);
    expect((await a.contentSyncStatus(id)).recoveryId, draft);
    expect((await a.load(id)).card(card)!.title, 'Recovered saved text');
    await a.dispose();
    a = FileLibraryStore(left.root);
    expect((await a.contentSyncStatus(id)).recoveryId, draft);
    expect(a.recoveredEditingDrafts, {id});
    await expectLater(a.acknowledgeContentRecovery(id, 'outdated'), failure(ContentSyncActionFailure.stale));
    final ledger = (await a.syncLedger)!;
    final before = (await ledger.history()).length;
    await a.acknowledgeContentRecovery(id, draft);
    expect(a.recoveredEditingDrafts, isEmpty);
    expect((await ledger.history()).length, before, reason: 'acknowledgement is private, never a shared edit');
    await a.dispose();
    a = FileLibraryStore(left.root);
    expect((await a.contentSyncStatus(id)).recoveryId, isNull);
    expect(a.recoveredEditingDrafts, isEmpty);
  });

  test('projection retry repairs committed data without repeating an edit', () async {
    final blocker = Directory('${left.root.path}/sets/$id.mmset/studyset.json.tmp');
    await blocker.create();
    await a.rename(id, 'Durable title');
    expect((await a.contentSyncStatus(id)).repairNeeded, isTrue);
    final before = (await left.history()).length;
    await a.retryContentSync(id);
    expect((await a.contentSyncStatus(id)).repairNeeded, isTrue);
    await blocker.delete();
    await a.retryContentSync(id);
    expect((await a.contentSyncStatus(id)).repairNeeded, isFalse);
    expect((await left.history()).length, before);
    final file = File('${left.root.path}/sets/$id.mmset/studyset.json');
    expect(jsonDecode(await file.readAsString())['title'], 'Durable title');
    await a.delete(id);
    await file.writeAsString('stale projection');
    await left.project('${left.root.path}/sets/$id.mmset', () async => throw StateError('interrupted deletion'));
    await a.retryContentSync(id);
    expect(await file.exists(), isFalse);
    expect((await a.contentSyncStatus(id)).repairNeeded, isFalse);
  });

  test('failed startup sealing remains repairable and retry publishes the recovered draft once', () async {
    await a.beginContentTransaction(id);
    await a.update(id, (c) => editor.rename(c, card, 'Recover after disk repair'));
    await a.dispose();
    final flaky = RecoveryLedger(left.root);
    a = FileLibraryStore(left.root, sync: flaky);
    expect((await a.contentSyncStatus(id)).repairNeeded, isTrue);
    await expectLater(a.retryContentSync(id), throwsA(isA<FileSystemException>()));
    expect((await a.contentSyncStatus(id)).retryFailed, isTrue);
    flaky.failRecovery = false;
    await a.retryContentSync(id);
    final status = await a.contentSyncStatus(id);
    expect(status.recoveryId, isNotNull);
    expect(status.repairNeeded, isFalse);
    expect(status.retryFailed, isFalse);
    expect((await a.load(id)).card(card)!.title, 'Recover after disk repair');
    final before = (await flaky.history()).length;
    await a.retryContentSync(id);
    expect((await flaky.history()).length, before);
  });

  test('repair is scoped to the set and retries translation projections, including tombstones', () async {
    await a.update(id, (c) => editor.addDocument(c, title: 'Source', fileName: 'documents/a.pdf', pageCount: 2).$1);
    final document = (await a.load(id)).documents.single.id;
    final translations = await a.translationStore(id);
    final blocker = Directory('${left.root.path}/sets/$id.mmset/translations/$document/zh/segments.jsonl.tmp');
    await blocker.create(recursive: true);
    await translations.append(
      document,
      'zh',
      TranslationSegment(
        key: 'paragraph',
        fingerprint: 'fp',
        page: 1,
        index: 0,
        text: '人工译文',
        model: 'm',
        profile: '',
        origin: TranslationOrigin.edited,
        at: DateTime.utc(2026),
      ),
    );
    await left.project('vocabulary', () async => throw StateError('unrelated'));
    expect((await a.contentSyncStatus(id)).repairNeeded, isTrue);
    await blocker.delete();
    final before = (await left.history()).length;
    await a.retryContentSync(id);
    expect((await a.contentSyncStatus(id)).repairNeeded, isFalse);
    expect(left.projectionErrors, contains('vocabulary'));
    expect((await translations.load(document, 'zh')).segments['paragraph']!.text, '人工译文');
    expect((await left.history()).length, before);
    await a.delete(id);
    await left.project('translations/$id/$document/zh', () async => throw StateError('interrupted deletion'));
    await a.retryContentSync(id);
    expect((await a.contentSyncStatus(id)).repairNeeded, isFalse);
    expect((await translations.load(document, 'zh')).segments, isEmpty);
  });

  test('unreadable history is surfaced by the status stream and cancelled reads do not publish', () async {
    final badRoot = Directory('${root.path}/bad');
    await Directory('${badRoot.path}/.foliarc-sync').create(recursive: true);
    await File('${badRoot.path}/.foliarc-sync/identity.json').writeAsString('{');
    final bad = FileLibraryStore(badRoot);
    await expectLater(bad.watchContentSync('set').first, throwsFormatException);
    final subscription = bad
        .watchContentSync('set')
        .listen((_) => fail('cancelled'), onError: (_) => fail('cancelled'));
    await subscription.cancel();
    await bad.dispose();
  });

  test('watch observes editing deferral, release and delivery acknowledgement and cancels cleanly', () async {
    final queue = StreamIterator(b.watchContentSync(id));
    addTearDown(queue.cancel);
    expect(await queue.moveNext(), isTrue);
    final lease = b.protectContent(id, [
      ['cards', card],
    ]);
    await lease.ready;
    while (!queue.current.editing) {
      expect(await queue.moveNext(), isTrue);
    }
    await a.update(id, (c) => editor.rename(c, card, 'Received later'));
    await b.receiveSync(await left.pending());
    while (!queue.current.problems.contains(ContentSyncProblem.editing)) {
      expect(await queue.moveNext(), isTrue);
    }
    await lease.release();
    while (queue.current.editing || queue.current.problems.isNotEmpty) {
      expect(await queue.moveNext(), isTrue);
    }
    expect((await b.load(id)).card(card)!.title, 'Received later');
    await b.rename(id, 'Upload later');
    while (queue.current.queued == 0) {
      expect(await queue.moveNext(), isTrue);
    }
    await right.acknowledge((await right.pending()).map((c) => c.id));
    while (queue.current.queued != 0) {
      expect(await queue.moveNext(), isTrue);
    }
    await queue.cancel();
    await b.rename(id, 'After cancellation');
  });
}

class RecoveryLedger extends FileSyncLedger {
  RecoveryLedger(super.root) : super(libraryId: 'lib', deviceId: 'a');
  bool failRecovery = true;
  @override
  Future<Map<String, LocalSyncSnapshot>> commit(
    Iterable<SyncMutation> mutations, {
    Map<String, String?> expected = const {},
    void Function(Map<String, LocalSyncSnapshot>)? validate,
    bool Function(String scope)? tombstoneWhere,
    Iterable<String> resolved = const [],
    Map<String, String> recovered = const {},
  }) {
    if (recovered.isNotEmpty && failRecovery) throw const FileSystemException('disk unavailable');
    return super.commit(
      mutations,
      expected: expected,
      validate: validate,
      tombstoneWhere: tombstoneWhere,
      resolved: resolved,
      recovered: recovered,
    );
  }
}
