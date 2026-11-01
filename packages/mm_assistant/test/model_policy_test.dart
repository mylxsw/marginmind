import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart' hide MessageRole;
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

const compiler = DefaultProviderPolicyCompiler();
AssistantModel model(ModelProtocol protocol) => AssistantModel(
  provider: switch (protocol) {
    ModelProtocol.chatCompletions => AssistantProvider.compatible,
    ModelProtocol.responses => AssistantProvider.responses,
    ModelProtocol.anthropicMessages => AssistantProvider.claude,
    ModelProtocol.gemini => AssistantProvider.gemini,
    ModelProtocol.ollamaChat => AssistantProvider.ollama,
  },
  model: 'fixture-model',
  serviceId: 'fixture-service',
  endpoint: protocol == ModelProtocol.ollamaChat
      ? 'http://localhost:11434/v1'
      : protocol == ModelProtocol.gemini
      ? 'https://fixture.example/v1beta'
      : 'https://fixture.example/v1',
  localEnabled: protocol == ModelProtocol.ollamaChat,
);
CapabilityIdentity identity(ModelProtocol protocol) => CapabilityIdentity(
  model: const ModelReference('fixture-service', 'fixture-model'),
  protocol: protocol,
  endpointFingerprint: modelEndpointFingerprint(protocol, model(protocol).endpoint),
  adapterVersion: modelPolicyAdapterVersion,
  serviceRevision: 1,
);
ReasoningRecipe offRecipe(ModelProtocol protocol) => switch (protocol) {
  ModelProtocol.anthropicMessages => ReasoningRecipe.thinkingDisabled,
  ModelProtocol.gemini => ReasoningRecipe.thinkingBudgetZero,
  _ => ReasoningRecipe.effortNone,
};
ModelCapabilityProfile profile(
  ModelProtocol protocol, {
  ThinkingCapability thinking = ThinkingCapability.switchable,
  CapabilityEvidenceSource source = CapabilityEvidenceSource.maintainedProfile,
  bool wire = true,
  String? basis = 'Synthetic test semantics, not a production service admission',
  ReasoningRecipe? off,
}) => ModelCapabilityProfile(
  identity: identity(protocol),
  thinking: thinking,
  policies: {
    ReasoningPolicy.off: off ?? offRecipe(protocol),
    ReasoningPolicy.standard: ReasoningRecipe.effortMedium,
    ReasoningPolicy.deep: ReasoningRecipe.effortHigh,
  },
  evidence: CapabilityEvidence(
    source: source,
    reference: 'fixture-only',
    verifiedAt: DateTime.utc(2026),
    semanticBasis: basis,
    wireVerified: wire,
  ),
);
ProviderCallPolicy policy(ModelProtocol protocol) => compiler.compile(
  category: TaskCategory.quick,
  requested: ReasoningPolicy.deep,
  identity: identity(protocol),
  capabilities: profile(protocol),
);

class WireAdapter implements HttpClientAdapter {
  WireAdapter(this.protocol, {this.failFirst = false, this.reject = false, this.multiSignature = false});
  final ModelProtocol protocol;
  final bool failFirst, reject, multiSignature;
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Inspect the actual encoded bytes handed to the transport, not ModelConfig.extra.
    final bytes = <int>[];
    await for (final chunk in requestStream!) {
      bytes.addAll(chunk);
    }
    bodies.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    if (reject || (failFirst && bodies.length == 1)) {
      return ResponseBody.fromString(
        '{}',
        reject ? 400 : 429,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'retry-after': ['0'],
        },
      );
    }
    if (options.responseType == ResponseType.stream) {
      return ResponseBody.fromString(
        streamReply(protocol),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(reply(protocol, multiSignature: multiSignature)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> reply(ModelProtocol protocol, {bool multiSignature = false}) => switch (protocol) {
  ModelProtocol.anthropicMessages => {
    'id': 'msg-fixture',
    'type': 'message',
    'role': 'assistant',
    'model': 'fixture-model',
    'stop_reason': 'tool_use',
    'usage': {'input_tokens': 5, 'output_tokens': 3},
    'content': [
      {'type': 'thinking', 'thinking': 'private', 'signature': 'signed-one'},
      {'type': 'redacted_thinking', 'data': 'opaque-redacted'},
      {
        'type': 'tool_use',
        'id': 'call-1',
        'name': 'read',
        'input': {'page': 1},
      },
      {'type': 'thinking', 'thinking': 'private-two', 'signature': 'signed-two'},
      {'type': 'text', 'text': 'draft'},
    ],
  },
  ModelProtocol.responses => {
    'id': 'resp-fixture',
    'status': 'completed',
    'output': [
      {
        'type': 'reasoning',
        'id': 'reasoning-1',
        'encrypted_content': 'opaque-encrypted',
        'summary': [
          {'type': 'summary_text', 'text': 'summary'},
        ],
      },
      {'type': 'function_call', 'id': 'item-1', 'call_id': 'call-1', 'name': 'read', 'arguments': '{"page":1}'},
    ],
  },
  ModelProtocol.gemini => {
    'candidates': [
      {
        'content': {
          'role': 'model',
          'parts': [
            {
              'functionCall': {
                'id': 'call-1',
                'name': 'read',
                'args': {'page': 1},
              },
              'thoughtSignature': 'signed-one',
            },
            if (multiSignature)
              {
                'functionCall': {
                  'id': 'call-2',
                  'name': 'read',
                  'args': {'page': 2},
                },
                'thoughtSignature': 'signed-two',
              },
          ],
        },
        'finishReason': 'STOP',
      },
    ],
  },
  _ => {
    'id': 'chat-fixture',
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': 'draft',
          'reasoning_content': 'opaque-chat-thought',
          'tool_calls': [
            {
              'id': 'call-1',
              'type': 'function',
              'function': {'name': 'read', 'arguments': '{"page":1}'},
            },
          ],
        },
        'finish_reason': 'tool_calls',
      },
    ],
  },
};

String streamReply(ModelProtocol protocol) {
  final frames = switch (protocol) {
    ModelProtocol.anthropicMessages => <Map<String, dynamic>>[
      {
        'type': 'message_start',
        'message': {
          'id': 'msg-stream',
          'type': 'message',
          'role': 'assistant',
          'model': 'fixture-model',
          'content': [],
          'usage': {'input_tokens': 5, 'output_tokens': 0},
        },
      },
      {
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'thinking', 'thinking': ''},
      },
      {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'thinking_delta', 'thinking': 'private'},
      },
      {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'signature_delta', 'signature': 'signed-stream'},
      },
      {'type': 'content_block_stop', 'index': 0},
      {
        'type': 'content_block_start',
        'index': 1,
        'content_block': {'type': 'redacted_thinking', 'data': 'opaque-stream'},
      },
      {'type': 'content_block_stop', 'index': 1},
      {
        'type': 'content_block_start',
        'index': 2,
        'content_block': {'type': 'text', 'text': ''},
      },
      {
        'type': 'content_block_delta',
        'index': 2,
        'delta': {'type': 'text_delta', 'text': 'done'},
      },
      {'type': 'content_block_stop', 'index': 2},
      {
        'type': 'message_delta',
        'delta': {'stop_reason': 'end_turn'},
        'usage': {'output_tokens': 3},
      },
      {'type': 'message_stop'},
    ],
    ModelProtocol.responses => <Map<String, dynamic>>[
      {'type': 'response.output_text.delta', 'delta': 'done'},
      {
        'type': 'response.completed',
        'response': {'id': 'resp-stream', 'status': 'completed', 'output': []},
      },
    ],
    ModelProtocol.gemini => <Map<String, dynamic>>[
      {
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': 'done'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      },
    ],
    _ => <Map<String, dynamic>>[
      {
        'choices': [
          {
            'index': 0,
            'delta': {'content': 'done'},
            'finish_reason': 'stop',
          },
        ],
      },
    ],
  };
  return '${frames.map((frame) => '${protocol == ModelProtocol.anthropicMessages ? 'event: ${frame['type']}\n' : ''}data: ${jsonEncode(frame)}\n\n').join()}${protocol == ModelProtocol.chatCompletions || protocol == ModelProtocol.ollamaChat ? 'data: [DONE]\n\n' : ''}';
}

void main() {
  test('unknown and always-on models use provider defaults without admission checks', () {
    final protocol = ModelProtocol.chatCompletions;
    for (final candidate in [
      ModelCapabilityProfile(identity: identity(protocol)),
      profile(protocol, thinking: ThinkingCapability.alwaysOn),
      profile(protocol, wire: false),
      profile(protocol, basis: null),
      profile(protocol, source: CapabilityEvidenceSource.wireProbe),
      profile(protocol, source: CapabilityEvidenceSource.userDeclared),
      profile(protocol, off: ReasoningRecipe.omitted),
    ]) {
      final policy = compiler.compile(
        category: TaskCategory.quick,
        requested: ReasoningPolicy.auto,
        identity: identity(protocol),
        capabilities: candidate,
      );
      expect(policy.parameters, isEmpty);
      expect(policy.effective, ReasoningPolicy.auto);
    }
    final omitted = compiler.compile(
      category: TaskCategory.quick,
      requested: ReasoningPolicy.deep,
      identity: identity(protocol),
      capabilities: profile(protocol, thinking: ThinkingCapability.notApplicable),
    );
    expect(omitted.parameters, isEmpty);
    expect(omitted.effective, ReasoningPolicy.off);
    // Malformed internal parameter recipes still cannot alter a request.
    expect(
      () => compiler.compile(
        category: TaskCategory.quick,
        requested: ReasoningPolicy.auto,
        identity: identity(protocol),
        capabilities: profile(protocol, off: ReasoningRecipe.effortMedium),
      ),
      throwsA(isA<ConfigurationFailure>()),
    );
  });
  test('profiles invalidate by exact identity; no model name heuristic', () {
    final profiles = CapabilityProfiles()..put(profile(ModelProtocol.responses));
    expect(profiles.lookup(identity(ModelProtocol.responses)).thinking, ThinkingCapability.switchable);
    expect(profiles.lookup(identity(ModelProtocol.chatCompletions)).thinking, ThinkingCapability.unknown);
    profiles.invalidateService('fixture-service');
    expect(profiles.lookup(identity(ModelProtocol.responses)).thinking, ThinkingCapability.unknown);
    expect(
      () => compiler.compile(
        category: TaskCategory.quick,
        requested: ReasoningPolicy.off,
        identity: identity(ModelProtocol.responses),
        capabilities: profile(ModelProtocol.chatCompletions),
      ),
      throwsA(isA<ConfigurationFailure>()),
    );
  });
  test('heavy intensity whitelist and protocol constraints; injected options fail closed', () {
    for (final reasoning in [ReasoningPolicy.standard, ReasoningPolicy.deep, ReasoningPolicy.auto]) {
      final compiled = compiler.compile(
        category: TaskCategory.heavy,
        requested: reasoning,
        identity: identity(ModelProtocol.responses),
        capabilities: profile(ModelProtocol.responses),
      );
      expect(compiled.effective, reasoning);
    }
    expect(
      () => compiler.compile(
        category: TaskCategory.heavy,
        requested: ReasoningPolicy.deep,
        identity: identity(ModelProtocol.gemini),
        capabilities: profile(ModelProtocol.gemini),
      ),
      throwsA(isA<ConfigurationFailure>()),
    );
    final compiled = policy(ModelProtocol.responses);
    expect(
      () => verifyPolicyPayload(compiled, {
        'reasoning': {'effort': 'none', 'summary': 'auto'},
      }),
      throwsA(isA<ConfigurationFailure>()),
    );
    expect(
      () => verifyPolicyPayload(compiled, {
        'reasoning': {'effort': 'low'},
      }),
      throwsA(isA<ConfigurationFailure>()),
    );
    expect(() => compiled.parameters['reasoning']['effort'] = 'high', throwsUnsupportedError);
  });
  test('capability metadata never blocks a configured model', () {
    final spec = TaskSpec(
      type: TaskType.research,
      inputSchema: 'research.input.v1',
      resultSchema: 'research.result.v1',
      promptVersion: '1',
      schemaVersion: '1',
      completionRule: 'grounded',
      requiredCapabilities: {ModelCapability.tools},
    );
    for (final support in [CapabilitySupport.unknown, CapabilitySupport.unsupported]) {
      expect(
        () => validateTaskCapabilities(
          spec,
          ModelCapabilityProfile(identity: identity(ModelProtocol.responses), tools: support),
        ),
        returnsNormally,
      );
    }
    validateTaskCapabilities(
      spec,
      ModelCapabilityProfile(identity: identity(ModelProtocol.responses), tools: CapabilitySupport.supported),
    );
  });
  test('history replay is attempted without an SDK allowlist', () {
    final spec = TaskSpec(
      type: TaskType.assistantChat,
      inputSchema: 'i',
      resultSchema: 'o',
      promptVersion: '1',
      schemaVersion: '1',
      completionRule: 'grounded',
      requiredCapabilities: {ModelCapability.historyReplay},
    );
    for (final protocol in [ModelProtocol.responses, ModelProtocol.gemini]) {
      expect(
        () => validateTaskCapabilities(
          spec,
          ModelCapabilityProfile(identity: identity(protocol), historyReplay: CapabilitySupport.supported),
        ),
        returnsNormally,
      );
    }
  });
  test('budget rewrite preserves all SDK options, including generationConfig', () {
    final connection = connectAssistant(
      model(ModelProtocol.gemini),
      'fake-key',
      adapter: WireAdapter(ModelProtocol.gemini),
    );
    addTearDown(connection.close);
    final config = ModelConfig(
      model: 'fixture-model',
      temperature: 0.2,
      topP: 0.8,
      topK: 10,
      maxTokens: 100,
      generationConfig: {'candidateCount': 1},
      extra: {
        'thinkingConfig': {'thinkingBudget': 0},
      },
    );
    final agent = StatefulAgent(
      name: 'budget',
      client: connection.client,
      modelConfig: config,
      state: AgentState(sessionId: 'budget'),
    );
    final request = ModelCallRequest(
      systemMessage: null,
      requestMessages: [UserMessage.text('input')],
      tools: [],
      toolChoice: null,
      modelConfig: config,
      stream: false,
    );
    final rewritten = PolicyHook(
      allowed: {},
      budget: RunBudget(),
      online: false,
    ).beforeModelCall(ModelCallHookContext(agent, request: request, turnIndex: 0)).request!;
    expect(rewritten.modelConfig.toJson(), {...config.toJson(), 'maxTokens': 4096});
  });
  for (final protocol in ModelProtocol.values) {
    test('$protocol streaming uses the same off policy', () async {
      final compiled = policy(protocol);
      final adapter = WireAdapter(protocol);
      final connection = connectAssistant(model(protocol), 'fake-key', callPolicy: compiled, adapter: adapter);
      addTearDown(connection.close);
      final chunks = await (await connection.client.stream([
        UserMessage.text('input'),
      ], modelConfig: policyModelConfig(compiled, maxTokens: 64))).toList();
      expect(chunks, isNotEmpty);
      verifyPolicyPayload(compiled, adapter.bodies.single);
    });

    test('$protocol final HTTP payload and budget rewrite preserve off on retry and subsequent call', () async {
      final compiled = policy(protocol);
      final adapter = WireAdapter(protocol, failFirst: true);
      final connection = connectAssistant(model(protocol), 'fake-key', callPolicy: compiled, adapter: adapter);
      addTearDown(connection.close);
      final config = policyModelConfig(compiled, maxTokens: 100);
      final agent = StatefulAgent(
        name: 'fixture',
        client: connection.client,
        modelConfig: config,
        state: AgentState(sessionId: 'fixture'),
      );
      final hook = PolicyHook(allowed: {}, budget: RunBudget(), online: false);
      final rewritten = hook
          .beforeModelCall(
            ModelCallHookContext(
              agent,
              turnIndex: 0,
              request: ModelCallRequest(
                systemMessage: null,
                requestMessages: [UserMessage.text('input')],
                tools: [],
                toolChoice: null,
                modelConfig: config,
                stream: false,
              ),
            ),
          )
          .request!;
      expect(rewritten.modelConfig.extra, config.extra);
      await connection.client.generate(rewritten.requestMessages, modelConfig: rewritten.modelConfig);
      await connection.client.generate(rewritten.requestMessages, modelConfig: rewritten.modelConfig);
      expect(adapter.bodies.length, 3);
      for (final body in adapter.bodies) {
        verifyPolicyPayload(compiled, body);
      }
      expect(adapter.bodies[1], adapter.bodies.first);
      expect(adapter.bodies[2], adapter.bodies.first);
      final fixture = File('test/fixtures/model_policy/${protocol.name}_off.json');
      expect(adapter.bodies.first, jsonDecode(fixture.readAsStringSync()));
    });
    test('$protocol tool IDs survive response, persistence and outgoing round trip', () async {
      final adapter = WireAdapter(protocol);
      final connection = connectAssistant(model(protocol), 'fake-key', adapter: adapter);
      addTearDown(connection.close);
      final config = ModelConfig(model: 'fixture-model');
      final first = await connection.client.generate([UserMessage.text('input')], modelConfig: config);
      final restored = ModelMessage.fromJson(jsonDecode(jsonEncode(first.toJson())) as Map<String, dynamic>);
      expect(restored.functionCalls.single.id, 'call-1');
      final tool = FunctionExecutionResultMessage(
        results: [
          FunctionExecutionResult(
            id: 'call-1',
            name: 'read',
            isError: false,
            arguments: '{"page":1}',
            content: [TextPart('evidence')],
          ),
        ],
      );
      await connection.client.generate([
        UserMessage.text('input'),
        restored,
        FunctionExecutionResultMessage.fromJson(jsonDecode(jsonEncode(tool.toJson())) as Map<String, dynamic>),
      ], modelConfig: config);
      final body = adapter.bodies.last;
      expect(body, jsonDecode(File('test/fixtures/model_policy/${protocol.name}_replay.json').readAsStringSync()));
      switch (protocol) {
        case ModelProtocol.anthropicMessages:
          expect(body['messages'][1]['content'], reply(protocol)['content']);
          expect(body['messages'][2]['content'][0]['tool_use_id'], 'call-1');
        case ModelProtocol.responses:
          expect((body['input'] as List).where((item) => item['type'] == 'function_call').single['call_id'], 'call-1');
          expect((body['input'] as List).last['call_id'], 'call-1');
          // Known SDK 2.1.8 admission failure: opaque data persists but is not replayed.
          expect(restored.metadata!['output'][0]['encrypted_content'], 'opaque-encrypted');
          expect((body['input'] as List).where((item) => item['type'] == 'reasoning'), isEmpty);
        case ModelProtocol.gemini:
          expect(body['contents'][1]['parts'][0]['thoughtSignature'], 'signed-one');
          expect(body['contents'][1]['parts'][0]['functionCall']['id'], 'call-1');
          expect(body['contents'][2]['parts'][0]['functionResponse']['id'], 'call-1');
        case ModelProtocol.chatCompletions || ModelProtocol.ollamaChat:
          expect(body['messages'][1]['tool_calls'][0]['id'], 'call-1');
          expect(body['messages'][1]['reasoning_content'], 'opaque-chat-thought');
          expect(body['messages'][2]['tool_call_id'], 'call-1');
      }
    });
  }

  test('Anthropic streaming Agent state preserves signed and opaque blocks through persistence', () async {
    final adapter = WireAdapter(ModelProtocol.anthropicMessages);
    final connection = connectAssistant(model(ModelProtocol.anthropicMessages), 'fake-key', adapter: adapter);
    addTearDown(connection.close);
    final state = AgentState(sessionId: 'signed-stream');
    final config = ModelConfig(model: 'fixture-model');
    final agent = StatefulAgent(
      name: 'fixture',
      client: connection.client,
      modelConfig: config,
      state: state,
      withGeneralPrinciples: false,
    );
    await agent.runStream([UserMessage.text('input')]).toList();
    final last = state.history.messages.whereType<ModelMessage>().last;
    final restored = ModelMessage.fromJson(jsonDecode(jsonEncode(last.toJson())) as Map<String, dynamic>);
    expect(restored.contentBlocks, [
      {'type': 'thinking', 'thinking': 'private', 'signature': 'signed-stream'},
      {'type': 'redacted_thinking', 'data': 'opaque-stream'},
      {'type': 'text', 'text': 'done'},
    ]);
    await connection.client.generate([UserMessage.text('input'), restored], modelConfig: config);
    expect(adapter.bodies.last['messages'][1]['content'], restored.contentBlocks);
  });
  test('Gemini multiple signatures are not admitted: SDK flattens onto first call', () async {
    final adapter = WireAdapter(ModelProtocol.gemini, multiSignature: true);
    final connection = connectAssistant(model(ModelProtocol.gemini), 'fake-key', adapter: adapter);
    addTearDown(connection.close);
    final config = ModelConfig(model: 'fixture-model');
    final first = await connection.client.generate([UserMessage.text('input')], modelConfig: config);
    final restored = ModelMessage.fromJson(jsonDecode(jsonEncode(first.toJson())) as Map<String, dynamic>);
    await connection.client.generate([restored], modelConfig: config);
    final parts = adapter.bodies.last['contents'][0]['parts'] as List;
    expect(parts[0]['thoughtSignature'], 'signed-two');
    expect(parts[1].containsKey('thoughtSignature'), isFalse);
  });
  test('unsupported 400 is never retried without policy; missing policy rejected before wire', () async {
    final compiled = policy(ModelProtocol.chatCompletions);
    final adapter = WireAdapter(ModelProtocol.chatCompletions, reject: true);
    final connection = connectAssistant(
      model(ModelProtocol.chatCompletions),
      'fake-key',
      callPolicy: compiled,
      adapter: adapter,
    );
    addTearDown(connection.close);
    await expectLater(
      connection.client.generate([UserMessage.text('input')], modelConfig: policyModelConfig(compiled)),
      throwsA(anything),
    );
    expect(adapter.bodies.length, 1);
    await expectLater(
      connection.client.generate([UserMessage.text('input')], modelConfig: ModelConfig(model: 'fixture-model')),
      throwsA(anything),
    );
    expect(adapter.bodies.length, 1);
    expect(
      () => connectAssistant(model(ModelProtocol.responses), 'fake-key', callPolicy: compiled),
      throwsA(isA<ConfigurationFailure>()),
    );
  });
}
