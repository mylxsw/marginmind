import 'dart:async';
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
  final now = DateTime.utc(2026);
  late StudySetEditor editor;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sync-reviews-');
    left = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a');
    right = ReviewRacingLedger(Directory('${root.path}/b'));
    a = FileLibraryStore(left.root, sync: left);
    b = FileLibraryStore(right.root, sync: right);
    editor = StudySetEditor(newId: () => 'item-${++serial}', now: () => now);
    id = (await a.create(const NewStudySet(title: 'Set', colorIndex: 0))).id;
    await a.update(id, (c) {
      final n = editor.addNote(c, text: 'Question');
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

  test('review application rechecks external editing protection at the commit point', () async {
    await sendA();
    await a.update(id, (c) => editor.rate(c, card, Rating.good));
    var checks = 0;
    await b.receiveSync((await left.pending()).where((c) => c.scope == 'reviews/$id'), canApply: (_) => ++checks == 1);
    expect(checks, 2);
    expect((await b.load(id)).reviewLogs, isEmpty);
    expect((await right.issues()).values.map((i) => i['reason']), contains('editing'));
    await b.reconcileSync();
    expect((await b.load(id)).reviewLogs, hasLength(1));
    expect(await right.issues(), isEmpty);
  });

  test('a failed atomic rating leaves both schedule and outgoing history unchanged', () async {
    final before = (await left.pending()).map((c) => c.id).toList();
    final logs = Directory('${left.root.path}/.foliarc-sync/local');
    final saved = await logs.rename('${logs.path}.saved');
    final obstruction = File(logs.path);
    await obstruction.writeAsString('blocked');
    await expectLater(a.update(id, (c) => editor.rate(c, card, Rating.good)), throwsA(isA<FileSystemException>()));
    expect((await a.load(id)).reviewLogs, isEmpty);
    expect((await left.pending()).map((c) => c.id), before);
    await obstruction.delete();
    await saved.rename(logs.path);
    await a.update(id, (c) => editor.rate(c, card, Rating.good));
    expect((await a.load(id)).reviewLogs, hasLength(1));
    final reviewHead = (await left.snapshots())['reviews/$id']!.commit.id;
    await a.rename(id, 'Metadata only');
    expect((await left.snapshots())['reviews/$id']!.commit.id, reviewHead);
  });

  test('an intervening local score causes replay to recompute instead of overwriting it', () async {
    await sendA();
    await a.update(id, (c) => editor.rate(c, card, Rating.good));
    (right as ReviewRacingLedger).beforeAdvance = () async {
      final heads = await right.snapshots();
      final set = heads['sets/$id']!, reviews = heads['reviews/$id']!;
      final record = Map<String, Object?>.of(set.value!);
      final content = StudySetContent.fromJson((record['content'] as Map).cast());
      final rated = editor.rate(content, card, Rating.easy);
      record['content'] = rated.toJson();
      final timeline = ReviewTimeline.fromJson(reviews.value!).append(reviewData(rated), deviceId: 'b').toJson();
      await right.commit([
        SyncMutation('sets/$id', local: record, shared: set.commit.payload),
        SyncMutation('reviews/$id', local: timeline, shared: timeline, requireScopes: ['sets/$id']),
      ]);
    };
    await sendA();
    expect((await b.load(id)).reviewLogs, hasLength(2));
    expect((await b.load(id)).reviewOf(card)!.reps, 2);
    await sendB();
    expect(normalizeReviewData(reviewData(await a.load(id))), normalizeReviewData(reviewData(await b.load(id))));
  });

  test('legacy snapshots migrate once without losing due dates or incomplete history', () async {
    final original = (await left.snapshots())['sets/$id']!;
    final legacy = (await a.load(id)).copyWith(
      reviews: [
        ReviewState(
          cardId: card,
          due: now.add(const Duration(days: 9)),
          intervalDays: 9,
          ease: 2.3,
          reps: 20,
          lapses: 2,
          lastReviewedAt: now,
        ),
      ],
    );
    final record = {...original.value!, 'content': legacy.toJson()};
    await right.commit([
      SyncMutation('sets/$id', local: record, shared: original.commit.payload),
      SyncMutation('reviews/$id', local: reviewData(legacy), shared: reviewData(legacy)),
    ]);
    await b.dispose();
    b = FileLibraryStore(right.root, sync: right);
    expect((await b.load(id)).reviewOf(card)!.due, legacy.reviewOf(card)!.due);
    await b.rename(id, 'Migrate');
    final migrated = (await right.snapshots())['reviews/$id']!;
    expect(ReviewTimeline.fromJson(migrated.value!).events, isEmpty);
    await b.update(id, (c) => editor.rate(c, card, Rating.good));
    expect((await b.load(id)).reviewOf(card)!.reps, 21);
    await b.dispose();
    b = FileLibraryStore(right.root);
    await b.rename(id, 'After restart');
    expect((await b.load(id)).reviewLogs, hasLength(1));
  });

  test('missing and unsupported dependencies are retained without applying a score or content', () async {
    await sendA();
    final heads = await left.snapshots();
    final base = heads['reviews/$id']!.commit, set = heads['sets/$id']!.commit;
    final timeline = ReviewTimeline.fromJson(base.payload)
        .append(reviewData(editor.rate(await a.load(id), card, Rating.good)), deviceId: 'remote');
    for (final missing in [false, true]) {
      final remote = SyncCommit.create(
        libraryId: 'lib',
        scope: base.scope,
        deviceId: 'remote',
        sequence: missing ? 2 : 1,
        parents: [base.id],
        payload: timeline.toJson(),
        requires: missing ? {'sets/$id': '0' * 64} : {},
      );
      await b.receiveSync([remote]);
      expect((await b.load(id)).reviewLogs, isEmpty);
      expect((await right.issues())[remote.id]!['reason'], missing ? 'missingContent' : 'invalidReviews');
    }
    final unsupported = SyncCommit.create(
      libraryId: 'lib',
      scope: set.scope,
      deviceId: 'other',
      sequence: 1,
      parents: [set.id],
      payload: {...set.payload, 'title': 'Blocked'},
      requires: {base.scope: base.id},
    );
    await b.receiveSync([unsupported]);
    expect((await b.watchAll().first).single.title, 'Set');
    expect((await right.issues())[unsupported.id]!['reason'], 'unsupportedDependencies');
    expect((await b.contentSyncStatus(id)).problems, isNotEmpty);
  });

  test(
    'offline same-card ratings converge, survive restart and third-device bootstrap without duplicate logs',
    () async {
      await sendA();
      await a.update(id, (c) => editor.rate(c, card, Rating.good));
      final custom = StudySetEditor(
        newId: () => 'custom-score',
        now: () => now.add(const Duration(minutes: 1)),
        fsrsParameters: FsrsParameters(retention: .8, maximumInterval: 120),
      );
      await b.update(id, (c) => custom.rate(c, card, Rating.easy));
      final notifications = <StudySetContent>[];
      final subscription = b.watch(id).listen(notifications.add);
      await sendA();
      await sendB();
      await sendA();
      expect(normalizeReviewData(reviewData(await a.load(id))), normalizeReviewData(reviewData(await b.load(id))));
      expect((await a.load(id)).reviewLogs, hasLength(2));
      expect((await a.load(id)).reviewOf(card)!.reps, 2);
      final before = (await right.history()).length;
      await sendA();
      await sendB();
      expect((await right.history()).length, before);
      await Future<void>.delayed(Duration.zero);
      expect(notifications.last.reviewLogs, hasLength(2));
      await subscription.cancel();
      await b.dispose();
      b = FileLibraryStore(right.root);
      expect((await b.load(id)).reviewLogs, hasLength(2));
      final thirdLedger = FileSyncLedger(Directory('${root.path}/c'), libraryId: 'lib', deviceId: 'c');
      final third = FileLibraryStore(thirdLedger.root, sync: thirdLedger);
      await third.receiveSync((await left.history()).values.toList().reversed);
      expect(normalizeReviewData(reviewData(await third.load(id))), normalizeReviewData(reviewData(await a.load(id))));
      expect((await thirdLedger.pending()).where((c) => c.scope.startsWith('reviews/')), isEmpty);
      await third.dispose();
    },
  );

  test('review dependency binds to content created in the same atomic write and waits when delivered first', () async {
    await a.update(id, (c) {
      final created = editor.addNote(c, text: 'New rated card');
      card = created.$2.id;
      return editor.rate(created.$1, card, Rating.good);
    });
    final snapshots = await left.snapshots();
    final review = snapshots['reviews/$id']!;
    expect(review.commit.requires, {'sets/$id': snapshots['sets/$id']!.commit.id});
    expect(review.revision, snapshots['sets/$id']!.revision);
    final incoming = await left.pending();
    await b.receiveSync(incoming.where((c) => c.scope.startsWith('reviews/')));
    expect(await b.watchAll().first, isEmpty);
    expect((await right.issues()).values.map((i) => i['reason']), contains('missingContent'));
    await b.receiveSync(incoming.where((c) => c.scope.startsWith('sets/')));
    expect((await b.load(id)).reviewLogs.single.cardId, card);
    expect((await b.load(id)).card(card)!.title, 'New rated card');
    expect(await right.issues(), isEmpty);
  });

  test('content can be edited while a shared baseline is missing, but scoring cannot fork an empty baseline', () async {
    final all = await left.pending();
    await b.receiveSync(all.where((c) => c.scope.startsWith('sets/')));
    await b.rename(id, 'Offline content');
    await expectLater(b.update(id, (c) => editor.rate(c, card, Rating.good)), throwsA(isA<ReviewWriteUnavailable>()));
    expect((await right.snapshots()).containsKey('reviews/$id'), isFalse);
    await b.receiveSync(all.where((c) => c.scope.startsWith('reviews/')));
    await b.update(id, (c) => editor.rate(c, card, Rating.good));
    expect((await b.load(id)).reviewLogs, hasLength(1));
  });

  test('received review replay waits for an active draft and cancellation preserves the scores', () async {
    await sendA();
    final original = await b.load(id);
    await b.beginContentTransaction(id);
    await b.update(id, (c) => editor.rename(c, card, 'Draft title'));
    await a.update(id, (c) => editor.rate(c, card, Rating.good));
    await sendA();
    expect((await b.load(id)).reviewLogs, isEmpty);
    await expectLater(b.update(id, (c) => editor.rate(c, card, Rating.easy)), throwsA(isA<ReviewWriteUnavailable>()));
    await b.update(id, (_) => original);
    await b.endContentTransaction(id);
    expect((await b.load(id)).card(card)!.title, 'Question');
    expect((await b.load(id)).reviewLogs, hasLength(1));
    expect((await b.contentSyncStatus(id)).problems, isEmpty);
  });

  test('late scores do not resurrect a deleted set and projection repair does not duplicate ratings', () async {
    await sendA();
    await a.update(id, (c) => editor.rate(c, card, Rating.good));
    final blocker = Directory('${right.root.path}/sets/$id.mmset/studyset.json.tmp');
    await blocker.create();
    await sendA();
    expect((await b.load(id)).reviewLogs, hasLength(1));
    expect((await b.contentSyncStatus(id)).repairNeeded, isTrue);
    await blocker.delete();
    await b.retryContentSync(id);
    expect((await b.load(id)).reviewLogs, hasLength(1));
    await a.update(id, (c) => editor.rate(c, card, Rating.easy));
    await b.delete(id);
    await sendA();
    expect(await b.watchAll().first, isEmpty);
    expect((await right.snapshots())['reviews/$id']!.deleted, isTrue);
    expect((await right.issues()).values.map((i) => i['reason']), contains('deleteEdit'));
  });
}

class ReviewRacingLedger extends FileSyncLedger {
  ReviewRacingLedger(super.root) : super(libraryId: 'lib', deviceId: 'b');
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
    if (inputs.any((m) => m.scope.startsWith('reviews/') && (m.adopt != null || m.mergeParent != null))) {
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
