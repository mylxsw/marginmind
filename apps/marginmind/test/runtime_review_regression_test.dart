import 'dart:io';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../packages/mm_assistant/test/task_runtime_test.dart' as f;
import '../../../packages/mm_assistant/test/model_policy_test.dart' as policy;
import '../../../packages/mm_assistant/test/support.dart';
import '../../../packages/mm_data/test/file_run_store_test.dart' as disk;

class FailingPhaseStore extends f.Store {
  bool failPhase = true;
  @override
  Future<void> checkpoint(RunManifest snapshot, {required int? expectedRevision}) async {
    if (failPhase && snapshot.context.phase == 1) throw StateError('disk full');
    await super.checkpoint(snapshot, expectedRevision: expectedRevision);
  }
}

Future<(ScriptClient, List<int>)> switchedHeavy({
  bool failSave = false,
  bool previousTool = false,
  bool modelChange = false,
}) async {
  final spec = TaskSpec(
    type: TaskType.assistantChat,
    inputSchema: 'text',
    resultSchema: 'text',
    promptVersion: '1',
    schemaVersion: '1',
    completionRule: 'answer',
    allowedTools: {'read', 'wide'},
  );
  final phases = <int>[];
  final executions = <int>[];
  final tasks = TaskRegistry()
    ..register<String>(
      TaskDefinition<String>(
        spec: spec,
        instructions: 'Read then answer',
        decode: (s) => s,
        encode: (s) => {'text': s},
        restore: (j) => j['text'] as String,
        validator: f.Validator(),
        validateInput: (_) => ValidationReport(),
        createBindings: (c, state, input) {
          phases.add(c.phase);
          if (previousTool && c.phase == 1) expect(state.metadata['confirmed-write'], 'old-receipt');
          return TaskBindings(
            tools: [
              sdk.Tool(
                name: 'read',
                description: 'Read permitted context',
                parameters: {'type': 'object', 'properties': {}},
                parameterMode: sdk.ToolParameterMode.object,
                executable: (Map<String, dynamic> _) {
                  executions.add(c.phase);
                  if (c.phase == 0) state.metadata['confirmed-write'] = 'old-receipt';
                  return jsonEncode({'phase': c.phase, 'ids': c.inputRange['ids']});
                },
              ),
              sdk.Tool(
                name: 'wide',
                description: 'Old permission',
                parameters: {'type': 'object', 'properties': {}},
                parameterMode: sdk.ToolParameterMode.object,
                executable: (Map<String, dynamic> _) => throw StateError('Revoked tool executed'),
              ),
            ],
          );
        },
      ),
    );
  final old = encodeRunContext(f.context());
  (old['policy'] as Map)['requested'] = 'off';
  old['knowledgeVersions'] = {'assistant.core': '1', 'explain': '1'};
  final c = decodeRunContext(old);
  final next = encodeRunContext(c);
  next['phase'] = 1;
  next['inputRange'] = {
    'ids': ['narrow-page'],
  };
  next['knowledgeVersions'] = {'assistant.core': '2', 'explain': '1'};
  (next['identity'] as Map)['serviceRevision'] = 2;
  if (modelChange) ((next['identity'] as Map)['model'] as Map)['modelId'] = 'explicit-next-model';
  final client = ScriptClient([
    if (previousTool)
      sdk.ModelMessage(
        model: 'fake',
        stopReason: 'tool_calls',
        contentBlocks: [
          {'type': 'thinking', 'thinking': 'old private', 'signature': 'old-signature'},
        ],
        functionCalls: [sdk.FunctionCall(id: 'old-call', name: 'read', arguments: '{}')],
      ),
    call('read', '{}'),
    answer('Grounded'),
  ]);
  var loads = 0;
  final store = FailingPhaseStore()..failPhase = failSave;
  final runtime = SdkAgentRuntime(
    store: store,
    tasks: tasks,
    testClient: client,
    loadModel: (_) async => RuntimeModelBinding(
      model: policy.model(ModelProtocol.chatCompletions),
      key: '',
      serviceRevision: previousTool && loads++ == 0 ? 1 : 2,
    ),
    knowledge: VersionedKnowledgeRegistry([
      KnowledgeBundle(id: 'assistant.core', version: '1', instructions: 'Old wide knowledge', tools: {'read', 'wide'}),
      KnowledgeBundle(id: 'assistant.core', version: '2', instructions: 'New narrow knowledge', tools: {'read'}),
      KnowledgeBundle(id: 'explain', version: '1', instructions: 'Explain'),
    ]),
  );
  final handle = runtime.start(
    TaskRequest<String>(
      spec: spec,
      input: {'q': 'question'},
      inputFingerprint: 'q',
      modelOverride: modelChange ? c.config.model : null,
    ),
    c,
  );
  await pumpEventQueue(times: 50);
  expect(handle.status, RunStatus.paused);
  expect(client.calls, previousTool ? 1 : 0);
  if (failSave) {
    await expectLater(handle.useConfiguration(decodeRunContext(next)), throwsStateError);
    expect(handle.context.phase, 0);
    expect(store.saved!.context.phase, 0);
    expect(store.saved!.configurationPhases, hasLength(1));
    store.failPhase = false;
  }
  await handle.useConfiguration(decodeRunContext(next));
  await handle.resume();
  expect((await handle.result).status, RunStatus.completed);
  expect(client.calls, previousTool ? 3 : 2);
  expect(executions, previousTool ? [0, 1] : [1]);
  final wire = jsonEncode(client.requests.last.map((m) => m.toJson()).toList());
  expect(wire, isNot(contains('old-signature')));
  expect(wire, isNot(contains('old-call')));
  expect(wire, contains('narrow-page'));
  expect(wire, isNot(contains('phase-0')));
  expect(client.toolRequests.last.map((t) => t.name), ['read']);
  expect(wire, contains('New narrow knowledge'));
  expect(wire, isNot(contains('Old wide knowledge')));
  return (client, phases);
}

void main() {
  test('explicit next phase supersedes the original request model override', () async {
    await switchedHeavy(modelChange: true);
  });
  test('phase switch archives old signatures and preserves receipts without replaying old calls', () async {
    await switchedHeavy(previousTool: true);
  });
  test('failed configuration save rolls back snapshot before retry', () async {
    await switchedHeavy(failSave: true);
  });
  test('terminal retry on disk projects missing range and preserves parent and receipts', () async {
    final dir = await Directory.systemTemp.createTemp('runtime-retry-');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileRunStore(dir);
    final tasks = TaskRegistry()
      ..register<String>(
        TaskDefinition(
          spec: f.spec,
          instructions: 'Title',
          decode: (s) => s,
          encode: (s) => {'title': s},
          restore: (j) => j['title'] as String,
          validator: f.Validator(partial: true),
          validateInput: (_) => ValidationReport(),
          retryInput: (original, missing) => {'ids': missing.toList()},
          createBindings: (c, state, input) {
            if (c.parentRunId != null) {
              expect(state.metadata['write-receipt'], 'committed-once');
              expect(input, {
                'ids': ['missing-section'],
              });
              expect(c.inputRange, {
                'ids': ['missing-section'],
              });
            } else {
              state.metadata['write-receipt'] = 'committed-once';
            }
            return TaskBindings();
          },
        ),
      );
    final client = ScriptClient([answer('Parent result'), answer('Missing only')]);
    final runtime = SdkAgentRuntime(
      store: store,
      tasks: tasks,
      knowledge: VersionedKnowledgeRegistry([]),
      testClient: client,
      loadModel: (_) async =>
          RuntimeModelBinding(model: policy.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
    );
    final parent = runtime.start(f.request(), f.context());
    expect((await parent.result).status, RunStatus.partial);
    final before = encodeRunManifest((await store.load('run'))!);
    final resultBefore = await store.loadResult('run');
    final child = await runtime.retryUnfinished(f.request(), f.context(), childRunId: 'retry-child');
    expect(client.calls, 1);
    await child.resume();
    await child.result;
    expect(client.calls, 2);
    expect(jsonEncode(client.requests.last.map((m) => m.toJson()).toList()), isNot(contains('Title source')));
    expect(encodeRunManifest((await store.load('run'))!), before);
    expect(await store.loadResult('run'), resultBefore);
    expect((await store.load('retry-child'))!.context.parentRunId, 'run');
  });
  test('failed checkpoint retry reconciles receipts before dispatching only missing work', () async {
    final dir = await Directory.systemTemp.createTemp('runtime-failed-');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileRunStore(dir);
    final tasks = TaskRegistry()
      ..register<String>(
        TaskDefinition(
          spec: f.spec,
          instructions: 'Title',
          decode: (s) {
            if (s == 'bad') throw const FormatException('schema');
            return s;
          },
          encode: (s) => {'title': s},
          restore: (j) => j['title'] as String,
          validator: f.Validator(),
          validateInput: (_) => ValidationReport(),
          reconcileUnfinished: (original, checkpoint) {
            final metadata = (checkpoint['state'] as Map)['metadata'] as Map;
            expect(metadata['write-receipt'], 'page-1-committed');
            return {'page-2'};
          },
          retryInput: (original, missing) => {'ids': missing.toList()},
          createBindings: (c, state, input) {
            if (c.parentRunId == null) state.metadata['write-receipt'] = 'page-1-committed';
            return TaskBindings();
          },
        ),
      );
    final client = ScriptClient([answer('bad'), answer('bad'), answer('Recovered')]);
    final runtime = SdkAgentRuntime(
      store: store,
      tasks: tasks,
      knowledge: VersionedKnowledgeRegistry([]),
      testClient: client,
      loadModel: (_) async =>
          RuntimeModelBinding(model: policy.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
    );
    expect((await runtime.start(f.request(), f.context()).result).status, RunStatus.failed);
    final before = encodeRunManifest((await store.load('run'))!);
    final child = await runtime.retryUnfinished(f.request(), f.context(), childRunId: 'retry-failed');
    expect(client.calls, 2);
    await child.resume();
    expect((await child.result).status, RunStatus.completed);
    final wire = jsonEncode(client.requests.last.map((m) => m.toJson()).toList());
    expect(wire, contains('page-2'));
    expect(wire, isNot(contains('Title source')));
    expect(encodeRunManifest((await store.load('run'))!), before);
  });
  test('new configuration retains newly generated tool round in actual next request', () async {
    final (client, _) = await switchedHeavy();
    expect(
      client.requests.last.whereType<sdk.FunctionExecutionResultMessage>(),
      isNotEmpty,
      reason: 'New-phase tool results must reach the next model call.',
    );
  });
  test('new configuration rebuilds context-bound permissions and tools', () async {
    final (_, phases) = await switchedHeavy();
    expect(phases.last, 1, reason: 'Bindings must capture the current phase and scope.');
  });
  test('disk model-usage index includes partial and failed checkpoints', () async {
    final dir = await Directory.systemTemp.createTemp('runtime-review-');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileRunStore(dir);
    for (final status in [RunStatus.partial, RunStatus.failed]) {
      await store.checkpoint(disk.manifest(0, id: status.name), expectedRevision: null);
      await store.complete(disk.manifest(1, id: status.name, status: status), {
        'missingInputIds': ['page-2'],
      }, expectedRevision: 0);
    }
    expect((await store.resumable()).map((m) => m.context.runId).toSet(), {'partial', 'failed'});
  });
}
