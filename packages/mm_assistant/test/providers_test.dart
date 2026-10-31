import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' hide MessageRole;
import 'package:dart_agent_core/eval.dart';

import 'support.dart' show Reader;

import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.reply);
  final FutureOr<ResponseBody> Function(RequestOptions, int) reply;
  int calls = 0;
  bool closed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => reply(options, ++calls);
  @override
  void close({bool force = false}) {
    closed = true;
  }
}

AssistantModel config(AssistantProvider provider) => AssistantModel(
  provider: provider,
  model: 'model',
  endpoint: switch (provider) {
    AssistantProvider.claude => 'https://api.anthropic.com/v1/messages',
    AssistantProvider.responses => 'https://api.openai.com/v1/responses',
    AssistantProvider.compatible => 'https://example.com/v1/chat/completions',
    AssistantProvider.ollama => 'http://localhost:11434/v1/chat/completions',
    AssistantProvider.gemini => 'https://generativelanguage.googleapis.com/v1beta',
  },
  localEnabled: provider == AssistantProvider.ollama,
);
void main() {
  test('scheduler transport has no hidden retries and bounds bytes per request', () async {
    final adapter = Adapter((o, n) => ResponseBody.fromString(n == 1 ? 'rate' : 'ok', n == 1 ? 429 : 200));
    final connection = connectAssistant(
      config(AssistantProvider.compatible),
      'key',
      adapter: adapter,
      retryRequests: false,
      perRequestBudget: true,
      budget: const ResearchBudget(responseBytes: 4),
    );
    await expectLater(connection.dio.post('https://example.com/v1/chat/completions'), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
    for (var i = 0; i < 5; i++) {
      expect((await connection.dio.post('https://example.com/v1/chat/completions')).data, 'ok');
    }
    connection.close();
  });
  for (final provider in [AssistantProvider.compatible, AssistantProvider.ollama]) {
    test('$provider streams repeated, fragmented and cumulative tool names through execution', () async {
      for (final names in [
        ['read_selection', 'read_selection', 'read_selection'],
        ['read_', 'select', 'ion'],
        ['read_', 'read_select', 'read_selection'],
        ['read_selection', '', ''],
      ]) {
        final adapter = Adapter((options, number) {
          final request = options.data is String ? jsonDecode(options.data) : options.data;
          expect(request['stream'], true);
          if (number == 2) {
            final messages = request['messages'] as List;
            final call = messages.firstWhere((m) => m['tool_calls'] != null)['tool_calls'][0];
            expect(call['function']['name'], 'read_selection');
            expect(jsonDecode(call['function']['arguments']), {'selectionId': 'sel'});
            expect(messages.last['role'], 'tool');
            expect(messages.last['content'], contains('selection'));
          }
          final frames = number == 1
              ? [
                  for (var i = 0; i < names.length; i++)
                    {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'selection-call',
                          'type': 'function',
                          'function': {
                            'name': names[i],
                            'arguments': ['{"selectionId":', '"sel"', '}'][i],
                          },
                        },
                      ],
                    },
                ]
              : [
                  {'content': '选区解释完成。'},
                ];
          final wire = [
            ': keepalive',
            for (final delta in frames)
              'data: ${jsonEncode({
                'choices': [
                  {'index': 0, 'delta': delta, 'finish_reason': null},
                ],
              })}\r\n',
            'data: ${jsonEncode({
              'choices': [
                {'index': 0, 'delta': {}, 'finish_reason': number == 1 ? 'tool_calls' : 'stop'},
              ],
            })}\r\n',
            'data: [DONE]\r\n',
          ].join('\r\n');
          // Split at every byte, including inside Chinese UTF-8 characters.
          return ResponseBody(
            Stream.fromIterable(utf8.encode(wire).map((byte) => Uint8List.fromList([byte]))),
            200,
            headers: {
              Headers.contentTypeHeader: ['text/event-stream'],
            },
          );
        });
        final connection = connectAssistant(config(provider), 'test-key', adapter: adapter);
        final state = AgentState(sessionId: 'stream');
        final run = createAssistantRun(
          client: connection.client,
          model: 'model',
          state: state,
          requestId: 'r',
          reader: Reader(),
          scope: ReadScope(studySetId: 's', selections: {'sel'}),
          mapId: 'm',
          baseRevision: 0,
          parents: {},
        );
        try {
          final events = await run.run('解释选区').toList();
          final result =
              events.singleWhere((e) => e.eventType == StreamingEventType.functionCallResult).data
                  as FunctionExecutionResultMessage;
          expect(result.results.single.isError, false);
          final answer =
              events.lastWhere((e) => e.eventType == StreamingEventType.fullModelMessage).data as ModelMessage;
          expect(answer.textOutput, '选区解释完成。');
          expect(adapter.calls, 2);
          expect((state.metadata['assistant.diagnostics'] as Map)['r']['fallback'], isNot(true));
        } finally {
          connection.close();
        }
      }
    });
  }

  test('coding/auto wire response recording replays malformed tools and direct fallback', () async {
    final adapter = Adapter((options, number) {
      final data = options.data is String ? jsonDecode(options.data) : options.data;
      expect(data['model'], 'coding/auto');
      if (number == 4) expect(data['tools'] ?? [], isEmpty);
      return ResponseBody.fromString(
        jsonEncode({
          'id': 'recorded-$number',
          'model': 'coding/auto',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': number < 4 ? 'Let me look that up.' : '**结论：仅依据上下文。**\n- 原文要点。',
                if (number < 4)
                  'tool_calls': [
                    {
                      'id': 'tool-$number',
                      'type': 'function',
                      'function': {'name': 'functions.read_selction', 'arguments': '{}'},
                    },
                  ],
              },
              'finish_reason': number < 4 ? 'tool_calls' : 'stop',
            },
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });
    final connection = connectAssistant(
      const AssistantModel(
        provider: AssistantProvider.compatible,
        model: 'coding/auto',
        endpoint: 'https://example.com/v1',
      ),
      'test-key',
      adapter: adapter,
    );
    final store = InMemoryRecordingStore();
    try {
      for (final client in [
        RecordingLLMClient(inner: connection.client, store: store),
        ReplayLLMClient(store: store),
      ]) {
        final state = AgentState(sessionId: 'wire');
        final run = createAssistantRun(
          client: client,
          model: 'coding/auto',
          state: state,
          requestId: 'wire-request',
          reader: Reader(),
          scope: ReadScope(studySetId: 's'),
          mapId: 'm',
          baseRevision: 0,
          parents: {},
        );
        final events = await run.agent.runStream([UserMessage.text('解释上下文')], useStream: false).toList();
        expect((state.metadata['assistant.diagnostics'] as Map)['wire-request']['fallback'], true);
        expect(
          (events.lastWhere((e) => e.eventType == StreamingEventType.fullModelMessage).data as ModelMessage).textOutput,
          startsWith('**结论：'),
        );
      }
      expect(adapter.calls, 4);
    } finally {
      connection.close();
    }
  });

  test('compatible base URLs and full endpoints generate at the same exact route', () async {
    for (final address in [
      'https://squirrel.aicode.cc/v1',
      'https://squirrel.aicode.cc/v1/',
      ' https://squirrel.aicode.cc/v1/chat/completions/ ',
      'https://squirrel.aicode.cc',
    ]) {
      final adapter = Adapter((options, _) {
        expect(options.uri.toString(), 'https://squirrel.aicode.cc/v1/chat/completions');
        expect(options.headers['Authorization'], 'Bearer test-key');
        return ResponseBody.fromString(
          jsonEncode({
            'id': 'probe',
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'OK'},
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final connection = connectAssistant(
        AssistantModel(provider: AssistantProvider.compatible, model: 'coding/auto', endpoint: address),
        'test-key',
        adapter: adapter,
      );
      try {
        final reply = await connection.client.generate([
          UserMessage.text('ping'),
        ], modelConfig: ModelConfig(model: 'coding/auto', maxTokens: 1));
        expect(reply.textOutput, 'OK');
        expect(adapter.calls, 1);
        // Normalizing a base must not broaden the allowed request route.
        await expectLater(connection.dio.post('https://squirrel.aicode.cc/v1/models'), throwsA(isA<DioException>()));
        expect(adapter.calls, 1);
      } finally {
        connection.close();
      }
    }
  });

  test('base URL normalization preserves custom routing prefixes', () async {
    const route = 'https://example.com/gateway/v1/chat/completions';
    final adapter = Adapter((options, _) {
      expect(options.uri.toString(), route);
      return ResponseBody.fromString('ok', 200);
    });
    final connection = connectAssistant(
      const AssistantModel(
        provider: AssistantProvider.compatible,
        model: 'm',
        endpoint: 'https://example.com/gateway/v1/',
      ),
      'test-key',
      adapter: adapter,
    );
    try {
      await connection.dio.post(route);
    } finally {
      connection.close();
    }
  });

  test('Ollama generates through the real pinned loopback transport without a key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final config = AssistantModel(
      provider: AssistantProvider.ollama,
      model: 'local-model',
      endpoint: 'http://127.0.0.1:${server.port}/v1/',
      localEnabled: true,
    );
    final connection = connectAssistant(config, '');
    final served = () async {
      final request = await server.first;
      expect(request.uri.path, '/v1/chat/completions');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['model'], 'local-model');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'local',
          'object': 'chat.completion',
          'created': 1,
          'model': 'local-model',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'Local answer'},
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      await request.response.close();
    }();
    try {
      final result = await connection.client.generate([
        UserMessage.text('question'),
      ], modelConfig: ModelConfig(model: config.model, maxTokens: 16));
      expect(result.textOutput, 'Local answer');
      await served;
    } finally {
      connection.close();
      await server.close(force: true);
    }
  });

  for (final provider in AssistantProvider.values.where((p) => p != AssistantProvider.gemini)) {
    test('$provider builds correct SDK and exact endpoint with no SDK retries', () async {
      final adapter = Adapter((o, n) {
        expect(o.uri.toString(), config(provider).endpoint);
        expect(o.followRedirects, false);
        return ResponseBody.fromString('ok', 200);
      });
      final connection = connectAssistant(config(provider), 'secret', adapter: adapter);
      switch (connection.client) {
        case ClaudeClient c:
          expect(c.maxRetries, 0);
        case ResponsesClient c:
          expect(c.maxRetries, 0);
          expect(c.autoPreviousResponseId, false);
        case OpenAIClient c:
          expect(c.maxRetries, 0);
      }
      await connection.dio.post(config(provider).endpoint);
      connection.close();
      expect(adapter.closed, true);
      expect(AssistantModel.fromJson(config(provider).toJson()).provider, provider);
    });
  }
  test('only received retryable status is retried; failures and redirects are not', () async {
    for (final status in [429, 500, 401, 302]) {
      final adapter = Adapter(
        (o, n) => ResponseBody.fromString(
          'error',
          status,
          headers: {
            'retry-after': ['0'],
          },
        ),
      );
      final connection = connectAssistant(config(AssistantProvider.compatible), 'key', adapter: adapter);
      await expectLater(
        connection.dio.post(config(AssistantProvider.compatible).endpoint),
        throwsA(isA<DioException>()),
      );
      expect(adapter.calls, status == 429 || status == 500 ? 3 : 1);
      connection.close();
    }
    final adapter = Adapter((o, n) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
    final connection = connectAssistant(config(AssistantProvider.compatible), 'key', adapter: adapter);
    await expectLater(connection.dio.post(config(AssistantProvider.compatible).endpoint), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
    connection.close();
  });
  test('successful retry, byte ceiling, wrong endpoint and cancellation during backoff', () async {
    final adapter = Adapter(
      (o, n) => ResponseBody.fromString(
        n == 1 ? 'retry' : 'ok',
        n == 1 ? 429 : 200,
        headers: {
          'retry-after': ['0'],
        },
      ),
    );
    final connection = connectAssistant(config(AssistantProvider.compatible), 'key', adapter: adapter);
    expect((await connection.dio.post(config(AssistantProvider.compatible).endpoint)).data, 'ok');
    expect(adapter.calls, 2);
    await expectLater(connection.dio.post('https://example.com/elsewhere'), throwsA(isA<DioException>()));
    connection.close();
    final large = connectAssistant(
      config(AssistantProvider.compatible),
      'key',
      budget: const ResearchBudget(responseBytes: 3),
      adapter: Adapter((o, n) => ResponseBody.fromString('large', 200)),
    );
    await expectLater(large.dio.post(config(AssistantProvider.compatible).endpoint), throwsA(isA<DioException>()));
    large.close();
    final retry = Adapter(
      (o, n) => ResponseBody.fromString(
        'retry',
        429,
        headers: {
          'retry-after': ['10'],
        },
      ),
    );
    final conn = connectAssistant(config(AssistantProvider.compatible), 'key', adapter: retry);
    final token = CancelToken();
    final pending = conn.dio.post(config(AssistantProvider.compatible).endpoint, cancelToken: token);
    final expectation = expectLater(pending, throwsA(isA<DioException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel();
    await expectation;
    expect(retry.calls, 1);
    conn.close();
  });
  test('note connections omit token caps and accept cumulative responses over the old byte limit', () async {
    final body = 'x' * 3000000;
    final adapter = Adapter((options, n) {
      final request = options.data is String ? jsonDecode(options.data) : options.data;
      expect(request.containsKey('max_tokens'), isFalse);
      expect(request.containsKey('max_completion_tokens'), isFalse);
      return ResponseBody.fromString(
        jsonEncode({
          'model': 'model',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': jsonEncode({
                  'sections': [
                    {
                      'title': body,
                      'refs': ['h1'],
                    },
                  ],
                }),
              },
              'finish_reason': 'stop',
            },
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });
    final connection = connectAssistant(
      config(AssistantProvider.compatible),
      'key',
      budget: null,
      requestTimeout: const Duration(seconds: 2),
      adapter: adapter,
    );
    addTearDown(connection.close);
    final organizer = ModelNoteOrganizer(client: connection.client, model: 'model');
    final now = DateTime.utc(2026);
    final source = NoteMaterials([
      NoteMaterial(ref: 'h1', sourceId: 'a1', text: 'source', groupKey: 'g', groupTitle: 'title', createdAt: now),
    ], collectedAt: now);
    for (var i = 0; i < 3; i++) {
      final outline = await organizer.outline(source, NoteSettings());
      expect(outline.sections.single.title.length, body.length);
    }
    expect(adapter.calls, 3);
    await expectLater(connection.dio.post('https://example.com/elsewhere'), throwsA(isA<DioException>()));
    expect(adapter.calls, 3);
  });

  test('configuration rejects non HTTPS, wrong paths and unauthorized local endpoints', () {
    for (final c in [
      const AssistantModel(
        provider: AssistantProvider.compatible,
        model: 'm',
        endpoint: 'http://example.com/v1/chat/completions',
      ),
      const AssistantModel(
        provider: AssistantProvider.compatible,
        model: 'm',
        endpoint: 'https://example.com/v1?key=secret',
      ),
      const AssistantModel(
        provider: AssistantProvider.compatible,
        model: 'm',
        endpoint: 'https://user:pass@example.com/v1',
      ),
      const AssistantModel(
        provider: AssistantProvider.compatible,
        model: 'm',
        endpoint: 'https://example.com/v1#fragment',
      ),
      const AssistantModel(provider: AssistantProvider.compatible, model: 'm', endpoint: 'https://[bad'),
      const AssistantModel(provider: AssistantProvider.compatible, model: 'm', endpoint: 'https:/v1'),
      const AssistantModel(
        provider: AssistantProvider.responses,
        model: '',
        endpoint: 'https://api.openai.com/v1/responses',
      ),
      const AssistantModel(
        provider: AssistantProvider.ollama,
        model: 'm',
        endpoint: 'http://192.168.1.2/v1',
        localEnabled: true,
      ),
      const AssistantModel(
        provider: AssistantProvider.ollama,
        model: 'm',
        endpoint: 'ftp://localhost/v1',
        localEnabled: true,
      ),
      const AssistantModel(
        provider: AssistantProvider.ollama,
        model: 'm',
        endpoint: 'http://localhost:11434/v1/chat/completions',
      ),
      const AssistantModel(
        provider: AssistantProvider.ollama,
        model: 'm',
        endpoint: 'http://192.168.1.2/v1/chat/completions',
        localEnabled: true,
      ),
    ]) {
      expect(() => connectAssistant(c, ''), throwsA(isA<ResearchFailure>()));
    }
  });
  test('error classification never returns raw provider diagnostic', () {
    for (final pair in [
      (400, ResearchFailureKind.invalidRequest),
      (404, ResearchFailureKind.invalidRequest),
      (405, ResearchFailureKind.invalidRequest),
      (422, ResearchFailureKind.invalidRequest),
      (401, ResearchFailureKind.authentication),
      (403, ResearchFailureKind.authentication),
      (408, ResearchFailureKind.timeout),
      (504, ResearchFailureKind.timeout),
      (429, ResearchFailureKind.rateLimited),
      (500, ResearchFailureKind.unavailable),
    ]) {
      final options = RequestOptions();
      expect(
        assistantFailureKind(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: pair.$1),
          ),
        ),
        pair.$2,
      );
    }
    expect(assistantFailureKind(StateError('secret')), ResearchFailureKind.unavailable);
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      expect(
        assistantFailureKind(DioException(requestOptions: RequestOptions(), type: type)),
        ResearchFailureKind.timeout,
      );
    }
  });
  test('partial response stream errors are never retried', () async {
    Stream<Uint8List> broken() async* {
      yield Uint8List.fromList([65]);
      throw StateError('disconnect');
    }

    final adapter = Adapter((o, n) => ResponseBody(broken(), 200));
    final connection = connectAssistant(config(AssistantProvider.compatible), 'key', adapter: adapter);
    final response = await connection.dio.post<ResponseBody>(
      config(AssistantProvider.compatible).endpoint,
      options: Options(responseType: ResponseType.stream),
    );
    await expectLater(response.data!.stream.toList(), throwsStateError);
    expect(adapter.calls, 1);
    connection.close();
  });
}
