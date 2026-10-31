import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

import 'translation_scheduler_test.dart' show p, job, scheduler, FakeTranslator, tick;

class Journal extends InMemoryTranslationStore {
  final entries = <TranslationSegment>[];
  bool fail = false;
  @override
  Future<void> append(String id, String language, TranslationSegment segment) async {
    if (fail) throw StateError('disk');
    entries.add(segment);
    await super.append(id, language, segment);
  }
}

void main() {
  test('edit is durable, reused by demand, continue and retry; only explicit retranslation replaces it', () async {
    final store = Journal(), t = FakeTranslator();
    t.answer = (p) async => ParagraphTranslation('AI ${p.index}');
    final first = p(0), later = p(1, page: 6);
    final s = await scheduler([first, later], t, store: store);
    await s.start(job(pages: 6));
    await s.edit(p(0), '  My revision\nsecond line  ');
    final old = s.segments[s.keyOf(first)]!;
    expect(old.origin, TranslationOrigin.edited);
    expect(old.text, 'My revision\nsecond line');
    await s.continueBatch();
    await s.retry();
    await s.retry(first);
    await s.demand([1]);
    expect(t.calls.map((p) => p.index), [0, 1]);
    expect((await store.load('doc', 'zh')).segments[old.key]!.text, old.text);
    await s.retranslate(first);
    final replacement = s.segments[old.key]!;
    expect(replacement.origin, TranslationOrigin.ai);
    await s.restore(old, replacing: replacement);
    expect(s.segments[old.key], same(old));
    expect(store.entries.last, same(old));
    expect(store.entries.length, 5);
    await s.close();
  });

  test('an edit made while explicit request is in flight wins and stale undo is ignored', () async {
    final first = p(0), store = Journal(), t = FakeTranslator();
    final s = await scheduler([first], t, store: store);
    final initial = s.retry(first);
    await tick();
    t.finish(0);
    await initial;
    final old = s.segments[s.keyOf(first)]!;
    final pending = s.retranslate(first);
    await tick();
    await s.edit(first, 'newer edit');
    t.finish(1);
    await pending;
    expect(s.values[first.fingerprint], 'newer edit');
    final next = s.retranslate(first);
    await tick();
    t.finish(2);
    await next;
    final replacement = s.segments[old.key]!;
    await s.edit(first, 'latest');
    await s.restore(old, replacing: replacement);
    expect(s.values[first.fingerprint], 'latest');
    await s.close();
  });

  test('storage failure keeps the displayed value and later edits can recover', () async {
    final first = p(0), store = Journal(), t = FakeTranslator();
    t.answer = (_) async => const ParagraphTranslation('AI');
    final s = await scheduler([first], t, store: store);
    await s.retry(first);
    store.fail = true;
    await expectLater(s.edit(first, 'lost'), throwsStateError);
    expect(s.values[first.fingerprint], 'AI');
    store.fail = false;
    await s.edit(first, 'saved');
    expect(s.values[first.fingerprint], 'saved');
    await expectLater(s.edit(first, ' '), throwsArgumentError);
    await expectLater(s.edit(p(4), 'other'), throwsArgumentError);
    await s.close();
    await expectLater(s.edit(first, 'closed'), throwsStateError);
  });

  test('a failed edit does not discard a paid response that finishes after storage recovers', () async {
    final first = p(0), store = Journal(), t = FakeTranslator();
    final s = await scheduler([first], t, store: store);
    final initial = s.retry(first);
    await tick();
    t.finish(0);
    await initial;
    final pending = s.retranslate(first);
    await tick();
    store.fail = true;
    await expectLater(s.edit(first, 'unsaved'), throwsStateError);
    store.fail = false;
    t.finish(1);
    await pending;
    expect(s.values[first.fingerprint], '译文1');
    await s.close();
  });

  test('retranslation failure retains a manual edit and retry-all never buys it again', () async {
    final first = p(0), store = Journal(), t = FakeTranslator();
    t.answer = (_) async => const ParagraphTranslation('AI');
    final s = await scheduler([first], t, store: store);
    await s.start(job(pages: 1));
    await s.edit(first, 'manual');
    t.answer = (_) async => throw const ResearchFailure(ResearchFailureKind.protocol);
    await s.retranslate(first);
    expect(s.values[first.fingerprint], 'manual');
    await s.retry();
    expect(t.calls, hasLength(2));
    expect(store.entries.last.origin, TranslationOrigin.edited);
    await s.close();
  });
}
