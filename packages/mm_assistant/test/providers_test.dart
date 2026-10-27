import 'dart:async';
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart' hide MessageRole;
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
  },
  localEnabled: provider == AssistantProvider.ollama,
);
void main() {
  for (final provider in AssistantProvider.values) {
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
  test('configuration rejects non HTTPS, wrong paths and unauthorized local endpoints', () {
    for (final c in [
      const AssistantModel(
        provider: AssistantProvider.compatible,
        model: 'm',
        endpoint: 'http://example.com/v1/chat/completions',
      ),
      const AssistantModel(
        provider: AssistantProvider.responses,
        model: '',
        endpoint: 'https://api.openai.com/v1/responses',
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
      (401, ResearchFailureKind.authentication),
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
