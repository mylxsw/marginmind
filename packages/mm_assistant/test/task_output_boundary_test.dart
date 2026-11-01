import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'task_runtime_test.dart' as f;
import 'support.dart';

RunContext context(int phase, int limit) {
  final json = encodeRunContext(f.context(phase: phase));
  (json['policy'] as Map)['maxOutputTokens'] = limit;
  return decodeRunContext(json);
}

TaskRequest<String> request({int? limit, bool specLimit = false}) => TaskRequest<String>(
  spec: specLimit ? titleGenerationSpec : f.spec,
  input: {'text': 'Title source'},
  inputFingerprint: 'one',
  maxOutputTokens: limit,
);

void main() {
  test('initial Runtime boundary narrows prebuilt config and archives actual value on retry and repair', () async {
    final store = f.Store(), client = f.RetryThenRepairClient();
    final handle = f.runtime(store, client).start(request(limit: 64), context(0, 8192));
    expect((await handle.result).status, RunStatus.completed);
    expect(client.modelConfigs, hasLength(3));
    expect(client.modelConfigs.every((c) => c.maxTokens == 64 && c.extra?['reasoning_effort'] == 'none'), isTrue);
    expect(store.saved!.context.config.policy.maxOutputTokens, 64);
    expect(store.saved!.configurationPhases.single.config.policy.maxOutputTokens, 64);
  });
  test('switch and restart cannot raise frozen ceiling even when recovered request omits limit', () async {
    final store = f.Store();
    final blocked = SdkAgentRuntime(
      store: store,
      tasks: f.registry(),
      knowledge: VersionedKnowledgeRegistry([]),
      testClient: ScriptClient([]),
      loadModel: (_) async => throw const ConfigurationFailure('serviceConfigurationChanged'),
    );
    final handle = blocked.start(request(limit: 64), context(0, 64));
    await pumpEventQueue(times: 50);
    expect(handle.status, RunStatus.paused);
    await handle.useConfiguration(context(1, 8192));
    expect(store.saved!.context.config.policy.maxOutputTokens, 64);
    final client = f.RetryThenRepairClient();
    final restarted = await f.runtime(store, client).recover(request(), handle.context);
    await restarted.useConfiguration(context(2, 16384));
    await restarted.resume();
    expect((await restarted.result).status, RunStatus.completed);
    expect(client.modelConfigs.every((c) => c.maxTokens == 64), isTrue);
    expect(store.saved!.configurationPhases.map((p) => p.config.policy.maxOutputTokens), [64, 64, 64]);
  });
  test('spec ceiling applies without request override; invalid input does not reserve run ID', () async {
    final spec = TaskSpec(
      type: TaskType.titleGenerate,
      inputSchema: f.spec.inputSchema,
      resultSchema: f.spec.resultSchema,
      promptVersion: f.spec.promptVersion,
      schemaVersion: f.spec.schemaVersion,
      completionRule: f.spec.completionRule,
      maxOutputTokens: 64,
    );
    final store = f.Store(), client = ScriptClient([answer('Title')]);
    final tasks = TaskRegistry()
      ..register<String>(
        TaskDefinition<String>(
          spec: spec,
          instructions: 'Title',
          decode: (text) => text,
          encode: (text) => {'title': text},
          restore: (json) => json['title'] as String,
          validator: f.Validator(),
          validateInput: (_) => ValidationReport(),
        ),
      );
    final runtime = SdkAgentRuntime(
      store: store,
      tasks: tasks,
      knowledge: VersionedKnowledgeRegistry([]),
      testClient: client,
      loadModel: f.runtime(store, client).loadModel,
    );
    expect(
      () => runtime.start(
        TaskRequest<String>(spec: spec, input: {}, inputFingerprint: 'one', maxOutputTokens: 0),
        context(0, 8192),
      ),
      throwsA(isA<ConfigurationFailure>()),
    );
    final result = await runtime
        .start(
          TaskRequest<String>(spec: spec, input: {'text': 'Title source'}, inputFingerprint: 'one'),
          context(0, 8192),
        )
        .result;
    expect(result.status, RunStatus.completed);
    expect(client.modelConfigs.single.maxTokens, 64);
  });
}
