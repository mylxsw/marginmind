import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:dio/dio.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'model_policy_test.dart' as fixture;

class Store implements RunStore {
  RunManifest? saved;
  Map<String, dynamic>? value;
  bool failComplete = false;
  final committed = <RunManifest>[];
  @override
  Future<RunManifest?> load(String id) async => saved;
  @override
  Future<void> checkpoint(RunManifest snapshot, {required int? expectedRevision}) async {
    if (saved?.revision != expectedRevision) throw const RunStoreConflict();
    saved = decodeRunManifest(jsonDecode(jsonEncode(encodeRunManifest(snapshot))));
  }

  @override
  Future<void> complete(RunManifest snapshot, Map<String, dynamic> result, {required int expectedRevision}) async {
    if (failComplete) throw StateError('disk');
    await checkpoint(snapshot, expectedRevision: expectedRevision);
    value = result;
    committed.add(snapshot);
  }
}

class Validator implements TaskValidator<String> {
  Validator({this.partial = false});
  final bool partial;
  @override
  ValidationReport validate(String result, Map<String, dynamic> expectedInputManifest) =>
      ValidationReport(missingInputIds: partial ? {'missing-section'} : {});
}

RunContext context({String runId = 'run', int phase = 0}) {
  final caps = fixture.profile(ModelProtocol.chatCompletions);
  return RunContext(
    runId: runId,
    phase: phase,
    knowledgeVersions: {},
    modelDisplayName: 'Fixture',
    serviceDisplayName: 'Local fixture',
    inputRange: {
      'ids': ['one'],
    },
    config: ResolvedTaskConfig(
      capabilities: caps,
      policy: fixture.policy(ModelProtocol.chatCompletions),
      routingRevision: 1,
      source: RoutingSource.functionBinding,
    ),
  );
}

final spec = TaskSpec(
  type: TaskType.titleGenerate,
  inputSchema: 'text',
  resultSchema: 'nonempty-title',
  promptVersion: '1',
  schemaVersion: '1',
  completionRule: 'Valid title',
);
TaskRegistry registry({bool partial = false}) => TaskRegistry()
  ..register<String>(
    TaskDefinition<String>(
      spec: spec,
      instructions: 'Return a title only.',
      decode: (text) {
        if (text == 'bad') throw const FormatException('title');
        return text;
      },
      encode: (text) => {'title': text},
      restore: (j) => j['title'] as String,
      validator: Validator(partial: partial),
      validateInput: (_) => ValidationReport(),
    ),
  );
TaskRequest<String> request() =>
    TaskRequest<String>(spec: spec, input: {'text': 'Title source'}, inputFingerprint: 'one');
SdkAgentRuntime runtime(Store store, sdk.LLMClient client, {bool partial = false}) => SdkAgentRuntime(
  store: store,
  tasks: registry(partial: partial),
  knowledge: VersionedKnowledgeRegistry([]),
  testClient: client,
  loadModel: (_) async =>
      RuntimeModelBinding(model: fixture.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
);

class DelayedClient extends ScriptClient {
  DelayedClient() : super([]);
  final received = Completer<void>();
  final response = Completer<sdk.ModelMessage>();
  @override
  Future<sdk.ModelMessage> generate(
    List<sdk.LLMMessage> messages, {
    List<sdk.Tool>? tools,
    sdk.ToolChoice? toolChoice,
    required sdk.ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    calls++;
    received.complete();
    return response.future;
  }
}

void main() {
  test('quick runs SDK, no tools/knowledge, off on every repair and records unknown usage', () async {
    final store = Store(), client = ScriptClient([answer('bad'), answer('Title')]);
    final handle = runtime(store, client).start(request(), context());
    final events = <RunEvent>[];
    final sub = handle.events.listen(events.add);
    final result = await handle.result;
    expect(result.status, RunStatus.completed);
    expect(client.calls, 2);
    expect(client.toolRequests.every((t) => t.isEmpty), true);
    expect(client.modelConfigs.every((c) => c.extra?['reasoning_effort'] == 'none'), true);
    expect(jsonEncode(client.requests.last.map((m) => m.toJson()).toList()), contains('schema_repair'));
    expect(result.usage.quality, UsageQuality.unknown);
    expect(result.usage.repairs, 1);
    expect(store.committed, hasLength(1));
    expect(store.saved!.context.modelDisplayName, 'Fixture');
    expect(events.map((e) => e.sequence).toSet().length, events.length);
    await sub.cancel();
  });
  test('missing ranges remain partial', () async {
    final store = Store();
    final result = await runtime(
      store,
      ScriptClient([answer('Title')]),
      partial: true,
    ).start(request(), context()).result;
    expect(result.status, RunStatus.partial);
    expect(result.validation.missingInputIds, {'missing-section'});
    expect(store.value!['missingInputIds'], ['missing-section']);
  });
  test('save failure retains verified result; resume saves without another purchase', () async {
    final store = Store()..failComplete = true;
    final client = ScriptClient([answer('Title')]);
    final handle = runtime(store, client).start(request(), context());
    await pumpEventQueue(times: 50);
    expect(handle.status, RunStatus.paused);
    expect(store.saved!.checkpoint['pending'], isNotNull);
    store.failComplete = false;
    await Future.wait([handle.resume(), handle.resume()]);
    expect((await handle.result).value, 'Title');
    expect(client.calls, 1);
    await handle.resume();
    expect(store.committed, hasLength(1));
  });
  test('crash after validation recovers pending result without model dispatch', () async {
    final store = Store()..failComplete = true;
    final client = ScriptClient([answer('Title')]);
    final original = runtime(store, client).start(request(), context());
    await pumpEventQueue(times: 50);
    final recovered = await runtime(store, client).recover(request(), context());
    expect(recovered.status, RunStatus.interrupted);
    expect(client.calls, 1);
    store.failComplete = false;
    await recovered.resume();
    expect((await recovered.result).value, 'Title');
    expect(client.calls, 1);
    expect(original.status, RunStatus.paused);
  });
  test('cancel isolates a late response even when client ignores cancellation', () async {
    final store = Store(), client = DelayedClient();
    final handle = runtime(store, client).start(request(), context());
    await client.received.future;
    await handle.cancel();
    expect((await handle.result).status, RunStatus.cancelled);
    client.response.complete(answer('too late'));
    await pumpEventQueue();
    expect(store.committed, hasLength(1));
    expect(store.value!['value'], isNull);
  });
  test('pause allows in-flight validated result to finish, rejects in-flight model changes', () async {
    final store = Store(), client = DelayedClient();
    final handle = runtime(store, client).start(request(), context());
    await client.received.future;
    await handle.pause();
    await expectLater(handle.useConfiguration(context(phase: 1)), throwsStateError);
    client.response.complete(answer('Title'));
    expect((await handle.result).status, RunStatus.completed);
  });
  test('heavy tools are task/knowledge/host intersection and preserve SDK tool turns', () async {
    final heavySpec = TaskSpec(
      type: TaskType.assistantChat,
      inputSchema: 'text',
      resultSchema: 'text',
      promptVersion: '1',
      schemaVersion: '1',
      completionRule: 'answer',
      allowedTools: {'read', 'forbidden'},
    );
    var reads = 0, forbidden = 0;
    final tasks = TaskRegistry()
      ..register<String>(
        TaskDefinition<String>(
          spec: heavySpec,
          instructions: 'Answer from read data',
          decode: (s) => s,
          encode: (s) => {'text': s},
          restore: (j) => j['text'] as String,
          validator: Validator(),
          validateInput: (_) => ValidationReport(),
          tools: [
            sdk.Tool(
              name: 'read',
              description: 'read',
              parameters: {'type': 'object', 'properties': {}},
              parameterMode: sdk.ToolParameterMode.object,
              executable: (Map<String, dynamic> _) {
                reads++;
                return 'evidence';
              },
            ),
            sdk.Tool(
              name: 'forbidden',
              description: 'forbidden',
              parameters: {'type': 'object', 'properties': {}},
              parameterMode: sdk.ToolParameterMode.object,
              executable: (Map<String, dynamic> _) {
                forbidden++;
                return 'bad';
              },
            ),
          ],
        ),
      );
    final store = Store(), client = ScriptClient([call('read', '{}'), answer('Grounded')]);
    final c = context();
    final heavyContext = RunContext(
      runId: c.runId,
      config: ResolvedTaskConfig(
        capabilities: c.config.capabilities,
        policy: const DefaultProviderPolicyCompiler().compile(
          category: TaskCategory.heavy,
          requested: ReasoningPolicy.off,
          identity: c.config.capabilities.identity,
          capabilities: c.config.capabilities,
        ),
        routingRevision: 1,
        source: RoutingSource.functionBinding,
      ),
      knowledgeVersions: {'assistant.core': '1', 'explain': '1'},
    );
    final harness = SdkAgentRuntime(
      store: store,
      tasks: tasks,
      testClient: client,
      loadModel: (_) async =>
          RuntimeModelBinding(model: fixture.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
      knowledge: VersionedKnowledgeRegistry([
        KnowledgeBundle(id: 'assistant.core', version: '1', instructions: 'Read first', tools: {'read'}),
        KnowledgeBundle(id: 'explain', version: '1', instructions: 'Explain faithfully'),
      ]),
    );
    final handle = harness.start(
      TaskRequest<String>(spec: heavySpec, input: {'text': 'question'}, inputFingerprint: 'q'),
      heavyContext,
    );
    await pumpEventQueue(times: 50);
    expect(handle.persistenceError, isNull);
    final result = await handle.result;
    expect(result.status, RunStatus.completed);
    expect(reads, 1);
    expect(forbidden, 0);
    expect(client.toolRequests.every((ts) => ts.map((t) => t.name).toSet().difference({'read'}).isEmpty), true);
    expect(client.requests.last.whereType<sdk.FunctionExecutionResultMessage>().single.results.single.id, 'call');
  });
  test('service revision change pauses before dispatch and explicit configuration records new phase', () async {
    final store = Store(), client = ScriptClient([answer('Title')]);
    var changed = true;
    final harness = SdkAgentRuntime(
      store: store,
      tasks: registry(),
      knowledge: VersionedKnowledgeRegistry([]),
      testClient: client,
      loadModel: (_) async => RuntimeModelBinding(
        model: fixture.model(ModelProtocol.chatCompletions),
        key: '',
        serviceRevision: changed ? 2 : 1,
      ),
    );
    final handle = harness.start(request(), context());
    await pumpEventQueue(times: 50);
    expect(handle.status, RunStatus.paused);
    expect(client.calls, 0);
    await handle.useConfiguration(context(phase: 1));
    changed = false;
    await handle.resume();
    expect((await handle.result).status, RunStatus.completed);
    expect(store.saved!.configurationPhases.map((c) => c.phase), [0, 1]);
    final attempts = ((store.saved!.checkpoint['state'] as Map)['metadata'] as Map)['runtime.attempts.v1'] as List;
    expect(attempts.single['phase'], 1);
  });
  test('reported provider tokens are distinct from unknown usage', () async {
    final store = Store(),
        client = ScriptClient([
          sdk.ModelMessage(
            model: 'fake',
            textOutput: 'Title',
            stopReason: 'stop',
            usage: sdk.ModelUsage(promptTokens: 12, completionTokens: 4),
          ),
        ]);
    final result = await runtime(store, client).start(request(), context()).result;
    expect(result.usage.quality, UsageQuality.reported);
    expect(result.usage.inputTokens, 12);
    expect(result.usage.outputTokens, 4);
  });
  test('stateful bindings are created for each run', () async {
    var created = 0;
    final tasks = TaskRegistry()
      ..register<String>(
        TaskDefinition<String>(
          spec: spec,
          instructions: 'title',
          decode: (s) => s,
          encode: (s) => {'title': s},
          restore: (j) => j['title'] as String,
          validator: Validator(),
          validateInput: (_) => ValidationReport(),
          createBindings: (_, _, _) {
            created++;
            return TaskBindings();
          },
        ),
      );
    for (var i = 0; i < 2; i++) {
      final harness = SdkAgentRuntime(
        store: Store(),
        tasks: tasks,
        knowledge: VersionedKnowledgeRegistry([]),
        testClient: ScriptClient([answer('Title')]),
        loadModel: (_) async =>
            RuntimeModelBinding(model: fixture.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
      );
      expect((await harness.start(request(), context(runId: 'run-$i')).result).status, RunStatus.completed);
    }
    expect(created, 2);
  });
  test('unknown checkpoint version fails closed without dispatch', () async {
    final store = Store();
    final client = ScriptClient([answer('Title')]);
    store.saved = RunManifest(
      context: context(),
      taskType: spec.type,
      inputFingerprint: 'one',
      promptVersion: '1',
      schemaVersion: '1',
      status: RunStatus.running,
      revision: 0,
      checkpoint: {'version': 'future'},
    );
    await expectLater(runtime(store, client).recover(request(), context()), throwsA(isA<ConfigurationFailure>()));
    expect(client.calls, 0);
  });
}
