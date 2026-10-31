import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

final epoch = DateTime.utc(2026, 10, 31);
TranslationParagraph p(int index, {int? page, String? text}) => TranslationParagraph(
  documentId: 'doc',
  index: index,
  page: page ?? index + 1,
  fingerprint: 'fp$index',
  text: text ?? 'Source fragment $index',
  rects: [const PageRect(20, 400, 200, 380)],
);
TranslationJob job({int pages = 12, TranslationMode mode = TranslationMode.batch, int estimate = 10000}) =>
    TranslationJob(
      id: 'job',
      documentId: 'doc',
      targetLang: 'zh',
      range: TranslationRange(1, pages),
      mode: mode,
      batchSize: 5,
      model: 'fixture',
      state: TranslationJobState.running,
      batch: TranslationBatch(
        index: 1,
        range: TranslationRange(
          1,
          mode == TranslationMode.all
              ? pages
              : pages < 5
              ? pages
              : 5,
        ),
      ),
      estimateTokens: estimate,
      createdAt: epoch,
      updatedAt: epoch,
    );

class FakeTranslator implements ParagraphTranslator {
  final calls = <TranslationParagraph>[];
  final pending = <Completer<ParagraphTranslation>>[];
  bool closed = false;
  Future<ParagraphTranslation> Function(TranslationParagraph)? answer;
  @override
  Future<ParagraphTranslation> translate(
    TranslationParagraph p,
    String language,
    CancellationToken cancel,
    int maxTokens, {
    String? sourceLanguage,
  }) {
    calls.add(p);
    if (answer != null) return answer!(p);
    final c = Completer<ParagraphTranslation>();
    pending.add(c);
    return c.future;
  }

  void finish(int n, {int tokens = 2}) =>
      pending[n].complete(ParagraphTranslation('译文$n', tokens: tokens, inputTokens: 1));
  @override
  void close() {
    closed = true;
  }
}

class FakePack extends FakeTranslator implements PackedParagraphTranslator {
  final packs = <List<TranslationParagraph>>[];
  bool malformed = false;
  @override
  Future<PackedParagraphTranslation> translatePack(
    List<TranslationParagraph> ps,
    String language,
    CancellationToken cancel,
    int maxTokens, {
    String? sourceLanguage,
    String note = '',
  }) async {
    packs.add(ps);
    if (malformed && ps.length > 1) return const PackedParagraphTranslation(['bad'], inputTokens: 3, outputTokens: 2);
    return PackedParagraphTranslation([for (final p in ps) '译${p.index}'], inputTokens: 3, outputTokens: 2);
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
Future<TranslationScheduler> scheduler(
  List<TranslationParagraph> ps,
  ParagraphTranslator t, {
  TranslationStore? store,
  DateTime Function()? now,
  Future<void> Function(Duration)? sleep,
  bool online = true,
  Map<int, double> pageHeights = const {},
}) async {
  final s = TranslationScheduler(
    documentId: 'doc',
    language: 'zh',
    paragraphs: ps,
    translator: t,
    store: store ?? InMemoryTranslationStore(),
    model: 'fixture',
    now: now,
    sleep: sleep,
    random: () => .5,
    online: online,
    pageHeights: pageHeights,
  );
  await s.initialize();
  return s;
}

class LedgerStore extends InMemoryTranslationStore {
  final writes = <TranslationJob>[];
  bool failAppend = false;
  @override
  Future<void> saveJob(TranslationJob job) async {
    writes.add(job);
    await super.saveJob(job);
  }

  @override
  Future<void> append(String documentId, String targetLang, TranslationSegment segment) async {
    if (failAppend) throw StateError('disk unavailable');
    await super.append(documentId, targetLang, segment);
  }
}

class ManualTimer implements Timer {
  ManualTimer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() {
    isActive = false;
  }

  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}

void main() {
  test('every paragraph on a visible page precedes other pages in the batch', () async {
    final t = FakeTranslator();
    final s = await scheduler([p(0, page: 1), p(1, page: 2), p(2, page: 2), p(3, page: 1)], t);
    s.prioritize([1], focus: 0);
    final run = s.start(job(pages: 2));
    await tick();
    expect(t.calls.map((p) => p.index), [1, 2]);
    t.finish(0);
    t.finish(1);
    await tick();
    t.finish(2);
    t.finish(3);
    await run;
    await s.close();
  });
  test('closing preserves checkpoints, errors, budgets and the user pause reason', () async {
    for (final state in [
      TranslationJobState.review,
      TranslationJobState.error,
      TranslationJobState.budget,
      TranslationJobState.paused,
    ]) {
      final store = InMemoryTranslationStore(), t = FakeTranslator();
      await store.saveJob(
        job().copyWith(
          state: state,
          errorKind: state == TranslationJobState.error ? 'authentication' : null,
          pauseReason: state == TranslationJobState.paused ? TranslationPauseReason.user : null,
        ),
      );
      final s = await scheduler([p(0)], t, store: store);
      await s.close();
      final saved = (await store.loadJob('doc', 'zh'))!;
      expect(saved.state, state);
      expect(t.calls, isEmpty);
      if (state == TranslationJobState.paused) expect(saved.pauseReason, TranslationPauseReason.user);
      if (state == TranslationJobState.error) expect(saved.errorKind, 'authentication');
    }
  });
  test('invalid usage counters cannot discard a paid translation or bypass the ledger', () async {
    final t = FakeTranslator()..answer = ((_) async => const ParagraphTranslation('完整译文', tokens: -1, inputTokens: 0));
    final s = await scheduler([p(0)], t);
    await s.start(job(pages: 1));
    expect(s.values['fp0'], '完整译文');
    expect(t.calls, hasLength(1));
    expect(s.job!.usage.totalTokens, greaterThan(0));
    await s.close();
  });
  test('tiny reservations serialize workers; oversized input fails without sending', () async {
    for (final cap in [1, 10000]) {
      final t = FakeTranslator()..answer = ((_) async => const ParagraphTranslation('ok', tokens: 1));
      final s = TranslationScheduler(
        documentId: 'doc',
        language: 'zh',
        paragraphs: [p(0), p(1)],
        translator: t,
        store: InMemoryTranslationStore(),
        model: 'fixture',
        budget: ResearchBudget(outputTokens: cap, inputCharacters: cap == 1 ? 10000 : 1),
      );
      await s.initialize();
      await s.start(job(pages: 2));
      expect(t.calls.length, cap == 1 ? 2 : 0);
      expect(s.job!.failures.length, cap == 1 ? 0 : 2);
      await s.close();
    }
  });
  test('a degraded worker rejoins after ten minutes without waiting for the whole job', () async {
    var now = epoch, requests = 0;
    final gates = <Completer<ParagraphTranslation>>[];
    final t = FakeTranslator()
      ..answer = ((_) {
        if (requests++ < 2) return Future.error(const ResearchFailure(ResearchFailureKind.rateLimited));
        final c = Completer<ParagraphTranslation>();
        gates.add(c);
        return c.future;
      });
    final s = await scheduler([for (var i = 0; i < 5; i++) p(i)], t, now: () => now, sleep: (_) async {});
    final run = s.start(job(pages: 5, estimate: 100000));
    await tick();
    expect(s.concurrency, 1);
    expect(gates, hasLength(1));
    now = now.add(const Duration(minutes: 10));
    gates[0].complete(const ParagraphTranslation('ok'));
    await tick();
    expect(gates, hasLength(3));
    for (var round = 0; round < 5; round++) {
      for (final c in gates.toList()) {
        if (!c.isCompleted) c.complete(const ParagraphTranslation('ok'));
      }
      await tick();
    }
    await run;
    expect(s.job!.state, TranslationJobState.done);
    await s.close();
  });
  test('explicit calls have independent slots and share in-flight keys', () async {
    final t = FakeTranslator();
    final ps = [p(0), p(1), p(2), p(3)];
    final s = await scheduler(ps, t);
    final run = s.start(job(pages: 4));
    await tick();
    final explicit = s.retry(ps[3]);
    final duplicate = s.retranslate(ps[3]);
    await tick();
    expect(t.calls.map((p) => p.index), [0, 1, 3]);
    await s.pause();
    t.finish(2);
    await explicit;
    await duplicate;
    t.finish(0);
    t.finish(1);
    await run;
    expect(s.values, hasLength(3));
    expect(s.job!.state, TranslationJobState.paused);
    final resume = s.resume();
    await tick();
    t.finish(3);
    await resume;
    expect(t.calls.map((p) => p.index), [0, 1, 3, 2]);
    await s.close();
  });

  test('ledger has a trailing two-second flush and mandatory transition flushes', () async {
    var now = epoch;
    final t = FakeTranslator(), store = LedgerStore();
    ManualTimer? timer;
    final s = TranslationScheduler(
      documentId: 'doc',
      language: 'zh',
      paragraphs: [p(0), p(1), p(2)],
      translator: t,
      store: store,
      model: 'fixture',
      now: () => now,
      schedule: (delay, callback) {
        expect(delay, const Duration(seconds: 2));
        return timer = ManualTimer(callback);
      },
    );
    await s.initialize();
    final run = s.start(job(pages: 3));
    await tick();
    t.finish(0);
    await tick();
    expect(store.writes, hasLength(1));
    expect(timer!.isActive, true);
    now = now.add(const Duration(seconds: 2));
    timer!.fire();
    await tick();
    expect(store.writes.last.usage.outputTokens, 2);
    expect(store.writes.last.usage.requests, 3);
    await s.pause();
    t.finish(1);
    t.finish(2);
    await run;
    expect(store.writes.last.usage.totalTokens, 9);
    await s.close();
    expect(timer!.isActive, false);
  });

  test('exhaustion, network reset and timeout retry exactly three times', () async {
    for (final error in [
      TimeoutException('timeout'),
      const ResearchFailure(ResearchFailureKind.unavailable),
      const ResearchFailure(ResearchFailureKind.network),
    ]) {
      final t = FakeTranslator()..answer = ((_) async => throw error);
      final delays = <Duration>[];
      final s = await scheduler(
        [p(0)],
        t,
        sleep: (d) async {
          delays.add(d);
        },
      );
      await s.start(job(pages: 1));
      expect(t.calls, hasLength(4));
      expect(delays.map((d) => d.inSeconds), [2, 8, 30]);
      expect(s.job!.failures['fp0']!.attempts, 4);
      await s.close();
    }
  });

  test('pausing during backoff prevents another request', () async {
    final t = FakeTranslator()..answer = ((_) async => throw const ResearchFailure(ResearchFailureKind.unavailable));
    final wait = Completer<void>();
    final s = await scheduler([p(0)], t, sleep: (_) => wait.future);
    final run = s.start(job(pages: 1));
    await tick();
    await s.pause();
    wait.complete();
    await run;
    expect(t.calls, hasLength(1));
    expect(s.job!.failures, isEmpty);
    await s.close();
  });

  test('fatal errors after stop cannot revive a completed job', () async {
    final t = FakeTranslator();
    final s = await scheduler([p(0), p(1)], t);
    final run = s.start(job(pages: 2));
    await tick();
    await s.stop();
    t.pending[0].completeError(const ResearchFailure(ResearchFailureKind.authentication));
    t.finish(1);
    await run;
    expect(s.job!.state, TranslationJobState.stopped);
    expect(s.values, hasLength(1));
    await s.close();
  });

  test('repairing credentials creates a fresh connection after paid calls drain', () async {
    final first = FakeTranslator(), second = FakeTranslator();
    var calls = 0;
    final s = TranslationScheduler(
      documentId: 'doc',
      language: 'zh',
      paragraphs: [p(0), p(1), p(2)],
      createTranslator: () async => calls++ == 0 ? first : second,
      store: InMemoryTranslationStore(),
      model: 'fixture',
    );
    await s.initialize();
    final run = s.start(job(pages: 3));
    await tick();
    first.pending[0].completeError(const ResearchFailure(ResearchFailureKind.authentication));
    await tick();
    final resume = s.resume();
    await tick();
    expect(first.closed, false);
    first.finish(1);
    await run;
    await tick();
    expect(first.closed, true);
    expect(second.calls.map((p) => p.index), [0, 2]);
    second.finish(0);
    second.finish(1);
    await resume;
    expect(s.job!.state, TranslationJobState.done);
    await s.close();
  });

  test('storage failures stop dispatch instead of paying for automatic retries', () async {
    final store = LedgerStore()..failAppend = true;
    final t = FakeTranslator()..answer = ((_) async => const ParagraphTranslation('paid'));
    final s = await scheduler([p(0), p(1), p(2)], t, store: store);
    await expectLater(s.start(job(pages: 3)), throwsStateError);
    expect(t.calls.length, lessThanOrEqualTo(2));
    expect(s.job!.errorKind, 'storage');
    store.failAppend = false;
    await s.close();
  });

  test('HTTP quota and model errors are durable task causes; Retry-After accepts dates', () async {
    final options = RequestOptions(path: '/');
    for (final entry in [
      (429, 'insufficient_quota', 'quota'),
      (404, 'model_not_found', 'model'),
      (400, 'other', 'invalidRequest'),
    ]) {
      final t = FakeTranslator()
        ..answer = ((_) async => throw DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: entry.$1,
            data: {
              'error': {'code': entry.$2},
            },
          ),
        ));
      final s = await scheduler([p(0)], t);
      await s.start(job(pages: 1));
      expect(s.job!.errorKind, entry.$3);
      expect(s.job!.failures, isEmpty);
      await s.close();
    }
    for (final header in ['Sat, 31 Oct 2026 00:01:00 GMT', 'invalid', '-1']) {
      var requests = 0;
      final delays = <Duration>[];
      final t = FakeTranslator()
        ..answer = ((_) async {
          if (requests++ == 0) {
            throw DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 429,
                headers: Headers.fromMap({
                  'retry-after': [header],
                }),
              ),
            );
          }
          return const ParagraphTranslation('ok');
        });
      final s = await scheduler(
        [p(0)],
        t,
        now: () => epoch,
        sleep: (d) async {
          delays.add(d);
        },
      );
      await s.demand([1]);
      expect(delays.single.inSeconds, header.startsWith('Sat') ? 60 : 2);
      await s.close();
    }
  });

  test('two workers, visible priority inside batch, review gate, dedup and explicit bypass', () async {
    final t = FakeTranslator();
    final ps = [for (var i = 0; i < 7; i++) p(i), p(8, page: 5, text: 'Source fragment 0')];
    final s = await scheduler(ps, t);
    final events = <TranslationSchedulerState>[];
    final sub = s.states.listen(events.add);
    s.prioritize([4, 6]);
    final run = s.start(job(pages: 7));
    await tick();
    expect(t.calls.map((p) => p.index), [4, 0]);
    for (var n = 0; n < 5; n++) {
      t.finish(n);
      await tick();
    }
    await run;
    expect(s.job!.state, TranslationJobState.review);
    expect(t.calls, hasLength(5));
    expect(s.values['fp8'], s.values['fp0']);
    await s.demand([7]);
    expect(t.calls, hasLength(5));
    final explicit = s.retry(ps[6]);
    await tick();
    expect(t.calls.last.index, 6);
    t.finish(5);
    await explicit;
    expect(s.job!.state, TranslationJobState.review);
    final next = s.continueBatch(note: 'new requirements', all: true);
    await tick();
    expect(t.calls.last.index, 5);
    t.finish(6);
    await next;
    expect(s.job!.state, TranslationJobState.done);
    expect(events.last.values, hasLength(8));
    expect(
      (await s.store.load('doc', 'zh')).segments[textKey(ps[5].text, 'zh')]!.profile,
      translationProfile('new requirements', promptVersion: 1),
    );
    await s.retry();
    expect(t.calls, hasLength(7));
    await sub.cancel();
    await s.close();
    expect(t.closed, true);
  });

  test('pause and stop issue zero new requests but durably save paid in-flight results', () async {
    final t = FakeTranslator(), store = InMemoryTranslationStore();
    final s = await scheduler([for (var i = 0; i < 6; i++) p(i)], t, store: store);
    final run = s.start(job(pages: 6));
    await tick();
    await s.pause();
    t.finish(0);
    t.finish(1);
    await run;
    expect(t.calls, hasLength(2));
    expect((await store.load('doc', 'zh')).segments, hasLength(2));
    expect(s.job!.pauseReason, TranslationPauseReason.user);
    final resumed = s.resume();
    await tick();
    expect(t.calls, hasLength(4));
    await s.stop();
    t.finish(2);
    t.finish(3);
    await resumed;
    expect(s.job!.state, TranslationJobState.stopped);
    expect((await store.load('doc', 'zh')).segments, hasLength(4));
    await s.start(job(pages: 4));
    expect(t.calls, hasLength(4));
    expect(s.job!.state, TranslationJobState.done);
    await s.close();
  });

  test('cached-only batches advance automatically and edited values are never overwritten', () async {
    final store = InMemoryTranslationStore(), t = FakeTranslator();
    final ps = [p(0), p(1, page: 6)];
    await store.append(
      'doc',
      'zh',
      TranslationSegment(
        key: textKey(ps[0].text, 'zh'),
        fingerprint: 'old',
        page: 100,
        index: 0,
        text: '手工',
        model: 'old',
        profile: '',
        origin: TranslationOrigin.edited,
        at: epoch,
      ),
    );
    final s = await scheduler(ps, t, store: store);
    final run = s.start(job(pages: 6));
    await tick();
    expect(t.calls.single.index, 1);
    t.finish(0);
    await run;
    expect(s.job!.state, TranslationJobState.done);
    expect(s.values['fp0'], '手工');
    await s.retry(ps[0]);
    expect(t.calls, hasLength(1));
    final explicit = s.retranslate(ps[0]);
    await tick();
    t.finish(1);
    await explicit;
    expect(s.values['fp0'], '译文1');
    await s.close();
  });

  test('budget pauses once after saving both workers; continuation never asks again', () async {
    final t = FakeTranslator();
    final s = await scheduler([for (var i = 0; i < 5; i++) p(i)], t);
    final run = s.start(job(pages: 5, mode: TranslationMode.all, estimate: 2));
    await tick();
    t.finish(0, tokens: 10);
    t.finish(1, tokens: 10);
    await run;
    expect(s.job!.state, TranslationJobState.budget);
    expect(s.values, hasLength(2));
    final resume = s.resume();
    await tick();
    for (var n = 2; n < 5; n++) {
      t.finish(n, tokens: 10);
      await tick();
    }
    await resume;
    expect(s.job!.state, TranslationJobState.done);
    expect(s.job!.budgetAcknowledged, true);
    expect(s.job!.usage.requests, 5);
    expect(s.job!.usage.totalTokens, 55);
    await s.close();
  });

  test('offline auto resume, manual pause and process recovery never auto-spend', () async {
    final store = InMemoryTranslationStore(), t = FakeTranslator();
    var s = await scheduler([p(0), p(1), p(2)], t, store: store, online: false);
    await s.start(job(pages: 3));
    expect(s.job!.state, TranslationJobState.offline);
    expect(t.calls, isEmpty);
    final online = s.setOnline(true);
    await tick();
    await s.setOnline(false);
    t.pending[0].completeError(const ResearchFailure(ResearchFailureKind.network));
    t.finish(1);
    await online;
    expect(s.job!.failures, isEmpty);
    expect(s.job!.state, TranslationJobState.offline);
    await s.pause();
    await s.setOnline(true);
    expect(t.calls, hasLength(2));
    await s.close();
    final recoveredTranslator = FakeTranslator();
    s = await scheduler([p(0), p(1), p(2)], recoveredTranslator, store: store);
    expect(s.job!.state, TranslationJobState.paused);
    await s.setOnline(true);
    expect(s.values, hasLength(1));
    final resumed = s.resume();
    await tick();
    expect(recoveredTranslator.calls.map((p) => p.index), [0, 2]);
    final closing = s.close();
    await tick();
    recoveredTranslator.finish(0);
    recoveredTranslator.finish(1);
    await resumed;
    await closing;
    expect(recoveredTranslator.closed, true);
    expect((await store.load('doc', 'zh')).segments, hasLength(3));
  });

  test('transient delays, jitter midpoint, Retry-After, 429 degradation and recovery', () async {
    var now = epoch;
    final delays = <Duration>[];
    final t = FakeTranslator();
    var count = 0;
    t.answer = (_) async {
      count++;
      if (count <= 3) throw const ResearchFailure(ResearchFailureKind.rateLimited);
      return const ParagraphTranslation('ok', tokens: 1);
    };
    final s = await scheduler(
      [p(0)],
      t,
      now: () => now,
      sleep: (d) async {
        delays.add(d);
        now = now.add(d);
      },
    );
    await s.start(job(pages: 1));
    expect(delays.map((d) => d.inSeconds), [2, 8, 30]);
    expect(s.concurrency, 1);
    expect(s.job!.failures, isEmpty);
    expect(s.job!.usage.requests, 4);
    now = now.add(const Duration(minutes: 10));
    expect(s.concurrency, 2);
    await s.close();
    final options = RequestOptions(path: '/');
    t.answer = (_) async {
      if (count++ == 4) {
        throw DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 503,
            headers: Headers.fromMap({
              'retry-after': ['60'],
            }),
          ),
        );
      }
      return const ParagraphTranslation('ok');
    };
    final other = await scheduler(
      [p(0)],
      t,
      sleep: (d) async {
        delays.add(d);
      },
    );
    await other.demand([1]);
    expect(delays.last.inSeconds, 60);
    await other.close();
  });

  test('paragraph failures persist, retry recovers; task errors halt without failing paragraphs', () async {
    final t = FakeTranslator();
    t.answer = (_) async => throw const ResearchFailure(ResearchFailureKind.protocol);
    final s = await scheduler([p(0), p(1)], t);
    await s.start(job(pages: 2));
    expect(s.job!.failures, hasLength(2));
    t.answer = (_) async => const ParagraphTranslation('ok');
    await s.retry();
    expect(s.job!.failures, isEmpty);
    expect(s.values, hasLength(2));
    await s.close();
    for (final error in [
      const ResearchFailure(ResearchFailureKind.authentication),
      const ResearchFailure(ResearchFailureKind.invalidRequest, 'model'),
      const ResearchFailure(ResearchFailureKind.rateLimited, 'insufficient_quota'),
    ]) {
      final t = FakeTranslator();
      t.answer = (_) async => throw error;
      final s = await scheduler([for (var i = 0; i < 10; i++) p(i)], t);
      await s.start(job());
      expect(s.job!.state, TranslationJobState.error);
      expect(s.job!.errorKind, isNotNull);
      expect(s.job!.failures, isEmpty);
      expect(t.calls.length, lessThanOrEqualTo(2));
      await s.demand([10]);
      expect(t.calls.length, lessThanOrEqualTo(2));
      t.answer = (_) async => const ParagraphTranslation('ok');
      await s.resume();
      expect(s.job!.errorKind, isNull);
      await s.close();
    }
  });

  test('pack caps page, adjacency, source characters and count; malformed packs split', () async {
    final t = FakePack();
    final ps = [
      for (var i = 0; i < 14; i++) p(i, page: 1),
      p(14, page: 2),
      p(15, page: 2, text: 'x' * 2390),
      p(16, page: 2),
      p(17, page: 3, text: 'x' * 2500),
    ];
    final s = await scheduler(ps, t);
    await s.start(job(pages: 3, mode: TranslationMode.all));
    expect(t.packs.first, hasLength(12));
    expect(t.packs.every((ps) => ps.length <= 12 && ps.map((p) => p.page).toSet().length == 1), true);
    expect(
      t.packs.where((ps) => ps.length > 1).every((ps) => ps.fold<int>(0, (n, p) => n + p.text.length) <= 2400),
      true,
    );
    await s.close();
    final split = FakePack()..malformed = true;
    final other = await scheduler([p(0, page: 1), p(1, page: 1)], split);
    await other.start(job(pages: 1));
    expect(split.packs.map((ps) => ps.length), [2, 1, 1]);
    expect(other.values, hasLength(2));
    await other.close();
  });

  test('no-send rules, identical content fanout and immutable state', () async {
    final t = FakeTranslator()..answer = ((_) async => const ParagraphTranslation('translated'));
    final ps = [
      p(0, text: '123'),
      p(1, text: 'https://example.com'),
      p(2, text: '这是中文学习内容'),
      p(3, text: 'Header'),
      p(4, text: 'Header'),
      p(5),
      p(6, page: 6, text: 'Source fragment 5'),
    ];
    // Put repeated headers in the PDF margin.
    ps[3] = TranslationParagraph(
      documentId: 'doc',
      page: 4,
      index: 3,
      text: 'Header',
      fingerprint: 'fp3',
      rects: [const PageRect(20, 790, 200, 780)],
    );
    ps[4] = TranslationParagraph(
      documentId: 'doc',
      page: 5,
      index: 4,
      text: 'Header',
      fingerprint: 'fp4',
      rects: [const PageRect(20, 790, 200, 780)],
    );
    final s = await scheduler(ps, t, pageHeights: {for (var i = 1; i <= 6; i++) i: 800});
    await s.start(job(pages: 7, mode: TranslationMode.all));
    expect(t.calls, hasLength(1));
    expect(s.values, hasLength(7));
    expect(s.segmentState(ps.last), TranslationSegmentState.done);
    expect(() => s.state.values.clear(), throwsUnsupportedError);
    await s.close();
  });

  test('model numbered protocol validates count, order, empty text and unsafe source isolation', () async {
    final client = ScriptClient([
      answer('[[1]]\n甲\n[[2]]\n乙'),
      answer('[[2]]\n甲\n[[1]]\n乙'),
      answer('[[1]]\n甲'),
      answer('prefix\n[[1]]\n甲\n[[2]]\n乙'),
      answer('[[1]]\n\n[[2]]\n乙'),
    ]);
    final t = ModelParagraphTranslator(AssistantConnection(client, Dio()), 'fixture');
    final ps = [p(0), p(1)];
    expect((await t.translatePack(ps, 'zh', CancellationToken(), 100, note: 'term')).texts, ['甲', '乙']);
    expect(client.toolRequests.single, isEmpty);
    expect(client.modelConfigs.single.extra, {'store': false});
    expect(client.requests.single.first.toJson().toString(), contains('untrusted'));
    expect(client.requests.single.first.toJson().toString(), contains('term'));
    for (var i = 0; i < 4; i++) {
      await expectLater(t.translatePack(ps, 'zh', CancellationToken(), 100), throwsA(isA<ResearchFailure>()));
    }
    t.close();
  });
}
