import 'package:test/test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'task_runtime_test.dart' as fixture;
import 'model_policy_test.dart' as policy;
import 'support.dart';

void main() {
  test('changing model configuration cannot increase the task request ceiling', () async {
    RunContext config(int phase, int limit) {
      final json = encodeRunContext(fixture.context(phase: phase));
      (json['policy'] as Map)['maxOutputTokens'] = limit;
      return decodeRunContext(json);
    }
    var changed = true;
    final client = ScriptClient([answer('Title')]);
    final harness = SdkAgentRuntime(
      store: fixture.Store(), tasks: fixture.registry(),
      knowledge: VersionedKnowledgeRegistry([]), testClient: client,
      loadModel: (_) async {
        if (changed) throw const ConfigurationFailure('serviceConfigurationChanged');
        return RuntimeModelBinding(model: policy.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1);
      },
    );
    final handle = harness.start(
      TaskRequest<String>(spec: fixture.spec, input: {'text': 'Title source'}, inputFingerprint: 'one', maxOutputTokens: 64),
      config(0, 64),
    );
    await pumpEventQueue(times: 50);
    expect(handle.status, RunStatus.paused);
    await handle.useConfiguration(config(1, 8192));
    changed = false;
    await handle.resume();
    expect((await handle.result).status, RunStatus.completed);
    expect(client.modelConfigs.single.maxTokens, lessThanOrEqualTo(64));
  });

  test('maintained production profile admits a basic tool-using Heavy task', () {
    final service = AssistantService(id: 'official', protocol: ServiceProtocol.openai,
      name: 'Official', endpoint: 'https://api.openai.com/v1',
      models: [const ServiceModel(id: 'gpt-4.1-2025-04-14')]);
    final profile = maintainedCapabilityProfile(service, service.models.single)!;
    final spec = TaskSpec(type: TaskType.assistantChat, inputSchema: 'i', resultSchema: 'o',
      promptVersion: '1', schemaVersion: '1', completionRule: 'answer',
      requiredCapabilities: {ModelCapability.tools, ModelCapability.historyReplay});
    expect(() => validateTaskCapabilities(spec, profile), returnsNormally);
  });
}
