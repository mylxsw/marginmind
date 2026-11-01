import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'model_policy_test.dart' show WireAdapter;

AssistantService official(ModelProtocol protocol) => AssistantService(
  id: 'official',
  revision: 7,
  protocol: protocol == ModelProtocol.gemini ? ServiceProtocol.gemini : ServiceProtocol.openai,
  name: 'Official',
  responses: protocol == ModelProtocol.responses,
  endpoint: protocol == ModelProtocol.gemini
      ? 'https://generativelanguage.googleapis.com/v1beta'
      : 'https://api.openai.com/v1',
  models: [ServiceModel(id: protocol == ModelProtocol.gemini ? 'gemini-2.5-flash' : 'gpt-4.1-2025-04-14')],
);

void main() {
  for (final (protocol, modelId) in [
    (ModelProtocol.chatCompletions, 'gpt-4.1-2025-04-14'),
    (ModelProtocol.responses, 'gpt-4.1-2025-04-14'),
    (ModelProtocol.chatCompletions, 'gpt-5.1-2025-11-13'),
    (ModelProtocol.responses, 'gpt-5.1-2025-11-13'),
    (ModelProtocol.gemini, 'gemini-2.5-flash'),
  ]) {
    test('$protocol $modelId maintained semantic rule and SDK wire preserve off and ceiling on retry', () async {
      final model = ServiceModel(id: modelId);
      final service = official(protocol).copyWith(models: [model]);
      final profile = maintainedCapabilityProfile(service, model)!;
      expect(profile.evidence!.admitsPolicy, isTrue);
      final policy = const DefaultProviderPolicyCompiler().compile(
        category: TaskCategory.quick,
        requested: ReasoningPolicy.deep,
        identity: profile.identity,
        capabilities: profile,
        maxOutputTokens: 64,
      );
      final wire = WireAdapter(protocol, failFirst: true);
      final connection = connectAssistant(service.configuration(model), 'test', callPolicy: policy, adapter: wire);
      addTearDown(connection.close);
      await connection.client.generate([sdk.UserMessage.text('Test')], modelConfig: policyModelConfig(policy));
      expect(wire.bodies.length, 2);
      for (final body in wire.bodies) {
        verifyPolicyPayload(policy, body);
        expect(policy.effective, ReasoningPolicy.off);
      }
      expect(() => policyModelConfig(policy, maxTokens: 65), throwsA(isA<ConfigurationFailure>()));
      final bad = Map<String, dynamic>.from(wire.bodies.last);
      if (protocol == ModelProtocol.gemini) {
        bad['generationConfig'] = {...bad['generationConfig'] as Map, 'maxOutputTokens': 65};
      } else {
        bad[protocol == ModelProtocol.responses ? 'max_output_tokens' : 'max_completion_tokens'] = 65;
      }
      expect(() => verifyPolicyPayload(policy, bad), throwsA(isA<ConfigurationFailure>()));
      final clipped = const DefaultProviderPolicyCompiler().compile(
        category: TaskCategory.quick,
        requested: ReasoningPolicy.off,
        identity: profile.identity,
        capabilities: profile,
        maxOutputTokens: 999999,
      );
      expect(clipped.maxOutputTokens, profile.outputTokens);
      if (modelId == 'gpt-5.1-2025-11-13') {
        for (final reasoning in [ReasoningPolicy.standard, ReasoningPolicy.deep]) {
          final heavy = const DefaultProviderPolicyCompiler().compile(
            category: TaskCategory.heavy,
            requested: reasoning,
            identity: profile.identity,
            capabilities: profile,
            maxOutputTokens: 128,
          );
          final connection = connectAssistant(service.configuration(model), 'test', callPolicy: heavy, adapter: wire);
          try {
            await connection.client.generate([sdk.UserMessage.text('Test')], modelConfig: policyModelConfig(heavy));
            verifyPolicyPayload(heavy, wire.bodies.last);
          } finally {
            connection.close();
          }
        }
      }
    });
  }
  test('exact model, protocol and official endpoint only; no substring or proxy admission', () {
    final service = official(ModelProtocol.chatCompletions);
    for (final endpoint in [
      'https://proxy.example/v1',
      'https://api.openai.com:8443/v1',
      'http://api.openai.com/v1',
      'https://api.openai.com/proxy/v1',
      'https://api.openai.com/v1?key=x',
    ]) {
      expect(maintainedCapabilityProfile(service.copyWith(endpoint: endpoint), service.models.single), isNull);
    }
    for (final id in ['gpt-4.1', 'prefix-gpt-4.1-2025-04-14', 'gpt-5', 'gemini-2.5-pro']) {
      expect(maintainedCapabilityProfile(service, ServiceModel(id: id)), isNull);
    }
  });
}
