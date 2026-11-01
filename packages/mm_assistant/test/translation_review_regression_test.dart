import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

import 'document_translation_test.dart' as runtime;
import 'translation_scheduler_test.dart' as fixtures;

void main() {
  test('a second journal failure stays retryable and never strands the UI in running', () async {
    final h = runtime.Harness();
    final store = runtime.FailingJournal();
    final scheduler = await fixtures.scheduler([fixtures.p(0)], h.translator(), store: store);
    try {
      await expectLater(scheduler.start(fixtures.job(pages: 1)), throwsStateError);
      expect(scheduler.job!.state, TranslationJobState.error);
      await expectLater(scheduler.resume(), throwsStateError);
      expect(h.client.calls, 1);
      expect(
        scheduler.job!.state,
        TranslationJobState.error,
        reason: 'Retry must remain reachable after a second disk failure; no task is running.',
      );
      expect(scheduler.job!.errorKind, 'storage');
      final usage = scheduler.job!.usage;
      await expectLater(scheduler.resume(), throwsStateError);
      expect(scheduler.job!.state, TranslationJobState.error);
      expect(scheduler.job!.errorKind, 'storage');
      expect(scheduler.values, isEmpty);
      store.fail = false;
      await scheduler.resume();
      expect(h.client.calls, 1);
      expect(scheduler.values, hasLength(1));
      expect(scheduler.job!.state, TranslationJobState.done);
      expect(scheduler.job!.usage.requests, usage.requests);
      expect(scheduler.job!.usage.totalTokens, usage.totalTokens);
    } finally {
      store.fail = false;
      await scheduler.close();
    }
  });
  for (final command in ['start', 'resume', 'continueBatch']) {
    test('$command ledger failures publish storage error before any dispatch', () async {
      final h = runtime.Harness();
      final store = FailingLedger();
      final scheduler = await fixtures.scheduler([fixtures.p(0), fixtures.p(1, page: 6)], h.translator(), store: store);
      try {
        if (command != 'start') {
          await scheduler.start(fixtures.job(pages: 6));
          expect(scheduler.job!.state, TranslationJobState.review);
          if (command == 'resume') await scheduler.pause();
        }
        final calls = h.client.calls;
        final usage = scheduler.job?.usage;
        store.fail = true;
        final work = switch (command) {
          'start' => scheduler.start(fixtures.job(pages: 6)),
          'resume' => scheduler.resume(),
          _ => scheduler.continueBatch(),
        };
        await expectLater(work, throwsStateError);
        expect(scheduler.job!.state, TranslationJobState.error);
        expect(scheduler.job!.errorKind, 'storage');
        expect(h.client.calls, calls);
        await expectLater(scheduler.resume(), throwsStateError);
        expect(scheduler.job!.state, TranslationJobState.error);
        expect(h.client.calls, calls);
        if (usage != null) expect(scheduler.job!.usage.requests, usage.requests);
        store.fail = false;
        await scheduler.resume();
        expect(
          scheduler.job!.state,
          command == 'continueBatch' ? TranslationJobState.done : TranslationJobState.review,
        );
        expect(
          h.client.calls,
          calls +
              (command == 'start'
                  ? 1
                  : command == 'continueBatch'
                  ? 1
                  : 0),
        );
      } finally {
        store.fail = false;
        await scheduler.close();
      }
    });
  }
}

class FailingLedger extends InMemoryTranslationStore {
  bool fail = false;
  @override
  Future<void> saveJob(TranslationJob job) async {
    if (fail) throw StateError('disk');
    await super.saveJob(job);
  }
}
