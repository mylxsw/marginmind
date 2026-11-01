import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'maintained_capabilities_test.dart' show official;

class ToolRoundWire implements HttpClientAdapter {
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = await requestStream!.expand((chunk) => chunk).toList();
    bodies.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    final first = bodies.length == 1;
    return ResponseBody.fromString(
      jsonEncode({
        'id': 'chat-test',
        'model': 'gpt-4.1-2025-04-14',
        'choices': [
          {
            'index': 0,
            'finish_reason': first ? 'tool_calls' : 'stop',
            'message': {
              'role': 'assistant',
              'content': first ? null : 'Grounded answer',
              if (first)
                'tool_calls': [
                  {
                    'id': 'read-page-1',
                    'type': 'function',
                    'function': {'name': 'read', 'arguments': '{"page":1}'},
                  },
                ],
            },
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final custom in [false, true]) {
    test('SDK tool execution and persisted replay with custom proxy = $custom', () async {
      final service = custom
          ? AssistantService(
              id: 'proxy',
              protocol: ServiceProtocol.openai,
              name: 'Squirrel',
              endpoint: 'https://proxy.example/v1',
              models: const [ServiceModel(id: 'deepseek-flash')],
            )
          : official(ModelProtocol.chatCompletions);
      final model = service.models.single;
      final resolver = TaskModelResolver(
        catalog: () async => AssistantServices(services: [service]),
        profiles: CapabilityProfiles(),
      );
      final config = await resolver.resolve(
        TaskRequest<String>(
          spec: assistantChatSpec,
          input: const {},
          inputFingerprint: 'tool-wire',
          modelOverride: ModelReference(service.id, model.id),
        ),
        RoutingConfig(document: {'version': 1, 'revision': 0}),
      );
      final policy = config.policy;
      expect(policy.parameters, isEmpty);
      expect(config.capabilities.tools, CapabilitySupport.unknown);
      final wire = ToolRoundWire();
      final connection = connectAssistant(service.configuration(model), 'test', callPolicy: policy, adapter: wire);
      addTearDown(connection.close);
      var executions = 0;
      final tool = sdk.Tool(
        name: 'read',
        description: 'Read a page',
        parameters: {
          'type': 'object',
          'properties': {
            'page': {'type': 'integer'},
          },
          'required': ['page'],
        },
        parameterMode: sdk.ToolParameterMode.object,
        executable: (Map<String, dynamic> input) {
          expect(input['page'], 1);
          executions++;
          return 'Evidence for page 1';
        },
      );
      sdk.StatefulAgent agent(sdk.AgentState state) => sdk.StatefulAgent(
        name: 'tool-test',
        state: state,
        client: connection.client,
        tools: [tool],
        modelConfig: policyModelConfig(policy),
      );
      final state = sdk.AgentState(sessionId: 'tools');
      final responses = await agent(state).run([sdk.UserMessage.text('Read page 1')], useStream: false);
      expect((responses.last as sdk.ModelMessage).stopReason, 'stop');
      expect(executions, 1);
      expect(wire.bodies, hasLength(2));
      expect(wire.bodies.first['model'], model.id);
      final declaration =
          (wire.bodies.first['tools'] as List).where((t) => t['function']['name'] == 'read').single as Map;
      expect(declaration['type'], 'function');
      expect(declaration['function']['name'], 'read');
      expect(declaration['function']['parameters']['required'], ['page']);
      void verifyRound(Map<String, dynamic> body) {
        verifyPolicyPayload(policy, body);
        final messages = body['messages'] as List;
        final call = messages.where((m) => m['tool_calls'] != null).single['tool_calls'].single;
        expect(call['id'], 'read-page-1');
        expect(jsonDecode(call['function']['arguments'] as String), {'page': 1});
        final result = messages.where((m) => m['role'] == 'tool').single;
        expect(result['tool_call_id'], 'read-page-1');
        expect(result['content'], contains('Evidence for page 1'));
      }

      verifyRound(wire.bodies[1]);
      final restored = sdk.AgentState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      await agent(restored).run([sdk.UserMessage.text('Explain that evidence')], useStream: false);
      verifyRound(wire.bodies.last);
      expect(executions, 1);
    });
  }
  test('tool admission does not spread to other protocols or unaudited models', () {
    for (final protocol in [ModelProtocol.responses, ModelProtocol.gemini]) {
      final service = official(protocol);
      final profile = maintainedCapabilityProfile(service, service.models.single)!;
      expect(profile.tools, CapabilitySupport.unknown);
      expect(profile.historyReplay, CapabilitySupport.unsupported);
    }
    final service = official(ModelProtocol.chatCompletions);
    expect(
      maintainedCapabilityProfile(service, const ServiceModel(id: 'gpt-5.1-2025-11-13'))!.tools,
      CapabilitySupport.unknown,
    );
    expect(
      maintainedCapabilityProfile(service.copyWith(endpoint: 'https://proxy.example/v1'), service.models.single),
      isNull,
    );
  });
}
