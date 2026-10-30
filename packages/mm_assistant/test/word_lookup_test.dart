import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';

const model = AssistantModel(
  provider: AssistantProvider.compatible,
  model: 'fixture',
  endpoint: 'https://example.com/v1',
);
Map<String, dynamic> value() => {
  'lemma': 'plateau',
  'phonetics': {'uk': '/ˈplætəʊ/', 'us': ''},
  'senses': [
    {'pos': 'n.', 'meaning': '高原'},
  ],
  'contextMeaning': '停滞期',
  'sentenceTranslation': '进步进入了停滞期。',
  'gloss': '停滞期',
  'forms': ['plateau', 'plateaus'],
};
Matcher failure(ResearchFailureKind kind) => isA<ResearchFailure>().having((e) => e.kind, 'kind', kind);

Future<WordLookupResult> lookup(
  WordLookup service, {
  String term = 'plateaus',
  String sentence = 'Progress plateaus.',
  String? source = 'en',
  String target = 'zh',
  AssistantModel? selected = model,
  CancellationToken? cancel,
  bool online = true,
}) => service.lookup(
  term: term,
  sentence: sentence,
  sourceLanguage: source,
  targetLanguage: target,
  model: selected,
  cancel: cancel ?? CancellationToken(),
  online: online,
);

Future<WordContext> context(WordLookup service, {String sentence = 'Progress plateaus.'}) => service.lookupContext(
  lemma: 'plateau',
  sentence: sentence,
  sourceLanguage: 'en',
  targetLanguage: 'zh',
  model: model,
  cancel: CancellationToken(),
);

class PendingClient extends ScriptClient {
  PendingClient() : super([]);
  final pending = Completer<ModelMessage>();
  CancelToken? token;
  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) {
    token = cancelToken;
    return pending.future;
  }
}

class TrackingDio extends DioForNative {
  bool closed = false;
  @override
  void close({bool force = false}) {
    closed = true;
    super.close(force: force);
  }
}

void main() {
  test('typed parsing, empty phonetics, Unicode gloss and immutable lists', () {
    final j = value()..['gloss'] = '😀😀😀😀😀😀😀😀';
    final result = WordLookupResult.parse(jsonEncode(j));
    expect(result.lemma, 'plateau');
    expect(result.ukPhonetic, '/ˈplætəʊ/');
    expect(result.usPhonetic, '');
    expect(result.senses.single.pos, 'n.');
    expect(result.senses.single.meaning, '高原');
    expect(result.context.contextMeaning, '停滞期');
    expect(result.context.sentenceTranslation, '进步进入了停滞期。');
    expect(result.gloss.runes, hasLength(8));
    expect(() => result.forms.add('other'), throwsUnsupportedError);
    expect(() => result.senses.clear(), throwsUnsupportedError);
  });
  test('rejects missing, wrong-type, blank, malformed and oversized fields', () {
    final invalid = <String>['not json', '```json\n{}\n```', '[]', 'null', '"text"', 'x' * 65537];
    for (final key in ['lemma', 'senses', 'contextMeaning', 'sentenceTranslation']) {
      invalid.add(jsonEncode(value()..remove(key)));
      invalid.add(jsonEncode(value()..[key] = null));
      invalid.add(jsonEncode(value()..[key] = 123));
    }
    for (final (key, bad) in <(String, Object)>[
      ('lemma', ''),
      ('lemma', 'a' * 65),
      ('senses', []),
      ('senses', [null]),
      (
        'senses',
        [
          {'pos': 'n'},
        ],
      ),
      (
        'senses',
        [
          {'pos': 'a' * 33, 'meaning': 'x'},
        ],
      ),
      (
        'senses',
        [
          {'pos': 'n', 'meaning': 'a' * 2001},
        ],
      ),
      ('sentenceTranslation', 'a' * 24001),
      ('contextMeaning', ' '),
    ]) {
      invalid.add(jsonEncode(value()..[key] = bad));
    }
    for (final text in invalid) {
      expect(
        () => WordLookupResult.parse(text),
        throwsA(failure(ResearchFailureKind.protocol)),
        reason: text.substring(0, text.length.clamp(0, 80)),
      );
    }
    expect(() => WordContext.parse('{}'), throwsA(failure(ResearchFailureKind.protocol)));
  });
  test('extracts first JSON object from fences and prose, respecting quoted braces and escapes', () {
    final j = value()..['contextMeaning'] = 'a {brace} and "quote" and \\ slash';
    final json = jsonEncode(j);
    for (final text in [
      json,
      '```json\n$json\n```',
      '```\n$json\n```',
      'Here is the result:\n$json\nHope this helps.',
      'Ignore {not JSON}. $json',
      '$json ${jsonEncode(value()..["lemma"] = "second")}',
    ]) {
      expect(WordLookupResult.parse(text).context.contextMeaning, j['contextMeaning']);
      expect(WordLookupResult.parse(text).lemma, 'plateau');
    }
    final context = WordContext.parse('Translation: ${jsonEncode(value())} done.');
    expect(context.contextMeaning, '停滞期');
    for (final text in ['{', '{"x": "unterminated', '{"x": {}} trailing {', 'prefix {} ${jsonEncode(value())}']) {
      expect(() => WordLookupResult.parse(text), throwsA(failure(ResearchFailureKind.protocol)));
    }
    expect(() => WordLookupResult.parse('x' * 65536 + json), throwsA(failure(ResearchFailureKind.protocol)));
  });
  test('gloss truncates by rune and tolerates empty or unavailable values', () {
    for (final gloss in ['一二三四五六七八九', '😀😀😀😀😀😀😀😀😀']) {
      final result = WordLookupResult.parse(jsonEncode(value()..['gloss'] = gloss));
      expect(result.gloss, String.fromCharCodes(gloss.runes.take(8)));
    }
    for (final gloss in ['', '  ', null, 42]) {
      expect(WordLookupResult.parse(jsonEncode(value()..['gloss'] = gloss)).gloss, '');
    }
    expect(WordLookupResult.parse(jsonEncode(value()..remove('gloss'))).gloss, '');
  });
  test('takes first six senses and discards malformed entries without losing valid ones', () {
    final result = WordLookupResult.parse(
      jsonEncode(
        value()
          ..['senses'] = [
            null,
            {'pos': 'n'},
            {'pos': '', 'meaning': 'blank'},
            {'pos': 'n', 'meaning': 'valid'},
            {'pos': 'x' * 33, 'meaning': 'long'},
            {'pos': 'v', 'meaning': 'valid too'},
            {'pos': 'n', 'meaning': 'seventh'},
          ],
      ),
    );
    expect(result.senses.map((s) => s.meaning), ['valid', 'valid too']);
    expect(
      WordLookupResult.parse(jsonEncode(value()..['senses'] = List.filled(9, {'pos': 'n', 'meaning': 'valid'}))).senses,
      hasLength(6),
    );
    expect(
      () => WordLookupResult.parse(
        jsonEncode(
          value()
            ..['senses'] = [
              ...List.filled(6, null),
              {'pos': 'n', 'meaning': 'seventh'},
            ],
        ),
      ),
      throwsA(failure(ResearchFailureKind.protocol)),
    );
  });
  test('normalizes first sixteen forms, filters invalid ones and always includes lemma within cap', () {
    final result = WordLookupResult.parse(
      jsonEncode(
        value()
          ..['lemma'] = 'Plateau'
          ..['forms'] = [' PLATEAUS ', 'plateaus', null, 12, '', '  ', 'x' * 65, 'PLATEAU'],
      ),
    );
    expect(result.forms, ['plateau', 'plateaus']);
    final capped = WordLookupResult.parse(jsonEncode(value()..['forms'] = List.generate(20, (i) => 'form$i')));
    expect(capped.forms, hasLength(16));
    expect(capped.forms.first, 'plateau');
    expect(capped.forms, isNot(contains('form16')));
    expect(WordLookupResult.parse(jsonEncode(value()..['forms'] = [...List.filled(16, null), 'seventeenth'])).forms, [
      'plateau',
    ]);
    for (final forms in [null, 42, <String>[]]) {
      expect(WordLookupResult.parse(jsonEncode(value()..['forms'] = forms)).forms, ['plateau']);
    }
    expect(WordLookupResult.parse(jsonEncode(value()..remove('forms'))).forms, ['plateau']);
  });
  test('phrases and malformed optional phonetics do not invalidate dictionary data', () {
    for (final phonetics in [
      null,
      'none',
      [],
      42,
      {},
      {'uk': null, 'us': 42},
    ]) {
      final result = WordLookupResult.parse(jsonEncode(value()..['phonetics'] = phonetics));
      expect(result.ukPhonetic, '');
      expect(result.usPhonetic, '');
    }
    final missing = WordLookupResult.parse(jsonEncode(value()..remove('phonetics')));
    expect(missing.ukPhonetic, '');
    expect(missing.usPhonetic, '');
    final partial = WordLookupResult.parse(jsonEncode(value()..['phonetics'] = {'uk': '/word/'}));
    expect(partial.ukPhonetic, '/word/');
    expect(partial.usPhonetic, '');
    final long = WordLookupResult.parse(jsonEncode(value()..['phonetics'] = {'us': 'a' * 129}));
    expect(long.usPhonetic, 'a' * 128);
  });
  test(
    'canonical lemma cache, inflected aliases, target/sentence isolation, lightweight requests and clearing',
    () async {
      final client = ScriptClient(List.generate(8, (_) => answer(jsonEncode(value()))));
      final service = WordLookup(connect: (_) async => AssistantConnection(client, Dio()));
      final first = await lookup(service);
      expect(await lookup(service, term: ' PLATEAUS '), same(first));
      expect(await lookup(service, term: 'plateau'), same(first));
      expect((await context(service)).contextMeaning, '停滞期');
      expect(client.calls, 1);
      await lookup(service, target: 'ja');
      await lookup(service, sentence: 'A different sentence.');
      await context(service, sentence: 'A new sentence.');
      expect(client.calls, 4);
      final prompt = client.requests.last.first.toJson().toString();
      expect(prompt, contains('contextMeaning, sentenceTranslation'));
      expect(prompt, isNot(contains('phonetics')));
      await context(service, sentence: 'A new sentence.');
      expect(client.calls, 4);
      await lookup(service, term: 'plateau', sentence: 'A new sentence.');
      expect(client.calls, 5, reason: 'context-only result cannot masquerade as dictionary data');
      service.clearCache();
      await lookup(service);
      expect(client.calls, 6);
      expect(client.toolRequests.every((tools) => tools.isEmpty), isTrue);
      expect(client.requests.first.first.toJson().toString(), contains('untrusted'));
      expect(client.requests.first.last.toJson().toString(), contains('Progress plateaus.'));
    },
  );
  test('tolerant model response is returned and cached through the lookup service', () async {
    final j = value()
      ..remove('phonetics')
      ..['gloss'] = '一二三四五六七八九'
      ..['senses'] = [
        null,
        {'pos': 'n.', 'meaning': '高原'},
      ]
      ..['forms'] = List.generate(20, (i) => 'FORM$i');
    final client = ScriptClient([answer('Result:\n```json\n${jsonEncode(j)}\n```')]);
    final service = WordLookup(connect: (_) async => AssistantConnection(client, Dio()));
    final result = await lookup(service);
    expect(result.gloss, '一二三四五六七八');
    expect(result.ukPhonetic, '');
    expect(result.senses.single.meaning, '高原');
    expect(result.forms, hasLength(16));
    expect(result.forms, contains('plateau'));
    expect(await lookup(service), same(result));
    expect(client.calls, 1);
  });
  test('automatic source detection matches selection translation defaults', () async {
    final client = ScriptClient([answer(jsonEncode(value()))]);
    final service = WordLookup(connect: (_) async => AssistantConnection(client, Dio()));
    expect(service.timeout, const Duration(seconds: 90));
    await lookup(service, source: null);
    expect(client.requests.single.first.toJson().toString(), contains('detect source language automatically'));
  });
  test('cache is bounded and evicts oldest values', () async {
    final client = ScriptClient(List.generate(130, (_) => answer(jsonEncode(value()))));
    final service = WordLookup(connect: (_) async => AssistantConnection(client, Dio()));
    for (var i = 0; i < 129; i++) {
      await lookup(service, sentence: '$i');
    }
    await lookup(service, sentence: '0');
    expect(client.calls, 130);
  });
  test('invalid and incomplete responses are not cached; failed calls can retry', () async {
    final client = ScriptClient([
      answer('{}'),
      answer('partial', stop: 'length'),
      call('execute', '{}'),
      answer(jsonEncode(value())),
    ]);
    final service = WordLookup(connect: (_) async => AssistantConnection(client, Dio()));
    for (var i = 0; i < 3; i++) {
      await expectLater(lookup(service), throwsA(failure(ResearchFailureKind.protocol)));
    }
    await lookup(service);
    expect(client.calls, 4);
  });
  test('validates input, configuration and online policy before making a connection', () async {
    var connections = 0;
    final service = WordLookup(
      connect: (_) async {
        connections++;
        return AssistantConnection(ScriptClient([answer(jsonEncode(value()))]), Dio());
      },
    );
    for (final request in [
      () => lookup(service, term: ''),
      () => lookup(service, term: 'x' * 65),
      () => lookup(service, term: List.filled(9, 'x').join(' ')),
      () => lookup(service, sentence: ''),
      () => lookup(service, sentence: 'x' * 24001),
      () => lookup(service, source: 'bad'),
      () => lookup(service, target: 'bad'),
    ]) {
      await expectLater(request(), throwsA(failure(ResearchFailureKind.invalidRequest)));
    }
    await expectLater(lookup(service, selected: null), throwsA(failure(ResearchFailureKind.authentication)));
    await expectLater(lookup(service, online: false), throwsA(failure(ResearchFailureKind.network)));
    final cancel = CancellationToken()..cancel();
    await expectLater(lookup(service, cancel: cancel), throwsA(failure(ResearchFailureKind.cancelled)));
    expect(connections, 0);
    const local = AssistantModel(
      provider: AssistantProvider.ollama,
      model: 'local',
      endpoint: 'http://localhost:11434',
      localEnabled: true,
    );
    await lookup(service, selected: local, online: false);
    expect(connections, 1);
    final invalidTimeout = WordLookup(connect: service.connect, timeout: Duration.zero);
    await expectLater(lookup(invalidTimeout), throwsA(failure(ResearchFailureKind.invalidRequest)));
  });
  test('maps auth/network failures without exposing raw error details, including key resolution', () async {
    for (final status in [401, 403, 429]) {
      final service = WordLookup(
        connect: (_) async => throw DioException(
          requestOptions: RequestOptions(),
          response: Response(requestOptions: RequestOptions(), statusCode: status),
          message: 'secret',
        ),
      );
      await expectLater(
        lookup(service),
        throwsA(failure(status == 429 ? ResearchFailureKind.rateLimited : ResearchFailureKind.authentication)),
      );
    }
    final service = WordLookup(connect: (_) async => throw StateError('secret'));
    await expectLater(lookup(service), throwsA(failure(ResearchFailureKind.unavailable)));
  });
  for (final cancelRequest in [true, false]) {
    test(
      '${cancelRequest ? 'cancellation' : 'timeout'} aborts transport, closes connection and drops late result',
      () async {
        final client = PendingClient(), dio = TrackingDio();
        final service = WordLookup(
          connect: (_) async => AssistantConnection(client, dio),
          timeout: const Duration(milliseconds: 20),
        );
        final cancel = CancellationToken();
        final future = lookup(service, cancel: cancel);
        final expectation = expectLater(
          future,
          throwsA(failure(cancelRequest ? ResearchFailureKind.cancelled : ResearchFailureKind.timeout)),
        );
        await Future<void>.delayed(Duration.zero);
        if (cancelRequest) cancel.cancel();
        await expectation;
        expect(client.token!.isCancelled, isTrue);
        expect(dio.closed, isTrue);
        client.pending.complete(answer(jsonEncode(value())));
        await Future<void>.delayed(Duration.zero);
      },
    );
  }
  test('cancels during credential loading and closes a connection that arrives after timeout', () async {
    for (final cancelRequest in [true, false]) {
      final gate = Completer<AssistantConnection>(), dio = TrackingDio();
      final service = WordLookup(connect: (_) => gate.future, timeout: const Duration(milliseconds: 20));
      final cancel = CancellationToken();
      final future = lookup(service, cancel: cancel);
      final expectation = expectLater(
        future,
        throwsA(failure(cancelRequest ? ResearchFailureKind.cancelled : ResearchFailureKind.timeout)),
      );
      if (cancelRequest) cancel.cancel();
      await expectation;
      final client = ScriptClient([]);
      gate.complete(AssistantConnection(client, dio));
      await Future<void>.delayed(Duration.zero);
      expect(dio.closed, isTrue);
      expect(client.calls, 0);
    }
  });
}
