import 'dart:async';

import 'package:dio/dio.dart';

import 'support.dart';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

TranslationParagraph paragraph(int i, {String? key}) => TranslationParagraph(
  documentId: 'doc',
  page: 1,
  index: i,
  text: 'source $i',
  fingerprint: key ?? '$i',
  rects: [const PageRect(40, 700, 300, 680)],
);

class Translator implements ParagraphTranslator {
  final calls = <int>[];
  final gates = <int, Completer<ParagraphTranslation>>{};
  final allowances = <int>[];
  bool closed = false;
  @override
  Future<ParagraphTranslation> translate(TranslationParagraph p, String lang, CancellationToken cancel, int maxTokens) {
    calls.add(p.index);
    allowances.add(maxTokens);
    return (gates[p.index] = Completer<ParagraphTranslation>()).future;
  }

  void finish(int i, {String? text, int tokens = 3}) =>
      gates[i]!.complete(ParagraphTranslation(text ?? '译文 $i', tokens: tokens));
  @override
  void close() => closed = true;
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  test('direct translator exposes no tools, requires complete output and propagates cancellation', () async {
    final client = ScriptClient([
      answer('完整译文'),
      answer('truncated', stop: 'length'),
      call('execute', '{}'),
      answer('late'),
    ]);
    final translator = ModelParagraphTranslator(AssistantConnection(client, Dio()), 'fixture');
    final cancel = CancellationToken();
    expect((await translator.translate(paragraph(0), 'zh', cancel, 200)).text, '完整译文');
    expect(client.toolRequests.single, isEmpty);
    expect(client.requests.single.first.toJson().toString(), contains('untrusted'));
    await expectLater(translator.translate(paragraph(0), 'en', cancel, 200), throwsA(isA<ResearchFailure>()));
    await expectLater(translator.translate(paragraph(0), 'zh', cancel, 200), throwsA(isA<ResearchFailure>()));
    cancel.cancel();
    await expectLater(translator.translate(paragraph(0), 'en', cancel, 200), throwsA(isA<ResearchFailure>()));
    translator.close();
  });
  test('visible first, concurrency two, pending reprioritized, one request per key; caches complete values', () async {
    final t = Translator(), saved = <String, String>{};
    var changes = 0;
    final s = TranslationSession(
      paragraphs: [
        for (var i = 0; i < 5; i++) paragraph(i),
        paragraph(9, key: '3'),
      ],
      language: 'zh',
      translator: t,
      save: (p, text) async {
        saved[p.fingerprint] = text;
      },
      changed: () => changes++,
      cached: {'0': 'cached'},
    );
    s.prioritize([2, 3], focus: 3);
    final run = s.start();
    await tick();
    expect(t.calls, [3, 2]);
    s.prioritize([1], focus: 1);
    t.finish(3);
    await tick();
    expect(t.calls, [3, 2, 1]);
    t.finish(2);
    await tick();
    expect(t.calls, [3, 2, 1, 4]);
    t.finish(1);
    t.finish(4);
    await run;
    expect(s.done, 6);
    expect(s.complete, true);
    expect(saved.length, 4);
    expect(changes, greaterThan(3));
    expect(s.values['0'], 'cached');
    s.cancel();
    expect(t.closed, true);
  });
  test('cancel drops late results, cancels queued work and preserves earlier cache', () async {
    final t = Translator(), saved = <String>[];
    final s = TranslationSession(
      paragraphs: [for (var i = 0; i < 5; i++) paragraph(i)],
      language: 'en',
      translator: t,
      save: (p, text) async {
        saved.add(text);
      },
      changed: () {},
    );
    final run = s.start();
    t.finish(0);
    await tick();
    expect(t.calls.length, 3);
    s.cancel();
    await run;
    t.finish(1);
    t.finish(2);
    await tick();
    expect(saved, ['译文 0']);
    expect(s.done, 1);
    expect(s.cancelled, true);
    expect(t.closed, true);
  });
  test('fully cached session makes no model calls, failures retry only missing paragraphs', () async {
    final t = Translator();
    final cached = TranslationSession(
      paragraphs: [paragraph(0)],
      language: 'zh',
      translator: t,
      save: (p, text) async {},
      changed: () {},
      cached: {'0': 'offline'},
    );
    await cached.start();
    expect(cached.complete, true);
    expect(t.calls, isEmpty);
    cached.cancel();
    final model = Translator();
    final s = TranslationSession(
      paragraphs: [paragraph(0), paragraph(1)],
      language: 'zh',
      translator: model,
      save: (p, text) async {},
      changed: () {},
    );
    final run = s.start();
    model.gates[0]!.completeError(StateError('failed'));
    model.finish(1);
    await run;
    expect(s.failure, isNotNull);
    expect(s.done, 1);
    final retry = s.retry();
    await tick();
    model.finish(0);
    await retry;
    expect(s.complete, true);
    expect(model.calls, [0, 1, 0]);
    s.cancel();
  });
  test('budget is shared across workers and retry; invalid/empty outputs never saved', () async {
    final t = Translator();
    var saved = 0;
    final s = TranslationSession(
      paragraphs: [paragraph(0), paragraph(1), paragraph(2)],
      language: 'zh',
      translator: t,
      save: (p, text) async {
        saved++;
      },
      changed: () {},
      budget: const ResearchBudget(outputTokens: 8),
    );
    final run = s.start();
    expect(t.allowances.reduce((a, b) => a + b), lessThanOrEqualTo(8));
    t.finish(0, tokens: 8);
    t.finish(1, text: '', tokens: 1);
    await run;
    expect(saved, 0);
    expect(s.failure, isNotNull);
    final retry = s.retry();
    await retry;
    expect(t.calls.length, 2);
    s.cancel();
  });
  test('empty output is a retryable protocol failure while remaining budget is preserved', () async {
    final model = Translator();
    final s = TranslationSession(
      paragraphs: [paragraph(0)],
      language: 'zh',
      translator: model,
      save: (p, text) async {},
      changed: () {},
      budget: const ResearchBudget(outputTokens: 32),
    );
    final run = s.start();
    model.finish(0, text: '', tokens: 0);
    await run;
    expect((s.failure as ResearchFailure).kind, ResearchFailureKind.protocol);
    expect(s.done, 0);
    final retry = s.retry();
    await tick();
    model.finish(0);
    await retry;
    expect(s.complete, true);
    expect(model.calls, [0, 0]);
    s.cancel();
  });
  test('a global byte limit stops queued requests and retry cannot replenish it', () async {
    final model = Translator();
    var saved = 0;
    final s = TranslationSession(
      paragraphs: [for (var i = 0; i < 5; i++) paragraph(i)],
      language: 'zh',
      translator: model,
      save: (p, text) async {
        saved++;
      },
      changed: () {},
      budget: const ResearchBudget(responseBytes: 1),
    );
    final run = s.start();
    expect(model.calls, [0, 1]);
    model.finish(0);
    await tick();
    expect(model.calls, [0, 1]);
    model.finish(1);
    await run;
    await s.retry();
    expect(model.calls, [0, 1]);
    expect(saved, 0);
    expect(s.failure, isNotNull);
    s.cancel();
  });
  test('missing or zero usage is conservatively charged and cannot bypass output limit', () async {
    final model = Translator();
    final s = TranslationSession(
      paragraphs: [paragraph(0)],
      language: 'zh',
      translator: model,
      save: (p, text) async {
        fail('must not cache oversized output');
      },
      changed: () {},
      budget: const ResearchBudget(outputTokens: 8),
    );
    final run = s.start();
    model.finish(0, text: 'much longer output', tokens: 0);
    await run;
    expect(s.done, 0);
    expect(s.failure, isNotNull);
    s.cancel();
  });
  test('deadline, input and response byte limits, save failure all surface without caching', () async {
    for (final budget in [const ResearchBudget(inputCharacters: 1), const ResearchBudget(responseBytes: 1)]) {
      final t = Translator();
      var saved = 0;
      final s = TranslationSession(
        paragraphs: [paragraph(0)],
        language: 'zh',
        translator: t,
        save: (p, text) async {
          saved++;
        },
        changed: () {},
        budget: budget,
      );
      final run = s.start();
      if (t.calls.isNotEmpty) t.finish(0);
      await run;
      expect(s.failure, isNotNull);
      expect(saved, 0);
      s.cancel();
    }
    var now = DateTime(2026);
    final t = Translator();
    final s = TranslationSession(
      paragraphs: [paragraph(0)],
      language: 'zh',
      translator: t,
      save: (p, text) async {},
      changed: () {},
      now: () => now,
    );
    now = now.add(const Duration(minutes: 2));
    await s.start();
    expect(t.calls, isEmpty);
    expect(s.failure, isNotNull);
    s.cancel();
    final model = Translator();
    final fail = TranslationSession(
      paragraphs: [paragraph(0)],
      language: 'zh',
      translator: model,
      save: (p, text) async {
        throw StateError('disk');
      },
      changed: () {},
    );
    final run = fail.start();
    model.finish(0);
    await run;
    expect(fail.done, 0);
    expect(fail.failure, isNotNull);
    fail.cancel();
  });
}
