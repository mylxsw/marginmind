import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:test/test.dart';

import 'providers_test.dart' show Adapter;

void main() {
  test('Gemini generate and stream are routed to exact configured native paths', () async {
    const config = AssistantModel(
      provider: AssistantProvider.gemini,
      model: 'gemini-flash',
      endpoint: 'https://proxy.example/v1beta',
      serviceId: 'gemini',
    );
    final response = {
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': 'Hello'},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
    };
    final adapter = Adapter((o, n) {
      expect(o.uri.host, 'proxy.example');
      expect(o.headers['x-goog-api-key'], 'secret');
      expect(o.followRedirects, false);
      expect(o.uri.query, isEmpty);
      final stream = o.uri.path.endsWith(':streamGenerateContent');
      expect(o.uri.path, '/v1beta/models/gemini-flash:${stream ? 'streamGenerateContent' : 'generateContent'}');
      return ResponseBody.fromString(
        stream ? '[${jsonEncode(response)}]' : jsonEncode(response),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    });
    final connection = connectAssistant(config, 'secret', adapter: adapter);
    addTearDown(connection.close);
    expect((connection.client as GeminiClient).maxRetries, 0);
    expect(
      (await connection.client.generate([
        UserMessage.text('ping'),
      ], modelConfig: ModelConfig(model: config.model))).textOutput,
      'Hello',
    );
    final chunks = await (await connection.client.stream([
      UserMessage.text('ping'),
    ], modelConfig: ModelConfig(model: config.model))).toList();
    expect(chunks, isNotEmpty);
    await expectLater(
      connection.dio.post('https://proxy.example/v1beta/models/other:generateContent'),
      throwsA(isA<DioException>()),
    );
    expect(AssistantModel.fromJson(config.toJson()).serviceId, 'gemini');
  });
}
